Backend API client for Flutter

This app can generate a typed Dart client from the backend OpenAPI spec using OpenAPI Generator.

Generate

1) From repo root:

   make gen-app

   This writes generated sources to lib/api/generated.

2) Add dependencies to pubspec.yaml (if not present):

   dependencies:
     dio: ^5.0.0

3) Import and use:

   import 'package:messie_api/api.dart' as api;

   import 'package:messie_app/api/env.dart';
   final client = api.ApiClient(basePath: apiBaseUrl);
   final connections = await api.DefaultApi(client).getConnections();

Notes

- The generator used is dart-dio. Adjust generator/options as needed in the Makefile.
- The OpenAPI source is docs/openapi.yaml. Update it first, then re-run make gen-app and make gen-be.
- Dev runs pass the base URL via `--dart-define=MESSIE_API_BASE_URL=...` (set by the Makefile).
