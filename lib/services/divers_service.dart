import 'package:cloud_firestore/cloud_firestore.dart';

class DiversService {
  static CollectionReference<Map<String, dynamic>> get _coll =>
      FirebaseFirestore.instance.collection('divers');

  // Return a list of divers with explicit 'id' and 'name' fields.
  // For backward-compat if older docs don't have a 'name' field, fall back to doc id.
  static Future<List<Map<String, dynamic>>> getDivers() async {
    final snap = await _coll.get();
    final list = <Map<String, dynamic>>[];
    for (final d in snap.docs) {
      final data = d.data();
      final name = (data['name'] ?? d.id).toString();
      list.add({...data, 'id': d.id, 'name': name});
    }
    return list;
  }

  // Create a diver with an auto-generated Firestore doc ID.
  static Future<String> createDiver(Map<String, dynamic> data) async {
    final doc = await _coll.add(data);
    return doc.id;
  }

  // Update an existing diver by id.
  static Future<void> updateDiver(String id, Map<String, dynamic> data) async {
    await _coll.doc(id).set(data, SetOptions(merge: true));
  }

  // Remove diver by id and cascade delete any active check-in document keyed by diverId.
  static Future<void> removeDiver(String id) async {
    final fs = FirebaseFirestore.instance;
    await fs.collection('checkins').doc(id).delete().catchError((_) {});
    await _coll.doc(id).delete();
  }
}
