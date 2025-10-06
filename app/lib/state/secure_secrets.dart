import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// Abstraction for storing/loading the recovery key. Production should use
// SecureStorageRecoveryKeyStore. Tests/CI can inject FileRecoveryKeyStore.
abstract class RecoveryKeyStore {
  Future<void> write(String key);
  Future<String?> read();
}

class SecureStorageRecoveryKeyStore implements RecoveryKeyStore {
  SecureStorageRecoveryKeyStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const String _kRecoveryKey = 'messie.ssss.recovery_key';
  final FlutterSecureStorage _storage;

  @override
  Future<void> write(String key) async {
    await _storage.write(key: _kRecoveryKey, value: key);
  }

  @override
  Future<String?> read() async {
    final value = await _storage.read(key: _kRecoveryKey);
    return (value != null && value.isNotEmpty) ? value : null;
  }
}

// Plaintext file implementation intended for CI/headless usage only.
class FileRecoveryKeyStore implements RecoveryKeyStore {
  FileRecoveryKeyStore({Directory? baseDir}) : _baseDir = baseDir;

  final Directory? _baseDir;

  @override
  Future<void> write(String key) async {
    final file = await _recoveryKeyFile();
    await file.parent.create(recursive: true);
    final payload = jsonEncode({
      'format': 'bech32',
      'created_ms': DateTime.now().millisecondsSinceEpoch,
      'key': key,
    });
    await file.writeAsString(payload, flush: true);
  }

  @override
  Future<String?> read() async {
    final file = await _recoveryKeyFile();
    if (!await file.exists()) return null;
    final text = await file.readAsString();
    try {
      final map = jsonDecode(text) as Map<String, dynamic>;
      final key = map['key'] as String?;
      return (key != null && key.isNotEmpty) ? key : null;
    } catch (_) {
      // Allow plain text as a convenience in CI.
      final trimmed = text.trim();
      return trimmed.isNotEmpty ? trimmed : null;
    }
  }

  Future<File> _recoveryKeyFile() async {
    final dir = _baseDir ?? await getApplicationSupportDirectory();
    return File(p.join(dir.path, 'messie', 'matrix', 'recovery_key.json'));
  }
}

class SecureSecrets {
  SecureSecrets({RecoveryKeyStore? store})
      : _store = store ?? SecureStorageRecoveryKeyStore();

  final RecoveryKeyStore _store;

  // Save to the configured store. No automatic fallback.
  Future<bool> saveRecoveryKey(String key) async {
    try {
      await _store.write(key);
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('Failed to save recovery key: $e');
      }
      return false;
    }
  }

  // Load from the configured store only. No automatic fallback.
  Future<String?> loadRecoveryKey() async {
    try {
      return await _store.read();
    } catch (e) {
      if (kDebugMode) {
        print('Failed to load recovery key: $e');
      }
      return null;
    }
  }

  Future<void> copyToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
  }
}
