import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:messie_app/bridge/messie_bridge.dart';

String _env(String name, {String? fallback}) => Platform.environment[name] ?? fallback ?? '';

List<Map<String, dynamic>> _summariesFromPayload(Map<String, dynamic> p) {
  final raw = p['summaries'];
  if (raw is List) {
    return raw.cast<Map<dynamic, dynamic>>().map((e) => e.cast<String, dynamic>()).toList();
  }
  if (raw is Map) {
    return raw.values.cast<Map<dynamic, dynamic>>().map((e) => e.cast<String, dynamic>()).toList();
  }
  return const <Map<String, dynamic>>[];
}

Future<Map<String, dynamic>> _waitForPayload(Stream<dynamic> stream, Set<String> kinds, {Duration timeout = const Duration(seconds: 30)}) async {
  final end = DateTime.now().add(timeout);
  await for (final message in stream) {
    if (DateTime.now().isAfter(end)) throw TimeoutException('timed out waiting for payload', timeout);
    if (message is! String) continue;
    final decoded = jsonDecode(message) as Map<String, dynamic>;
    final kind = decoded['kind'] as String? ?? '';
    if (kinds.contains(kind)) return decoded;
  }
  throw StateError('stream closed before payload');
}

void main() async {
  final storePath = _env('MESSIE_BRIDGE_STORE_PATH', fallback: '${Directory.systemTemp.path}/messie_order_smoke');
  final dir = Directory(storePath);
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  dir.createSync(recursive: true);

  final login = await rustRestoreOrLogin(
    homeserverUrl: _env('MESSIE_MATRIX_HOMESERVER', fallback: 'http://127.0.0.1:8008'),
    username: _env('MESSIE_MATRIX_USERNAME', fallback: 'bridge-tester'),
    password: _env('MESSIE_MATRIX_PASSWORD', fallback: 'bridgeTesterPass!'),
    basePath: storePath,
  );
  if (!login.isOk) {
    stderr.writeln('login failed: ${login.error}');
    exit(2);
  }

  final sync = await rustStartSlidingSync(handle: 'order-smoke', hpSize: 24, lpBatch: 120, hpTimeline: 20, lpTimeline: 8);
  if (!sync.isOk) {
    stderr.writeln('sliding sync start failed: ${sync.error}');
    exit(2);
  }

  final port = ReceivePort('order_smoke');
  final stream = port.asBroadcastStream();
  final reg = await rustRoomListStream(handle: 'order-smoke', port: port.sendPort);
  if (!reg.isOk) {
    stderr.writeln('room list stream failed: ${reg.error}');
    exit(2);
  }

  // Accumulate until we have enough non-null latest_event_ts
  List<Map<String, dynamic>> summaries = const [];
  int nonNullTs = 0;
  final end = DateTime.now().add(const Duration(seconds: 90));
  while (DateTime.now().isBefore(end) && nonNullTs < 10) {
    final payload = await _waitForPayload(stream, const {'sliding_sync_update'}, timeout: const Duration(seconds: 20));
    summaries = _summariesFromPayload(payload);
    nonNullTs = summaries.map<int?>((s) => (s['latest_event_ts'] as num?)?.toInt()).whereType<int>().length;
  }
  port.close();

  if (summaries.isEmpty || nonNullTs == 0) {
    stderr.writeln('no usable summaries (nonNull latest_event_ts=$nonNullTs)');
    exit(3);
  }

  // Print top 20 by real vs mapped vs recency for quick eyeballing
  final rows = summaries.map((s) {
    final name = (s['name'] as String?) ?? '';
    final realTs = (s['latest_event_ts'] as num?)?.toInt();
    final recency = (s['bump_ts'] as num?)?.toInt();
    final mapped = RoomOverviewData.fromJson(s).bumpTs;
    return {'name': name, 'real': realTs, 'mapped': mapped, 'recency': recency};
  }).where((r) => (r['name'] as String).isNotEmpty).toList();

  int score(v) => (v as int?) ?? 0;
  rows.sort((a, b) => score(b['real']).compareTo(score(a['real'])));
  stdout.writeln('top by latest_event_ts:');
  for (final r in rows.take(20)) {
    stdout.writeln('  ${r['name']} real=${r['real']} mapped=${r['mapped']} recency=${r['recency']}');
  }

  rows.sort((a, b) => score(b['mapped']).compareTo(score(a['mapped'])));
  stdout.writeln('top by mapped bumpTs:');
  for (final r in rows.take(20)) {
    stdout.writeln('  ${r['name']} real=${r['real']} mapped=${r['mapped']} recency=${r['recency']}');
  }

  rows.sort((a, b) => score(b['recency']).compareTo(score(a['recency'])));
  stdout.writeln('top by recency bump_ts:');
  for (final r in rows.take(20)) {
    stdout.writeln('  ${r['name']} real=${r['real']} mapped=${r['mapped']} recency=${r['recency']}');
  }
}

