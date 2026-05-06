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
    final doc = await _firestore.raw.doc('users/${firebaseUser.uid}').get();
    if (!doc.exists) {
      await _firestore.raw.doc('users/${firebaseUser.uid}').set({
        'uid': firebaseUser.uid,
        'name': firebaseUser.displayName ?? 'User',
        'email': firebaseUser.email ?? '',
        'role': expectedRole,
        'balance': 0.0,
        'available_balance': 0.0,
        'tradingEnabled': true,
        'createdAt': Timestamp.now(),
      });
    }

    final profile = await _loadProfile(firebaseUser);
    if (profile.role != expectedRole) {
      await _auth.signOut();
      throw Exception('This Google account is not registered as a $expectedRole.');
    }
    return profile;
  }

  /// Register a new user. Steps:
  /// 1. Create Firebase Auth account (this signs the user in automatically).
  /// 2. Write Firestore doc — user is now authenticated so isOwner() passes.
  Future<AppUserProfile> registerUser({
    required String name,
    required String email,
    required String password,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();

    if (normalizedEmail == kPrimaryAdminEmail) {
      throw Exception(
        'This email is reserved for the admin. Use another email.',
      );
    }

    UserCredential credential;
    try {
      credential = await _auth.createUserWithEmailAndPassword(
        email: normalizedEmail,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        // Auth account exists — sign in and ensure Firestore doc exists.
        // This handles the case where a previous registration created the
        // Auth account but the Firestore write failed.
        try {
          final signInCred = await _auth.signInWithEmailAndPassword(
            email: normalizedEmail,
            password: password,
          );
          final firebaseUser = signInCred.user;
          if (firebaseUser == null) throw Exception('Sign-in failed.');

          final existing = await _firestore.raw
              .doc('users/${firebaseUser.uid}')
              .get();

          if (!existing.exists) {
            // Doc missing — create it now. User is authenticated so rule passes.
            await _firestore.raw.doc('users/${firebaseUser.uid}').set({
              'uid': firebaseUser.uid,
              'name': name,
              'email': normalizedEmail,
              'role': 'user',
              'balance': 0.0,
              'available_balance': 0.0,
              'tradingEnabled': true,
              'createdAt': Timestamp.now(),
            });
          }

          return _loadProfile(firebaseUser);
        } catch (_) {
          throw Exception(
            'An account with this email already exists. Please sign in instead.',
          );
        }
      }
      rethrow;
    }

    final firebaseUser = credential.user;
    if (firebaseUser == null) throw Exception('Registration failed.');

    // Force a token refresh so the Firestore SDK has a valid auth token
    // before we attempt the write. On Flutter Web this is critical — the
    // SDK may not have propagated the new auth state yet.
    try {
      await firebaseUser.getIdToken(true);
    } catch (_) {
      // Non-fatal — proceed anyway
    }

    // Small delay to ensure the Firestore SDK picks up the new auth state.
    await Future.delayed(const Duration(milliseconds: 300));

    // At this point Firebase Auth has signed the user in automatically.
    // Write the Firestore doc — isOwner(userId) will pass because
    // request.auth.uid == firebaseUser.uid.
    try {
      await _firestore.raw.doc('users/${firebaseUser.uid}').set({
        'uid': firebaseUser.uid,
        'name': name,
        'email': normalizedEmail,
        'role': 'user',
        'balance': 0.0,
        'available_balance': 0.0,
        'tradingEnabled': true,
        'createdAt': Timestamp.now(),
      });
    } catch (e) {
      // Firestore write failed — roll back the Auth account so the user
      // can try again cleanly with the same email.
      try {
        await firebaseUser.delete();
      } catch (_) {}
      throw Exception('Failed to create user profile. Please try again.');
    }

    return AppUserProfile(
      uid: firebaseUser.uid,
      email: normalizedEmail,
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

    await _firestore.raw.doc('users/${firebaseUser.uid}').set({
      'uid': firebaseUser.uid,
      'name': 'Primary Admin',
      'email': kPrimaryAdminEmail,
      'role': 'admin',
      'balance': 0.0,
      'available_balance': 0.0,
      'tradingEnabled': true,
      'createdAt': Timestamp.now(),
    });

    return _loadProfile(firebaseUser);
  }

  Future<AppUserProfile> _loadProfile(User firebaseUser) async {
    final doc = await _firestore.raw
        .doc('users/${firebaseUser.uid}')
        .get()
        .timeout(const Duration(seconds: 8), onTimeout: () {
      throw Exception('Profile fetch timed out. Check your connection.');
    });

    Map<String, dynamic> data;

    if (!doc.exists || doc.data() == null) {
      // Auto-create profile if missing (e.g. account created via Firebase Console)
      data = {
        'uid': firebaseUser.uid,
        'name': firebaseUser.displayName ??
            firebaseUser.email?.split('@').first ??
            'User',
        'email': firebaseUser.email ?? '',
        'role': 'user',
        'balance': 0.0,
        'available_balance': 0.0,
        'tradingEnabled': true,
        'createdAt': Timestamp.now(),
      };
      await _firestore.raw.doc('users/${firebaseUser.uid}').set(data);
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
