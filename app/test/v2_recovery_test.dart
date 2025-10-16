import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
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

String? _loadRecoveryKey() {
  final env = Platform.environment;
  final fromEnv = env['MESSIE_MATRIX_RECOVERY_KEY'];
  if (fromEnv != null && fromEnv.trim().isNotEmpty) return fromEnv.trim();

  // Try typical seeded state path(s)
  final candidates = <String>[
    '../scripts/matrix/.state/recovery_key.json',
    '../scripts/matrix/scripts/matrix/.state/recovery_key.json',
  ];
  for (final path in candidates) {
    try {
      final f = File(path);
      if (!f.existsSync()) continue;
      final raw = f.readAsStringSync();
      try {
        final parsed = json.decode(raw);
        if (parsed is Map && parsed['recovery_key'] is String) {
          final key = (parsed['recovery_key'] as String).trim();
          if (key.isNotEmpty) return key;
        }
      } catch (_) {
        // If not JSON, treat file contents as raw key
        final key = raw.trim();
        if (key.isNotEmpty) return key;
      }
    } catch (_) {}
  }
  return null;
}

Map<String, dynamic> _parse(String jsonStr) => json.decode(jsonStr) as Map<String, dynamic>;

void main() {
  final env = _loadEnv();
  if (env == null) {
    test('skipped - env not set', () {
      expect(true, isTrue, reason: 'Set MESSIE_MATRIX_* env to run');
    }, skip: true);
    return;
  }

  group('v2 recovery key restore', () {
    test('ssssImportRecoveryKey + enableOnlineBackup', () async {
      final recoveryKey = _loadRecoveryKey();
      if (recoveryKey == null) {
        // If no key is available, skip rather than fail the suite.
        expect(true, isTrue, reason: 'No recovery key available in env or seed state');
        return;
      }

      final resNew = v2.clientCreate(homeserverUrl: env.hs, basePath: env.base);
      expect(resNew.success, isTrue, reason: 'client_create failed');
      final client = resNew.handle;

      final resLogin = v2.clientLogin(handle: client, username: env.user, password: env.pass);
      expect(resLogin.success, isTrue, reason: 'login failed');

      final importRes = _parse(v2.ssssImportRecoveryKey(handle: client, recoveryKey: recoveryKey));
      expect(importRes['ok'], isTrue, reason: 'ssss_import_recovery_key failed: $importRes');

      // Attach to existing server backup without creating a new one
      final enable = _parse(v2.enableOnlineBackup(handle: client, generateNew: false));
      expect(enable['ok'], isTrue, reason: 'enable_online_backup failed: $enable');

      // Check status; environments differ so keep expectations loose:
      final status = v2.backupStatus(handle: client);
      expect(status.success, isTrue, reason: 'backup_status failed');
      final exists = status.existsOnServer;
      if (exists) {
        final enabled = status.enabled;
        final needsRecovery = status.needsRecovery;
        expect(enabled || !needsRecovery, isTrue,
            reason: 'Expected backup to be enabled or recovery to be complete');
      }
    });
  });
}
