import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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
  final FlutterSecureStorage _secure = const FlutterSecureStorage();

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

    // Prime from persisted snapshot immediately so UI renders offline.
    _primeFromPersistedSnapshot();

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

        // Merge behavior: update upserts.
        for (final p in previews) {
          _roomCache[p.roomId] = p;
        }
        _rebuildFromCache();
        // Persist snapshot so next app start can render immediately offline.
        unawaited(_persistSnapshot());
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
      // Sort by real Unix ms bumpTs when present; fallback to recency score
      // (Matrix recency, non-epoch) only for ordering/subscription decisions.
      final aTs = (a.bumpTs ?? a.recency ?? 0);
      final bTs = (b.bumpTs ?? b.recency ?? 0);
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

  // ---- Persistence (secure storage) ----
  String get _snapshotKey => 'messie.room_list.snapshot.v1';

  Future<void> _persistSnapshot() async {
    try {
      final list = _roomCache.values
          .map((p) => {
                'room_id': p.roomId,
                'name': p.name,
                'avatar_url': p.avatarUrl,
                // Persist both fields with correct semantics:
                // - latest_event_ts: real Unix ms timestamp of latest event
                // - bump_ts: Matrix recency score (non-epoch)
                'latest_event_ts': p.bumpTs,
                'bump_ts': p.recency,
                'recency': p.recency,
                'notification_count': p.notificationCount,
                'highlight_count': p.highlightCount,
                'is_marked_unread': p.isMarkedUnread,
                'is_muted': p.isMuted,
              })
          .toList(growable: false);
      await _secure.write(key: _snapshotKey, value: jsonEncode({'rooms': list}));
    } catch (_) {}
  }

  Future<void> _primeFromPersistedSnapshot() async {
    try {
      final raw = await _secure.read(key: _snapshotKey);
      if (raw == null || raw.isEmpty) return;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final arr = (map['rooms'] as List?)?.cast<Map<String, dynamic>>();
      if (arr == null) return;
      debugPrint('[RoomListController] loaded ${arr.length} rooms from persisted snapshot');
      _roomCache
        ..clear()
        ..addEntries(arr.map((e) {
          final p = RoomOverviewData.fromJson(e);
          return MapEntry(
              p.roomId,
              RoomPreview.fromOverview(p));
        }));
      _rebuildFromCache();
    } catch (_) {
      // ignore
    }
  }

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
    // Sort by Unix ms when present; fallback to recency score.
    previews.sort((a, b) {
      final aTs = (a.bumpTs ?? a.recency ?? 0);
      final bTs = (b.bumpTs ?? b.recency ?? 0);
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
