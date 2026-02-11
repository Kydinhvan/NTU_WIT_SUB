class ApiConstants {
  /// Set to false when FastAPI backend is running.
  static bool useMock = false;

  // FastAPI base URL — update when backend is running
  // LOCAL:  'http://localhost:8000'
  // NGROK:  paste your ngrok URL here, e.g. 'https://abc123.ngrok-free.app'
  static const String apiBase = 'https://a3ec-202-94-70-51.ngrok-free.app';

  static const String transcribe     = '/transcribe';
  static const String extractProfile = '/extract-profile';
  static const String match          = '/match';
  static const String discover       = '/discover';
  static const String safetyCheck    = '/safety-check';
  static const String scaffold       = '/scaffold';

  static String url(String endpoint) => '$apiBase$endpoint';
}
