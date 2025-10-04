@Timeout(Duration(minutes: 5))
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
}) async {
  final end = DateTime.now().add(timeout);
  await for (final message in stream) {
    if (DateTime.now().isAfter(end)) {
      throw TimeoutException('Timed out waiting for payload', timeout);
    }
    if (message is! String) {
      continue;
    }
    try {
      final decoded = jsonDecode(message) as Map<String, dynamic>;
      final kind = decoded['kind'] as String? ?? '';
      if (kinds.contains(kind)) {
        return decoded;
      }
    } catch (_) {
      // ignore malformed payloads
    }
  }
  throw StateError('Stream closed before payload was received');
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

    roomListPort = ReceivePort('bridge_room_list_headless');
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
    );

    roomIds = await _waitForJoinedRooms(timeout: const Duration(seconds: 60));
    if (roomIds.isNotEmpty) {
      await rustDumpRoomCrypto(roomId: roomIds.first);
    }
  });

  tearDownAll(() async {
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
      timeout: const Duration(seconds: 180),
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
}
