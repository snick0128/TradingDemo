import '../../auth_repository.dart';

/// Firebase Authentication implementation stub.
///
/// HOW TO ACTIVATE:
/// 1. Add `firebase_core` and `firebase_auth` to pubspec.yaml.
/// 2. Run `flutterfire configure` to generate google-services.json / GoogleService-Info.plist.
/// 3. Initialize Firebase in main.dart: `await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);`
/// 4. Replace MockAuthRepository with FirebaseAuthRepository in main.dart.
///
/// Firebase Auth docs: https://firebase.google.com/docs/auth/flutter/start
class FirebaseAuthRepository implements AuthRepository {
  // FirebaseAuth get _auth => FirebaseAuth.instance;
  // FirebaseFirestore get _db => FirebaseFirestore.instance;

  @override
  Future<AuthResult> signIn(String identifier, String password) async {
    // final credential = await _auth.signInWithEmailAndPassword(
    //   email: identifier,
    //   password: password,
    // );
    // final user = credential.user!;
    // final doc = await _db.collection('users').doc(user.uid).get();
    // return AuthResult.success(AppUser(
    //   id: user.uid,
    //   name: doc['name'],
    //   email: user.email!,
    //   clientId: doc['clientId'] ?? user.uid,
    //   isAdmin: doc['isAdmin'] ?? false,
    //   balance: (doc['balance'] ?? 0).toDouble(),
    // ));
    throw UnimplementedError('Implement Firebase signIn');
  }

  @override
  Future<AuthResult> register({
    required String name,
    required String email,
    required String password,
    double initialBalance = 0,
  }) async {
    // final credential = await _auth.createUserWithEmailAndPassword(
    //   email: email,
    //   password: password,
    // );
    // final user = credential.user!;
    // await user.updateDisplayName(name);
    // await _db.collection('users').doc(user.uid).set({
    //   'name': name,
    //   'email': email,
    //   'clientId': email.split('@').first,
    //   'balance': initialBalance,
    //   'isAdmin': false,
    //   'createdAt': FieldValue.serverTimestamp(),
    // });
    // return AuthResult.success(AppUser(id: user.uid, name: name, email: email, clientId: email.split('@').first, balance: initialBalance));
    throw UnimplementedError('Implement Firebase register');
  }

  @override
  Future<void> signOut() async {
    // await _auth.signOut();
    throw UnimplementedError('Implement Firebase signOut');
  }

  @override
  Future<AppUser?> getCurrentUser() async {
    // final user = _auth.currentUser;
    // if (user == null) return null;
    // final doc = await _db.collection('users').doc(user.uid).get();
    // return AppUser(id: user.uid, name: doc['name'], email: user.email!, clientId: doc['clientId']);
    throw UnimplementedError('Implement Firebase getCurrentUser');
  }

  @override
  Stream<AppUser?> get authStateChanges {
    // return _auth.authStateChanges().asyncMap((user) async {
    //   if (user == null) return null;
    //   final doc = await _db.collection('users').doc(user.uid).get();
    //   return AppUser(id: user.uid, name: doc['name'], email: user.email!, clientId: doc['clientId']);
    // });
    throw UnimplementedError('Implement Firebase authStateChanges');
  }
}
