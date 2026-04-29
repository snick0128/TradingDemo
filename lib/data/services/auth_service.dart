import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../config/admin_auth_config.dart';
import '../../domain/auth/app_user_profile.dart';
import 'firestore_service.dart';

class AuthService {
  AuthService({
    required FirebaseAuth auth,
    required FirestoreService firestore,
  }) : _auth = auth,
       _firestore = firestore;

  final FirebaseAuth _auth;
  final FirestoreService _firestore;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<AppUserProfile> loginUser(String email, String password) {
    return _loginWithExpectedRole(email, password, expectedRole: 'user');
  }

  Future<AppUserProfile> loginAdmin(String email, String password) {
    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail != kPrimaryAdminEmail) {
      throw Exception('Only $kPrimaryAdminEmail can access admin portal.');
    }
    return _loginAdminWithBootstrap(normalizedEmail, password);
  }

  Future<void> logout() => _auth.signOut();

  /// Sign in with Google. Creates a Firestore user doc on first sign-in.
  Future<AppUserProfile> signInWithGoogle({String expectedRole = 'user'}) async {
    final googleUser = await GoogleSignIn(
      clientId: '421918726497-web.apps.googleusercontent.com',
    ).signIn();
    if (googleUser == null) throw Exception('Google sign-in cancelled.');

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final userCredential = await _auth.signInWithCredential(credential);
    final firebaseUser = userCredential.user;
    if (firebaseUser == null) throw Exception('Google sign-in failed.');

    // Check if user doc exists; create it on first sign-in
    final doc = await _firestore.getDocument('users/${firebaseUser.uid}');
    if (!doc.exists) {
      await _firestore.setDocument('users/${firebaseUser.uid}', {
        'uid': firebaseUser.uid,
        'name': firebaseUser.displayName ?? 'User',
        'email': firebaseUser.email ?? '',
        'role': expectedRole,
        'balance': 0.0,
        'tradingEnabled': true,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    final profile = await _loadProfile(firebaseUser);
    if (profile.role != expectedRole) {
      await _auth.signOut();
      throw Exception('This Google account is not registered as a $expectedRole.');
    }
    return profile;
  }

  Future<AppUserProfile> registerUser({
    required String name,
    required String email,
    required String password,
  }) async {
    if (email.trim().toLowerCase() == kPrimaryAdminEmail) {
      throw Exception(
        'This email is reserved for primary admin. Use another email.',
      );
    }

    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    final firebaseUser = credential.user;
    if (firebaseUser == null) throw Exception('Registration failed.');

    // Create user document in Firestore with role = "user"
    await _firestore.setDocument('users/${firebaseUser.uid}', {
      'uid': firebaseUser.uid,
      'name': name,
      'email': email,
      'role': 'user',
      'balance': 0.0,
      'tradingEnabled': true,
      'createdAt': FieldValue.serverTimestamp(),
    });

    return AppUserProfile(
      uid: firebaseUser.uid,
      email: email,
      role: 'user',
      name: name,
      balance: 0.0,
      tradingEnabled: true,
    );
  }

  Future<AppUserProfile?> getCurrentProfile() async {
    final current = _auth.currentUser;
    if (current == null) return null;
    return _loadProfile(current);
  }

  Future<AppUserProfile> _loginWithExpectedRole(
    String email,
    String password, {
    required String expectedRole,
  }) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    final firebaseUser = credential.user;
    if (firebaseUser == null) {
      throw Exception('Authentication failed.');
    }

    final profile = await _loadProfile(firebaseUser);
    if (profile.role != expectedRole) {
      await _auth.signOut();
      throw Exception('Role mismatch for this portal.');
    }
    return profile;
  }

  Future<AppUserProfile> _loginAdminWithBootstrap(
    String email,
    String password,
  ) async {
    if (password != kPrimaryAdminPassword) {
      throw Exception('Invalid admin credentials.');
    }

    try {
      return await _loginWithExpectedRole(
        email,
        password,
        expectedRole: 'admin',
      );
    } on FirebaseAuthException catch (e) {
      if (e.code != 'user-not-found' && e.code != 'invalid-credential') {
        rethrow;
      }
      return _createPrimaryAdminIfMissing();
    }
  }

  Future<AppUserProfile> _createPrimaryAdminIfMissing() async {
    UserCredential credential;
    try {
      credential = await _auth.createUserWithEmailAndPassword(
        email: kPrimaryAdminEmail,
        password: kPrimaryAdminPassword,
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        throw Exception('Invalid admin credentials.');
      }
      rethrow;
    }

    final firebaseUser = credential.user;
    if (firebaseUser == null) {
      throw Exception('Failed to create primary admin account.');
    }

    await _firestore.setDocument('users/${firebaseUser.uid}', {
      'uid': firebaseUser.uid,
      'name': 'Primary Admin',
      'email': kPrimaryAdminEmail,
      'role': 'admin',
      'balance': 0.0,
      'tradingEnabled': true,
      'createdAt': FieldValue.serverTimestamp(),
    });

    return _loadProfile(firebaseUser);
  }

  Future<AppUserProfile> _loadProfile(User firebaseUser) async {
    final doc = await _firestore.getDocument('users/${firebaseUser.uid}')
        .timeout(const Duration(seconds: 8), onTimeout: () {
      throw Exception('Profile fetch timed out. Check your connection.');
    });

    Map<String, dynamic> data;

    if (!doc.exists || doc.data() == null) {
      // Auto-create profile if missing (e.g. account created via Firebase Console)
      data = {
        'uid': firebaseUser.uid,
        'name': firebaseUser.displayName ?? firebaseUser.email?.split('@').first ?? 'User',
        'email': firebaseUser.email ?? '',
        'role': 'user',
        'balance': 0.0,
        'tradingEnabled': true,
        'createdAt': FieldValue.serverTimestamp(),
      };
      await _firestore.setDocument('users/${firebaseUser.uid}', data);
    } else {
      data = doc.data()!;
    }

    return AppUserProfile.fromMap(
      firebaseUser.uid,
      data,
      fallbackEmail: firebaseUser.email ?? '',
    );
  }
}
