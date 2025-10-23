// ignore_for_file: avoid_print
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:messie_app/bridge/messie_bridge.dart';

class _Env {
  final String hs;
  final String user;
  final String pass;
  final String base;
  final String groupRoom;
  final String senderUser;
  final String senderPass;
  final String senderBase;
  _Env(this.hs, this.user, this.pass, this.base, this.groupRoom,
      this.senderUser, this.senderPass, this.senderBase);
}

_Env? _loadEnv() {
  final env = Platform.environment;
  final hs = env['MESSIE_MATRIX_HOMESERVER'];
  final user = env['MESSIE_MATRIX_USERNAME'];
  final pass = env['MESSIE_MATRIX_PASSWORD'];
  final base = env['MESSIE_MATRIX_STORE_BASE'] ??
      Directory.systemTemp.createTempSync('messie_v1').path;
  final group = env['MESSIE_GROUP_ROOM'];
  final senderUser = env['MESSIE_SENDER_USERNAME'];
  final senderPass = env['MESSIE_SENDER_PASSWORD'];
  // Default to repo-level sender store so token persists across runs (avoid 429)
  final senderBase = env['MESSIE_SENDER_STORE_BASE'] ??
      (Platform.environment['PWD'] != null
          ? File('${Platform.environment['PWD']}/../.messie_store_v2_sender')
              .absolute
              .path
          : Directory.systemTemp.createTempSync('messie_v1_sender').path);
  if (hs == null ||
      user == null ||
      pass == null ||
      group == null ||
      senderUser == null ||
      senderPass == null) {
    return null;
  }
  return _Env(hs, user, pass, base, group, senderUser, senderPass, senderBase);
}

Future<String?> _readAccessToken(String basePath) async {
  try {
    final file = File('$basePath/session.json');
    if (!await file.exists()) return null;
    final obj = json.decode(await file.readAsString()) as Map<String, dynamic>;
    final t = obj['access_token'] as String?;
    return (t == null || t.isEmpty) ? null : t;
  } catch (_) {
    return null;
  }
}

Future<void> _writeAccessToken(String basePath, String accessToken) async {
  try {
    await Directory(basePath).create(recursive: true);
    final file = File('$basePath/session.json');
    await file.writeAsString(json.encode({'access_token': accessToken}),
        flush: true);
  } catch (_) {
    // best-effort persist; test still proceeds
  }
}

Future<String?> _sendWithCurl(
    {required String hs,
    required String roomId,
    required String body,
    required String accessToken}) async {
  final txn = DateTime.now().millisecondsSinceEpoch.toString();
  final url = Uri.parse(
          '$hs/_matrix/client/v3/rooms/${Uri.encodeComponent(roomId)}/send/m.room.message/$txn')
      .toString();
  final payload = json.encode({'msgtype': 'm.text', 'body': body});
  final result = await Process.run('curl', [
    '-sS',
    '-X',
    'PUT',
    '-H',
    'Authorization: Bearer $accessToken',
    '-H',
    'Content-Type: application/json',
    '--data',
    payload,
    url,
  ]);
  if (result.exitCode == 0) {
    try {
      final obj = json.decode(result.stdout as String) as Map<String, dynamic>;
      return obj['event_id'] as String?;
    } catch (_) {
      return null;
    }
  }
  print('curl send failed: ${result.exitCode} ${result.stderr}');
  return null;
}

// Sender assumed already joined; skip explicit join

class _SyncCounts {
  final int n;
  final int h;
  final String nextBatch;
  final bool present;
  const _SyncCounts(this.n, this.h, this.nextBatch, this.present);
}

Future<_SyncCounts> _syncFetchCounts({
  required String hs,
  required String accessToken,
  required String roomId,
  String? since,
  int timeoutMs = 0,
  bool fullState = false,
}) async {
  final qp = <String, String>{};
  if (since != null && since.isNotEmpty) qp['since'] = since;
  if (timeoutMs > 0) qp['timeout'] = '$timeoutMs';
  if (fullState) qp['full_state'] = 'true';
  final uri = Uri.parse(hs).replace(
      path: '/_matrix/client/v3/sync', queryParameters: qp.isEmpty ? null : qp);
  final client = HttpClient();
  try {
    final req = await client.getUrl(uri);
    req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $accessToken');
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final resp = await req.close();
    final text = await utf8.decoder.bind(resp).join();
    if (resp.statusCode != 200) {
      throw Exception('sync GET failed: ${resp.statusCode} $text');
    }
    final body = json.decode(text) as Map<String, dynamic>;
    final next = (body['next_batch'] as String?) ?? '';
    final rooms = (body['rooms'] as Map?) ?? const {};
    final join = (rooms['join'] as Map?) ?? const {};
    final room = (join[roomId] as Map?) ?? const {};
    final unread = (room['unread_notifications'] as Map?) ?? const {};
    final n = (unread['notification_count'] as num?)?.toInt() ?? 0;
    final h = (unread['highlight_count'] as num?)?.toInt() ?? 0;
    final present = join.containsKey(roomId);
    return _SyncCounts(n, h, next, present);
  } finally {
    client.close(force: true);
  }
}

void main() {
  final env = _loadEnv();
  if (env == null) {
    test('skipped - env not set', () {
      expect(true, isTrue,
          reason:
              'Set MESSIE_MATRIX_* + MESSIE_GROUP_ROOM + sender env to run');
    }, skip: true);
    return;
  }

  group('v1 unread counts via CS API', () {
    test('increase after external mention while sliding sync runs', () async {
      // Receiver: login and start sliding sync (to ensure coexistence)
      final login = await rustRestoreOrLogin(
        homeserverUrl: env.hs,
        username: env.user,
        password: env.pass,
        basePath: env.base,
      );
      expect(login.isOk, isTrue, reason: login.error);
      final session = login.data!;
      final start = await rustStartSlidingSync(
        handle: 'v1-ss-unread',
        hpSize: 24,
        lpBatch: 120,
        hpTimeline: 10,
        lpTimeline: 4,
      );
      expect(start.isOk, isTrue, reason: start.error);

      // Baseline via classic sync with timeout=0, capture next_batch for incremental follow-up
      final baseSync = await _syncFetchCounts(
        hs: session.homeserverUrl,
        accessToken: session.accessToken,
        roomId: env.groupRoom,
        timeoutMs: 0,
      );
      final baseN = baseSync.n;
      final baseH = baseSync.h;
      var nextBatch = baseSync.nextBatch;
      print('baseline unread for ${env.groupRoom}: n=$baseN h=$baseH');

      // Sender: ensure we have a persisted access token to avoid login 429s
      await Directory(env.senderBase).create(recursive: true);
      var senderToken = await _readAccessToken(env.senderBase);
      if (senderToken == null || senderToken.isEmpty) {
        // Login once via v1 bridge to obtain a token and persist it
        final senderLogin = await rustRestoreOrLogin(
          homeserverUrl: env.hs,
          username: env.senderUser,
          password: env.senderPass,
          basePath: env.senderBase,
        );
        expect(senderLogin.isOk, isTrue, reason: senderLogin.error);
        senderToken = senderLogin.data!.accessToken;
        await _writeAccessToken(env.senderBase, senderToken);
      }
      final st = senderToken;
      expect(st.isNotEmpty, isTrue, reason: 'sender token missing');

      // Send a mention to try to trigger default push rules in a group.
      // Include both full user id and localpart forms to maximize matches.
      final uid = session.userId;
      final lp = (uid.startsWith('@') && uid.contains(':'))
          ? uid.substring(1, uid.indexOf(':'))
          : uid;
      final body =
          'v1 unread ping @$lp $uid ${DateTime.now().millisecondsSinceEpoch}';
      final sentEventId = await _sendWithCurl(
        hs: env.hs,
        roomId: env.groupRoom,
        body: body,
        accessToken: st,
      );
      debugPrint('send via curl: ${sentEventId ?? '(unknown event id)'}');
      expect(sentEventId != null, isTrue,
          reason: 'failed to send test message via curl');

      // Poll incremental /sync (since=baseline.next_batch) and expect counts to increase
      final end = DateTime.now().add(const Duration(seconds: 30));
      var gotN = baseN;
      var gotH = baseH;
      while (DateTime.now().isBefore(end)) {
        final s = await _syncFetchCounts(
          hs: session.homeserverUrl,
          accessToken: session.accessToken,
          roomId: env.groupRoom,
          since: nextBatch,
          timeoutMs: 10000,
        );
        if (s.nextBatch.isNotEmpty) nextBatch = s.nextBatch;
        gotN = s.n;
        gotH = s.h;
        if (s.present && gotN > baseN) break;
        await Future<void>.delayed(const Duration(seconds: 2));
      }
      debugPrint(
          'server unread after send: n=$gotN (+${gotN - baseN}) h=$gotH (+${gotH - baseH})');
      expect(gotN > baseN, isTrue,
          reason: 'notification count did not increase');
      // Highlight may depend on push rules; do not require strictly > baseline
    }, timeout: const Timeout(Duration(seconds: 90)));
  });
}
