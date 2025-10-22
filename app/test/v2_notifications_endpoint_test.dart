import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
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
      (Platform.environment['PWD'] != null
          ? File('${Platform.environment['PWD']}/../.messie_store_v2_sender').absolute.path
          : Directory.systemTemp.createTempSync('messie_v2_sender').path);
  if (hs == null || user == null || pass == null || group == null || senderUser == null || senderPass == null) {
    return null;
  }
  return _Env(hs, user, pass, base, group, senderUser, senderPass, senderBase);
}

Future<String?> _readAccessToken(String basePath) async {
  try {
    final file = File('$basePath/session.json');
    if (!await file.exists()) return null;
    final data = json.decode(await file.readAsString()) as Map<String, dynamic>;
    return data['access_token'] as String?;
  } catch (_) {
    return null;
  }
}

Future<(List<Map<String, dynamic>> notifications, String? nextToken)> _fetchNotifications({
  required String hs,
  required String accessToken,
  String? from,
  int limit = 50,
}) async {
  final uri = Uri.parse(hs).replace(
    path: '/_matrix/client/v3/notifications',
    queryParameters: {
      if (from != null) 'from': from,
      'limit': '$limit',
    },
  );
  final client = HttpClient();
  try {
    final req = await client.getUrl(uri);
    req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $accessToken');
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final resp = await req.close();
    final text = await utf8.decoder.bind(resp).join();
    if (resp.statusCode != 200) {
      throw Exception('notifications GET failed: ${resp.statusCode} $text');
    }
    final body = json.decode(text) as Map<String, dynamic>;
    final notifs = (body['notifications'] as List?)?.cast<Map<String, dynamic>>() ?? const <Map<String, dynamic>>[];
    final nextToken = body['next_token'] as String?;
    return (notifs, nextToken);
  } finally {
    client.close(force: true);
  }
}

Future<String?> _sendWithCurl({required String hs, required String roomId, required String body, required String accessToken}) async {
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
    try {
      final obj = json.decode(result.stdout as String) as Map<String, dynamic>;
      final eid = obj['event_id'] as String?;
      return eid;
    } catch (_) {
      return null;
    }
  }
  // ignore: avoid_print
  print('curl send failed: ${result.exitCode} ${result.stderr}');
  return null;
}

void main() {
  final env = _loadEnv();
  if (env == null) {
    test('skipped - env not set', () {
      expect(true, isTrue, reason: 'Set MESSIE_MATRIX_* and sender env to run');
    }, skip: true);
    return;
  }

  group('v2 notifications endpoint', () {
    test('returns new notification after mention in group room', () async {
      // Receiver: login and ensure joined
      final recvCreate = v2.clientCreate(homeserverUrl: env.hs, basePath: env.base);
      expect(recvCreate.success, isTrue, reason: 'client_create failed');
      final recv = recvCreate.handle;
      final login = v2.clientLogin(handle: recv, username: env.user, password: env.pass);
      expect(login.success, isTrue, reason: 'login failed');
      final userId = login.userId!;
      final joinRes = v2.roomJoin(handle: recv, roomId: env.groupRoom);
      // ignore: avoid_print
      print('join(receiver): $joinRes');

      // Receiver token
      final recvToken = await _readAccessToken(env.base);
      expect(recvToken != null && recvToken!.isNotEmpty, isTrue, reason: 'receiver token missing');

      // Reset baseline read state to latest, so we know the pivot
      expect(
        v2.roomMarkReadUpTo(clientHandle: recv, roomId: env.groupRoom, eventId: '__LATEST__'),
        isTrue,
        reason: 'mark_read_up_to __LATEST__ failed',
      );
      v2.clientSyncOnce(handle: recv);
      await Future<void>.delayed(const Duration(milliseconds: 250));

      // Baseline notifications: capture the current latest page and note room items
      final sdkBefore = v2.roomGetUnreadCounts(handle: recv, roomId: env.groupRoom);
      final srvBefore = v2.roomFetchServerUnreadCounts(handle: recv, roomId: env.groupRoom);
      final (baselineNotifs, baselineToken) = await _fetchNotifications(hs: env.hs, accessToken: recvToken!);
      final baselineRoomIds = baselineNotifs
          .where((n) => n['room_id'] == env.groupRoom)
          .map((n) => ((n['event'] as Map<String, dynamic>?)?['event_id'] as String?) ?? '')
          .where((e) => e.isNotEmpty)
          .toSet();
      // ignore: avoid_print
      print('baseline: token=${baselineToken ?? '(none)'} roomCount=${baselineRoomIds.length} sdk(n=${sdkBefore.notification} h=${sdkBefore.highlight}) server(n=${srvBefore.notification} h=${srvBefore.highlight})');

      // Sender: send a mention
      Directory(env.senderBase).createSync(recursive: true);
      final senderCreate = v2.clientCreate(homeserverUrl: env.hs, basePath: env.senderBase);
      expect(senderCreate.success, isTrue, reason: 'sender client_create failed');
      final sender = senderCreate.handle;
      final senderLogin = v2.clientLogin(handle: sender, username: env.senderUser, password: env.senderPass);
      expect(senderLogin.success, isTrue, reason: 'sender login failed');
      v2.roomJoin(handle: sender, roomId: env.groupRoom);
      v2.clientSyncOnce(handle: sender);
      final ts = DateTime.now().millisecondsSinceEpoch;
      final body = 'notif ping @$userId $ts';
      final senderToken = await _readAccessToken(env.senderBase);
      String? sentEventId;
      if (senderToken != null && senderToken.isNotEmpty) {
        // ignore: avoid_print
        print('sending via curl to ${env.groupRoom} with persisted token ...');
        sentEventId = await _sendWithCurl(hs: env.hs, roomId: env.groupRoom, body: body, accessToken: senderToken);
      }
      var sent = sentEventId != null;
      if (!sent) {
        // ignore: avoid_print
        print('curl send not used or failed; falling back to SDK send ...');
        sent = v2.roomSendText(clientHandle: sender, roomId: env.groupRoom, body: body);
      }
      // ignore: avoid_print
      print('send result: ${sent ? 'ok' : 'failed'}; eventId=${sentEventId ?? '(unknown)'}');
      expect(sent, isTrue, reason: 'send failed');

      // Poll notifications endpoint (latest page) and expect room count to strictly increase
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      var roomNewCount = 0;
      var foundEvent = false;
      while (DateTime.now().isBefore(deadline)) {
        // Always fetch the latest page (no 'from')
        final (notifs, _) = await _fetchNotifications(hs: env.hs, accessToken: recvToken, from: null, limit: 50);
        final ids = notifs
            .where((n) => n['room_id'] == env.groupRoom)
            .map((n) => ((n['event'] as Map<String, dynamic>?)?['event_id'] as String?) ?? '')
            .where((e) => e.isNotEmpty)
            .toSet();
        final delta = ids.difference(baselineRoomIds).length;
        roomNewCount = delta;
        if (sentEventId != null) {
          foundEvent = ids.contains(sentEventId);
        }
        if (roomNewCount > 0) break;
        await Future<void>.delayed(const Duration(seconds: 2));
      }

      // ignore: avoid_print
      // Nudge unread summaries via classic sync to reflect the new event
      var sdkAfter = v2.roomGetUnreadCounts(handle: recv, roomId: env.groupRoom);
      var srvAfter = v2.roomFetchServerUnreadCounts(handle: recv, roomId: env.groupRoom);
      if (sdkAfter.notification == 0 && srvAfter.notification == 0) {
        final end = DateTime.now().add(const Duration(seconds: 20));
        while (DateTime.now().isBefore(end)) {
          v2.clientSyncOnce(handle: recv);
          await Future<void>.delayed(const Duration(milliseconds: 300));
          sdkAfter = v2.roomGetUnreadCounts(handle: recv, roomId: env.groupRoom);
          srvAfter = v2.roomFetchServerUnreadCounts(handle: recv, roomId: env.groupRoom);
          if (sdkAfter.notification > 0 || srvAfter.notification > 0) break;
        }
      }
      print('notifications endpoint delta for ${env.groupRoom}: +$roomNewCount (baseline=${baselineRoomIds.length}); matchedEvent=${foundEvent ? 'yes' : 'no'}; sdk after (n=${sdkAfter.notification} h=${sdkAfter.highlight}) server after (n=${srvAfter.notification} h=${srvAfter.highlight})');
      if (sentEventId != null) {
        expect(foundEvent, isTrue, reason: 'notifications endpoint did not include sent event $sentEventId');
      }
      expect(roomNewCount, greaterThan(0), reason: 'notifications latest page did not include a new item for the room');
      // And unread totals should reflect the new event after nudging
      expect(sdkAfter.notification > 0 || srvAfter.notification > 0, isTrue, reason: 'unread totals did not increase after send');
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
