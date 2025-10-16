import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:messie_app/bridge_v2/messie_bridge_v2.dart' as v2;

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
  final base = env['MESSIE_MATRIX_STORE_BASE'] ?? Directory.systemTemp.createTempSync('messie_v2_perf').path;
  if (hs == null || user == null || pass == null) return null;
  return _Env(hs, user, pass, base);
}

Future<Map<String, dynamic>> _waitForKind(Stream<dynamic> stream, String kind, {Duration timeout = const Duration(seconds: 30)}) async {
  final end = DateTime.now().add(timeout);
  await for (final msg in stream) {
    if (DateTime.now().isAfter(end)) {
      throw TimeoutException('Timed out waiting for $kind', timeout);
    }
    if (msg is! String) continue;
    try {
      final m = json.decode(msg) as Map<String, dynamic>;
      if (m['kind'] == kind) return m;
    } catch (_) {}
  }
  throw StateError('Stream ended before $kind');
}

void main() {
  final env = _loadEnv();
  final runPerf = Platform.environment['MESSIE_RUN_PERF'] == '1';
  if (env == null || !runPerf) {
    test('skipped - perf not enabled', () {
      expect(true, isTrue, reason: 'Set MESSIE_MATRIX_* and MESSIE_RUN_PERF=1 to run');
    }, skip: true);
    return;
  }

  test('sliding_sync_performance', () async {
    final swTotal = Stopwatch()..start();

    final swCreate = Stopwatch()..start();
    final resNew = v2.clientCreate(homeserverUrl: env!.hs, basePath: env.base);
    swCreate.stop();
    expect(resNew.success, isTrue);

    final client = resNew.handle;
    final swLogin = Stopwatch()..start();
    final login = v2.clientLogin(handle: client, username: env.user, password: env.pass);
    swLogin.stop();
    expect(login.success, isTrue);

    // Create SS
    final swSs = Stopwatch()..start();
    final ss = v2.ssCreate(clientHandle: client, pollTimeoutMs: 0, networkTimeoutMs: 0, enableE2ee: true, enableToDevice: true);
    swSs.stop();

    // Start streaming
    final port = ReceivePort('v2_perf_ss');
    final stream = port.asBroadcastStream();
    final swStart = Stopwatch()..start();
    expect(v2.ssStart(ssHandle: ss, port: port.sendPort.nativePort), isTrue);
    await _waitForKind(stream, 'sync_update');
    swStart.stop();

    // Pick first room
    final rooms = v2.clientListJoinedRooms(clientHandle: client);
    if (rooms.isNotEmpty) {
      final roomId = rooms.first;
      final swTl = Stopwatch()..start();
      final tlRes = v2.timelineOpen(clientHandle: client, roomId: roomId);
      expect(tlRes.success, isTrue);
      final tl = tlRes.handle;
      expect(v2.timelineStartStreaming(timelineHandle: tl, port: port.sendPort.nativePort), isTrue);
      await _waitForKind(stream, 'timeline_snapshot');
      swTl.stop();

      final swBack = Stopwatch()..start();
      expect(v2.timelineLoadBackward(timelineHandle: tl, limit: 5), isTrue);
      swBack.stop();

      // Basic thresholds (conservative to avoid flakiness on CI)
      expect(swTl.elapsedMilliseconds, lessThan(1500));
      expect(swBack.elapsedMilliseconds, lessThan(1500));
    }

    // Conservative sanity thresholds
    expect(swCreate.elapsedMilliseconds, lessThan(2000));
    expect(swLogin.elapsedMilliseconds, lessThan(3000));
    expect(swSs.elapsedMilliseconds, lessThan(1500));
    expect(swStart.elapsedMilliseconds, lessThan(4000));

    swTotal.stop();
    // Entire routine within a broad bound
    expect(swTotal.elapsedMilliseconds, lessThan(15000));
    port.close();
  });
}

