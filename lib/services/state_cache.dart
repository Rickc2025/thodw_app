import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Real-time cache for Firestore collections used across screens.
/// Provides synchronous getters backed by listeners to `checkins` and `logs`.
class StateCache {
  static final StateCache _instance = StateCache._internal();
  factory StateCache() => _instance;
  StateCache._internal();

  final db = FirebaseFirestore.instance;

  // name -> { checkedIn: bool, tag: int? }
  final Map<String, Map<String, dynamic>> _checkins = {};

  // key name|tag -> latest log map { name, status, tag, datetime, gasIn?, gasOut? }
  final Map<String, Map<String, dynamic>> _lastLogByKey = {};
  // name -> latest log (by datetime) regardless of tag
  final Map<String, Map<String, dynamic>> _latestLogByName = {};

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

    // Keep only last log per name|tag
    _logsSub = db
        .collection('logs')
        .orderBy('datetime', descending: true)
        .snapshots()
        .listen((snap) {
          for (final d in snap.docs) {
            final data = d.data();
            final key = "${data['name'] ?? ''}|${data['tag'] ?? ''}";
            // Always update the latest log for this name|tag so counts refresh across devices
            _lastLogByKey[key] = data;
            final name = (data['name'] ?? '').toString();
            final dtStr = (data['datetime'] ?? '').toString();
            DateTime? dt;
            try {
              dt = DateTime.parse(dtStr);
            } catch (_) {
              dt = null;
            }
            if (name.isNotEmpty) {
              final prev = _latestLogByName[name];
              DateTime? prevDt;
              try {
                prevDt = prev == null
                    ? null
                    : DateTime.parse((prev['datetime'] ?? '').toString());
              } catch (_) {
                prevDt = null;
              }
              if (prev == null ||
                  (dt != null && (prevDt == null || dt.isAfter(prevDt)))) {
                _latestLogByName[name] = data;
              }
            }
          }
        });
  }

  static int? _parseInt(dynamic t) {
    if (t == null) return null;
    if (t is int) return t;
    return int.tryParse('$t');
  }

  // Synchronous getters used by UI
  static bool isCheckedIn(String name) {
    final m = _instance._checkins[name];
    return (m?['checkedIn'] ?? false) == true;
  }

  static int? checkedInTank(String name) {
    final m = _instance._checkins[name];
    return m?['tag'] as int?;
  }

  static String? checkedInTimestamp(String name) {
    final m = _instance._checkins[name];
    final ts = (m?['timestamp'] ?? '').toString();
    return ts.isEmpty ? null : ts;
  }

  static bool diverIsInWater(String name) {
    final m = _instance._latestLogByName[name];
    if (m == null) return false;
    final status = (m['status'] ?? '').toString().toUpperCase();
    return status == 'IN';
  }

  static int currentlyIn() {
    int count = 0;
    for (final v in _instance._latestLogByName.values) {
      final status = (v['status'] ?? '').toString().toUpperCase();
      if (status == 'IN') count++;
    }
    return count;
  }

  // Synchronous list of names that are currently checked-in on deck
  static List<String> checkedInNames() {
    final List<String> names = [];
    _instance._checkins.forEach((name, m) {
      if ((m['checkedIn'] ?? false) == true) names.add(name);
    });
    names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return names;
  }

  static Future<void> addLogs(List<Map<String, dynamic>> logs) async {
    // Optimistically update local cache so UI reflects immediately
    for (final l in logs) {
      final key = "${l['name'] ?? ''}|${l['tag'] ?? ''}";
      _instance._lastLogByKey[key] = l;
      final name = (l['name'] ?? '').toString();
      final dtStr = (l['datetime'] ?? '').toString();
      DateTime? dt;
      try {
        dt = DateTime.parse(dtStr);
      } catch (_) {
        dt = null;
      }
      final prev = _instance._latestLogByName[name];
      DateTime? prevDt;
      try {
        prevDt = prev == null
            ? null
            : DateTime.parse((prev['datetime'] ?? '').toString());
      } catch (_) {
        prevDt = null;
      }
      if (name.isNotEmpty) {
        if (prev == null ||
            (dt != null && (prevDt == null || dt.isAfter(prevDt)))) {
          _instance._latestLogByName[name] = l;
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
    String name, {
    required bool checkedIn,
    int? tag,
  }) async {
    // Optimistically update local cache so UI reflects immediately
    final prev = _instance._checkins[name] ?? {};
    final String prevTs = (prev['timestamp'] ?? '').toString();
    // If marking checkedIn true and there is no timestamp, set now; if updating tag only, preserve timestamp.
    final String ts = checkedIn
        ? (prevTs.isEmpty ? DateTime.now().toIso8601String() : prevTs)
        : prevTs;
    _instance._checkins[name] = {
      'checkedIn': checkedIn,
      'tag': tag,
      'timestamp': ts,
    };
    // Persist to Firestore
    final doc = _instance.db.collection('checkins').doc(name);
    await doc.set({
      'checkedIn': checkedIn,
      'tag': tag,
      'timestamp': ts,
    }, SetOptions(merge: true));
  }

  // Check if a tank tag is currently assigned to any checked-in diver, optionally excluding a name
  static Future<bool> tankInUse(int tag, {String? exceptName}) async {
    final snap = await _instance.db
        .collection('checkins')
        .where('checkedIn', isEqualTo: true)
        .get();
    for (final d in snap.docs) {
      final name = d.id;
      if (exceptName != null && name == exceptName) continue;
      final data = d.data();
      final t = _parseInt(data['tag']);
      if (t == tag) return true;
    }
    return false;
  }
}
