import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';

import '../../../bridge/messie_bridge.dart';
import '../../../services/counts_sync_service.dart';

const _slidingSyncHandle = 'primary';
const String _envForceOffline = String.fromEnvironment('MESSIE_FORCE_OFFLINE', defaultValue: '');
const _defaultHpSize = 12;
const _defaultLpBatch = 40;
// Request a few events per room so the SDK can compute a proper
// latest_event (with a real origin_server_ts). A value of 5 keeps
// bandwidth modest while ensuring a message-like event is usually present.
// Request a deeper timeline by default to help the SDK compute latest events
// reliably without extra calls.
const _defaultHpTimeline = 20;
const _defaultLpTimeline = 20;
const _kNoUpdate = Object();

final roomListControllerProvider =
    StateNotifierProvider<RoomListViewModel, RoomListState>(
  (ref) => RoomListViewModel(ref),
);

class RoomListViewModel extends StateNotifier<RoomListState> {
  RoomListViewModel(this._ref) : super(RoomListState.initial());

  final Ref _ref;

  ReceivePort? _receivePort;
  StreamSubscription<dynamic>? _subscription;
  bool _started = false;
  // Legacy throttling flags removed; sliding sync drives updates.
  final Map<String, RoomPreview> _roomCache = <String, RoomPreview>{};
  // Track last subscription set to avoid redundant FFI calls.
  Set<String> _lastSubscribed = <String>{};
  ProviderSubscription<Map<String, UnreadCounts>>? _countsSub;

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

    _countsSub =
        _ref.listen<Map<String, UnreadCounts>>(countsSyncProvider, (prev, next) {
      if (_started) _rebuildFromCache();
    });

    // Keep it simple: no offline snapshot priming. Rely on live Sliding Sync.

    // Allow forcing offline in tests via --dart-define=MESSIE_FORCE_OFFLINE=true
    final forceOffline = _envForceOffline == '1' || _envForceOffline.toLowerCase() == 'true';
    if (forceOffline) {
      state = state.copyWith(isLoading: false);
      return;
    }

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

      // Room data will arrive via sliding sync snapshots/updates.

      // Align with the test flow: explicitly subscribe to a window of joined
      // rooms so per-room timelines flow promptly. This avoids waiting for
      // the SDK cache to hydrate before we see latest_event_ts.
      try {
        final rooms = await rustListJoinedRooms();
        if (rooms.isOk && rooms.data != null && rooms.data!.rooms.isNotEmpty) {
          final ids = rooms.data!.rooms.take(64).toList(growable: false);
          await rustSlidingSyncSubscribeRooms(
            handle: _slidingSyncHandle,
            roomIds: ids,
            reset: true,
          );
        }
      } catch (_) {}
    });
  }

  void _stop() {
    _started = false;
    _subscription?.cancel();
    _subscription = null;
    _receivePort?.close();
    _receivePort = null;
    _countsSub?.close();
    _countsSub = null;
  }

  void _handleMessage(dynamic message) {
    if (!mounted || message is! String) {
      return;
    }

    try {
      final decoded = jsonDecode(message) as Map<String, dynamic>;
      final kind = decoded['kind'] as String? ?? '';
      if (kind == 'sliding_sync_update') {
        // Build room previews directly from sliding sync summaries to avoid N calls.
        final raw = decoded['summaries'];
        List<RoomPreview> previews = <RoomPreview>[];
        try {
          if (raw is List) {
            previews = raw
                .whereType<Map>()
                .map((e) => RoomOverviewData.fromJson(e.cast<String, dynamic>()))
                .map(RoomPreview.fromOverview)
                .toList();
          } else if (raw is Map) {
            // Some builds may send a map of roomId -> summary
            previews = raw.values
                .whereType<Map>()
                .map((e) => RoomOverviewData.fromJson(e.cast<String, dynamic>()))
                .map(RoomPreview.fromOverview)
                .toList();
          }
        } catch (_) {
          // fall through to fallback below
        }

        // Fallback: if summaries are missing/empty, derive minimal previews from room IDs.
        if (previews.isEmpty) {
          final roomsRaw = decoded['rooms'];
          final List<String> roomIds;
          if (roomsRaw is List) {
            roomIds = roomsRaw.map((e) => e.toString()).toList();
          } else if (roomsRaw is Map) {
            roomIds = roomsRaw.keys.map((e) => e.toString()).toList();
          } else {
            roomIds = const <String>[];
          }
          previews = roomIds
              .map((id) => RoomPreview(
                    roomId: id,
                    name: id,
                    avatarUrl: null,
                    bumpTs: null,
                    recency: null,
                    notificationCount: 0,
                    highlightCount: 0,
                    isMarkedUnread: false,
                    isMuted: false,
                  ))
              .toList();
        }

        // Merge behavior: update upserts but never downgrade a real timestamp
        // to an empty one. If we already have a positive Unix ms for a room,
        // keep it unless the incoming preview provides a newer positive value.
        for (final p in previews) {
          final existing = _roomCache[p.roomId];
          if (existing == null) {
            _roomCache[p.roomId] = p;
            continue;
          }
          final int oldTs = existing.bumpTs ?? 0;
          final int newTs = p.bumpTs ?? 0;
          final merged = RoomPreview(
            roomId: p.roomId,
            name: p.name,
            avatarUrl: p.avatarUrl,
            bumpTs: (newTs > 0) ? newTs : oldTs,
            recency: p.recency ?? existing.recency,
            notificationCount: p.notificationCount,
            highlightCount: p.highlightCount,
            isMarkedUnread: p.isMarkedUnread,
            isMuted: p.isMuted,
          );
          _roomCache[p.roomId] = merged;
        }
        // Diagnostics: count rooms that carry a real latest_event_ts (bumpTs)
        assert(() {
          final withTs = _roomCache.values.where((p) => (p.bumpTs ?? 0) > 0).length;
          String fmtTs(int? v) => v == null || v <= 0 ? '-' : v.toString();
          final sample = _roomCache.values
              .take(8)
              .map((p) => '${p.name} ts=${fmtTs(p.bumpTs)}')
              .join(' | ');
          // ignore: avoid_print
          print('[room-list] cache=${_roomCache.length} with_ts=$withTs sample=[ $sample ]');
          return true;
        }());
        _rebuildFromCache();
        // Refresh subscriptions based on the latest ordering.
        unawaited(_refreshRooms());
      } else if (kind == 'sliding_sync_ready') {
        // Ignore 'ready' for cache mutation; we already sent/primed a snapshot.
      }
    } catch (err) {
      // Non-fatal: ignore malformed payloads; next update will reconcile.
      debugPrint('[RoomListController] Failed to parse sliding sync payload: $err');
    }
  }

  Future<void> _refreshRooms() async {
    if (!_started) return;
    // Build the current ordered list using the same sort as _rebuildFromCache
    final counts = _ref.read(countsSyncProvider);
    final previews = _roomCache.values.map((p) {
      final c = counts[p.roomId];
      if (c == null) return p;
      return RoomPreview(
        roomId: p.roomId,
        name: p.name,
        avatarUrl: p.avatarUrl,
        bumpTs: p.bumpTs,
        recency: p.recency,
        notificationCount: c.notification,
        highlightCount: c.highlight,
        isMarkedUnread: p.isMarkedUnread,
        isMuted: p.isMuted,
      );
    }).toList();

    previews.sort((a, b) {
      // Sort strictly by real Unix ms timestamps. Do not use Matrix recency
      // here, as it is not an epoch and causes "x1000"-looking values in UI.
      final aTs = a.bumpTs ?? 0;
      final bTs = b.bumpTs ?? 0;
      final cmp = bTs.compareTo(aTs);
      if (cmp != 0) return cmp;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    // Choose a reasonable subscribe window: all HP + first LP window.
    final hp = previews.take(_defaultHpSize).toList();
    // Subscribe to a modest LP window beyond HP to keep timelines warm.
    final lpWindow = previews.skip(_defaultHpSize).take(_defaultLpBatch).toList();

    final next = <String>{
      ...hp.map((r) => r.roomId),
      ...lpWindow.map((r) => r.roomId),
    };

    if (setEquals(next, _lastSubscribed)) return;
    final isInitial = _lastSubscribed.isEmpty;
    _lastSubscribed = next;

    try {
      // Reset to cancel any in-flight subscriptions for rooms we dropped.
      final res = await rustSlidingSyncSubscribeRooms(
        handle: _slidingSyncHandle,
        roomIds: next.toList(growable: false),
        // Avoid thrashing resets; use reset only for the initial subscribe.
        reset: isInitial,
      );
      if (!res.isOk) {
        debugPrint('[RoomListController] subscribe_rooms failed: ${res.error}');
      }
    } catch (e) {
      debugPrint('[RoomListController] subscribe_rooms threw: $e');
    }
  }

  // No persistence: keep runtime-only state for clarity during debugging.

  void _rebuildFromCache() {
    final counts = _ref.read(countsSyncProvider);
    final previews = _roomCache.values.map((p) {
      final c = counts[p.roomId];
      if (c == null) return p;
      return RoomPreview(
        roomId: p.roomId,
        name: p.name,
        avatarUrl: p.avatarUrl,
        bumpTs: p.bumpTs,
        recency: p.recency,
        notificationCount: c.notification,
        highlightCount: c.highlight,
        isMarkedUnread: p.isMarkedUnread,
        isMuted: p.isMuted,
      );
    }).toList();
    // Sort strictly by Unix ms; never use recency for ordering/display.
    previews.sort((a, b) {
      final aTs = a.bumpTs ?? 0;
      final bTs = b.bumpTs ?? 0;
      final cmp = bTs.compareTo(aTs);
      if (cmp != 0) return cmp;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
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
  }

  void _setError(String message) {
    if (!mounted) return;
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
    required this.recency,
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
      recency: data.recency,
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
  final int? recency; // matrix recency score (non-epoch)
  final int notificationCount;
  final int highlightCount;
  final bool isMarkedUnread;
  final bool isMuted;
}
