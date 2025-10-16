import 'dart:async';
import 'dart:ffi';
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


Future<Map<String, dynamic>> _waitForKinds(
  Stream<dynamic> stream,
  Set<String> kinds, {
  Duration timeout = const Duration(seconds: 30),
  String label = 'v2-backup',
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
      if (kinds.contains(kind)) return decoded;
    } catch (_) {}
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

  group('v2 backup / ssss smoke', () {
    test('backup_status + stream ack', () async {
      final resNew = v2.clientCreate(homeserverUrl: env.hs, basePath: env.base);
      expect(resNew.success, isTrue, reason: 'client_create failed');
      final client = resNew.handle;

      final resLogin = v2.clientLogin(handle: client, username: env.user, password: env.pass);
      expect(resLogin.success, isTrue, reason: 'login failed');

      final status = v2.backupStatus(handle: client);
      expect(status.success, isTrue, reason: 'backup_status failed');

      final port = ReceivePort('v2_backup');
      final stream = port.asBroadcastStream();
      final ok = v2.backupStatusStream(handle: client, port: port.sendPort.nativePort);
      expect(ok, isTrue, reason: 'backup_status_stream failed');
      // Expect at least one status payload
      final snap = await _waitForKinds(stream, {'backup_status'});
      expect(snap['kind'], equals('backup_status'));
      port.close();
    });
  });
}
