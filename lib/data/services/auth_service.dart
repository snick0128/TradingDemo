import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../config/admin_auth_config.dart';
import '../../domain/auth/app_user_profile.dart';
import '../../services/notification_service.dart';
import 'firestore_service.dart';

class AuthService {
  AuthService({required FirebaseAuth auth, required FirestoreService firestore})
    : _auth = auth,
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

  Future<void> sendPasswordResetEmail(String email) async {
    await _auth.sendPasswordResetEmail(email: email.trim().toLowerCase());
  }

  Future<void> invalidateCurrentSession() async {
    await _auth.signOut();
  }

  /// Sign in with Google. Creates a Firestore user doc on first sign-in.
  ///
  /// On Web: uses Firebase's native OAuth popup (no client ID needed — Firebase
  ///         reads credentials from the project configuration automatically).
  /// On Mobile: uses the google_sign_in package to handle the native flow.
  Future<AppUserProfile> signInWithGoogle({
    String expectedRole = 'user',
  }) async {
    debugPrint('[Auth] signInWithGoogle: platform=web:$kIsWeb role=$expectedRole');

    UserCredential userCredential;

    if (kIsWeb) {
      // Web: Firebase handles OAuth entirely — no clientId required.
      // signInWithPopup opens Google's OAuth consent screen in a popup window.
      debugPrint('[Auth] Web: using signInWithPopup');
      try {
        final provider = GoogleAuthProvider();
        provider.setCustomParameters({'prompt': 'select_account'});
        userCredential = await _auth.signInWithPopup(provider);
      } on FirebaseAuthException catch (e) {
        debugPrint('[Auth] signInWithPopup failed: ${e.code} ${e.message}');
        if (e.code == 'popup-closed-by-user' ||
            e.code == 'cancelled-popup-request') {
          throw Exception('Google sign-in was cancelled.');
        }
        if (e.code == 'popup-blocked') {
          throw Exception(
            'Google sign-in popup was blocked by your browser. '
            'Please allow popups for this site and try again.',
          );
        }
        throw Exception('Google sign-in failed: ${e.message}');
      }
    } else {
      // Mobile (Android / iOS): use the google_sign_in package.
      debugPrint('[Auth] Mobile: using GoogleSignIn package');
      final GoogleSignIn googleSignIn = GoogleSignIn();

      GoogleSignInAccount? googleUser;
      try {
        googleUser = await googleSignIn.signIn();
      } catch (e) {
        debugPrint('[Auth] GoogleSignIn.signIn() threw: $e');
        throw Exception('Google sign-in error: $e');
      }

      if (googleUser == null) {
        debugPrint('[Auth] User cancelled Google sign-in');
        throw Exception('Google sign-in cancelled.');
      }

      debugPrint('[Auth] GoogleSignIn success: email=${googleUser.email}');

      GoogleSignInAuthentication googleAuth;
      try {
        googleAuth = await googleUser.authentication;
      } catch (e) {
        debugPrint('[Auth] Failed to get Google auth tokens: $e');
        throw Exception('Failed to get Google authentication tokens: $e');
      }

      if (googleAuth.idToken == null) {
        debugPrint('[Auth] Google idToken is null');
        throw Exception(
          'Google sign-in failed: missing ID token. '
          'Ensure SHA-1/SHA-256 fingerprints are registered in Firebase Console.',
        );
      }

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken:     googleAuth.idToken,
      );

      try {
        userCredential = await _auth.signInWithCredential(credential);
      } on FirebaseAuthException catch (e) {
        debugPrint('[Auth] signInWithCredential failed: ${e.code} ${e.message}');
        throw Exception('Google sign-in failed: ${e.message}');
      }
    }

    final firebaseUser = userCredential.user;
    if (firebaseUser == null) {
      debugPrint('[Auth] signIn succeeded but user is null');
      throw Exception('Google sign-in failed: user is null after credential sign-in.');
    }

    debugPrint('[Auth] Firebase user: uid=${firebaseUser.uid} email=${firebaseUser.email}');

    // Force token refresh so Firestore SDK has a valid auth token immediately.
    try {
      await firebaseUser.getIdToken(true).timeout(const Duration(seconds: 8));
      debugPrint('[Auth] Token refresh successful');
    } catch (e) {
      debugPrint('[Auth] Token refresh failed (non-fatal): $e');
    }

    // Small delay for web Firestore SDK to propagate the new auth state.
    if (kIsWeb) await Future.delayed(const Duration(milliseconds: 400));

    // Create Firestore user doc on first sign-in (idempotent set).
    try {
      final doc = await _firestore.raw
          .doc('users/${firebaseUser.uid}')
          .get()
          .timeout(const Duration(seconds: 8));

      if (!doc.exists) {
        debugPrint('[Auth] First sign-in — creating Firestore user doc');
        await _firestore.raw.doc('users/${firebaseUser.uid}').set({
          'uid':               firebaseUser.uid,
          'name':              firebaseUser.displayName ?? 'User',
          'email':             firebaseUser.email ?? '',
          'role':              expectedRole,
          'balance':           0.0,
          'available_balance': 0.0,
          'tradingEnabled':    true,
          'createdAt':         Timestamp.now(),
          'signInProvider':    'google',
        }).timeout(const Duration(seconds: 10));
      }
    } catch (e) {
      debugPrint('[Auth] Firestore user doc check/create failed: $e');
      // Non-fatal for existing users — _loadProfile will handle missing docs.
    }

    final profile = await _loadProfile(firebaseUser);
    debugPrint('[Auth] Profile loaded: role=${profile.role}');

    if (profile.role != expectedRole) {
      await _auth.signOut();
      throw Exception(
        'This Google account (${firebaseUser.email}) is registered as a '
        '"${profile.role}" account, not a "$expectedRole" account. '
        'Please use the correct portal.',
      );
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
      await firebaseUser.getIdToken(true).timeout(const Duration(seconds: 5));
    } catch (_) {
      // Non-fatal — proceed anyway
    }

    // Small delay to ensure the Firestore SDK picks up the new auth state.
    await Future.delayed(const Duration(milliseconds: 500));

    // At this point Firebase Auth has signed the user in automatically.
    // Write the Firestore doc — isOwner(userId) will pass because
    // request.auth.uid == firebaseUser.uid.
    try {
      await _firestore.raw
          .doc('users/${firebaseUser.uid}')
          .set({
            'uid': firebaseUser.uid,
            'name': name,
            'email': normalizedEmail,
            'role': 'user',
            'balance': 0.0,
            'available_balance': 0.0,
            'tradingEnabled': true,
            'createdAt': Timestamp.now(),
          })
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw Exception('Firestore write timed out.');
            },
          );
    } catch (e) {
      // Firestore write failed — roll back the Auth account so the user
      // can try again cleanly with the same email.
      try {
        await firebaseUser.delete();
      } catch (_) {}
      throw Exception('Failed to create user profile: ${e.toString()}');
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
    debugPrint('[Auth] _loginWithExpectedRole email=$email role=$expectedRole');
    UserCredential credential;
    try {
      credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      debugPrint('[Auth] signInWithEmailAndPassword failed: ${e.code}');
      switch (e.code) {
        case 'user-not-found':
          throw Exception('No account found with this email address.');
        case 'wrong-password':
        case 'invalid-credential':
        case 'INVALID_LOGIN_CREDENTIALS':
          throw Exception('Incorrect email or password.');
        case 'user-disabled':
          throw Exception('This account has been disabled. Contact support.');
        case 'too-many-requests':
          throw Exception('Too many failed attempts. Please try again later.');
        case 'network-request-failed':
          throw Exception('Network error. Please check your internet connection.');
        default:
          throw Exception('Login failed: ${e.message}');
      }
    }

    final firebaseUser = credential.user;
    if (firebaseUser == null) {
      throw Exception('Authentication failed: user is null.');
    }

    final profile = await _loadProfile(firebaseUser);
    if (profile.role != expectedRole) {
      await _auth.signOut();
      throw Exception(
        'This account is registered as a "${profile.role}" — '
        'please use the correct portal.',
      );
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

  /// Save FCM token to users/{uid}.fcmTokens array (merge, no duplicates).
  /// Called after successful login so every device/browser gets push delivery.
  Future<void> _saveFcmToken(String uid) async {
    try {
      final token = await NotificationService.instance.getToken();
      if (token == null || token.isEmpty) return;
      await _firestore.raw.doc('users/$uid').update({
        'fcmTokens': FieldValue.arrayUnion([token]),
        'fcmTokenUpdatedAt': Timestamp.now(),
      });
    } catch (_) {
      // Non-fatal — app works without saved token
    }
  }

  Future<AppUserProfile> _loadProfile(User firebaseUser) async {
    debugPrint('[Auth] _loadProfile uid=${firebaseUser.uid}');

    DocumentSnapshot<Map<String, dynamic>>? doc;

    // Retry up to 3 times for transient network failures (common on first sign-in).
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        doc = await _firestore.raw
            .doc('users/${firebaseUser.uid}')
            .get()
            .timeout(const Duration(seconds: 10));
        break;
      } catch (e) {
        debugPrint('[Auth] _loadProfile attempt $attempt failed: $e');
        if (attempt == 3) {
          throw Exception(
            'Could not load your profile after $attempt attempts. '
            'Check your internet connection and try again.',
          );
        }
        await Future.delayed(Duration(milliseconds: 500 * attempt));
      }
    }

    Map<String, dynamic> data;

    if (doc == null || !doc.exists || doc.data() == null) {
      debugPrint('[Auth] User doc missing — auto-creating for uid=${firebaseUser.uid}');
      data = {
        'uid':               firebaseUser.uid,
        'name':              firebaseUser.displayName ??
                             firebaseUser.email?.split('@').first ??
                             'User',
        'email':             firebaseUser.email ?? '',
        'role':              'user',
        'balance':           0.0,
        'available_balance': 0.0,
        'tradingEnabled':    true,
        'createdAt':         Timestamp.now(),
      };
      try {
        await _firestore.raw
            .doc('users/${firebaseUser.uid}')
            .set(data)
            .timeout(const Duration(seconds: 10));
        debugPrint('[Auth] User doc created successfully');
      } catch (e) {
        debugPrint('[Auth] Failed to create user doc: $e');
        // Non-fatal — return profile with default data so the user can proceed.
      }
    } else {
      data = doc.data()!;
    }

    final profile = AppUserProfile.fromMap(
      firebaseUser.uid,
      data,
      fallbackEmail: firebaseUser.email ?? '',
    );

    debugPrint('[Auth] Profile loaded: name=${profile.name} role=${profile.role}');

    // Save FCM token after every sign-in so push notifications reach this device.
    unawaited(_saveFcmToken(firebaseUser.uid));

    return profile;
  }
}
