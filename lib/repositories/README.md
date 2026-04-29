# Repository Layer — Plug & Play Architecture

## Structure

```
repositories/
├── auth_repository.dart          ← Abstract interface for auth
├── trading_repository.dart       ← Abstract interface for trading
├── repository_registry.dart      ← 🔑 SINGLE place to swap implementations
└── impl/
    ├── mock/
    │   └── mock_auth_repository.dart     ← Current: local mock data
    ├── firebase/
    │   └── firebase_auth_repository.dart ← Ready: Firebase Auth stub
    └── zerodha/
        └── zerodha_trading_repository.dart ← Ready: Zerodha Kite stub
```

## How to Switch to Firebase Auth

1. Add dependencies to `pubspec.yaml`:
   ```yaml
   firebase_core: ^3.x.x
   firebase_auth: ^5.x.x
   cloud_firestore: ^5.x.x
   ```

2. Run `flutterfire configure` to generate Firebase config.

3. Initialize in `main.dart`:
   ```dart
   await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
   ```

4. In `repository_registry.dart`, change:
   ```dart
   // FROM:
   static AuthRepository get auth => MockAuthRepository();
   // TO:
   static AuthRepository get auth => FirebaseAuthRepository();
   ```

5. Implement the methods in `firebase_auth_repository.dart` (stubs are ready).

## How to Switch to Zerodha Kite API

1. Add `http` package to `pubspec.yaml`.

2. Obtain API key + access token via Zerodha OAuth flow.

3. In `repository_registry.dart`, uncomment:
   ```dart
   static TradingRepository get trading => ZerodhaTradingRepository(
     apiKey: const String.fromEnvironment('ZERODHA_API_KEY'),
     accessToken: const String.fromEnvironment('ZERODHA_ACCESS_TOKEN'),
   );
   ```

4. Update `TradingStore` to call `RepositoryRegistry.trading` instead of `MockData`.

5. Implement the methods in `zerodha_trading_repository.dart` (all endpoints are documented).

## Key Principle

**The UI layer never changes.** All screens use `TradingScope.of(context)` and `SecurityScope.of(context)`.
Only the store/repository layer changes when switching from mock → real API.
