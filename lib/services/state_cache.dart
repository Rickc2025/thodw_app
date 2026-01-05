import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Real-time cache for Firestore collections used across screens.
/// Provides synchronous getters backed by listeners to `checkins` and `logs`.
class StateCache {
  static final StateCache _instance = StateCache._internal();
  factory StateCache() => _instance;
  StateCache._internal();

  final db = FirebaseFirestore.instance;

  // diverId -> { checkedIn: bool, tag: int?, timestamp: String }
  final Map<String, Map<String, dynamic>> _checkins = {};

  // key diverId|tag -> latest log map { diverId, name, status, tag, datetime, gasIn?, gasOut? }
  final Map<String, Map<String, dynamic>> _lastLogByKey = {};
  // diverId -> latest log (by datetime) regardless of tag
  final Map<String, Map<String, dynamic>> _latestLogById = {};

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _checkinsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _logsSub;

  static Future<void> init() async {
    await _instance._start();
  }

  Future<void> _start() async {
    _checkinsSub?.cancel();
    _logsSub?.cancel();

    _checkinsSub = db.collection('checkins').snapshots().listen((snap) {
      // Rebuild entire check-ins map from snapshot to reflect deletions
      final Map<String, Map<String, dynamic>> next = {};
      for (final d in snap.docs) {
        final data = d.data();
        next[d.id] = {
          'checkedIn': (data['checkedIn'] ?? false) == true,
          'tag': _parseInt(data['tag']),
          'timestamp': (data['timestamp'] ?? '').toString(),
        };
      }
      _checkins
        ..clear()
        ..addAll(next);
    });

    // Rebuild latest status per diverId on each snapshot. We read logs in
    // descending datetime order, so the first occurrence of a diverId is the
    // latest status regardless of timestamp parsing.
    _logsSub = db
        .collection('logs')
        .orderBy('datetime', descending: true)
        .snapshots()
        .listen((snap) {
          final Map<String, Map<String, dynamic>> latestById = {};
          for (final d in snap.docs) {
            final data = d.data();
            final diverId = (data['diverId'] ?? '').toString();
            final tagStr = (data['tag'] ?? '').toString();
            final key = "$diverId|$tagStr";
            // Track last log per diverId|tag for editing/use cases.
            _lastLogByKey[key] = data;
            if (diverId.isEmpty) continue;
            // First hit wins due to descending order = latest
            latestById.putIfAbsent(diverId, () => data);
          }
          _latestLogById
            ..clear()
            ..addAll(latestById);
        });
  }

  static int? _parseInt(dynamic t) {
    if (t == null) return null;
    if (t is int) return t;
    return int.tryParse('$t');
  }

  // Synchronous getters used by UI
  static bool isCheckedIn(String diverId) {
    final m = _instance._checkins[diverId];
    return (m?['checkedIn'] ?? false) == true;
  }

  static int? checkedInTank(String diverId) {
    final m = _instance._checkins[diverId];
    return m?['tag'] as int?;
  }

  static String? checkedInTimestamp(String diverId) {
    final m = _instance._checkins[diverId];
    final ts = (m?['timestamp'] ?? '').toString();
    return ts.isEmpty ? null : ts;
  }

  static bool diverIsInWater(String diverId) {
    final m = _instance._latestLogById[diverId];
    if (m == null) return false;
    final status = (m['status'] ?? '').toString().trim().toUpperCase();
    return status == 'IN';
  }

  static int currentlyIn() {
    int count = 0;
    for (final v in _instance._latestLogById.values) {
      final status = (v['status'] ?? '').toString().trim().toUpperCase();
      if (status == 'IN') count++;
    }
    return count;
  }

  // Synchronous list of diverIds that are currently checked-in on deck
  static List<String> checkedInIds() {
    final List<String> ids = [];
    _instance._checkins.forEach((id, m) {
      if ((m['checkedIn'] ?? false) == true) ids.add(id);
    });
    ids.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return ids;
  }

  static Future<void> addLogs(List<Map<String, dynamic>> logs) async {
    // Optimistically update local cache so UI reflects immediately
    for (final l in logs) {
      final key = "${l['diverId'] ?? ''}|${l['tag'] ?? ''}";
      _instance._lastLogByKey[key] = l;
      final diverId = (l['diverId'] ?? '').toString();
      final dtStr = (l['datetime'] ?? '').toString();
      DateTime? dt;
      try {
        dt = DateTime.parse(dtStr);
      } catch (_) {
        dt = null;
      }
      final prev = _instance._latestLogById[diverId];
      DateTime? prevDt;
      try {
        prevDt = prev == null
            ? null
            : DateTime.parse((prev['datetime'] ?? '').toString());
      } catch (_) {
        prevDt = null;
      }
      if (diverId.isNotEmpty) {
        if (prev == null ||
            (dt != null && (prevDt == null || dt.isAfter(prevDt)))) {
          _instance._latestLogById[diverId] = l;
        }
      }
    }
    // Persist to Firestore
    final batch = _instance.db.batch();
    final coll = _instance.db.collection('logs');
    for (final l in logs) {
      final doc = coll.doc();
      batch.set(doc, l);
    }
    await batch.commit();
  }

  static Future<void> setCheckin(
    String diverId, {
    required bool checkedIn,
    int? tag,
  }) async {
    // Optimistically update local cache so UI reflects immediately
    final prev = _instance._checkins[diverId] ?? {};
    final String prevTs = (prev['timestamp'] ?? '').toString();
    // If marking checkedIn true and there is no timestamp, set now; if updating tag only, preserve timestamp.
    final String ts = checkedIn
        ? (prevTs.isEmpty ? DateTime.now().toIso8601String() : prevTs)
        : prevTs;
    _instance._checkins[diverId] = {
      'checkedIn': checkedIn,
      'tag': tag,
      'timestamp': ts,
    };
    // Persist to Firestore
    final doc = _instance.db.collection('checkins').doc(diverId);
    await doc.set({
      'checkedIn': checkedIn,
      'tag': tag,
      'timestamp': ts,
    }, SetOptions(merge: true));
  }

  // Check if a tank tag is currently assigned to any checked-in diver, optionally excluding a name
  static Future<bool> tankInUse(int tag, {String? exceptId}) async {
    final snap = await _instance.db
        .collection('checkins')
        .where('checkedIn', isEqualTo: true)
        .get();
    for (final d in snap.docs) {
      final id = d.id;
      if (exceptId != null && id == exceptId) continue;
      final data = d.data();
      final t = _parseInt(data['tag']);
      if (t == tag) return true;
    }
    return false;
  }
}
