// ignore_for_file: avoid_print
@Timeout(Duration(minutes: 2))
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:messie_app/bridge/messie_bridge.dart';

class _Env {
  final String hs;
  final String user;
  final String pass;
  final String base;
  _Env(this.hs, this.user, this.pass, this.base);
}

_Env? _loadEnv() {
  final env = Platform.environment;
  final hs = env['MESSIE_MATRIX_HOMESERVER'];
  final user = env['MESSIE_MATRIX_USERNAME'];
  final pass = env['MESSIE_MATRIX_PASSWORD'];
  final base = env['MESSIE_MATRIX_STORE_BASE'] ?? Directory.systemTemp.createTempSync('messie_v1').path;
  if (hs == null || user == null || pass == null) return null;
  return _Env(hs, user, pass, base);
}

Future<Map<String, (int n, int h)>> _fetchBaselineCounts({
  required String hs,
  required String accessToken,
}) async {
  // Perform a full_state baseline snapshot without a filter to ensure all joined rooms appear.
  final uri = Uri.parse(hs).replace(
    path: '/_matrix/client/v3/sync',
    queryParameters: {'timeout': '0', 'full_state': 'true'},
  );
  final client = HttpClient();
  try {
    final req = await client.getUrl(uri);
    req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $accessToken');
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final resp = await req.close();
    final text = await utf8.decoder.bind(resp).join();
    if (resp.statusCode != 200) {
      throw Exception('baseline sync failed: ${resp.statusCode} $text');
    }
    final body = json.decode(text) as Map<String, dynamic>;
    final rooms = (body['rooms'] as Map?) ?? const {};
    final join = (rooms['join'] as Map?) ?? const {};
    final out = <String, (int, int)>{};
    join.forEach((key, value) {
      final room = value as Map<String, dynamic>?;
      if (room == null) return;
      final unread = (room['unread_notifications'] as Map?) ?? const {};
      final n = (unread['notification_count'] as num?)?.toInt() ?? 0;
      final h = (unread['highlight_count'] as num?)?.toInt() ?? 0;
      out[key.toString()] = (n, h);
    });
    return out;
  } finally {
    client.close(force: true);
  }
}

void main() {
  final env = _loadEnv();
  if (env == null) {
    test('skipped - env not set', () {
      expect(true, isTrue, reason: 'Set MESSIE_MATRIX_* env to run');
    }, skip: true);
    return;
  }

  test('baseline unread counts match room_overview for visible rooms', () async {
    // Login and start SS
    final login = await rustRestoreOrLogin(
      homeserverUrl: env.hs,
      username: env.user,
      password: env.pass,
      basePath: env.base,
    );
    expect(login.isOk, isTrue, reason: login.error);
    final session = login.data!;
    final start = await rustStartSlidingSync(
      handle: 'v1-ss-base',
      hpSize: 48,
      lpBatch: 240,
      hpTimeline: 5,
      lpTimeline: 1,
    );
    expect(start.isOk, isTrue, reason: start.error);

    // Collect a set of visible rooms (from SS stream)
    final port = ReceivePort('baseline_room_list');
    addTearDown(() => port.close());
    final stream = port.asBroadcastStream();
    final reg = await rustRoomListStream(handle: 'v1-ss-base', port: port.sendPort);
    expect(reg.isOk, isTrue, reason: reg.error);

    final visible = <String>{};
    final end = DateTime.now().add(const Duration(seconds: 6));
    await for (final msg in stream) {
      if (DateTime.now().isAfter(end)) break;
      if (msg is! String) continue;
      try {
        final dec = json.decode(msg) as Map<String, dynamic>;
        final kind = dec['kind'];
        if (kind == 'sliding_sync_ready' || kind == 'sliding_sync_update') {
          final ids = (dec['rooms'] as List?)?.map((e) => e.toString()) ?? const <String>[];
          visible.addAll(ids);
        }
      } catch (_) {}
    }
    expect(visible.isNotEmpty, isTrue, reason: 'No visible rooms from SS');
    final sample = visible.take(50).toList();

    // Fetch baseline counts from classic /sync full_state
    final baseline = await _fetchBaselineCounts(hs: env.hs, accessToken: session.accessToken);
    // Compare against room_overview for sample rooms
    var mismatches = 0;
    for (final rid in sample) {
      final ov = await rustRoomOverview(roomId: rid);
      if (!ov.isOk || ov.data == null) continue;
      final sdkN = ov.data!.notificationCount;
      final sdkH = ov.data!.highlightCount;
      final srv = baseline[rid] ?? (0, 0);
      if (sdkN != srv.$1 || sdkH != srv.$2) {
        mismatches++;
        debugPrint('[baseline] mismatch room=$rid sdk=($sdkN,$sdkH) srv=(${srv.$1},${srv.$2})');
      }
    }
    expect(mismatches == 0, isTrue, reason: 'baseline mismatches observed: $mismatches');
  });
}
