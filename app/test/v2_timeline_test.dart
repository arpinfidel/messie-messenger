import 'dart:async';
import 'dart:convert';
import 'dart:ffi'; // for SendPort.nativePort
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

Map<String, dynamic> _parse(String jsonStr) => json.decode(jsonStr) as Map<String, dynamic>;

Future<Map<String, dynamic>> _waitForKinds(
  Stream<dynamic> stream,
  Set<String> kinds, {
  Duration timeout = const Duration(seconds: 60),
  String label = 'v2-timeline',
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

void main() {
  final env = _loadEnv();
  if (env == null) {
    test('skipped - env not set', () {
      expect(true, isTrue, reason: 'Set MESSIE_MATRIX_* env to run');
    }, skip: true);
    return;
  }

  group('v2 timeline + messaging', () {
    test('open → stream → backward → send → read', () async {
      final resNew = v2.clientCreate(homeserverUrl: env.hs, basePath: env.base);
      expect(resNew.success, isTrue, reason: 'client_create failed');
      final client = resNew.handle;

      final resLogin = v2.clientLogin(handle: client, username: env.user, password: env.pass);
      expect(resLogin.success, isTrue, reason: 'login failed');

      // Pick any joined room, or skip if none
      final rooms = v2.clientListJoinedRooms(clientHandle: client);
      if (rooms.isEmpty) {
        expect(true, isTrue, reason: 'No joined rooms to test timeline');
        return;
      }
      final roomId = rooms.first;

      // Open and start timeline stream
      final tlRes = v2.timelineOpen(clientHandle: client, roomId: roomId);
      expect(tlRes.success, isTrue, reason: 'timeline_open failed');
      final tl = tlRes.handle;

      final port = ReceivePort('v2_timeline');
      final stream = port.asBroadcastStream();
      final okStart = v2.timelineStartStreaming(timelineHandle: tl, port: port.sendPort.nativePort);
      expect(okStart, isTrue, reason: 'timeline_start_streaming failed');

      // Expect initial snapshot
      final snap = await _waitForKinds(stream, {'timeline_snapshot'});
      expect(snap['kind'], equals('timeline_snapshot'));

      // Load backward small page
      expect(v2.timelineLoadBackward(timelineHandle: tl, limit: 5), isTrue,
          reason: 'timeline_load_backward failed');

      // Send a message and expect append
      expect(
        v2.roomSendText(clientHandle: client, roomId: roomId, body: 'hi from dart', replyTo: null),
        isTrue,
        reason: 'room_send_text failed',
      );

      final next = await _waitForKinds(stream, {'timeline_append'});
      expect(next['kind'], equals('timeline_append'));

      // Pre-read unread counts via FFI (avoid JSON summaries here)
      final preCounts = v2.roomGetUnreadCounts(clientHandle: client, roomId: roomId);
      final preCount = preCounts.notificationCount;

      // Mark read up to latest
      expect(
        v2.roomMarkReadUpTo(clientHandle: client, roomId: roomId, eventId: '__LATEST__'),
        isTrue,
        reason: 'room_mark_read_up_to failed',
      );

      // Post-read unread counts via typed FFI
      final postCounts = v2.roomGetUnreadCounts(clientHandle: client, roomId: roomId);
      final postCount = postCounts.notificationCount;

      // Assert counts do not increase; if there were unread, they should reduce
      expect(postCount <= preCount, isTrue, reason: 'notification_count did not decrease or stay the same');
      if (preCount > 0) {
        expect(postCount < preCount, isTrue, reason: 'notification_count did not reduce after mark read');
      }

      port.close();
    });
  });
}
