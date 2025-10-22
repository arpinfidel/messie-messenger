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
  final String groupRoom;
  final String senderUser;
  final String senderPass;
  final String senderBase;
  _Env(this.hs, this.user, this.pass, this.base, this.groupRoom, this.senderUser, this.senderPass, this.senderBase);
}

_Env? _loadEnv() {
  final env = Platform.environment;
  final hs = env['MESSIE_MATRIX_HOMESERVER'];
  final user = env['MESSIE_MATRIX_USERNAME'];
  final pass = env['MESSIE_MATRIX_PASSWORD'];
  final base = env['MESSIE_MATRIX_STORE_BASE'] ?? Directory.systemTemp.createTempSync('messie_v2').path;
  final group = env['MESSIE_GROUP_ROOM'];
  final senderUser = env['MESSIE_SENDER_USERNAME'];
  final senderPass = env['MESSIE_SENDER_PASSWORD'];
  final senderBase = env['MESSIE_SENDER_STORE_BASE'] ??
      // Default to repo-level persistent sender store to avoid 429s
      // Use a path that persists across runs rather than temp.
      (Platform.environment['PWD'] != null
          ? File('${Platform.environment['PWD']}/../.messie_store_v2_sender').absolute.path
          : Directory.systemTemp.createTempSync('messie_v2_sender').path);
  if (hs == null || user == null || pass == null || group == null || senderUser == null || senderPass == null) {
    return null;
  }
  return _Env(hs, user, pass, base, group, senderUser, senderPass, senderBase);
}

Future<String?> _readSenderAccessToken(String senderBase) async {
  try {
    final file = File('$senderBase/session.json');
    if (!await file.exists()) return null;
    final jsonStr = await file.readAsString();
    final data = json.decode(jsonStr) as Map<String, dynamic>;
    final token = data['access_token'] as String?;
    return token;
  } catch (_) {
    return null;
  }
}

Future<bool> _sendWithCurl({required String hs, required String roomId, required String body, required String accessToken}) async {
  // PUT /_matrix/client/v3/rooms/{roomId}/send/m.room.message/{txnId}
  final txn = DateTime.now().millisecondsSinceEpoch.toString();
  final url = Uri.parse('$hs/_matrix/client/v3/rooms/${Uri.encodeComponent(roomId)}/send/m.room.message/$txn').toString();
  final payload = json.encode({'msgtype': 'm.text', 'body': body});
  final result = await Process.run('curl', [
    '-sS',
    '-X', 'PUT',
    '-H', 'Authorization: Bearer $accessToken',
    '-H', 'Content-Type: application/json',
    '--data', payload,
    url,
  ]);
  if (result.exitCode == 0) {
    return true;
  }
  // ignore: avoid_print
  print('curl send failed: ${result.exitCode} ${result.stderr}');
  return false;
}

Future<Map<String, dynamic>> _waitForCounts(
  Stream<dynamic> stream,
  String roomId, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final end = DateTime.now().add(timeout);
  await for (final message in stream) {
    if (DateTime.now().isAfter(end)) {
      throw TimeoutException('Timed out waiting for counts_update for room', timeout);
    }
    if (message is! String) continue;
    try {
      final decoded = json.decode(message) as Map<String, dynamic>;
      if (decoded['kind'] == 'counts_update' && decoded['room_id'] == roomId) {
        return decoded;
      }
    } catch (_) {}
  }
  throw StateError('Stream closed before receiving counts_update for room');
}

Future<(int n, int h)> _settleCounts(
  Stream<dynamic> stream,
  String roomId, {
  Duration window = const Duration(seconds: 8),
  Duration perWait = const Duration(seconds: 4),
}) async {
  var end = DateTime.now().add(window);
  var lastN = -1;
  var lastH = -1;
  while (DateTime.now().isBefore(end)) {
    try {
      final snap = await _waitForCounts(stream, roomId, timeout: perWait);
      final n = (snap['notification_count'] as num?)?.toInt() ?? lastN;
      final h = (snap['highlight_count'] as num?)?.toInt() ?? lastH;
      if (n == lastN && h == lastH && lastN >= 0) {
        break; // stable
      }
      lastN = n;
      lastH = h;
      end = DateTime.now().add(const Duration(seconds: 2)); // require brief stability
    } on TimeoutException {
      // No update within perWait; keep trying within window
      await Future<void>.delayed(const Duration(milliseconds: 50));
    } on StateError {
      // Stream closed unexpectedly; stop early with last observed values
      break;
    }
  }
  return (lastN < 0 ? 0 : lastN, lastH < 0 ? 0 : lastH);
}

void main() {
  final env = _loadEnv();
  if (env == null) {
    test('skipped - env not set', () {
      expect(true, isTrue, reason: 'Set MESSIE_MATRIX_* and sender env to run');
    }, skip: true);
    return;
  }

  group('v2 global counts stream', () {
    test('counts_update bumps after mention in group room', () async {
      // Receiver
      final recvCreate = v2.clientCreate(homeserverUrl: env.hs, basePath: env.base);
      expect(recvCreate.success, isTrue, reason: 'client_create failed');
      final recv = recvCreate.handle;
      final login = v2.clientLogin(handle: recv, username: env.user, password: env.pass);
      expect(login.success, isTrue, reason: 'login failed');
      final userId = login.userId!;
      // Ensure receiver is joined to the target room
      final joinRes = v2.roomJoin(handle: recv, roomId: env.groupRoom);
      // ignore: avoid_print
      print('join(receiver): $joinRes');

      // Thin SS: subscribe target room with a small timeline window to ensure ingestion
      final ss = v2.ssCreate(
        clientHandle: recv,
        enableToDevice: false,
        pollTimeoutMs: 0,
        networkTimeoutMs: 0,
      );
      expect(v2.ssStart(ssHandle: ss, port: 0), isTrue, reason: 'ssStart failed');
      final okSub = v2.ssSubscribeToRooms(
        ssHandle: ss,
        roomIds: [env.groupRoom],
        timelineLimit: 20,
        requiredState: [
          ('m.room.name', ''),
          ('m.room.avatar', ''),
          ('m.room.encryption', ''),
          ('m.room.power_levels', ''),
          ('m.room.join_rules', ''),
          ('m.room.member', userId),
        ],
        cancelInFlight: true,
      );
      expect(okSub, isTrue, reason: 'subscribe_to_rooms failed');

      // Warm receiver once so push rules/account data are available and SS has emitted
      v2.clientSyncOnce(handle: recv);
      // Nudge once more after listeners register
      await Future<void>.delayed(const Duration(milliseconds: 250));
      // Also open a timeline stream for the target room to ensure immediate ingestion
      final tl = v2.timelineOpen(clientHandle: recv, roomId: env.groupRoom);
      expect(tl.success, isTrue, reason: 'timeline_open failed');
      expect(v2.timelineStartStreaming(timelineHandle: tl.handle, port: 0), isTrue, reason: 'timeline_start_streaming failed');

      // Start counts stream AFTER SS + timeline are set up so initial snapshot captures room
      final port = ReceivePort('v2_counts');
      addTearDown(() => port.close());
      final stream = port.asBroadcastStream();
      final okCounts = v2.roomCountsStream(handle: recv, port: port.sendPort.nativePort);
      expect(okCounts, isTrue, reason: 'room_counts_stream failed');
      // Force a clean baseline by marking read up to the latest event
      expect(
        v2.roomMarkReadUpTo(clientHandle: recv, roomId: env.groupRoom, eventId: '__LATEST__'),
        isTrue,
        reason: 'mark_read_up_to __LATEST__ failed',
      );
      v2.clientSyncOnce(handle: recv);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      // Set baseline based on SDK after mark-read
      var baselineN = 0;
      var baselineH = 0;
      final sdkBaseline = v2.roomGetUnreadCounts(handle: recv, roomId: env.groupRoom);
      final srvBaseline = v2.roomFetchServerUnreadCounts(handle: recv, roomId: env.groupRoom, timeoutMs: 0);
      // ignore: avoid_print
      print('counts baseline (post-read) for ${env.groupRoom}: sdk-get n=${sdkBaseline.notification} h=${sdkBaseline.highlight}; server-get n=${srvBaseline.notification} h=${srvBaseline.highlight}');
      expect(sdkBaseline.notification, equals(0), reason: 'baseline notification not zero after mark-read');

      // Sender: join + sync + send mention
      // Ensure persistent sender store exists to reuse access token and avoid 429s
      Directory(env.senderBase).createSync(recursive: true);
      final senderCreate = v2.clientCreate(homeserverUrl: env.hs, basePath: env.senderBase);
      expect(senderCreate.success, isTrue, reason: 'sender client_create failed');
      final sender = senderCreate.handle;
      final senderLogin = v2.clientLogin(handle: sender, username: env.senderUser, password: env.senderPass);
      expect(senderLogin.success, isTrue, reason: 'sender login failed');
      // Best-effort ensure sender is joined
      v2.roomJoin(handle: sender, roomId: env.groupRoom);
      // Warm sender once so send succeeds promptly and reduces server churn
      v2.clientSyncOnce(handle: sender);

      final ts = DateTime.now().millisecondsSinceEpoch;
      final body = 'counts ping $userId $ts';
      // Try curl with persisted sender token to avoid login churn / 429
      final token = await _readSenderAccessToken(env.senderBase);
      var sent = false;
      if (token != null && token.isNotEmpty) {
        // ignore: avoid_print
        print('sending via curl to ${env.groupRoom} with persisted token ...');
        sent = await _sendWithCurl(hs: env.hs, roomId: env.groupRoom, body: body, accessToken: token);
      }
      if (!sent) {
        // Fallback to SDK send
        // ignore: avoid_print
        print('curl send not used or failed; falling back to SDK send ...');
        sent = v2.roomSendText(clientHandle: sender, roomId: env.groupRoom, body: body);
      }
      // ignore: avoid_print
      print('send result: ${sent ? 'ok' : 'failed'}; waiting for counts to increase from baseline n=$baselineN h=$baselineH');
      expect(sent, isTrue, reason: 'send failed');

      // Expect counts to strictly increase (notification count)
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      var n = baselineN;
      var h = baselineH;
      while (DateTime.now().isBefore(deadline)) {
        final settled = await _settleCounts(
          stream,
          env.groupRoom,
          window: const Duration(seconds: 6),
          perWait: const Duration(seconds: 3),
        );
        n = settled.$1;
        h = settled.$2;
        final got = v2.roomGetUnreadCounts(handle: recv, roomId: env.groupRoom);
        if (got.notification > n) n = got.notification;
        if (got.highlight > h) h = got.highlight;
        if (n > baselineN || got.notification > baselineN) break;
        // Nudge receiver to ingest more updates
        v2.clientSyncOnce(handle: recv);
      }
      // Log final counts for diagnostics
      // ignore: avoid_print
      final sdkAfter = v2.roomGetUnreadCounts(handle: recv, roomId: env.groupRoom);
      final srvAfter = v2.roomFetchServerUnreadCounts(handle: recv, roomId: env.groupRoom, timeoutMs: 0);
      print('counts after (final) for ${env.groupRoom}: n=$n h=$h (baseline n=$baselineN h=$baselineH) sdk-get(n=${sdkAfter.notification} h=${sdkAfter.highlight}) server-get(n=${srvAfter.notification} h=${srvAfter.highlight})');
      expect(n > baselineN || sdkAfter.notification > baselineN, isTrue, reason: 'notification count did not strictly increase (stream:$n sdk:${sdkAfter.notification} vs baseline $baselineN)');
    }, timeout: const Timeout(Duration(seconds: 45)));
  });
}
