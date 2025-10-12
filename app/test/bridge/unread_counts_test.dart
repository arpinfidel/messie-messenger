@Timeout(Duration(minutes: 2))
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:test_api/test_api.dart' show Timeout; // for @Timeout
import 'package:messie_app/bridge/messie_bridge.dart';
import 'package:dio/dio.dart' as dio;

String _env(String name, {String? fallback}) {
  return Platform.environment[name] ?? fallback ?? '';
}

Future<Map<String, dynamic>> _waitForPayload(
  Stream<dynamic> stream,
  Set<String> kinds, {
  Duration timeout = const Duration(seconds: 30),
  String label = 'stream',
}) async {
  final completer = Completer<Map<String, dynamic>>();
  late StreamSubscription sub;
  Timer? timer;
  void finishWithTimeout() {
    if (!completer.isCompleted) {
      sub.cancel();
      completer.completeError(
        TimeoutException('Timed out waiting for $kinds on $label', timeout),
      );
    }
  }

  timer = Timer(timeout, finishWithTimeout);
  sub = stream.listen((message) {
    if (completer.isCompleted) return;
    if (message is! String) return;
    try {
      final decoded = jsonDecode(message) as Map<String, dynamic>;
      final kind = (decoded['kind'] as String?) ?? '';
      if (kinds.contains(kind)) {
        timer?.cancel();
        sub.cancel();
        completer.complete(decoded);
      }
    } catch (_) {
      // ignore and keep listening
    }
  }, onError: (error) {
    if (!completer.isCompleted) {
      timer?.cancel();
      completer.completeError(error);
    }
  });

  return completer.future;
}

Map<String, dynamic> _decodeEvent(String raw) => jsonDecode(raw) as Map<String, dynamic>;

Future<String?> _matrixLoginToken({
  required Uri homeserverUrl,
  required String username,
  required String password,
}) async {
  final client = dio.Dio(dio.BaseOptions(baseUrl: homeserverUrl.toString()));
  try {
    final resp = await client.post('/_matrix/client/v3/login', data: {
      'type': 'm.login.password',
      'identifier': {'type': 'm.id.user', 'user': username},
      'password': password,
    });
    return (resp.data is Map<String, dynamic>) ? (resp.data['access_token'] as String?) : null;
  } catch (_) {
    return null;
  }
}

Future<String?> _matrixFetchLatestEventId({
  required Uri homeserverUrl,
  required String accessToken,
  required String roomId,
}) async {
  final client = dio.Dio(dio.BaseOptions(baseUrl: homeserverUrl.toString(), headers: {
    'Authorization': 'Bearer $accessToken',
  }));
  try {
    final resp = await client.get(
      '/_matrix/client/v3/rooms/${Uri.encodeComponent(roomId)}/messages',
      queryParameters: {'dir': 'b', 'limit': 1},
    );
    final data = resp.data;
    if (data is Map<String, dynamic>) {
      final chunk = data['chunk'];
      if (chunk is List && chunk.isNotEmpty) {
        final first = chunk.first;
        if (first is Map<String, dynamic>) {
          return first['event_id'] as String?;
        }
      }
    }
    return null;
  } catch (_) {
    return null;
  }
}

Future<String?> _matrixSendText({
  required Uri homeserverUrl,
  required String accessToken,
  required String roomId,
  required String body,
}) async {
  final client = dio.Dio(dio.BaseOptions(baseUrl: homeserverUrl.toString(), headers: {
    'Authorization': 'Bearer $accessToken',
    'Content-Type': 'application/json',
  }));
  final txn = DateTime.now().microsecondsSinceEpoch.toString();
  try {
    final resp = await client.put('/_matrix/client/v3/rooms/${Uri.encodeComponent(roomId)}/send/m.room.message/$txn', data: {
      'msgtype': 'm.text',
      'body': body,
    });
    if (resp.statusCode != null && resp.statusCode! ~/ 100 == 2) {
      final data = resp.data;
      if (data is Map<String, dynamic>) {
        return data['event_id'] as String?;
      }
      return '';
    }
    return null;
  } catch (_) {
    return null;
  }
}

Map<String, dynamic>? _readSeedState() {
  final candidates = <String>{
    _env('MESSIE_SEED_STATE_FILE'),
    '../scripts/matrix/.state/seed_state.json',
    '../scripts/matrix/scripts/matrix/.state/seed_state.json',
  }.where((p) => p.isNotEmpty).toList();
  for (final p in candidates) {
    final f = File(p);
    if (!f.existsSync()) continue;
    try {
      final raw = f.readAsStringSync();
      final json = jsonDecode(raw) as Map<String, dynamic>;
      if (json['rooms'] is Map<String, dynamic>) return json;
    } catch (_) {}
  }
  return null;
}

({String roomId, String creator})? _pickRoomNotCreatedBy(String primaryMxid) {
  final state = _readSeedState();
  if (state == null) return null;
  final rooms = (state['rooms'] as Map<String, dynamic>);
  for (final entry in rooms.values) {
    if (entry is Map<String, dynamic>) {
      final rid = entry['roomId'] as String?;
      final creator = entry['creator'] as String?; // may be absent
      if (rid != null && rid.isNotEmpty && creator != null && creator.isNotEmpty && creator != primaryMxid) {
        return (roomId: rid, creator: creator);
      }
    }
  }
  return null;
}

String _passwordForUserLocalpart(String localpart) {
  final adminUser = _env('MESSIE_MATRIX_ADMIN_USERNAME', fallback: 'bridge-admin');
  final adminPass = _env('MESSIE_MATRIX_ADMIN_PASSWORD', fallback: 'bridgeAdminPass!');
  final userPass = _env('MESSIE_MATRIX_PASSWORD', fallback: 'bridgeTesterPass!');
  return localpart == adminUser ? adminPass : userPass;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Sliding Sync handle must be <16 chars.
  const slidingHandle = 'unread';
  late String storePath;
  late Uri homeserverUrl;
  late String username;
  late String password;
  late LoginData session;
  late List<String> roomIds;
  ReceivePort? roomListPort;
  Stream<dynamic>? roomListStream;

  setUpAll(() async {
    storePath = _env(
      'MESSIE_BRIDGE_STORE_PATH',
      fallback: '${Directory.systemTemp.path}/messie_bridge_unread',
    );
    final storeDir = Directory(storePath);
    if (storeDir.existsSync()) {
      storeDir.deleteSync(recursive: true);
    }
    storeDir.createSync(recursive: true);

    homeserverUrl = Uri.parse(
      _env('MESSIE_MATRIX_HOMESERVER', fallback: 'http://127.0.0.1:8008'),
    );
    username = _env('MESSIE_MATRIX_USERNAME', fallback: 'bridge-tester');
    password = _env('MESSIE_MATRIX_PASSWORD', fallback: 'bridgeTesterPass!');

    final loginResult = await rustRestoreOrLogin(
      homeserverUrl: homeserverUrl.toString(),
      username: username,
      password: password,
      basePath: storePath,
    );
    expect(loginResult.isOk, isTrue, reason: loginResult.error);
    session = loginResult.data!;

    final syncResult = await rustStartSlidingSync(
      handle: slidingHandle,
      hpSize: 24,
      lpBatch: 120,
      hpTimeline: 10,
      lpTimeline: 4,
    );
    expect(syncResult.isOk, isTrue, reason: syncResult.error);

    roomListPort = ReceivePort('unread_room_list');
    roomListStream = roomListPort!.asBroadcastStream();
    final streamResult = await rustRoomListStream(
      handle: slidingHandle,
      port: roomListPort!.sendPort,
    );
    expect(streamResult.isOk, isTrue, reason: streamResult.error);

    await _waitForPayload(
      roomListStream!,
      <String>{'sliding_sync_ready'},
      timeout: const Duration(seconds: 60),
      label: 'room-list',
    );

    // Poll joined rooms until we have at least 1
    final end = DateTime.now().add(const Duration(seconds: 60));
    roomIds = <String>[];
    while (DateTime.now().isBefore(end)) {
      final res = await rustListJoinedRooms();
      expect(res.isOk, isTrue, reason: res.error);
      if (res.data!.rooms.isNotEmpty) { roomIds = res.data!.rooms; break; }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    expect(roomIds, isNotEmpty, reason: 'Need at least 1 joined room');
  });

  tearDownAll(() async {
    roomListPort?.close();
    await rustLogout(basePath: storePath);
  });

  test('unread counts are exposed and clear on read', () async {
    // Find a room with unread notifications (try for a short window)
    String? target;
    int beforeCount = 0;
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (DateTime.now().isBefore(deadline) && target == null) {
      for (final id in roomIds) {
        final ov = await rustRoomOverview(roomId: id);
        if (ov.isOk) {
          final n = ov.data!.notificationCount;
          if (n > 0) { target = id; beforeCount = n; break; }
        }
      }
      if (target == null) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    }

    String? injectedEventId;
    if (target == null) {
      // Deterministic injection using seed state: pick a room not created by the
      // primary user and send as its creator.
      final pick = _pickRoomNotCreatedBy(session.userId);
      if (pick != null) {
        final creatorMxid = pick.creator; // format @localpart:server
        final colon = creatorMxid.indexOf(':');
        final localEnd = colon > 0 ? colon : creatorMxid.length;
        final localpart = creatorMxid.substring(1, localEnd); // drop '@'
        final pass = _passwordForUserLocalpart(localpart);
        final token = await _matrixLoginToken(
          homeserverUrl: homeserverUrl,
          username: localpart,
          password: pass,
        );
        if (token != null) {
          final eid = await _matrixSendText(
            homeserverUrl: homeserverUrl,
            accessToken: token,
            roomId: pick.roomId,
            body: 'Seeded unread ${DateTime.now().millisecondsSinceEpoch}',
          );
          if (eid != null) {
            injectedEventId = eid.isEmpty ? null : eid;
            await Future<void>.delayed(const Duration(seconds: 2));
            final ov = await rustRoomOverview(roomId: pick.roomId);
            if (ov.isOk && ov.data!.notificationCount > 0) {
              target = pick.roomId;
              beforeCount = ov.data!.notificationCount;
            }
          }
        }
      }
      // Fallback: try generic secondary user into the first joined room.
      if (target == null) {
        final senderUser = _env('MESSIE_UNREAD_SENDER_USERNAME', fallback: 'bridge-tester2');
        final senderPass = _env('MESSIE_UNREAD_SENDER_PASSWORD', fallback: 'bridgeTesterPass!');
        final token = await _matrixLoginToken(
          homeserverUrl: homeserverUrl,
          username: senderUser,
          password: senderPass,
        );
        if (token != null && roomIds.isNotEmpty) {
          final eid = await _matrixSendText(
            homeserverUrl: homeserverUrl,
            accessToken: token,
            roomId: roomIds.first,
            body: 'Inject unread ${DateTime.now().millisecondsSinceEpoch}',
          );
          if (eid != null) {
            injectedEventId = eid.isEmpty ? null : eid;
            await Future<void>.delayed(const Duration(seconds: 2));
            for (final id in roomIds) {
              final ov = await rustRoomOverview(roomId: id);
              if (ov.isOk && ov.data!.notificationCount > 0) {
                target = id;
                beforeCount = ov.data!.notificationCount;
                break;
              }
            }
          }
        }
      }
      // If still not found, fail: we couldn't create an unread, so the
      // feature can't be validated.
      if (target == null) {
        fail('Failed to create an unread message via seed-state creator and fallback sender; cannot validate unread counts');
      }
    }

    // Helper: fetch freshest latest id via timeline snapshot (no HTTP in flutter_test)
    Future<String?> _latestFromTimeline(String roomId) async {
      final open = await rustOpenRoom(handle: slidingHandle, roomId: roomId);
      expect(open.isOk, isTrue, reason: open.error);
      final port = ReceivePort('unread_timeline_probe');
      final stream = port.asBroadcastStream();
      final reg = await rustTimelineStream(handle: slidingHandle, roomId: roomId, port: port.sendPort);
      expect(reg.isOk, isTrue, reason: reg.error);
      final snap = await _waitForPayload(stream, <String>{'timeline_snapshot', 'timeline_initial'}, label: 'timeline');
      port.close();
      final evs = (snap['events'] as List<dynamic>).cast<String>().map(_decodeEvent).toList();
      return evs.isNotEmpty ? (evs.last['event_id'] as String?) : null;
    }

    // Baseline-clear existing unread in the chosen room (if any)
    // Use core-side __LATEST__ sentinel to resolve server-latest and mark it read.
    final baseAck = await rustMarkReadUpTo(roomId: target!, eventId: '__LATEST__');
    expect(baseAck.isOk, isTrue, reason: baseAck.error);
    // Wait a short moment for SS to deliver updated counts, then poll until 0
    try {
      await _waitForPayload(roomListStream!, <String>{'sliding_sync_update'}, timeout: const Duration(seconds: 5), label: 'room-list');
    } catch (_) {}
    final baseEnd = DateTime.now().add(const Duration(seconds: 8));
    var baseZero = false;
    while (DateTime.now().isBefore(baseEnd)) {
      final ov = await rustRoomOverview(roomId: target!);
      expect(ov.isOk, isTrue, reason: ov.error);
      final n = ov.data!.notificationCount;
      // ignore: avoid_print
      print('[unread] baseline polling notif_count=$n');
      if (n == 0) { baseZero = true; break; }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    expect(baseZero, isTrue, reason: 'Failed to baseline unread to 0 before test');

    // Inject a fresh unread deterministically if we didn't already earlier
    if (injectedEventId == null) {
      final pick = _pickRoomNotCreatedBy(session.userId) ?? (roomIds.isNotEmpty ? (roomId: roomIds.first, creator: '@bridge-tester2:${homeserverUrl.host}') : null);
      if (pick != null) {
        final creatorMxid = pick.creator;
        final colon = creatorMxid.indexOf(':');
        final localEnd = colon > 0 ? colon : creatorMxid.length;
        final localpart = creatorMxid.substring(1, localEnd);
        final pass = _passwordForUserLocalpart(localpart);
        final tok = await _matrixLoginToken(homeserverUrl: homeserverUrl, username: localpart, password: pass);
        if (tok != null) {
          injectedEventId = await _matrixSendText(
            homeserverUrl: homeserverUrl,
            accessToken: tok,
            roomId: target!,
            body: 'Post-baseline unread ${DateTime.now().millisecondsSinceEpoch}',
          );
        }
      }
      // allow SS to tick this new unread in
      await Future<void>.delayed(const Duration(seconds: 2));
    }

    // Now fetch freshest latest again and pick the best id to ack
    final eventIdToAck = injectedEventId ?? '__LATEST__';
    expect(eventIdToAck, isNotNull, reason: 'Need event id to send read receipt');

    final ack = await rustMarkReadUpTo(roomId: target!, eventId: eventIdToAck!);
    expect(ack.isOk, isTrue, reason: ack.error);

    // Wait for a Sliding Sync update so unread counters have a chance to
    // refresh before we start polling the overview.
    try {
      await _waitForPayload(
        roomListStream!,
        <String>{'sliding_sync_update'},
        timeout: const Duration(seconds: 5),
        label: 'room-list',
      );
    } catch (_) {
      // best-effort; continue to polling below
    }

    // Poll until unread count reduces to 0 (strict) within a short timeout
    final end = DateTime.now().add(const Duration(seconds: 12));
    var cleared = false;
    var lastCnt = beforeCount;
    while (DateTime.now().isBefore(end)) {
      final after = await rustRoomOverview(roomId: target!);
      expect(after.isOk, isTrue, reason: after.error);
      final cnt = after.data!.notificationCount;
      // Diagnostic log to see how counts evolve while polling
      // ignore: avoid_print
      print('[unread] polling notif_count=$cnt (before=$beforeCount)');
      if (cnt == 0) { cleared = true; break; }
      lastCnt = cnt;
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    expect(cleared, isTrue, reason: 'Unread count did not clear to 0 after fully-read receipt (last=$lastCnt, before=$beforeCount)');
  });
}
