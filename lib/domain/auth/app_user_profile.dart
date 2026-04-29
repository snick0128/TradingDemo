class AppUserProfile {
  final String uid;
  final String email;
  final String role; // "admin" | "user"
  final String name;
  final double balance;
  final bool tradingEnabled;

  const AppUserProfile({
    required this.uid,
    required this.email,
    required this.role,
    required this.name,
    required this.balance,
    required this.tradingEnabled,
  });

  bool get isAdmin => role == 'admin';
  bool get isUser => role == 'user';

  factory AppUserProfile.fromMap(
    String uid,
    Map<String, dynamic> data, {
    required String fallbackEmail,
  }) {
    return AppUserProfile(
      uid: uid,
      email: (data['email'] as String?) ?? fallbackEmail,
      role: (data['role'] as String?) ?? 'user',
      name: (data['name'] as String?) ?? 'User',
      balance: ((data['balance'] as num?) ?? 0).toDouble(),
      tradingEnabled: (data['tradingEnabled'] as bool?) ?? true,
    );
  }
}
