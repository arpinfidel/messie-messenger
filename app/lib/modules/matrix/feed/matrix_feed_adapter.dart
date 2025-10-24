import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../bridge/messie_bridge.dart';
import '../../../core/feed/models.dart';
import '../state/auth_view_model.dart';
import '../state/room_list_view_model.dart';

final matrixFeedAdapterProvider = Provider<MatrixFeedAdapter>((ref) {
  return MatrixFeedAdapter(ref);
});

class MatrixFeedAdapter {
  MatrixFeedAdapter(this._ref);

  final Ref _ref;
  final Map<String, _RoomFeed> _rooms = <String, _RoomFeed>{};
  final _controller = StreamController<List<FeedItem>>.broadcast();
  Stream<List<FeedItem>> get updates => _controller.stream;
  ProviderSubscription<RoomListState>? _roomListSub;
  bool _started = false;

  void start({int maxRooms = 8}) {
    if (_started) return;
    _started = true;
    _roomListSub = _ref.listen<RoomListState>(
      roomListControllerProvider,
      (prev, next) async {
        await _syncRooms(next, maxRooms: maxRooms);
      },
      fireImmediately: true,
    );
  }

  Future<void> _syncRooms(RoomListState state, {required int maxRooms}) async {
    final ordered = <RoomPreview>[...state.hpRooms, ...state.lpRooms]
        ..sort((a, b) => (b.bumpTs ?? 0).compareTo(a.bumpTs ?? 0));
    final selected = ordered.take(maxRooms).toList(growable: false);
    final selectedIds = selected.map((r) => r.roomId).toSet();

    // Stop removed rooms
    for (final rid in List<String>.from(_rooms.keys)) {
      if (!selectedIds.contains(rid)) {
        await _rooms.remove(rid)?.stop();
      }
    }
    // Start new rooms
    for (final room in selected) {
      _rooms.putIfAbsent(room.roomId, () {
        final rf = _RoomFeed(ref: _ref, room: room, onItems: _emitItems);
        unawaited(rf.start());
        return rf;
      }).room = room; // keep preview fresh for title/avatar if needed
    }
  }

  void _emitItems(List<FeedItem> items) {
    if (items.isEmpty) return;
    _controller.add(items);
  }

  Future<void> stop() async {
    _roomListSub?.close();
    _roomListSub = null;
    for (final rf in _rooms.values) {
      await rf.stop();
    }
    _rooms.clear();
    _started = false;
  }
}

class _RoomFeed {
  _RoomFeed({required this.ref, required this.room, required this.onItems});

  final Ref ref;
  RoomPreview room;
  final void Function(List<FeedItem>) onItems;
  ReceivePort? _port;
  StreamSubscription<dynamic>? _sub;
  bool _running = false;
  late final String _handle = 'feed_${room.roomId}';

  Future<void> start() async {
    if (_running) return;
    _running = true;
    final open = await rustOpenRoom(handle: _handle, roomId: room.roomId);
    if (!open.isOk) {
      debugPrint('[MatrixFeedAdapter] openRoom failed: ${open.error}');
      _running = false;
      return;
    }
    _port = ReceivePort('messie_feed_${room.roomId}');
    _sub = _port!.listen(_onMessage, onError: (Object e) {
      debugPrint('[MatrixFeedAdapter] timeline error: $e');
    });
    final stream = await rustTimelineStream(
      handle: _handle,
      roomId: room.roomId,
      port: _port!.sendPort,
    );
    if (!stream.isOk) {
      debugPrint('[MatrixFeedAdapter] stream failed: ${stream.error}');
    }
  }

  Future<void> stop() async {
    _running = false;
    await _sub?.cancel();
    _sub = null;
    _port?.close();
    _port = null;
  }

  void _onMessage(dynamic message) {
    if (message is! String) return;
    try {
      final decoded = jsonDecode(message) as Map<String, dynamic>;
      final kind = decoded['kind'] as String? ?? '';
      final eventsRaw = (decoded['events'] as List<dynamic>? ?? [])
          .map((value) => value as String)
          .toList(growable: false);
      switch (kind) {
        case 'timeline_snapshot':
        case 'timeline_initial':
        case 'timeline_append':
          final items = eventsRaw
              .map(_parse)
              .whereType<FeedItem>()
              .toList(growable: false);
          if (items.isNotEmpty) onItems(items);
          break;
        default:
          break;
      }
    } catch (e) {
      debugPrint('[MatrixFeedAdapter] parse error: $e');
    }
  }

  FeedItem? _parse(String raw) {
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final type = map['type'] as String?;
      if (type != 'm.room.message' && type != 'm.room.encrypted') return null;
      final eventId = map['event_id'] as String?;
      final unsigned = map['unsigned'] as Map<String, dynamic>? ?? const {};
      final txnId = unsigned['transaction_id'] as String?;
      final sender = map['sender'] as String?;
      final ts = (map['origin_server_ts'] as num?)?.toInt();
      final content = map['content'] as Map<String, dynamic>? ?? const {};
      final msgtype = content['msgtype'] as String?;
      final body = _extractBody(type ?? '', content);
      final session = ref.read(authControllerProvider).asData?.value;
      final isOwn = session != null && sender == session.userId;
      final id = 'matrix:${room.roomId}:${eventId ?? txnId ?? ''}';
      return FeedItem(
        id: id,
        module: FeedModule.matrix,
        threadId: room.roomId,
        timestamp: ts != null ? DateTime.fromMillisecondsSinceEpoch(ts) : null,
        isOwn: isOwn,
        sender: sender,
        title: room.name,
        body: body,
        extras: <String, Object?>{
          'msgtype': msgtype,
        },
      );
    } catch (_) {
      return null;
    }
  }

  String? _extractBody(String eventType, Map<String, dynamic> content) {
    if (eventType == 'm.room.message') {
      return content['body'] as String? ?? content['formatted_body'] as String?;
    }
    if (eventType == 'm.room.encrypted') {
      return '[encrypted]';
    }
    return null;
  }
}

