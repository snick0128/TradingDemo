/// Abstract contract for authentication.
/// Swap implementations: MockAuthRepository → FirebaseAuthRepository
abstract class AuthRepository {
  /// Sign in with client ID + password (broker login) or email+password (Firebase).
  Future<AuthResult> signIn(String identifier, String password);

  /// Register a new user.
  Future<AuthResult> register({
    required String name,
    required String email,
    required String password,
    double initialBalance = 0,
  });

  /// Sign out the current user.
  Future<void> signOut();

  /// Returns the currently authenticated user, or null.
  Future<AppUser?> getCurrentUser();

  /// Stream of auth state changes.
  Stream<AppUser?> get authStateChanges;
}

class AuthResult {
  final bool success;
  final AppUser? user;
  final String? errorMessage;

  const AuthResult({required this.success, this.user, this.errorMessage});

  factory AuthResult.success(AppUser user) =>
      AuthResult(success: true, user: user);
  factory AuthResult.failure(String message) =>
      AuthResult(success: false, errorMessage: message);
}

class AppUser {
  final String id;
  final String name;
  final String email;
  final String clientId;
  final bool isAdmin;
  final double balance;

  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.clientId,
    this.isAdmin = false,
    this.balance = 0,
  });
}
