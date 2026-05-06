/// Backend API configuration.
///
/// Change [backendBaseUrl] to point to your deployed server.
/// For local testing with `npm start` in paper_trading_backend/:
///   http://localhost:3000
///
/// For Flutter Web running in Chrome, localhost works directly.
/// For Flutter on Android emulator, use: http://10.0.2.2:3000
/// For Flutter on physical device, use your machine's LAN IP: http://192.168.x.x:3000
class BackendConfig {
  BackendConfig._();

  /// The base URL of the Node.js paper trading backend.
  static const String backendBaseUrl = 'https://paper-trading-backend-bnn7.onrender.com';

  /// Poll interval for live market prices (milliseconds).
  static const int pricePollingIntervalMs = 2000;

  /// Whether to use the live backend or fall back to mock data.
  /// Set to false to run the app fully offline with mock prices.
  static const bool useLiveBackend = true;
}
