import 'dart:async';
import 'dart:ffi'; // for SendPort.nativePort extension
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
  final base = env['MESSIE_MATRIX_STORE_BASE'] ?? Directory.systemTemp.createTempSync('messie_v2').path;
  if (hs == null || user == null || pass == null) return null;
  return _Env(hs, user, pass, base);
}


void main() {
  group('v2 thin + errors (offline)', () {
    test('client_create invalid URL returns false', () {
      final base = Directory.systemTemp.createTempSync('messie_v2_offline').path;
      final res = v2.clientCreate(homeserverUrl: 'not a url', basePath: base);
      expect(res.success, isFalse);
    });

    test('unknown sliding sync handle returns false', () {
      final ok = v2.ssStart(ssHandle: 123456789, port: 0);
      expect(ok, isFalse);
    });

    test('room_get_summary unknown handle returns false', () {
      final res = v2.roomGetSummary(clientHandle: 0, roomId: "!unknown:example.org");
      expect(res.success, isFalse);
    });
  });

  group('v2 login + sliding sync', () {
    final env = _loadEnv();
    if (env == null) {
      test('skipped - env not set', () {
        expect(true, isTrue, reason: 'Set MESSIE_MATRIX_* env to run');
      }, skip: true);
      return;
    }

    test('login ok', () {
      final resNew = v2.clientCreate(homeserverUrl: env.hs, basePath: env.base);
      expect(resNew.success, isTrue, reason: 'client_create failed');
      final handle = resNew.handle;

      final resLogin = v2.clientLogin(handle: handle, username: env.user, password: env.pass);
      expect(resLogin.success, isTrue, reason: 'login failed');
      expect((resLogin.userId ?? '').isNotEmpty, isTrue);

      // Do not logout; keep session persisted to avoid frequent logins.
    });

    test('sliding sync start/stop (no port)', () async {
      final resNew = v2.clientCreate(homeserverUrl: env.hs, basePath: env.base);
      expect(resNew.success, isTrue, reason: 'client_create failed');
      final client = resNew.handle;
      final resLogin = v2.clientLogin(handle: client, username: env.user, password: env.pass);
      expect(resLogin.success, isTrue, reason: 'login failed');

      final ss = v2.ssCreate(
        clientHandle: client,
        enableToDevice: false,
        pollTimeoutMs: 0,
        networkTimeoutMs: 0,
      );
      final okStart = v2.ssStart(ssHandle: ss, port: 0);
      expect(okStart, isTrue, reason: 'start failed');
      final okStop = v2.ssStop(ssHandle: ss);
      expect(okStop, isTrue, reason: 'stop failed');
    });

    Future<Map<String, dynamic>> waitForKinds(
      Stream<dynamic> stream,
      Set<String> kinds, {
      Duration timeout = const Duration(seconds: 60),
      String label = 'v2-room-list',
    }) async {
      final end = DateTime.now().add(timeout);
      await for (final message in stream) {
        if (DateTime.now().isAfter(end)) {
          throw TimeoutException('Timed out waiting for $kinds on $label', timeout);
        }
        if (message is! String) continue;
        try {
          final decoded = json.decode(message) as Map<String, dynamic>;
          final kind = (decoded['kind'] as String?) ?? '';
          if (kind.isNotEmpty) {
            if (kinds.contains(kind)) return decoded;
          }
        } catch (_) {
          // ignore parse errors and continue
        }
      }
      throw StateError('Stream closed before receiving $kinds on $label');
    }

    test('sliding sync emits ready + update', () async {
      final resNew = v2.clientCreate(homeserverUrl: env.hs, basePath: env.base);
      expect(resNew.success, isTrue, reason: 'client_create failed');
      final client = resNew.handle;
      final resLogin = v2.clientLogin(handle: client, username: env.user, password: env.pass);
      expect(resLogin.success, isTrue, reason: 'login failed');

      final ss = v2.ssCreate(
        clientHandle: client,
        enableToDevice: false,
        pollTimeoutMs: 0,
        networkTimeoutMs: 0,
      );

      final port = ReceivePort('v2_room_list_probe');
      final stream = port.asBroadcastStream();
      // Obtain native port id for Rust stream callbacks.
      final nativePort = port.sendPort.nativePort;
      final okStart = v2.ssStart(ssHandle: ss, port: nativePort);
      expect(okStart, isTrue, reason: 'start failed');

      // 1) Expect ready
      final ready = await waitForKinds(stream, {'sliding_sync_ready'});
      expect(ready['kind'], equals('sliding_sync_ready'));

      // 2) Expect at least one update or surface stream error
      final next = await waitForKinds(stream, {'sliding_sync_update', 'sliding_sync_error'});
      final kind = next['kind'] as String? ?? '';
      if (kind == 'sliding_sync_error') {
        final msg = next['message'] as String? ?? '<no message>';
        fail('sliding sync stream error: $msg');
      }
      expect(kind, equals('sliding_sync_update'));

      port.close();
      final okStop = v2.ssStop(ssHandle: ss);
      expect(okStop, isTrue, reason: 'stop failed');
    });

    test('subscribe subset + expire_session keeps updates flowing', () async {
      final resNew = v2.clientCreate(homeserverUrl: env.hs, basePath: env.base);
      expect(resNew.success, isTrue, reason: 'client_create failed');
      final client = resNew.handle;

      final resLogin = v2.clientLogin(handle: client, username: env.user, password: env.pass);
      expect(resLogin.success, isTrue, reason: 'login failed');

      final ss = v2.ssCreate(
        clientHandle: client,
        enableToDevice: false,
        pollTimeoutMs: 0,
        networkTimeoutMs: 0,
      );
      final port = ReceivePort('v2_room_list_subscribe');
      final stream = port.asBroadcastStream();
      final okStart = v2.ssStart(ssHandle: ss, port: port.sendPort.nativePort);
      expect(okStart, isTrue);

      // Wait for ready/update once
      await waitForKinds(stream, {'sliding_sync_ready'});
      await waitForKinds(stream, {'sliding_sync_update', 'sliding_sync_error'});

      // Subscribe to subset of joined rooms if any
      final rooms = v2.clientListJoinedRooms(clientHandle: client);
      if (rooms.isNotEmpty) {
        if (rooms.isNotEmpty) {
          final subset = rooms.take(5).toList();
          final okSub = v2.ssSubscribeToRooms(
            ssHandle: ss,
            roomIds: subset,
            timelineLimit: 20,
            requiredState: const [
              ('m.room.name', ''),
              ('m.room.avatar', ''),
              ('m.room.encryption', ''),
            ],
            cancelInFlight: true,
          );
          expect(okSub, isTrue);
        }
      }

      // Expire session and ensure we still receive an update or error
      expect(v2.ssExpireSession(ssHandle: ss), isTrue);
      final next = await waitForKinds(stream, {'sliding_sync_update', 'sliding_sync_error'}, timeout: const Duration(seconds: 30));
      final kind = next['kind'] as String? ?? '';
      if (kind == 'sliding_sync_error') {
        final msg = next['message'] as String? ?? '<no message>';
        fail('sliding sync stream error after expire_session: $msg');
      }
      expect(kind, equals('sliding_sync_update'));
      port.close();
      expect(v2.ssStop(ssHandle: ss), isTrue);
    });

    test('joined rooms -> batched room summaries (subset)', () async {
      final resNew = v2.clientCreate(homeserverUrl: env.hs, basePath: env.base);
      expect(resNew.success, isTrue, reason: 'client_create failed');
      final client = resNew.handle;
      final resLogin = v2.clientLogin(handle: client, username: env.user, password: env.pass);
      expect(resLogin.success, isTrue, reason: 'login failed');

      // Fetch joined rooms (typed)
      final rooms = v2.clientListJoinedRooms(clientHandle: client);
      // It’s fine if there are no rooms on a fresh account — just skip
      if (rooms.isEmpty) {
        expect(true, isTrue, reason: 'No joined rooms to summarize');
        return;
      }

      final subset = rooms.take(rooms.length < 3 ? rooms.length : 3).toList();
      for (final id in subset) {
        final s = v2.roomGetSummary(clientHandle: client, roomId: id);
        expect(s.success, isTrue, reason: 'room_get_summary failed for $id');
        expect(s.roomId, isA<String?>());
        expect(s.name, isA<String?>());
      }
    });
  });
}
