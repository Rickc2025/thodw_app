import 'package:cloud_firestore/cloud_firestore.dart';

class DiversService {
  static CollectionReference<Map<String, dynamic>> get _coll =>
      FirebaseFirestore.instance.collection('divers');

  static Future<List<Map<String, dynamic>>> getDivers() async {
    final snap = await _coll.get();
    final list = <Map<String, dynamic>>[];
    for (final d in snap.docs) {
      final data = d.data();
      data['name'] = d.id; // store name in doc id
      list.add(data);
    }
    return list;
  }

  static Future<void> setDiver(String name, Map<String, dynamic> data) async {
    await _coll.doc(name).set(data, SetOptions(merge: true));
  }

  static Future<void> removeDiver(String name) async {
    // Cascade: remove diver document and any active check-in document.
    final fs = FirebaseFirestore.instance;
    await fs.collection('checkins').doc(name).delete().catchError((_) {});
    await _coll.doc(name).delete();
  }
}
