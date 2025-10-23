import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bridge/messie_bridge.dart';

const _timelineHandle = 'primary';
const _defaultLoadPage = 20;
const _kNoUpdate = Object();

final timelineControllerProvider =
    StateNotifierProvider<TimelineViewModel, TimelineState>(
  (ref) => TimelineViewModel(),
);

class TimelineViewModel extends StateNotifier<TimelineState> {
  TimelineViewModel() : super(TimelineState.initial());

  ReceivePort? _receivePort;
  StreamSubscription<dynamic>? _subscription;
  String? _roomId;
  bool _isStarting = false;
  bool _loadingOlder = false;
  final Set<String> _attemptedKeyDownload = <String>{};

  Future<void> openRoom(String roomId) async {
    if (_isStarting) return;
    if (_roomId == roomId && state.events.isNotEmpty) {
      return;
    }

    _isStarting = true;
    _roomId = roomId;
    state = state.copyWith(
      roomId: roomId,
      events: const <TimelineItem>[],
      isLoading: true,
      error: null,
      lastChange: null,
      reachedStart: false,
      isLoadingMore: false,
    );

    final openResult = await rustOpenRoom(handle: _timelineHandle, roomId: roomId);
    if (!openResult.isOk) {
      _isStarting = false;
      state = state.copyWith(
        isLoading: false,
        error: openResult.error ?? 'Failed to open room timeline',
      );
      return;
    }

    await _startStream(roomId);

    // Opportunistically attempt to fetch room keys from backup once per room.
    // This helps make encrypted history readable without manual recovery.
    if (!_attemptedKeyDownload.contains(roomId)) {
      _attemptedKeyDownload.add(roomId);
      // Fire-and-forget; on success, refresh the snapshot to benefit from
      // decryption on the Rust side.
      unawaited(() async {
        final download = await rustDownloadRoomKeysForRoom(roomId: roomId);
        if (download.isOk) {
          // Re-registering the stream triggers a fresh snapshot which should
          // now contain decrypted events.
          if (_roomId == roomId) {
            await _startStream(roomId);
          }
        }
      }());
    }
    _isStarting = false;
  }

  Future<void> _startStream(String roomId) async {
    _receivePort?.close();
    await _subscription?.cancel();

    _receivePort = ReceivePort('messie_timeline_$roomId');
    _subscription = _receivePort!.listen(_handleMessage, onError: (Object error) {
      state = state.copyWith(error: 'Timeline stream error: $error');
    });

    final streamResult = await rustTimelineStream(
      handle: _timelineHandle,
      roomId: roomId,
      port: _receivePort!.sendPort,
    );

    if (!streamResult.isOk) {
      await _subscription?.cancel();
      _subscription = null;
      _receivePort?.close();
      _receivePort = null;
      state = state.copyWith(
        isLoading: false,
        error: streamResult.error ?? 'Failed to subscribe to timeline stream',
      );
      return;
    }

    state = state.copyWith(isLoading: false, error: null);
  }

  Future<void> loadOlder({int limit = _defaultLoadPage}) async {
    if (_loadingOlder || _roomId == null || state.reachedStart) {
      return;
    }
    _loadingOlder = true;
    state = state.copyWith(isLoadingMore: true, error: null, lastChange: null);

    final result = await rustLoadBackward(
      handle: _timelineHandle,
      roomId: _roomId!,
      limit: limit,
    );

    if (!result.isOk || result.data == null) {
      state = state.copyWith(
        isLoadingMore: false,
        error: result.error ?? 'Failed to load older messages',
      );
      _loadingOlder = false;
      return;
    }

    final data = result.data!;
    final items = data.events
        .map(_parseTimelineEvent)
        .whereType<TimelineItem>()
        .toList(growable: false);

    if (items.isNotEmpty) {
      final events = List<TimelineItem>.from(state.events);
      for (final item in items.reversed) {
        if (_contains(events, item.key)) {
          continue;
        }
        events.insert(0, item);
      }
      state = state.copyWith(
        events: events,
        lastChange: TimelineChange(op: TimelineOp.prepend, count: items.length),
      );
    }

    state = state.copyWith(
      isLoadingMore: false,
      reachedStart: data.reachedStart,
    );
    _loadingOlder = false;
  }

  void acknowledgeChange() {
    if (state.lastChange != null) {
      state = state.copyWith(lastChange: null);
    }
  }

  void stop() {
    _roomId = null;
    _subscription?.cancel();
    _subscription = null;
    _receivePort?.close();
    _receivePort = null;
    state = TimelineState.initial();
  }

  Future<bool> sendText({required String roomId, required String body, String? replyTo}) async {
    final res = await rustSendText(roomId: roomId, body: body, replyTo: replyTo);
    if (!res.isOk) {
      // Surface the error in state for observers; UI may also show a snackbar.
      state = state.copyWith(error: res.error ?? 'Failed to send');
    }
    return res.isOk;
  }

  // UI policies (centralized for consistency/testing)
  bool shouldShowJumpToLatest(double distanceFromBottom) => distanceFromBottom > 200;
  bool shouldAutoScrollToLatest(double distanceFromBottom) => distanceFromBottom < 120;

  void _handleMessage(dynamic message) {
    if (_roomId == null || message is! String) {
      return;
    }

    try {
      final decoded = jsonDecode(message) as Map<String, dynamic>;
      final roomId = decoded['room_id'] as String?;
      if (roomId != _roomId) {
        return;
      }
      final kind = decoded['kind'] as String? ?? '';
      final eventsRaw = (decoded['events'] as List<dynamic>? ?? [])
          .map((value) => value as String)
          .toList(growable: false);

      switch (kind) {
        case 'timeline_snapshot':
        case 'timeline_initial':
          _applySnapshot(eventsRaw);
          // If after snapshot we still have no readable messages, try a
          // one-off room keys download and refresh the stream.
          if ((state.events.isEmpty) && _roomId != null) {
            final roomId = _roomId!;
            if (!_attemptedKeyDownload.contains(roomId)) {
              _attemptedKeyDownload.add(roomId);
              unawaited(() async {
                final download = await rustDownloadRoomKeysForRoom(roomId: roomId);
                if (download.isOk && _roomId == roomId) {
                  await _startStream(roomId);
                }
              }());
            }
          }
          break;
        case 'timeline_append':
          _appendEvents(eventsRaw);
          break;
        default:
          break;
      }
    } catch (err) {
      state = state.copyWith(error: 'Failed to parse timeline payload: $err');
    }
  }

  void _applySnapshot(List<String> rawEvents) {
    final items = rawEvents
        .map(_parseTimelineEvent)
        .whereType<TimelineItem>()
        .toList(growable: false);

    state = state.copyWith(
      events: items,
      isLoading: false,
      error: null,
      lastChange: TimelineChange(op: TimelineOp.reset, count: items.length),
    );
  }

  void _appendEvents(List<String> rawEvents) {
    final parsed = rawEvents
        .map(_parseTimelineEvent)
        .whereType<TimelineItem>()
        .toList(growable: false);

    if (parsed.isEmpty) {
      return;
    }

    final events = List<TimelineItem>.from(state.events);
    final appended = <TimelineItem>[];
    for (final item in parsed) {
      if (_contains(events, item.key)) {
        continue;
      }
      events.add(item);
      appended.add(item);
    }

    if (appended.isEmpty) {
      return;
    }

    state = state.copyWith(
      events: events,
      isLoading: false,
      error: null,
      lastChange: TimelineChange(op: TimelineOp.append, count: appended.length),
    );
  }

  TimelineItem? _parseTimelineEvent(String raw) {
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      // Keep user-visible events: plain messages and encrypted (until decrypted).
      final type = map['type'] as String?;
      if (type != 'm.room.message' && type != 'm.room.encrypted') {
        return null;
      }
      return TimelineItem.fromRaw(map);
    } catch (_) {
      return null;
    }
  }

  bool _contains(List<TimelineItem> items, TimelineEventKey key) {
    return items.any((item) => item.key == key);
  }
}

class TimelineState {
  const TimelineState({
    required this.roomId,
    required this.events,
    required this.isLoading,
    required this.isLoadingMore,
    required this.reachedStart,
    this.error,
    this.lastChange,
  });

  factory TimelineState.initial() => const TimelineState(
        roomId: null,
        events: [],
        isLoading: false,
        isLoadingMore: false,
        reachedStart: false,
        error: null,
        lastChange: null,
      );

  final String? roomId;
  final List<TimelineItem> events;
  final bool isLoading;
  final bool isLoadingMore;
  final bool reachedStart;
  final String? error;
  final TimelineChange? lastChange;

  TimelineState copyWith({
    String? roomId,
    List<TimelineItem>? events,
    bool? isLoading,
    bool? isLoadingMore,
    bool? reachedStart,
    Object? error = _kNoUpdate,
    Object? lastChange = _kNoUpdate,
  }) {
    return TimelineState(
      roomId: roomId ?? this.roomId,
      events: events ?? this.events,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      reachedStart: reachedStart ?? this.reachedStart,
      error: identical(error, _kNoUpdate) ? this.error : error as String?,
      lastChange:
          identical(lastChange, _kNoUpdate) ? this.lastChange : lastChange as TimelineChange?,
    );
  }
}

class TimelineItem {
  const TimelineItem({
    required this.key,
    required this.sender,
    required this.body,
    required this.timestamp,
    required this.msgtype,
    required this.isOwn,
    required this.raw,
  });

  factory TimelineItem.fromRaw(Map<String, dynamic> json) {
    final eventId = json['event_id'] as String?;
    final unsigned = json['unsigned'] as Map<String, dynamic>? ?? const {};
    final txnId = unsigned['transaction_id'] as String?;
    final sender = json['sender'] as String? ?? 'Unknown';
    final ts = (json['origin_server_ts'] as num?)?.toInt();
    final content = json['content'] as Map<String, dynamic>? ?? const {};
    final msgtype = content['msgtype'] as String?;
    final body = _extractBody(json['type'] as String? ?? '', content);

    return TimelineItem(
      key: TimelineEventKey(eventId: eventId, transactionId: txnId),
      sender: sender,
      body: body,
      timestamp: ts != null ? DateTime.fromMillisecondsSinceEpoch(ts) : null,
      msgtype: msgtype,
      isOwn: false,
      raw: json,
    );
  }

  static String? _extractBody(String eventType, Map<String, dynamic> content) {
    // For message events, prefer plain body and fall back to formatted.
    if (eventType == 'm.room.message') {
      return content['body'] as String? ?? content['formatted_body'] as String?;
    }
    if (eventType == 'm.room.encrypted') {
      return '[encrypted]';
    }
    // Other events were filtered earlier.
    return null;
  }

  final TimelineEventKey key;
  final String sender;
  final String? body;
  final DateTime? timestamp;
  final String? msgtype;
  final bool isOwn;
  final Map<String, dynamic> raw;
}

class TimelineEventKey {
  const TimelineEventKey({this.eventId, this.transactionId});

  final String? eventId;
  final String? transactionId;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! TimelineEventKey) return false;
    return eventId == other.eventId && transactionId == other.transactionId;
  }

  @override
  int get hashCode => Object.hash(eventId, transactionId);
}

enum TimelineOp { reset, append, prepend }

class TimelineChange {
  const TimelineChange({required this.op, required this.count});

  final TimelineOp op;
  final int count;
}
