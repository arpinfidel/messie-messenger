import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bridge/messie_bridge.dart';

const _slidingSyncHandle = 'primary';
const _defaultHpSize = 12;
const _defaultLpBatch = 40;
const _defaultHpTimeline = 5;
const _defaultLpTimeline = 1;

final roomListControllerProvider =
    StateNotifierProvider<RoomListController, RoomListState>(
  (ref) => RoomListController(),
);

class RoomListController extends StateNotifier<RoomListState> {
  RoomListController() : super(RoomListState.initial());

  ReceivePort? _receivePort;
  StreamSubscription<dynamic>? _subscription;
  bool _started = false;

  Future<void> start() async => _ensureStarted();

  void stop() {
    _stop();
    state = RoomListState.initial();
  }

  Future<void> loadMoreLp() async {
    if (!_started) return;
    final result = await rustSubscribeMoreLp(handle: _slidingSyncHandle);
    if (!result.isOk) {
      _setError(result.error ?? 'Failed to request more rooms');
    }
  }

  Future<void> resubscribeAll() async {
    if (!_started) return;
    final result = await rustResubscribeAll(handle: _slidingSyncHandle);
    if (!result.isOk) {
      _setError(result.error ?? 'Failed to resubscribe');
    }
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  void _ensureStarted() {
    if (_started) return;
    _started = true;
    state = state.copyWith(isLoading: true, error: null);

    Future<void>(() async {
      final startResult = await rustStartSlidingSync(
        handle: _slidingSyncHandle,
        hpSize: _defaultHpSize,
        lpBatch: _defaultLpBatch,
        hpTimeline: _defaultHpTimeline,
        lpTimeline: _defaultLpTimeline,
      );

      if (!startResult.isOk) {
        _stop();
        _setError(startResult.error ?? 'Failed to start sliding sync');
        return;
      }

      _receivePort = ReceivePort('messie_room_list');
      _subscription =
          _receivePort!.listen(_handleMessage, onError: (Object error) {
        _setError('Room stream error: $error');
      });

      final streamResult = await rustRoomListStream(
        handle: _slidingSyncHandle,
        port: _receivePort!.sendPort,
      );

      if (!streamResult.isOk) {
        _setError(streamResult.error ?? 'Failed to subscribe to room stream');
        _stop();
        return;
      }
      if (mounted) {
        state = state.copyWith(isLoading: false, error: null);
      }
    });
  }

  void _stop() {
    _started = false;
    _subscription?.cancel();
    _subscription = null;
    _receivePort?.close();
    _receivePort = null;
  }

  void _handleMessage(dynamic message) {
    if (!mounted) {
      return;
    }
    if (message is! String) {
      return;
    }

    try {
      final decoded = jsonDecode(message) as Map<String, dynamic>;
      final envelope = RoomListEnvelope.fromJson(decoded);
      _applyEnvelope(envelope);
    } catch (err) {
      _setError('Failed to parse room list payload: $err');
    }
  }

  void _applyEnvelope(RoomListEnvelope envelope) {
    final hp = List<RoomPreview>.from(state.hpRooms);
    final lp = List<RoomPreview>.from(state.lpRooms);

    for (final update in envelope.updates) {
      final target = update.list == RoomListKind.hp ? hp : lp;
      _applyOps(target, update.ops);
    }

    if (!mounted) {
      return;
    }
    state = state.copyWith(
      hpRooms: hp,
      lpRooms: lp,
      hpSize: envelope.hpSize,
      lpWindow: envelope.lpWindow,
      lpTotal: envelope.lpTotal,
      isLoading: false,
      error: null,
    );
  }

  void _applyOps(List<RoomPreview> target, List<RoomListOp> ops) {
    for (final op in ops) {
      switch (op) {
        case InsertOp(:final index, :final item):
          final insertIndex = index.clamp(0, target.length);
          target.insert(insertIndex, item.toPreview());
          break;
        case UpdateOp(:final index, :final item):
          if (index >= 0 && index < target.length) {
            target[index] = item.toPreview();
          }
          break;
        case RemoveOp(:final index):
          if (index >= 0 && index < target.length) {
            target.removeAt(index);
          }
          break;
        case ReorderOp(:final from, :final to):
          if (from < 0 || from >= target.length) {
            continue;
          }
          final entry = target.removeAt(from);
          final insertIndex = to.clamp(0, target.length);
          target.insert(insertIndex, entry);
          break;
      }
    }
  }

  void _setError(String message) {
    if (!mounted) {
      return;
    }
    state = state.copyWith(error: message, isLoading: false);
  }
}

class RoomListState {
  const RoomListState({
    required this.hpRooms,
    required this.lpRooms,
    required this.hpSize,
    required this.lpWindow,
    required this.lpTotal,
    required this.isLoading,
    this.error,
  });

  factory RoomListState.initial() => const RoomListState(
        hpRooms: [],
        lpRooms: [],
        hpSize: 0,
        lpWindow: 0,
        lpTotal: 0,
        isLoading: true,
      );

  final List<RoomPreview> hpRooms;
  final List<RoomPreview> lpRooms;
  final int hpSize;
  final int lpWindow;
  final int lpTotal;
  final bool isLoading;
  final String? error;

  RoomListState copyWith({
    List<RoomPreview>? hpRooms,
    List<RoomPreview>? lpRooms,
    int? hpSize,
    int? lpWindow,
    int? lpTotal,
    bool? isLoading,
    String? error,
  }) {
    return RoomListState(
      hpRooms: hpRooms ?? this.hpRooms,
      lpRooms: lpRooms ?? this.lpRooms,
      hpSize: hpSize ?? this.hpSize,
      lpWindow: lpWindow ?? this.lpWindow,
      lpTotal: lpTotal ?? this.lpTotal,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class RoomPreview {
  const RoomPreview({
    required this.roomId,
    required this.name,
    required this.avatarUrl,
    required this.bumpTs,
    required this.notificationCount,
    required this.highlightCount,
    required this.isMarkedUnread,
  });

  final String roomId;
  final String name;
  final String? avatarUrl;
  final int? bumpTs;
  final int notificationCount;
  final int highlightCount;
  final bool isMarkedUnread;
}

class RoomListEnvelope {
  RoomListEnvelope({
    required this.hpSize,
    required this.lpWindow,
    required this.lpTotal,
    required this.updates,
  });

  factory RoomListEnvelope.fromJson(Map<String, dynamic> json) {
    return RoomListEnvelope(
      hpSize: (json['hp_size'] as num?)?.toInt() ?? 0,
      lpWindow: (json['lp_window'] as num?)?.toInt() ?? 0,
      lpTotal: (json['lp_total'] as num?)?.toInt() ?? 0,
      updates: (json['updates'] as List<dynamic>? ?? [])
          .map(
              (entry) => RoomListUpdate.fromJson(entry as Map<String, dynamic>))
          .toList(),
    );
  }

  final int hpSize;
  final int lpWindow;
  final int lpTotal;
  final List<RoomListUpdate> updates;
}

class RoomListUpdate {
  RoomListUpdate({required this.list, required this.ops});

  factory RoomListUpdate.fromJson(Map<String, dynamic> json) {
    final listRaw = (json['list'] as String? ?? 'hp').toLowerCase();
    final kind = listRaw == 'lp' ? RoomListKind.lp : RoomListKind.hp;
    return RoomListUpdate(
      list: kind,
      ops: (json['ops'] as List<dynamic>? ?? [])
          .map((entry) => RoomListOp.fromJson(entry as Map<String, dynamic>))
          .toList(),
    );
  }

  final RoomListKind list;
  final List<RoomListOp> ops;
}

enum RoomListKind { hp, lp }

abstract class RoomListOp {
  const RoomListOp();

  factory RoomListOp.fromJson(Map<String, dynamic> json) {
    final op = (json['op'] as String? ?? '').toUpperCase();
    switch (op) {
      case 'INSERT':
        return InsertOp(
          index: (json['index'] as num?)?.toInt() ?? 0,
          item: RoomListItem.fromJson(json['item'] as Map<String, dynamic>),
        );
      case 'UPDATE':
        return UpdateOp(
          index: (json['index'] as num?)?.toInt() ?? 0,
          item: RoomListItem.fromJson(json['item'] as Map<String, dynamic>),
        );
      case 'REMOVE':
        return RemoveOp(index: (json['index'] as num?)?.toInt() ?? 0);
      case 'REORDER':
        return ReorderOp(
          from: (json['from'] as num?)?.toInt() ?? 0,
          to: (json['to'] as num?)?.toInt() ?? 0,
        );
      default:
        return const RemoveOp(index: -1);
    }
  }
}

class InsertOp extends RoomListOp {
  const InsertOp({required this.index, required this.item});

  final int index;
  final RoomListItem item;
}

class UpdateOp extends RoomListOp {
  const UpdateOp({required this.index, required this.item});

  final int index;
  final RoomListItem item;
}

class RemoveOp extends RoomListOp {
  const RemoveOp({required this.index});

  final int index;
}

class ReorderOp extends RoomListOp {
  const ReorderOp({required this.from, required this.to});

  final int from;
  final int to;
}

class RoomListItem {
  const RoomListItem({
    required this.roomId,
    required this.name,
    required this.avatarUrl,
    required this.bumpTs,
    required this.notificationCount,
    required this.highlightCount,
    required this.isMarkedUnread,
  });

  factory RoomListItem.fromJson(Map<String, dynamic> json) {
    return RoomListItem(
      roomId: json['room_id'] as String,
      name: json['name'] as String? ?? json['room_id'] as String,
      avatarUrl: json['avatar_url'] as String?,
      bumpTs: (json['bump_ts'] as num?)?.toInt(),
      notificationCount: (json['notification_count'] as num?)?.toInt() ?? 0,
      highlightCount: (json['highlight_count'] as num?)?.toInt() ?? 0,
      isMarkedUnread: json['is_marked_unread'] as bool? ?? false,
    );
  }

  final String roomId;
  final String name;
  final String? avatarUrl;
  final int? bumpTs;
  final int notificationCount;
  final int highlightCount;
  final bool isMarkedUnread;

  RoomPreview toPreview() {
    return RoomPreview(
      roomId: roomId,
      name: name,
      avatarUrl: avatarUrl,
      bumpTs: bumpTs,
      notificationCount: notificationCount,
      highlightCount: highlightCount,
      isMarkedUnread: isMarkedUnread,
    );
  }
}
