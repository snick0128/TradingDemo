import '../../auth_repository.dart';

/// Mock implementation — replace with FirebaseAuthRepository when ready.
/// To switch: change the binding in main.dart from MockAuthRepository → FirebaseAuthRepository.
class MockAuthRepository implements AuthRepository {
  AppUser? _currentUser;
  final _controller = _StreamController<AppUser?>();

  static const _validUsers = {
    'demo': ('password', 'Demo User', 'demo@boxtradingpro.com', false),
    'admin': ('admin123', 'Admin User', 'admin@boxtradingpro.com', true),
  };

  @override
  Future<AuthResult> signIn(String identifier, String password) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final entry = _validUsers[identifier.toLowerCase()];
    if (entry == null || entry.$1 != password) {
      return AuthResult.failure('Invalid credentials.');
    }
    _currentUser = AppUser(
      id: 'u_$identifier',
      name: entry.$2,
      email: entry.$3,
      clientId: identifier,
      isAdmin: entry.$4,
      balance: 100000,
    );
    _controller.add(_currentUser);
    return AuthResult.success(_currentUser!);
  }

  @override
  Future<AuthResult> register({
    required String name,
    required String email,
    required String password,
    double initialBalance = 0,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));
    _currentUser = AppUser(
      id: 'u_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      email: email,
      clientId: email.split('@').first,
      balance: initialBalance,
    );
    _controller.add(_currentUser);
    return AuthResult.success(_currentUser!);
  }

  @override
  Future<void> signOut() async {
    _currentUser = null;
    _controller.add(null);
  }

  @override
  Future<AppUser?> getCurrentUser() async => _currentUser;

  @override
  Stream<AppUser?> get authStateChanges => _controller.stream;
}

// Minimal broadcast stream controller
class _StreamController<T> {
  final _listeners = <void Function(T)>[];
  late final Stream<T> stream = Stream<T>.multi((c) {
    _listeners.add(c.add);
    c.onCancel = () => _listeners.remove(c.add);
  });
  void add(T value) {
    for (final l in List.of(_listeners)) l(value);
  }
}
