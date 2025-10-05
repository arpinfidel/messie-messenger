import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bridge/messie_bridge.dart';

final backupControllerProvider =
    StateNotifierProvider<BackupController, BackupState>(
  (ref) => BackupController(),
);

class BackupController extends StateNotifier<BackupState> {
  BackupController() : super(const BackupState.initial());

  ReceivePort? _port;
  StreamSubscription<dynamic>? _sub;
  bool _started = false;

  Future<void> ensureStarted() async {
    if (_started) return;
    _started = true;

    // Seed initial status
    final initial = await rustBackupStatus();
    if (initial.isOk && initial.data != null) {
      state = state.copyWith(
        enabled: initial.data!.enabled,
        existsOnServer: initial.data!.existsOnServer,
        error: null,
      );
    }

    _port = ReceivePort('messie_backup_status');
    _sub = _port!.listen(_onMessage, onError: (Object e) {
      state = state.copyWith(error: e.toString());
    });
    final stream = await rustBackupStatusStream(
      handle: 'primary',
      port: _port!.sendPort,
    );
    if (!stream.isOk) {
      state = state.copyWith(error: stream.error);
    }
  }

  void _onMessage(dynamic message) {
    if (message is! String) return;
    try {
      final map = jsonDecode(message) as Map<String, dynamic>;
      if (map['kind'] == 'backup_status') {
        final enabled = map['enabled'] == true;
        final exists = map['exists_on_server'] == true;
        state = state.copyWith(enabled: enabled, existsOnServer: exists, error: null);
      }
    } catch (_) {
      // ignore
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _sub = null;
    _port?.close();
    _port = null;
    _started = false;
    super.dispose();
  }
}

class BackupState {
  const BackupState({this.enabled, this.existsOnServer, this.error});

  const BackupState.initial() : this(enabled: null, existsOnServer: null, error: null);

  final bool? enabled;
  final bool? existsOnServer;
  final String? error;

  BackupState copyWith({bool? enabled, bool? existsOnServer, String? error}) {
    return BackupState(
      enabled: enabled ?? this.enabled,
      existsOnServer: existsOnServer ?? this.existsOnServer,
      error: error,
    );
  }
}

