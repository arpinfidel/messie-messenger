import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class SecureSecrets {
  SecureSecrets({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const String _kRecoveryKey = 'messie.ssss.recovery_key';

  final FlutterSecureStorage _storage;

  Future<bool> saveRecoveryKey(String key) async {
    try {
      await _storage.write(key: _kRecoveryKey, value: key);
      return true;
    } catch (_) {
      // Fallback to file if secure storage is unavailable
      return saveRecoveryKeyToFile(key);
    }
  }

  Future<String?> loadRecoveryKey() async {
    try {
      final value = await _storage.read(key: _kRecoveryKey);
      if (value != null && value.isNotEmpty) return value;
    } catch (_) {
      // ignore and try file fallback
    }
    return loadRecoveryKeyFromFile();
  }

  Future<bool> saveRecoveryKeyToFile(String key) async {
    try {
      final file = await _recoveryKeyFile();
      await file.parent.create(recursive: true);
      final payload = jsonEncode({
        'format': 'bech32',
        'created_ms': DateTime.now().millisecondsSinceEpoch,
        'key': key,
      });
      await file.writeAsString(payload, flush: true);
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('Failed to save recovery key to file: $e');
      }
      return false;
    }
  }

  Future<String?> loadRecoveryKeyFromFile() async {
    try {
      final file = await _recoveryKeyFile();
      if (!await file.exists()) return null;
      final text = await file.readAsString();
      final map = jsonDecode(text) as Map<String, dynamic>;
      final key = map['key'] as String?;
      return (key != null && key.isNotEmpty) ? key : null;
    } catch (e) {
      if (kDebugMode) {
        print('Failed to read recovery key from file: $e');
      }
      return null;
    }
  }

  Future<void> copyToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
  }

  Future<File> _recoveryKeyFile() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, 'messie', 'matrix', 'recovery_key.json'));
  }
}

