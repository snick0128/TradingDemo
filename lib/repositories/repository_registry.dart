import 'auth_repository.dart';
import 'impl/mock/mock_auth_repository.dart';

// ─────────────────────────────────────────────────────────────────────────────
// REPOSITORY REGISTRY
// ─────────────────────────────────────────────────────────────────────────────
//
// This is the SINGLE place to swap between mock and real implementations.
//
// TO SWITCH TO FIREBASE AUTH:
//   1. Uncomment the Firebase import below
//   2. Comment out MockAuthRepository
//   3. Uncomment FirebaseAuthRepository
//
// TO SWITCH TO ZERODHA TRADING:
//   1. Uncomment the Zerodha import below
//   2. Provide your apiKey + accessToken
//   3. The TradingStore will use ZerodhaTradingRepository instead of mock data
//
// ─────────────────────────────────────────────────────────────────────────────

// import 'impl/firebase/firebase_auth_repository.dart';
// import 'impl/zerodha/zerodha_trading_repository.dart';

class RepositoryRegistry {
  RepositoryRegistry._();

  // ── Auth ──────────────────────────────────────────────────────────────────
  // CURRENT: Mock (local, no network)
  static AuthRepository get auth => MockAuthRepository();

  // FIREBASE (uncomment when ready):
  // static AuthRepository get auth => FirebaseAuthRepository();

  // ── Trading ───────────────────────────────────────────────────────────────
  // CURRENT: Handled by TradingStore + MockData (no separate repository yet)
  //
  // ZERODHA (uncomment when ready):
  // static TradingRepository get trading => ZerodhaTradingRepository(
  //   apiKey: const String.fromEnvironment('ZERODHA_API_KEY'),
  //   accessToken: const String.fromEnvironment('ZERODHA_ACCESS_TOKEN'),
  // );
  //
  // NOTE: When switching to Zerodha, TradingStore should delegate all
  // data fetching to ZerodhaTradingRepository instead of MockData.
  // The UI layer (screens) does NOT need to change — only TradingStore changes.
}
