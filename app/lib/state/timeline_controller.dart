import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bridge/messie_bridge.dart';

const _timelineHandle = 'primary';
const _defaultLoadPage = 20;
const _kNoUpdate = Object();

final timelineControllerProvider =
    StateNotifierProvider<TimelineController, TimelineState>(
  (ref) => TimelineController(),
);

class TimelineController extends StateNotifier<TimelineState> {
  TimelineController() : super(TimelineState.initial());

  ReceivePort? _receivePort;
  StreamSubscription<dynamic>? _subscription;
  String? _roomId;
  bool _isStarting = false;
  bool _loadingOlder = false;

  Future<void> openRoom(String roomId) async {
    if (_isStarting) return;
    if (_roomId == roomId && state.events.isNotEmpty) {
      return;
    }

    _isStarting = true;
    _roomId = roomId;
    state = state.copyWith(
      roomId: roomId,
      events: <TimelineItem>[],
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

    if (!result.isOk) {
      state = state.copyWith(
        isLoadingMore: false,
        error: result.error ?? 'Failed to load older messages',
      );
      _loadingOlder = false;
      return;
    }

    final data = result.data;
    state = state.copyWith(
      isLoadingMore: false,
      reachedStart: data?.reachedStart ?? state.reachedStart,
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

  void _handleMessage(dynamic message) {
    if (message is! String) {
      return;
    }

    try {
      final decoded = jsonDecode(message) as Map<String, dynamic>;
      final envelope = TimelineEnvelope.fromJson(decoded);
      if (_roomId != envelope.roomId) {
        return;
      }
      _applyEnvelope(envelope);
    } catch (err) {
      state = state.copyWith(error: 'Failed to parse timeline payload: $err');
    }
  }

  void _applyEnvelope(TimelineEnvelope envelope) {
    var events = List<TimelineItem>.from(state.events);
    TimelineChange? lastChange;

    for (final update in envelope.updates) {
      switch (update.op) {
        case TimelineOp.reset:
          events = update.items.map(TimelineItem.fromEntry).toList();
          lastChange = TimelineChange(op: TimelineOp.reset, count: events.length);
          break;
        case TimelineOp.append:
          final appended = <TimelineItem>[];
          for (final entry in update.items) {
            final item = TimelineItem.fromEntry(entry);
            if (!_contains(events, item.key)) {
              events.add(item);
              appended.add(item);
            }
          }
          if (appended.isNotEmpty) {
            lastChange = TimelineChange(op: TimelineOp.append, count: appended.length);
          }
          break;
        case TimelineOp.prepend:
          final prepended = <TimelineItem>[];
          for (final entry in update.items) {
            final item = TimelineItem.fromEntry(entry);
            if (_contains(events, item.key)) {
              continue;
            }
            events.insert(prepended.length, item);
            prepended.add(item);
          }
          if (prepended.isNotEmpty) {
            lastChange = TimelineChange(op: TimelineOp.prepend, count: prepended.length);
          }
          break;
      }
    }

    state = state.copyWith(
      events: events,
      isLoading: false,
      error: null,
      lastChange: lastChange ?? state.lastChange,
    );
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
  });

  factory TimelineItem.fromEntry(TimelineEntry entry) {
    return TimelineItem(
      key: entry.eventKey,
      sender: entry.sender,
      body: entry.body,
      timestamp:
          entry.timestamp != null ? DateTime.fromMillisecondsSinceEpoch(entry.timestamp!) : null,
      msgtype: entry.msgtype,
      isOwn: entry.isOwn,
    );
  }

  final TimelineEventKey key;
  final String sender;
  final String? body;
  final DateTime? timestamp;
  final String? msgtype;
  final bool isOwn;
}

class TimelineEventKey {
  const TimelineEventKey({this.eventId, this.transactionId});

  factory TimelineEventKey.fromJson(Map<String, dynamic> json) {
    return TimelineEventKey(
      eventId: json['event_id'] as String?,
      transactionId: json['txn_id'] as String?,
    );
  }

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

class TimelineEnvelope {
  TimelineEnvelope({required this.roomId, required this.updates});

  factory TimelineEnvelope.fromJson(Map<String, dynamic> json) {
    return TimelineEnvelope(
      roomId: json['room_id'] as String? ?? '',
      updates: (json['updates'] as List<dynamic>? ?? [])
          .map((entry) => TimelineUpdate.fromJson(entry as Map<String, dynamic>))
          .toList(),
    );
  }

  final String roomId;
  final List<TimelineUpdate> updates;
}

class TimelineUpdate {
  TimelineUpdate({required this.op, required this.items});

  factory TimelineUpdate.fromJson(Map<String, dynamic> json) {
    final opRaw = (json['op'] as String? ?? 'RESET').toUpperCase();
    return TimelineUpdate(
      op: TimelineOp.values
          .firstWhere((value) => value.name.toUpperCase() == opRaw, orElse: () => TimelineOp.reset),
      items: (json['items'] as List<dynamic>? ?? [])
          .map((item) => TimelineEntry.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  final TimelineOp op;
  final List<TimelineEntry> items;
}

class TimelineEntry {
  const TimelineEntry({
    required this.eventKey,
    required this.timestamp,
    required this.sender,
    required this.body,
    required this.msgtype,
    required this.isOwn,
  });

  factory TimelineEntry.fromJson(Map<String, dynamic> json) {
    final keyJson = json['event_key'];
    return TimelineEntry(
      eventKey: keyJson is Map<String, dynamic>
          ? TimelineEventKey.fromJson(keyJson)
          : const TimelineEventKey(),
      timestamp: (json['timestamp'] as num?)?.toInt(),
      sender: json['sender'] as String? ?? 'Unknown',
      body: json['body'] as String?,
      msgtype: json['msgtype'] as String?,
      isOwn: json['is_own'] as bool? ?? false,
    );
  }

  final TimelineEventKey eventKey;
  final int? timestamp;
  final String sender;
  final String? body;
  final String? msgtype;
  final bool isOwn;
}

enum TimelineOp { reset, append, prepend }

class TimelineChange {
  const TimelineChange({required this.op, required this.count});

  final TimelineOp op;
  final int count;
}
