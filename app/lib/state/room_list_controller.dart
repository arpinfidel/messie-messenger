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
const _kNoUpdate = Object();

final roomListControllerProvider =
    StateNotifierProvider<RoomListController, RoomListState>(
  (ref) => RoomListController(),
);

class RoomListController extends StateNotifier<RoomListState> {
  RoomListController() : super(RoomListState.initial());

  ReceivePort? _receivePort;
  StreamSubscription<dynamic>? _subscription;
  bool _started = false;
  bool _refreshing = false;

  Future<void> start() async => _ensureStarted();

  void stop() {
    _stop();
    state = RoomListState.initial();
  }

  Future<void> loadMoreLp() async => _refreshRooms();

  Future<void> resubscribeAll() async => _refreshRooms();

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
      _subscription = _receivePort!.listen(_handleMessage, onError: (Object error) {
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

      await _refreshRooms();
    });
  }

  void _stop() {
    _started = false;
    _subscription?.cancel();
    _subscription = null;
    _receivePort?.close();
    _receivePort = null;
    _refreshing = false;
  }

  void _handleMessage(dynamic message) {
    if (!mounted || message is! String) {
      return;
    }

    try {
      final decoded = jsonDecode(message) as Map<String, dynamic>;
      final kind = decoded['kind'] as String? ?? '';
      if (kind == 'sliding_sync_ready' || kind == 'sliding_sync_update') {
        _refreshRooms();
      }
    } catch (err) {
      _setError('Failed to parse room list payload: $err');
    }
  }

  Future<void> _refreshRooms() async {
    if (!_started || _refreshing) return;
    _refreshing = true;

    if (mounted && state.hpRooms.isEmpty && state.lpRooms.isEmpty) {
      state = state.copyWith(isLoading: true, error: null);
    }

    try {
      final roomsResult = await rustListJoinedRooms();
      if (!roomsResult.isOk || roomsResult.data == null) {
        _setError(roomsResult.error ?? 'Failed to load rooms');
        return;
      }

      final previews = <RoomPreview>[];
      for (final roomId in roomsResult.data!.rooms) {
        final overviewResult = await rustRoomOverview(roomId: roomId);
        if (!overviewResult.isOk || overviewResult.data == null) {
          continue;
        }
        previews.add(RoomPreview.fromOverview(overviewResult.data!));
      }

      previews.sort((a, b) {
        final aTs = a.bumpTs ?? 0;
        final bTs = b.bumpTs ?? 0;
        final cmp = bTs.compareTo(aTs);
        if (cmp != 0) return cmp;
        return a.roomId.compareTo(b.roomId);
      });

      final hp = previews.take(_defaultHpSize).toList();
      final lp = previews.skip(_defaultHpSize).toList();

      if (mounted) {
        state = state.copyWith(
          hpRooms: hp,
          lpRooms: lp,
          hpSize: hp.length,
          lpWindow: lp.length,
          lpTotal: previews.length,
          isLoading: false,
          error: null,
        );
      }
    } catch (err) {
      _setError('Failed to refresh rooms: $err');
    } finally {
      _refreshing = false;
    }
  }

  void _setError(String message) {
    _refreshing = false;
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
        error: null,
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
    Object? error = _kNoUpdate,
  }) {
    return RoomListState(
      hpRooms: hpRooms ?? this.hpRooms,
      lpRooms: lpRooms ?? this.lpRooms,
      hpSize: hpSize ?? this.hpSize,
      lpWindow: lpWindow ?? this.lpWindow,
      lpTotal: lpTotal ?? this.lpTotal,
      isLoading: isLoading ?? this.isLoading,
      error: identical(error, _kNoUpdate) ? this.error : error as String?,
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
    required this.isMuted,
  });

  factory RoomPreview.fromOverview(RoomOverviewData data) {
    return RoomPreview(
      roomId: data.roomId,
      name: data.name,
      avatarUrl: data.avatarUrl,
      bumpTs: data.bumpTs,
      notificationCount: data.notificationCount,
      highlightCount: data.highlightCount,
      isMarkedUnread: data.isMarkedUnread,
      isMuted: data.isMuted,
    );
  }

  final String roomId;
  final String name;
  final String? avatarUrl;
  final int? bumpTs;
  final int notificationCount;
  final int highlightCount;
  final bool isMarkedUnread;
  final bool isMuted;
}
