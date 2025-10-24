import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:messie_api/messie_api.dart' as api;

import '../api/env.dart' as env;
import '../modules/matrix/state/auth_view_model.dart';

/// Shared MessieApi client configured with base URL and bearer token.
final messieApiProvider = Provider<api.MessieApi>((ref) {
  final client = api.MessieApi(basePathOverride: env.apiBaseUrl);
  final session = ref.watch(authControllerProvider).asData?.value;
  final jwt = session?.backendJwt;
  if (jwt != null && jwt.isNotEmpty) {
    client.setBearerAuth('bearerAuth', jwt);
  }
  return client;
});

