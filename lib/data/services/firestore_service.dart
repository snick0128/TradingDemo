import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
  FirestoreService(this._firestore);

  final FirebaseFirestore _firestore;

  Stream<QuerySnapshot<Map<String, dynamic>>> getCollectionStream(String path) {
    return _firestore.collection(path).snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> getCollectionQueryStream(
    String path, {
    String? field,
    dynamic isEqualTo,
  }) {
    Query<Map<String, dynamic>> query = _firestore.collection(path);
    if (field != null) {
      query = query.where(field, isEqualTo: isEqualTo);
    }
    return query.snapshots();
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> getDocument(String path) {
    return _firestore.doc(path).get();
  }

  Future<DocumentReference<Map<String, dynamic>>> addDocument(
    String path,
    Map<String, dynamic> data,
  ) {
    return _firestore.collection(path).add(data);
  }

  Future<void> setDocument(String path, Map<String, dynamic> data) {
    return _firestore.doc(path).set(data, SetOptions(merge: true));
  }

  Future<void> updateDocument(String path, Map<String, dynamic> data) {
    return _firestore.doc(path).update(data);
  }

  Future<void> deleteDocument(String path) {
    return _firestore.doc(path).delete();
  }

  FirebaseFirestore get raw => _firestore;
}
