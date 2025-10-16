import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:messie_app/bridge_v2/messie_bridge_v2.dart' as v2;

class _Env {
  final String hs;
  final String recvUser;
  final String recvPass;
  final String? groupRoom;
  final String? dmRoom;
  final String sendUser;
  final String sendPass;
  final String base;
  final String senderBase;
  _Env({
    required this.hs,
    required this.recvUser,
    required this.recvPass,
    required this.groupRoom,
    required this.dmRoom,
    required this.sendUser,
    required this.sendPass,
    required this.base,
    required this.senderBase,
  });
}

_Env? _loadEnv() {
  final env = Platform.environment;
  final hs = env['MESSIE_MATRIX_HOMESERVER'];
  final recvUser = env['MESSIE_MATRIX_USERNAME'];
  final recvPass = env['MESSIE_MATRIX_PASSWORD'];
  final groupRoom = env['MESSIE_GROUP_ROOM'];
  final dmRoom = env['MESSIE_DM_ROOM'];
  final sendUser = env['MESSIE_SENDER_USERNAME'];
  final sendPass = env['MESSIE_SENDER_PASSWORD'];
  final base = env['MESSIE_MATRIX_STORE_BASE'] ?? Directory.systemTemp.createTempSync('messie_v2_recv').path;
  final senderBase = env['MESSIE_MATRIX_STORE_BASE_SENDER'] ?? Directory.systemTemp.createTempSync('messie_v2_sender').path;
  if ([hs, recvUser, recvPass, sendUser, sendPass].any((e) => e == null)) return null;
  return _Env(
    hs: hs!,
    recvUser: recvUser!,
    recvPass: recvPass!,
    groupRoom: groupRoom,
    dmRoom: dmRoom,
    sendUser: sendUser!,
    sendPass: sendPass!,
    base: base,
    senderBase: senderBase,
  );
}

Map<String, dynamic> _parse(String jsonStr) => json.decode(jsonStr) as Map<String, dynamic>;

Future<Map<String, dynamic>> _waitForKinds(
  Stream<dynamic> stream,
  Set<String> kinds, {
  Duration timeout = const Duration(seconds: 60),
  String label = 'v2-notifs',
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
      if (kind.isNotEmpty && kinds.contains(kind)) return decoded;
    } catch (_) {}
  }
  throw StateError('Stream closed before receiving $kinds on $label');
}

// Wait for any SS update tick, then sample summaries to evaluate a predicate.
Future<(int,int)> _waitCountsOnTick({
  required int client,
  required String roomId,
  required Stream<dynamic> stream,
  required bool Function(int n, int h) pred,
  Duration timeout = const Duration(seconds: 60),
}) async {
  final end = DateTime.now().add(timeout);
  while (true) {
    await _waitForKinds(stream, {'sliding_sync_update'}, timeout: const Duration(seconds: 5));
    final s = v2.roomGetSummary(clientHandle: client, roomId: roomId);
    if (!s.success) continue;
    final n = s.notificationCount;
    final h = s.highlightCount;
    if (pred(n, h)) return (n, h);
    if (DateTime.now().isAfter(end)) {
      throw TimeoutException('Timed out waiting for counters', timeout);
    }
  }
}

Future<(int,int)> _waitCountsOnRoomUpdate({
  required int client,
  required String roomId,
  required Stream<dynamic> stream,
  required bool Function(int n, int h) pred,
  Duration timeout = const Duration(seconds: 60),
}) async {
  final end = DateTime.now().add(timeout);
  while (true) {
    final msg = await _waitForKinds(stream, {'sliding_sync_update'}, timeout: const Duration(seconds: 10));
    final rooms = (msg['rooms'] as List?)?.cast<String>() ?? const <String>[];
    if (!rooms.contains(roomId)) {
      if (DateTime.now().isAfter(end)) {
        throw TimeoutException('Timed out waiting for counters', timeout);
      }
      continue;
    }
    final s = v2.roomGetSummary(clientHandle: client, roomId: roomId);
    if (!s.success) continue;
    final n = s.notificationCount;
    final h = s.highlightCount;
    if (pred(n, h)) return (n, h);
    if (DateTime.now().isAfter(end)) {
      throw TimeoutException('Timed out waiting for counters', timeout);
    }
  }
}

void main() {
  final env = _loadEnv();
  if (env == null) {
    test('skipped - env not set for notifications', () {
      expect(true, isTrue, reason: 'Set MESSIE_MATRIX_* and sender/room envs to run');
    }, skip: true);
    return;
  }

  group('v2 notifications and highlights', () {
    test('group mention increments highlight and read clears', () async {
      if (env.groupRoom == null) {
        return; // skip if room not provided
      }
      // Receiver client
      final recvNew = v2.clientCreate(homeserverUrl: env.hs, basePath: env.base);
      expect(recvNew.success, isTrue);
      final recv = recvNew.handle;
      final login = v2.clientLogin(handle: recv, username: env.recvUser, password: env.recvPass);
      expect(login.success, isTrue);
      final recvUserId = login.userId!;


      // Sliding sync create + subscribe to target room
      final ss = v2.ssCreate(
        clientHandle: recv,
        pollTimeoutMs: 2000,
        networkTimeoutMs: 10000,
        enableToDevice: true,
        enableE2ee: true,
      );
      final port = ReceivePort('v2_notif_group');
      final stream = port.asBroadcastStream();
      expect(v2.ssStart(ssHandle: ss, port: port.sendPort.nativePort), isTrue);
      // Ensure we are subscribed to the target room
      expect(v2.ssSubscribeToRooms(ssHandle: ss, roomIds: [env.groupRoom!], timelineLimit: 20, requiredState: const [
        ('m.room.name',''), ('m.room.avatar',''), ('m.room.encryption','')
      ], cancelInFlight: true), isTrue);
      // Wait for ready (stream alive)
      await _waitForKinds(stream, {'sliding_sync_ready'});

      // Subscribe to room count changes
      final roomPort = ReceivePort('room_updates');
      final roomStream = roomPort.asBroadcastStream();
      expect(v2.roomSubscribeToCountChanges(clientHandle: recv, roomId: env.groupRoom!, port: roomPort.sendPort.nativePort), isTrue);

      // Sender client
      final sndNew = v2.clientCreate(homeserverUrl: env.hs, basePath: env.senderBase);
      expect(sndNew.success, isTrue);
      final sender = sndNew.handle;
      final sndLogin = v2.clientLogin(handle: sender, username: env.sendUser, password: env.sendPass);
      expect(sndLogin.success, isTrue);

      // Send mention to receiver
      final body = 'ping $recvUserId ${DateTime.now().millisecondsSinceEpoch}';
      expect(v2.roomSendText(clientHandle: sender, roomId: env.groupRoom!, body: body, replyTo: null),
          isTrue,
          reason: 'room_send_text failed');

      // Give the receiver a moment to process the message through sliding sync
      await Future.delayed(Duration(seconds: 1));

      // Trigger a manual sync to ensure the receiver processes the new message
      v2.clientSyncOnce(handle: recv);

      // Wait for room update indicating notification count change
      await _waitForKinds(roomStream, {'room_update'}, timeout: const Duration(seconds: 30));

      // Check notification counts directly
      final counts = v2.roomGetUnreadCounts(clientHandle: recv, roomId: env.groupRoom!);
      final notifCount = counts.notificationCount;
      final highlightCount = counts.highlightCount;
      expect(notifCount, greaterThan(0), reason: 'Expected notification count > 0, got $notifCount');
      expect(highlightCount, greaterThan(0), reason: 'Expected highlight count > 0, got $highlightCount');

      // Mark read and expect counts to drop to 0
      expect(v2.roomMarkReadUpTo(clientHandle: recv, roomId: env.groupRoom!, eventId: '__LATEST__'), isTrue);

      // Wait for room update indicating counts cleared
      await _waitForKinds(roomStream, {'room_update'}, timeout: const Duration(seconds: 30));

      // Check counts are now 0
      final clearedCounts = v2.roomGetUnreadCounts(clientHandle: recv, roomId: env.groupRoom!);
      final clearedNotifCount = clearedCounts.notificationCount;
      final clearedHighlightCount = clearedCounts.highlightCount;
      expect(clearedNotifCount, equals(0), reason: 'Expected notification count = 0, got $clearedNotifCount');
      expect(clearedHighlightCount, equals(0), reason: 'Expected highlight count = 0, got $clearedHighlightCount');

      port.close();
      roomPort.close();
      expect(v2.ssStop(ssHandle: ss), isTrue);
    });

    test('dm notifies without highlight and read clears', () async {
      if (env.dmRoom == null) {
        return; // skip if room not provided
      }
      // Receiver client
      final recvNew = v2.clientCreate(homeserverUrl: env.hs, basePath: env.base);
      expect(recvNew.success, isTrue);
      final recv = recvNew.handle;
      final recvLogin = v2.clientLogin(handle: recv, username: env.recvUser, password: env.recvPass);
      expect(recvLogin.success, isTrue);


      // Sliding sync + subscribe
      final ss = v2.ssCreate(
        clientHandle: recv,
        pollTimeoutMs: 2000,
        networkTimeoutMs: 10000,
        enableToDevice: true,
        enableE2ee: true,
      );
      final port = ReceivePort('v2_notif_dm');
      final stream = port.asBroadcastStream();
      expect(v2.ssStart(ssHandle: ss, port: port.sendPort.nativePort), isTrue);
      expect(v2.ssSubscribeToRooms(ssHandle: ss, roomIds: [env.dmRoom!], timelineLimit: 20, requiredState: const [
        ('m.room.name',''), ('m.room.avatar',''), ('m.room.encryption','')
      ], cancelInFlight: true), isTrue);
      await _waitForKinds(stream, {'sliding_sync_ready'});

      // Subscribe to room count changes
      final roomPort = ReceivePort('room_updates_dm');
      final roomStream = roomPort.asBroadcastStream();
      expect(v2.roomSubscribeToCountChanges(clientHandle: recv, roomId: env.dmRoom!, port: roomPort.sendPort.nativePort), isTrue);

      // Sender
      final sndNew = v2.clientCreate(homeserverUrl: env.hs, basePath: env.senderBase);
      expect(sndNew.success, isTrue);
      final sender = sndNew.handle;
      final sndLogin = v2.clientLogin(handle: sender, username: env.sendUser, password: env.sendPass);
      expect(sndLogin.success, isTrue);

      // Send DM
      expect(v2.roomSendText(clientHandle: sender, roomId: env.dmRoom!, body: 'dm ${DateTime.now().millisecondsSinceEpoch}', replyTo: null),
          isTrue,
          reason: 'room_send_text (dm) failed');

      // Give the receiver a moment to process the message through sliding sync
      await Future.delayed(Duration(seconds: 1));

      // Trigger a manual sync to ensure the receiver processes the new message
      v2.clientSyncOnce(handle: recv);

      // Wait for room update indicating notification count change
      await _waitForKinds(roomStream, {'room_update'}, timeout: const Duration(seconds: 30));

      // Check notification counts directly (DM should have notif > 0, highlight == 0)
      final counts = v2.roomGetUnreadCounts(clientHandle: recv, roomId: env.dmRoom!);
      final notifCount = counts.notificationCount;
      final highlightCount = counts.highlightCount;
      expect(notifCount, greaterThan(0), reason: 'Expected DM notification count > 0, got $notifCount');
      expect(highlightCount, equals(0), reason: 'Expected DM highlight count = 0, got $highlightCount');

      // Mark read and expect 0/0
      expect(v2.roomMarkReadUpTo(clientHandle: recv, roomId: env.dmRoom!, eventId: '__LATEST__'), isTrue);

      // Wait for room update indicating counts cleared
      await _waitForKinds(roomStream, {'room_update'}, timeout: const Duration(seconds: 30));

      // Check counts are now 0
      final clearedCounts = v2.roomGetUnreadCounts(clientHandle: recv, roomId: env.dmRoom!);
      final clearedNotifCount = clearedCounts.notificationCount;
      final clearedHighlightCount = clearedCounts.highlightCount;
      expect(clearedNotifCount, equals(0), reason: 'Expected DM notification count = 0, got $clearedNotifCount');
      expect(clearedHighlightCount, equals(0), reason: 'Expected DM highlight count = 0, got $clearedHighlightCount');

      port.close();
      roomPort.close();
      expect(v2.ssStop(ssHandle: ss), isTrue);
    });
  });
}
