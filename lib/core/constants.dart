/// App-wide build-time configuration. Override at build time with e.g.
/// `flutter run --dart-define=PAYMENT_BACKEND_URL=https://payos.example.com`.
class AppConfig {
  static const String paymentBackendUrl = String.fromEnvironment(
    'PAYMENT_BACKEND_URL',
    defaultValue: 'http://10.0.2.2:3000',
  );
}
