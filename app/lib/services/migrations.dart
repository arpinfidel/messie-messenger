import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Simple storage schema migrations.
///
/// Keeps a single integer version in secure storage and applies ordered
/// migrations to bump to the current version.
class MigrationManager {
  static const _versionKey = 'messie.storage.version';
  static const int currentVersion = 2;

  final FlutterSecureStorage _store;

  MigrationManager({FlutterSecureStorage? store})
      : _store = store ?? const FlutterSecureStorage();

  Future<void> run() async {
    int version = 0;
    try {
      final raw = await _store.read(key: _versionKey);
      version = int.tryParse(raw ?? '0') ?? 0;
    } catch (_) {}

    if (version < 2) {
      await _toV2();
      version = 2;
    }

    try {
      await _store.write(key: _versionKey, value: version.toString());
    } catch (e) {
      debugPrint('[Migration] failed to write storage version: $e');
    }
  }

  /// v2: Force counts filter recreation by removing old v1 filter entries.
  /// We changed the filter content to include m.receipt and m.fully_read so
  /// unread counters update when reads happen on other clients.
  Future<void> _toV2() async {
    try {
      final all = await _store.readAll();
      for (final key in all.keys) {
        // Remove any v1 filter-id entries so the app creates a new filter.
        if (key.startsWith('messie.counts.filter.') &&
            !key.startsWith('messie.counts.filter.v2.')) {
          await _store.delete(key: key);
        }
      }
      debugPrint('[Migration] v2 complete: cleared old counts filter keys');
    } catch (e) {
      debugPrint('[Migration] v2 failed: $e');
    }
  }
}

