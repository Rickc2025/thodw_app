import 'package:cloud_firestore/cloud_firestore.dart';

// Logs/Checkins helpers backed by Firestore (shared across devices)

Future<int> getCurrentlyInCount() async {
  final db = FirebaseFirestore.instance;
  // For each name+tag pair, consider last status; simpler approximation: count latest IN logs
  final snap = await db
      .collection('logs')
      .orderBy('datetime', descending: true)
      .get();
  final Map<String, Map<String, dynamic>> lastLogByDiverTag = {};
  for (final doc in snap.docs) {
    final data = doc.data();
    final key = "${data['name'] ?? ''}|${data['tag'] ?? ''}";
    lastLogByDiverTag.putIfAbsent(key, () => data);
  }
  return lastLogByDiverTag.values
      .where((l) => (l['status'] ?? '') == 'IN')
      .length;
}

Future<bool> diverIsInWater(String name) async {
  final db = FirebaseFirestore.instance;
  final snap = await db
      .collection('logs')
      .where('name', isEqualTo: name)
      .orderBy('datetime', descending: true)
      .limit(1)
      .get();
  if (snap.docs.isEmpty) return false;
  return (snap.docs.first.data()['status'] ?? '') == 'IN';
}

Future<int?> lastInTank(String name) async {
  final db = FirebaseFirestore.instance;
  final snap = await db
      .collection('logs')
      .where('name', isEqualTo: name)
      .where('status', isEqualTo: 'IN')
      .orderBy('datetime', descending: true)
      .limit(1)
      .get();
  if (snap.docs.isEmpty) return null;
  final data = snap.docs.first.data();
  final t = data['tag'];
  return t is int ? t : int.tryParse('$t');
}

Future<bool> isCheckedIn(String name) async {
  final db = FirebaseFirestore.instance;
  final doc = await db.collection('checkins').doc(name).get();
  final data = doc.data() ?? {};
  return (data['checkedIn'] ?? false) == true;
}

Future<int?> checkedInTank(String name) async {
  final db = FirebaseFirestore.instance;
  final doc = await db.collection('checkins').doc(name).get();
  final data = doc.data() ?? {};
  if (data.isEmpty) return null;
  final t = data['tag'];
  return t is int ? t : int.tryParse('$t');
}

Future<bool> tankInUse(int tag, {String? exceptName}) async {
  final db = FirebaseFirestore.instance;
  final snap = await db
      .collection('checkins')
      .where('checkedIn', isEqualTo: true)
      .get();
  for (final doc in snap.docs) {
    final name = doc.id;
    if (name == exceptName) continue;
    final data = doc.data();
    final t = data['tag'];
    final val = t is int ? t : int.tryParse('$t');
    if (val == tag) return true;
  }
  return false;
}
