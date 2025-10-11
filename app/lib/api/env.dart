/// API base URL for the backend.
/// Set at build time via: --dart-define=MESSIE_API_BASE_URL=...
/// Defaults to local dev backend.
const String apiBaseUrl = String.fromEnvironment(
  'MESSIE_API_BASE_URL',
  defaultValue: 'http://127.0.0.1:8080/api/v1',
);

