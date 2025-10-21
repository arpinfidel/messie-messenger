import 'dart:async';
import 'package:messie_app/api/env.dart';

// NOTE: The OpenAPI generator (dart-dio) writes under
// app/lib/api/generated/lib. Import accordingly.
import 'package:dio/dio.dart';

class BridgesService {
  final Dio _dio;

  BridgesService._(this._dio);

  factory BridgesService({String? bearerToken}) {
    // Ensure baseUrl ends with trailing slash so relative paths join as expected
    final base = apiBaseUrl.endsWith('/') ? apiBaseUrl : (apiBaseUrl + '/');
    final dio = Dio(BaseOptions(baseUrl: base));
    if (bearerToken != null && bearerToken.isNotEmpty) {
      dio.options.headers['Authorization'] = 'Bearer $bearerToken';
    }
    return BridgesService._(dio);
  }

  Future<String> pingHealth() async {
    final res = await _dio.get('health');
    return res.data?.toString() ?? '';
  }

  Future<List<Map<String, dynamic>>> listConnections() async {
    final res = await _dio.get('connections');
    final list = (res.data as List?) ?? const [];
    return list.map((e) => (e as Map).cast<String, dynamic>()).toList();
  }

  // Provider-agnostic provisioning endpoints (WhatsApp)
  Future<List<Map<String, dynamic>>> getLoginFlows({String provider = 'whatsapp'}) async {
    final res = await _dio.get('bridge/provision/v3/login/flows', queryParameters: {'provider': provider});
    final flows = (res.data['flows'] as List?) ?? const [];
    return flows.cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> startLogin(String flow, {String provider = 'whatsapp'}) async {
    final res = await _dio.post('bridge/provision/v3/login/start/$flow', queryParameters: {'provider': provider});
    return (res.data as Map).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> whoami({String provider = 'whatsapp'}) async {
    final res = await _dio.get('bridge/provision/v3/whoami', queryParameters: {'provider': provider});
    return (res.data as Map).cast<String, dynamic>();
  }

  Future<void> logoutAll({String provider = 'whatsapp'}) async {
    await _dio.post('bridge/provision/v3/logout/all', queryParameters: {'provider': provider});
  }

  Future<Map<String, dynamic>> submitDisplayAndWait({
    required String processId,
    required String stepId,
    String provider = 'whatsapp',
  }) async {
    final path = 'bridge/provision/v3/login/step/$processId/$stepId/display_and_wait';
    final res = await _dio.post(path, queryParameters: {'provider': provider});
    return (res.data as Map).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> submitUserInput({
    required String processId,
    required String stepId,
    required Map<String, String> fields,
    String provider = 'whatsapp',
  }) async {
    // For user_input, the bridge expects a flat object mapping field IDs to values.
    // Example: {"phone": "+123456789"}
    final path = 'bridge/provision/v3/login/step/$processId/$stepId/user_input';
    final res = await _dio.post(path,
        queryParameters: {'provider': provider}, data: fields);
    return (res.data as Map).cast<String, dynamic>();
  }
}
