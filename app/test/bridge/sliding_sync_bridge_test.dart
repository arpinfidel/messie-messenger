@Timeout(Duration(minutes: 2))
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:test_api/test_api.dart' show Timeout; // for @Timeout
import 'package:messie_app/bridge/messie_bridge.dart';

String _env(String name, {String? fallback}) {
  return Platform.environment[name] ?? fallback ?? '';
}

const String _bundledRecoveryKey =
    'EsTn sWPt RKU1 Wsth pLSe G32f jA3h uk4i gWYc kMz1 9w4o ruED';

Future<Map<String, dynamic>> _waitForPayload(
  Stream<dynamic> stream,
  Set<String> kinds, {
  Duration timeout = const Duration(seconds: 30),
  String label = 'stream',
}) async {
  final end = DateTime.now().add(timeout);
  final recentKinds = <String>[];
  final recentSamples = <Map<String, dynamic>>[];
  await for (final message in stream) {
    if (DateTime.now().isAfter(end)) {
      print('[$label] recent kinds before timeout: $recentKinds');
      if (recentSamples.isNotEmpty) {
        final sample = jsonEncode(recentSamples.last);
        print('[$label] last sample payload: $sample');
      }
      throw TimeoutException('Timed out waiting for payload on $label', timeout);
    }

    if (message is! String) {
      print('[$label] non-string message: ${message.runtimeType}');
      continue;
    }
    try {
      final decoded = jsonDecode(message) as Map<String, dynamic>;
      final kind = (decoded['kind'] as String?) ?? '';
      if (kind.isNotEmpty) {
        final ts = DateTime.now().toIso8601String();
        // Print concise summary for known payloads.
        if (kind == 'sliding_sync_update') {
          final lists = decoded['lists'];
          final rooms = decoded['rooms'];
          final listsLen = (lists is List) ? lists.length : 0;
          final roomsLen = (rooms is List) ? rooms.length : 0;
          print('[$label][$ts] kind=$kind lists=$listsLen rooms=$roomsLen');
        } else {
          print('[$label][$ts] kind=$kind');
        }
        recentKinds.add(kind);
        if (recentKinds.length > 20) recentKinds.removeAt(0);
      } else {
        print('[$label] decoded payload missing kind: ${jsonEncode(decoded)}');
      }
      recentSamples.add(decoded);
      if (recentSamples.length > 3) recentSamples.removeAt(0);

      if (kinds.contains(kind)) {
        return decoded;
      }
    } catch (err) {
      print('[$label] failed to decode message: $err');
    }
  }
  throw StateError('Stream closed before payload was received on $label');
}

Future<List<String>> _waitForJoinedRooms({
  Duration timeout = const Duration(seconds: 30),
  int minCount = 1,
}) async {
  final deadline = DateTime.now().add(timeout);
  List<String> rooms = const <String>[];
  var lastCount = -1;
  var lastLog = DateTime.fromMillisecondsSinceEpoch(0);

  while (DateTime.now().isBefore(deadline)) {
    final result = await rustListJoinedRooms();
    expect(result.isOk, isTrue, reason: result.error);
    rooms = result.data!.rooms;
    if (rooms.length != lastCount &&
        DateTime.now().difference(lastLog) > const Duration(seconds: 1)) {
      print('joined rooms: ${rooms.length}/${minCount}');
      lastCount = rooms.length;
      lastLog = DateTime.now();
    }
    if (rooms.length >= minCount) {
      return rooms;
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }

  print('joined rooms before timeout: ${rooms.length}/${minCount}');
  expect(
    rooms,
    hasLength(greaterThanOrEqualTo(minCount)),
    reason:
        'Expected at least $minCount seeded rooms (timed out after ${timeout.inSeconds}s)',
  );
  return rooms;
}

String? _loadRecoveryKey() {
  final envKey = _env('MESSIE_MATRIX_RECOVERY_KEY');
  if (envKey.isNotEmpty) {
    return envKey.trim();
  }

  // Probe common locations for the generated recovery key file.
  final candidates = <String>{
    _env('MESSIE_MATRIX_RECOVERY_FILE'),
    // Canonical location when running seeder from repo root.
    '../scripts/matrix/.state/recovery_key.json',
    // Fallback when seeder resolves state dir relative to scripts/matrix.
    '../scripts/matrix/scripts/matrix/.state/recovery_key.json',
  }.where((p) => p.isNotEmpty).toList();

  for (final candidate in candidates) {
    final file = File(candidate);
    if (!file.existsSync()) continue;
    try {
      final raw = file.readAsStringSync().trim();
      // Accept either a JSON object with `recovery_key` or a plain key string.
      if (raw.startsWith('{')) {
        final parsed = jsonDecode(raw) as Map<String, dynamic>;
        final key = parsed['recovery_key'] as String?;
        if (key != null && key.trim().isNotEmpty) {
          return key.trim();
        }
      } else if (raw.isNotEmpty) {
        return raw;
      }
    } catch (_) {
      // Try next candidate
    }
  }

  final fallback = _bundledRecoveryKey.trim();
  return fallback.isNotEmpty ? fallback : null;
}

Map<String, dynamic> _decodeEvent(String raw) {
  return jsonDecode(raw) as Map<String, dynamic>;
}

Map<String, String>? _loadSeedState() {
  final candidates = <String>{
    _env('MESSIE_SEED_STATE_FILE'),
    '../scripts/matrix/.state/seed_state.json',
    '../scripts/matrix/scripts/matrix/.state/seed_state.json',
  }.where((p) => p.isNotEmpty).toList();

  for (final candidate in candidates) {
    final file = File(candidate);
    if (!file.existsSync()) continue;
    try {
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final rooms = json['rooms'];
      if (rooms is Map<String, dynamic>) {
        final map = <String, String>{};
        rooms.forEach((alias, entry) {
          final roomId = (entry as Map<String, dynamic>)['roomId'] as String?;
          if (roomId != null && roomId.isNotEmpty) {
            map[alias] = roomId;
          }
        });
        if (map.isNotEmpty) return map;
      }
    } catch (_) {
      // try next candidate
    }
  }
  return null;
}

int _expectedSeededRoomCount() {
  // Allow explicit override for CI or custom seeds.
  final env = _env('MESSIE_SEEDED_ROOM_COUNT');
  if (env.isNotEmpty) {
    final parsed = int.tryParse(env);
    if (parsed != null && parsed > 0) return parsed;
  }

  // Probe common locations for the seeder state file.
  final candidates = <String>{
    _env('MESSIE_SEED_STATE_FILE'),
    '../scripts/matrix/.state/seed_state.json',
    '../scripts/matrix/scripts/matrix/.state/seed_state.json',
  }.where((p) => p.isNotEmpty).toList();

  for (final candidate in candidates) {
    final file = File(candidate);
    if (!file.existsSync()) continue;
    try {
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final rooms = json['rooms'];
      if (rooms is Map<String, dynamic>) {
        return rooms.length;
      }
    } catch (_) {
      // try next candidate
    }
  }

  // Last resort fallback matches seeder default.
  return 400;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const slidingHandle = 'headless-test';
  late String storePath;
  late Uri homeserverUrl;
  late String username;
  late String password;
  late LoginData initialSession;
  ReceivePort? roomListPort;
  Stream<dynamic>? roomListStream;
  late List<String> roomIds;
  ReceivePort? backupPort;
  Stream<dynamic>? backupStream;

  setUpAll(() async {
    storePath = _env(
      'MESSIE_BRIDGE_STORE_PATH',
      fallback: '${Directory.systemTemp.path}/messie_bridge_headless',
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

    final pingResult = await rustPing();
    expect(pingResult, equals('pong'));

    final loginResult = await rustRestoreOrLogin(
      homeserverUrl: homeserverUrl.toString(),
      username: username,
      password: password,
      basePath: storePath,
    );
    expect(loginResult.isOk, isTrue, reason: loginResult.error);
    initialSession = loginResult.data!;
    print('[setup] logged in as ${initialSession.userId} on ${initialSession.homeserverUrl}');

    final recoveryKey = _loadRecoveryKey();
    expect(recoveryKey, isNotNull,
        reason: 'Recovery key required for decrypt tests');
    var recoveryResult = await rustRecoverWithKey(recoveryKey: recoveryKey!);
    if (!recoveryResult.isOk && recoveryKey.contains(' ')) {
      final compact = recoveryKey.replaceAll(RegExp(r'\s+'), '');
      recoveryResult = await rustRecoverWithKey(recoveryKey: compact);
    }
    expect(recoveryResult.isOk, isTrue, reason: recoveryResult.error);
    final syncResult = await rustStartSlidingSync(
      handle: slidingHandle,
      hpSize: 24,
      lpBatch: 120,
      hpTimeline: 10,
      lpTimeline: 4,
    );
    expect(syncResult.isOk, isTrue, reason: syncResult.error);
    print('[setup] started sliding sync handle=$slidingHandle hpSize=24 lpBatch=120 hpTimeline=10 lpTimeline=4');

    roomListPort = ReceivePort('bridge_room_list_headless');
    roomListStream = roomListPort!.asBroadcastStream();
    final streamResult = await rustRoomListStream(
      handle: slidingHandle,
      port: roomListPort!.sendPort,
    );
    expect(streamResult.isOk, isTrue, reason: streamResult.error);
    print('[setup] room list stream registered for handle=$slidingHandle');

    // Attach a passive logger to the stream for the lifecycle of the suite.
    roomListStream!.listen((msg) {
      final now = DateTime.now().toIso8601String();
      if (msg is String) {
        try {
          final decoded = jsonDecode(msg) as Map<String, dynamic>;
          final kind = decoded['kind'];
          if (kind is String) {
            if (kind == 'sliding_sync_update') {
              final lists = decoded['lists'];
              final rooms = decoded['rooms'];
              final listsLen = (lists is List) ? lists.length : 0;
              final roomsLen = (rooms is List) ? rooms.length : 0;
              print('[room-list][$now] kind=$kind lists=$listsLen rooms=$roomsLen');
            } else if (kind == 'sliding_sync_error') {
              final msg = decoded['message'];
              print('[room-list][$now] kind=$kind message=$msg');
            } else {
              print('[room-list][$now] kind=$kind');
            }
          } else {
            print('[room-list][$now] missing kind: ${jsonEncode(decoded)}');
          }
        } catch (e) {
          print('[room-list][$now] failed to parse message: $e');
        }
      } else {
        print('[room-list][$now] non-string message: ${msg.runtimeType}');
      }
    }, onError: (err, st) {
      print('[room-list] stream error: $err');
      if (st != null) {
        print('[room-list] stack: $st');
      }
    });

    await _waitForPayload(
      roomListStream!,
      <String>{'sliding_sync_ready'},
      timeout: const Duration(seconds: 60),
      label: 'room-list',
    );

    roomIds = await _waitForJoinedRooms(timeout: const Duration(seconds: 60));
    if (roomIds.isNotEmpty) {
      await rustDumpRoomCrypto(roomId: roomIds.first);
    }
  });

  tearDownAll(() async {
    backupPort?.close();
    roomListPort?.close();
    await rustLogout(basePath: storePath);
  });

  test('restores existing session', () async {
    final restoreResult = await rustRestoreOrLogin(
      homeserverUrl: homeserverUrl.toString(),
      username: username,
      password: password,
      basePath: storePath,
    );
    expect(restoreResult.isOk, isTrue, reason: restoreResult.error);
    final restored = restoreResult.data!;
    expect(restored.didRestore, isTrue);
    expect(restored.userId, equals(initialSession.userId));
    expect(restored.deviceId, equals(initialSession.deviceId));
    expect(restored.accessToken, isNotEmpty);
  });

  test('sliding sync exposes seeded room list', () async {
    final expected = _expectedSeededRoomCount();
    print('expecting seeded rooms: $expected');
    final rooms = await _waitForJoinedRooms(
      timeout: const Duration(seconds: 60),
      minCount: expected,
    );
    expect(rooms.length, equals(expected));

    // If seed state is available, enforce exact membership and expected naming.
    final seed = _loadSeedState();
    if (seed != null) {
      final expectedIds = seed.values.toSet();
      expect(rooms.toSet(), equals(expectedIds));
      // Verify each expected room has a non-empty, human-readable name.
      for (final id in expectedIds) {
        final overviewResult = await rustRoomOverview(roomId: id);
        expect(overviewResult.isOk, isTrue, reason: overviewResult.error);
        final overview = overviewResult.data!;
        expect(overview.name.isNotEmpty, isTrue);
      }
    } else {
      // Fallback: basic overview sanity check
      final overviewResult = await rustRoomOverview(roomId: rooms.first);
      expect(overviewResult.isOk, isTrue, reason: overviewResult.error);
      final overview = overviewResult.data!;
      expect(overview.name.isNotEmpty, isTrue);
    }
  });

  test('sliding sync emits an initial update', () async {
    // Register a fresh listener to avoid missing early updates.
    final port = ReceivePort('bridge_room_list_update_probe');
    final stream = port.asBroadcastStream();
    final streamResult = await rustRoomListStream(
      handle: slidingHandle,
      port: port.sendPort,
    );
    expect(streamResult.isOk, isTrue, reason: streamResult.error);
    print('[probe] registered fresh room list listener');

    // Wait for at least one update from the sliding sync stream.
    // This validates that the simplified sliding sync endpoint accepts
    // our request shape and returns a summary instead of 400-ing.
    final payload = await _waitForPayload(
      stream,
      <String>{'sliding_sync_update', 'sliding_sync_error'},
      timeout: const Duration(seconds: 60),
      label: 'probe',
    );
    port.close();

    // Basic sanity: payload contains the expected keys.
    final kind = payload['kind'] as String? ?? '';
    if (kind == 'sliding_sync_error') {
      final msg = payload['message'] as String? ?? '<no message>';
      fail('sliding sync stream error from server: $msg');
    }
    expect(payload.containsKey('lists'), isTrue,
        reason: 'missing lists in payload: ${jsonEncode(payload)}');
    expect(payload.containsKey('rooms'), isTrue,
        reason: 'missing rooms in payload: ${jsonEncode(payload)}');
  });

  test('timeline snapshot contains events', () async {
    final targetRoom = roomIds.first;
    final openResult =
        await rustOpenRoom(handle: slidingHandle, roomId: targetRoom);
    expect(openResult.isOk, isTrue, reason: openResult.error);

    final timelinePort = ReceivePort('bridge_timeline_snapshot_headless');
    final timelineStream = timelinePort.asBroadcastStream();
    final streamResult = await rustTimelineStream(
      handle: slidingHandle,
      roomId: targetRoom,
      port: timelinePort.sendPort,
    );
    expect(streamResult.isOk, isTrue, reason: streamResult.error);

    final payload = await _waitForPayload(
      timelineStream,
      <String>{'timeline_snapshot', 'timeline_initial'},
    );
    timelinePort.close();

    final events = (payload['events'] as List<dynamic>)
        .map((event) => _decodeEvent(event as String))
        .toList();
    expect(events, isNotEmpty,
        reason: 'Timeline snapshot should contain events');
  });

  test('decrypts seeded timeline event bodies', () async {
    final targetRoom = roomIds.first;
    final openResult =
        await rustOpenRoom(handle: slidingHandle, roomId: targetRoom);
    expect(openResult.isOk, isTrue, reason: openResult.error);

    final timelinePort = ReceivePort('bridge_timeline_decrypt_headless');
    final timelineStream = timelinePort.asBroadcastStream();
    final streamResult = await rustTimelineStream(
      handle: slidingHandle,
      roomId: targetRoom,
      port: timelinePort.sendPort,
    );
    expect(streamResult.isOk, isTrue, reason: streamResult.error);

    final snapshotPayload = await _waitForPayload(
      timelineStream,
      <String>{'timeline_snapshot', 'timeline_initial'},
    );
    timelinePort.close();

    var allEvents = <Map<String, dynamic>>[
      ...snapshotPayload['events']
          .cast<String>()
          .map<Map<String, dynamic>>(_decodeEvent),
    ];

    Future<void> fetchMore() async {
      final loadResult = await rustLoadBackward(
        handle: slidingHandle,
        roomId: targetRoom,
        limit: 10,
      );
      if (loadResult.isOk) {
        allEvents = <Map<String, dynamic>>[
          ...allEvents,
          ...loadResult.data!.events.map<Map<String, dynamic>>(_decodeEvent),
        ];
      }
    }

    List<Map<String, dynamic>> decodedEvents() {
      return allEvents
          .where((event) => event['type'] == 'm.room.message')
          .toList();
    }

    var decoded = decodedEvents();
    for (var attempt = 0; attempt < 5 && decoded.isEmpty; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 1));
      final downloadResult =
          await rustDownloadRoomKeysForRoom(roomId: targetRoom);
      expect(downloadResult.isOk, isTrue, reason: downloadResult.error);
      await fetchMore();
      final types = allEvents.map((event) => event['type']).toList();
      print('attempt $attempt event types: $types');
      decoded = decodedEvents();
    }

    if (decoded.isEmpty) {
      final types = allEvents.map((event) => event['type']).toList();
      print('timeline events types: $types');
      if (allEvents.isNotEmpty) {
        print('timeline sample event: ${jsonEncode(allEvents.first)}');
        final encrypted = allEvents.firstWhere(
            (e) => e['type'] == 'm.room.encrypted',
            orElse: () => {});
        if (encrypted.isNotEmpty) {
          print('encrypted payload: ${jsonEncode(encrypted)}');
        }
      }
    }

    expect(decoded, isNotEmpty, reason: 'Expected decrypted room messages');

    final body =
        ((decoded.first['content'] as Map<String, dynamic>)['body']) as String?;
    expect(body, isNotNull);
    expect(body!, contains('Seed message'));
  });

  test('send_text appends a new message to timeline', () async {
    final targetRoom = roomIds.first;
    final openResult = await rustOpenRoom(handle: slidingHandle, roomId: targetRoom);
    expect(openResult.isOk, isTrue, reason: openResult.error);

    final port = ReceivePort('bridge_timeline_send_text');
    final stream = port.asBroadcastStream();
    final reg = await rustTimelineStream(handle: slidingHandle, roomId: targetRoom, port: port.sendPort);
    expect(reg.isOk, isTrue, reason: reg.error);

    // Prime with snapshot
    await _waitForPayload(stream, <String>{'timeline_snapshot', 'timeline_initial'}, label: 'timeline');

    final body = 'Bridge test message ${DateTime.now().millisecondsSinceEpoch}';
    final sent = await rustSendText(roomId: targetRoom, body: body);
    expect(sent.isOk, isTrue, reason: sent.error);

    // Wait for an append that includes our message body
    Map<String, dynamic>? matched;
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    while (DateTime.now().isBefore(deadline)) {
      final payload = await _waitForPayload(stream, <String>{'timeline_append'}, timeout: const Duration(seconds: 60), label: 'timeline');
      final events = (payload['events'] as List<dynamic>).cast<String>().map(_decodeEvent).toList();
      for (final event in events) {
        if (event['type'] == 'm.room.message') {
          final content = (event['content'] as Map<String, dynamic>?);
          final b = content?['body'] as String?;
          if (b == body) { matched = event; break; }
        }
      }
      if (matched != null) break;
    }
    port.close();
    expect(matched, isNotNull, reason: 'Expected to observe sent message in timeline_append');
  });

  test('send_text with reply_to sets m.in_reply_to', () async {
    final targetRoom = roomIds.first;
    final openResult = await rustOpenRoom(handle: slidingHandle, roomId: targetRoom);
    expect(openResult.isOk, isTrue, reason: openResult.error);

    final port = ReceivePort('bridge_timeline_send_reply');
    final stream = port.asBroadcastStream();
    final reg = await rustTimelineStream(handle: slidingHandle, roomId: targetRoom, port: port.sendPort);
    expect(reg.isOk, isTrue, reason: reg.error);

    final snapshot = await _waitForPayload(stream, <String>{'timeline_snapshot', 'timeline_initial'}, label: 'timeline');
    final initial = (snapshot['events'] as List<dynamic>).cast<String>().map(_decodeEvent).toList();
    // Use the most recent event from snapshot as a reply target if available.
    final baselineId = initial.isNotEmpty ? (initial.last['event_id'] as String?) : null;
    expect(baselineId, isNotNull, reason: 'Need an event_id from timeline snapshot to reply to');

    final body = 'Bridge reply ${DateTime.now().millisecondsSinceEpoch}';
    final sent = await rustSendText(roomId: targetRoom, body: body, replyTo: baselineId);
    expect(sent.isOk, isTrue, reason: sent.error);

    Map<String, dynamic>? matched;
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    while (DateTime.now().isBefore(deadline)) {
      final payload = await _waitForPayload(stream, <String>{'timeline_append'}, timeout: const Duration(seconds: 60), label: 'timeline');
      final events = (payload['events'] as List<dynamic>).cast<String>().map(_decodeEvent).toList();
      for (final event in events) {
        if (event['type'] == 'm.room.message') {
          final content = (event['content'] as Map<String, dynamic>?);
          final b = content?['body'] as String?;
          if (b == body) {
            final relates = (content?['m.relates_to'] as Map<String, dynamic>?);
            final inReply = (relates?['m.in_reply_to'] as Map<String, dynamic>?);
            final repliedTo = inReply?['event_id'] as String?;
            if (repliedTo == baselineId) {
              matched = event; break;
            }
          }
        }
      }
      if (matched != null) break;
    }
    port.close();
    expect(matched, isNotNull, reason: 'Expected reply with m.in_reply_to referencing baselineId');
  });

  test('set_room_mute toggles and reflects in room_overview', () async {
    final targetRoom = roomIds.first;
    final before = await rustRoomOverview(roomId: targetRoom);
    expect(before.isOk, isTrue, reason: before.error);
    final initiallyMuted = before.data!.isMuted;

    final toggled = await rustSetRoomMute(roomId: targetRoom, muted: !initiallyMuted);
    expect(toggled.isOk, isTrue, reason: toggled.error);

    // Re-read overview to observe change
    final after = await rustRoomOverview(roomId: targetRoom);
    expect(after.isOk, isTrue, reason: after.error);
    expect(after.data!.isMuted, equals(!initiallyMuted));

    // Restore original state
    final restore = await rustSetRoomMute(roomId: targetRoom, muted: initiallyMuted);
    expect(restore.isOk, isTrue, reason: restore.error);
  });

  test('mxc_to_http returns homeserver-scoped media URL', () async {
    // Prefer a real avatar MXC if available; otherwise use a sample MXC.
    String? mxc = null;
    for (final id in roomIds) {
      final ov = await rustRoomOverview(roomId: id);
      if (ov.isOk && ov.data?.avatarUrl != null) { mxc = ov.data!.avatarUrl; break; }
    }
    mxc ??= 'mxc://example.org/abc123';

    final converted = await rustMxcToHttp(mxc: mxc!, w: 64, h: 64);
    expect(converted.isOk, isTrue, reason: converted.error);
    final url = Uri.parse(converted.data!);
    // Must be same origin as homeserver URL
    final hs = homeserverUrl;
    expect(url.scheme, equals(hs.scheme));
    expect(url.host, equals(hs.host));
    // Path should contain media v3 endpoint
    expect(url.path.contains('/_matrix/media/v3/'), isTrue);
  });

  test('mark_read_up_to sends receipt and reduces unread when applicable', () async {
    // Find a room with any unread notifications (if none, just assert call ok)
    String? target;
    int beforeCount = 0;
    for (final id in roomIds) {
      final ov = await rustRoomOverview(roomId: id);
      if (ov.isOk) {
        final n = ov.data!.notificationCount;
        if (n > 0) { target = id; beforeCount = n; break; }
      }
    }

    target ??= roomIds.first;
    // Open timeline and get latest event id from snapshot
    final open = await rustOpenRoom(handle: slidingHandle, roomId: target!);
    expect(open.isOk, isTrue, reason: open.error);
    final port = ReceivePort('bridge_timeline_mark_read');
    final stream = port.asBroadcastStream();
    final reg = await rustTimelineStream(handle: slidingHandle, roomId: target!, port: port.sendPort);
    expect(reg.isOk, isTrue, reason: reg.error);
    final snapshot = await _waitForPayload(stream, <String>{'timeline_snapshot', 'timeline_initial'}, label: 'timeline');
    port.close();
    final initial = (snapshot['events'] as List<dynamic>).cast<String>().map(_decodeEvent).toList();
    final lastId = initial.isNotEmpty ? (initial.last['event_id'] as String?) : null;
    expect(lastId, isNotNull, reason: 'Need an event_id to send read receipt');

    final ack = await rustMarkReadUpTo(roomId: target!, eventId: lastId!);
    expect(ack.isOk, isTrue, reason: ack.error);

    // Give SDK some time to update unread counts; then check if reduced
    await Future<void>.delayed(const Duration(seconds: 2));
    final after = await rustRoomOverview(roomId: target!);
    expect(after.isOk, isTrue, reason: after.error);
    final afterCount = after.data!.notificationCount;
    if (beforeCount > 0) {
      expect(afterCount <= beforeCount, isTrue,
          reason: 'Expected notification_count to not increase after read receipt');
    }
  });

  test('import_recovery_key alias works and backup status stream emits', () async {
    final key = _loadRecoveryKey();
    expect(key, isNotNull);

    final importResult = await rustImportRecoveryKey(recoveryKey: key!);
    expect(importResult.isOk, isTrue, reason: importResult.error);

    backupPort = ReceivePort('bridge_backup_status_headless');
    backupStream = backupPort!.asBroadcastStream();
    final streamResult = await rustBackupStatusStream(
      handle: slidingHandle,
      port: backupPort!.sendPort,
    );
    expect(streamResult.isOk, isTrue, reason: streamResult.error);

    final payload = await _waitForPayload(
      backupStream!,
      <String>{'backup_status'},
      timeout: const Duration(seconds: 30),
      label: 'backup',
    );
    expect(payload['kind'], equals('backup_status'));
    expect(payload.containsKey('enabled'), isTrue);
    expect(payload.containsKey('exists_on_server'), isTrue);

    backupPort?.close();
    backupPort = null;
  });

  test('enable_online_backup returns status; export_recovery_key placeholder', () async {
    final enable = await rustEnableOnlineBackup(generateNew: false);
    expect(enable.isOk, isTrue, reason: enable.error);
    expect(enable.data!.enabled, isTrue);

    // Export not yet implemented: allow either success with a key or a clear error.
    final export = await rustExportRecoveryKey();
    if (!export.isOk) {
      expect(export.error, isNotNull);
    }
  });

  test('sas verification end-to-end with peer process (emoji + done)', () async {
    // Spawn peer process (Node helper) that accepts and confirms SAS.
    final serverUrl = homeserverUrl.toString();
    // Use Dockerized peer helper; remap loopback to host.docker.internal for container networking
    var dockerServerUrl = serverUrl.replaceFirst('127.0.0.1', 'host.docker.internal');
    dockerServerUrl = dockerServerUrl.replaceFirst('localhost', 'host.docker.internal');
    // Mount seed state for access token reuse to avoid login rate limits
    final stateFile = _env('MESSIE_SEED_STATE_FILE', fallback: '../scripts/matrix/.state/seed_state.json');
    // Use an absolute host path for Docker volume mounts; if the configured path
    // lacks the recovery key (older seeds), fall back to the Makefile’s verifier mount path.
    var stateDir = File(stateFile).parent.absolute.path;
    if (!File('$stateDir/recovery_key.json').existsSync()) {
      final alt = File('../scripts/matrix/scripts/matrix/.state/seed_state.json').parent.absolute.path;
      if (Directory(alt).existsSync() && File('$alt/recovery_key.json').existsSync()) {
        stateDir = alt;
      }
    }
    // Use a stable container name so it can be pruned or stopped consistently.
    final peerName = _env('MESSIE_SAS_PEER_CONTAINER', fallback: 'messie-matrix-peer');
    // Best-effort pre-remove any previous instance with the same name.
    await Process.run('docker', ['rm', '-f', peerName]);
    addTearDown(() async {
      await Process.run('docker', ['rm', '-f', peerName]);
    });

    // Start peer container in detached mode so the docker client process exiting
    // does not terminate the container prematurely.
    final peerInfoPath = '$stateDir/sas_peer.json';
    // // Best-effort remove stale peer info so we don't read an old device id
    // try { final f = File(peerInfoPath); if (f.existsSync()) { f.deleteSync(); } } catch (_) {}
    final launchTs = DateTime.now().millisecondsSinceEpoch;
    final started = await Process.run('docker', [
      'run', '-d', '--name', peerName, '--network', 'host',
      '-e', 'RECOVERY_KEY_PATH=/state/recovery_key.json',
      '-e', 'PEER_INFO_PATH=/state/sas_peer.json',
      '-v', '$stateDir:/state',
      'messie-matrix-peer:latest',
      '--server-url', dockerServerUrl,
      '--username', username,
      '--password', password,
      '--device-name', 'Messie SAS Peer',
    ]);
    expect(started.exitCode, 0, reason: 'failed to start peer container: ${started.stderr}\n${started.stdout}');
    // Start a background monitor to dump logs if the container dies early.
    var monitorCancelled = false;
    () async {
      while (!monitorCancelled) {
        final inspect = await Process.run('docker', ['inspect', '--type', 'container', '-f', '{{.State.Running}}', peerName]);
        final running = inspect.exitCode == 0 && (inspect.stdout as String?)?.trim() == 'true';
        if (!running) {
          final details = await Process.run('docker', ['inspect', '--type', 'container', peerName]);
          final ps = await Process.run('docker', ['ps', '-a', '--filter', 'name='+peerName]);
          final logs = await Process.run('docker', ['logs', '--tail', '200', peerName]);
          // Print helpful diagnostics
          // ignore: avoid_print
          print('[peer-container] not running. inspect: ${details.stdout}\n${details.stderr}\nps: ${ps.stdout}\n${ps.stderr}');
          // ignore: avoid_print
          print('[peer-container] logs (tail):\n${logs.stdout}\n${logs.stderr}');
          break;
        }
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }();

    // Do not pipe peer output to keep test logs quiet

    // Wait for peer to be ready and for a fresh (post-launch) device id
    final deviceId = await _waitForPeerReadyDevice(peerInfoPath, minTimestamp: launchTs);

    final start = await rustRequestSasVerification(userId: initialSession.userId, deviceId: deviceId);
    expect(start.isOk, isTrue, reason: start.error);
    final flowId = start.data!.flowId;
    expect(flowId, isNotEmpty);

    final port = ReceivePort('bridge_sas_observer');
    final stream = port.asBroadcastStream();
    final observe = await rustObserveSas(flowId: flowId, port: port.sendPort);
    expect(observe.isOk, isTrue, reason: observe.error);

    // Wait until keys_exchanged with emoji provided
    Map<String, dynamic> payload;
    while (true) {
      payload = await _waitForPayload(
        stream,
        <String>{'sas_update'},
        timeout: const Duration(seconds: 60),
        label: 'sas',
      );
      if (payload['state'] == 'keys_exchanged') break;
    }
    expect((payload['emoji'] as List?)?.isNotEmpty, isTrue,
        reason: 'Expected emoji tuple in keys_exchanged');

    final confirmed = await rustConfirmSas(flowId: flowId);
    expect(confirmed.isOk, isTrue, reason: confirmed.error);

    // Expect final done state
    Map<String, dynamic> donePayload;
    while (true) {
      donePayload = await _waitForPayload(
        stream,
        <String>{'sas_update'},
        timeout: const Duration(seconds: 60),
        label: 'sas',
      );
      if (donePayload['state'] == 'done') break;
    }

    port.close();
    // Container cleanup handled by tearDown via `docker rm -f`.
    monitorCancelled = true;
  });

  test('trust_state returns data for own user/device', () async {
    final deviceId = initialSession.deviceId;
    final state = await rustTrustState(userId: initialSession.userId, deviceId: deviceId);
    expect(state.isOk, isTrue, reason: state.error);
    expect(state.data, isNotNull);
    // We don't assert specific booleans (env-dependent), only presence and types
    expect(state.data!.userVerified is bool, isTrue);
  });
}

// Utility: wait up to a few seconds for the peer to write its device id file.
Future<String> _waitForPeerReadyDevice(String jsonPath, {required int minTimestamp, Duration timeout = const Duration(seconds: 30)}) async {
  final start = DateTime.now();
  while (DateTime.now().difference(start) < timeout) {
    final f = File(jsonPath);
    if (await f.exists()) {
      try {
        final raw = await f.readAsString();
        final obj = jsonDecode(raw) as Map<String, dynamic>;
        final did = obj['device_id'] as String?;
        final ready = obj['ready'] as bool?;
        final ts = (obj['ts'] is num) ? (obj['ts'] as num).toInt() : -1;
        if (did != null && did.isNotEmpty && ready == true && ts >= minTimestamp) {
          return did;
        }
      } catch (_) {
        // ignore parse errors; retry
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }
  throw StateError('Peer not ready with fresh device id at $jsonPath');
}
