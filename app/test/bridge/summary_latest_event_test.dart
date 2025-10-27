// ignore_for_file: unnecessary_library_name
@Timeout(Duration(minutes: 3))
library summary_latest_event_test;

import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:messie_app/bridge/messie_bridge.dart';

String _env(String name, {String? fallback}) {
  return Platform.environment[name] ?? fallback ?? '';
}

Future<Map<String, dynamic>> _waitForPayload(
  Stream<dynamic> stream,
  Set<String> kinds, {
  Duration timeout = const Duration(seconds: 45),
}) async {
  final end = DateTime.now().add(timeout);
  await for (final message in stream) {
    if (DateTime.now().isAfter(end)) {
      throw TimeoutException('Timed out waiting for ${kinds.join(', ')}', timeout);
    }
    if (message is! String) continue;
    try {
      final decoded = jsonDecode(message) as Map<String, dynamic>;
      final kind = (decoded['kind'] as String?) ?? '';
      if (kinds.contains(kind)) return decoded;
    } catch (_) {}
  }
  throw StateError('Stream closed before payload');
}

List<Map<String, dynamic>> _summariesFromPayload(Map<String, dynamic> p) {
  final raw = p['summaries'];
  if (raw is List) {
    return raw.cast<Map<dynamic, dynamic>>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
  }
  if (raw is Map) {
    return raw.values
        .cast<Map<dynamic, dynamic>>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
  }
  return const <Map<String, dynamic>>[];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const bool kLog = bool.fromEnvironment('FEED_TEST_LOG', defaultValue: true);
  void log(String msg) { if (kLog) // ignore: avoid_print
    print('[ss-ts] $msg'); }

  group('Sliding Sync timestamp presence (subscribed rooms)', () {
    late LoginData session;

    setUpAll(() async {
      final basePath = _env(
        'MESSIE_BRIDGE_STORE_PATH',
        fallback: '${Directory.systemTemp.path}/messie_bridge_ts_check',
      );
      final dir = Directory(basePath);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      dir.createSync(recursive: true);

      final login = await rustRestoreOrLogin(
        homeserverUrl: _env('MESSIE_MATRIX_HOMESERVER', fallback: 'http://127.0.0.1:8008'),
        username: _env('MESSIE_MATRIX_USERNAME', fallback: 'bridge-tester'),
        password: _env('MESSIE_MATRIX_PASSWORD', fallback: 'bridgeTesterPass!'),
        basePath: basePath,
      );
      expect(login.isOk, isTrue, reason: login.error);
      session = login.data!;
    });

    test('publishes latest_event_ts in subscribed-room updates', () async {
      // Start Sliding Sync with app-like params and subscribe to a window so
      // the SDK feeds EventCache and latest_event is populated.
      final sync = await rustStartSlidingSync(
        handle: 'ts-window',
        hpSize: 24,
        lpBatch: 120,
        hpTimeline: 20,
        lpTimeline: 8,
      );
      expect(sync.isOk, isTrue, reason: sync.error);

      // Register to the room list stream and wait for SS updates that include summaries
      final port = ReceivePort('summary_ts_sdk');
      final stream = port.asBroadcastStream();
      final reg = await rustRoomListStream(handle: 'ts-window', port: port.sendPort);
      expect(reg.isOk, isTrue, reason: reg.error);

      // Subscribe to a window of joined rooms to ensure timelines flow
      final joined = await rustListJoinedRooms();
      expect(joined.isOk, isTrue, reason: joined.error);
      final ids = joined.data!.rooms.take(64).toList(growable: false);
      log('subscribing to ${ids.length} rooms');
      if (ids.isNotEmpty) {
        final sub = await rustSlidingSyncSubscribeRooms(
          handle: 'ts-window',
          roomIds: ids,
          reset: true,
        );
        expect(sub.isOk, isTrue, reason: sub.error);
      }

      // Consume updates until we see at least one summary carrying latest_event_ts
      List<Map<String, dynamic>> summaries = const [];
      int withRealTs = 0;
      int updates = 0;
      final deadline = DateTime.now().add(const Duration(seconds: 120));
      while (DateTime.now().isBefore(deadline)) {
        final payload = await _waitForPayload(stream, const {'sliding_sync_update'}, timeout: const Duration(seconds: 40));
        final s = _summariesFromPayload(payload);
        final roomsLen = (payload['rooms'] is List)
            ? (payload['rooms'] as List).length
            : (payload['rooms'] is Map) ? (payload['rooms'] as Map).length : 0;
        updates += 1;
        log('update #$updates: rooms=$roomsLen summaries=${s.length}');
        if (s.isEmpty) {
          log('  (no summaries in this update; continuing)');
          continue; // skip 0-room updates
        }
        summaries = s;
        withRealTs = summaries
            .map<int?>((m) => (m['latest_event_ts'] as num?)?.toInt())
            .whereType<int>()
            .length;
        final preview = summaries.take(8).map((m) {
          final name = (m['name'] as String?) ?? '';
          final ts = (m['latest_event_ts'] as num?)?.toInt();
          return '$name ts=${ts ?? '-'}';
        }).join(' | ');
        log('  with_ts=$withRealTs sample=[ $preview ]');
        if (withRealTs > 0) break;
        // small settle delay before next iteration
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      port.close();

      expect(summaries, isNotEmpty, reason: 'no summaries after multiple updates');
      expect(withRealTs, greaterThan(0),
          reason:
              'no latest_event_ts observed in Sliding Sync list-mode updates (see logs above)');
    });
  });
}
