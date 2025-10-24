import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models.dart';
import '../../modules/matrix/feed/matrix_feed_adapter.dart';
import '../../modules/matrix/state/auth_view_model.dart';

final feedAggregatorProvider =
    StateNotifierProvider<FeedAggregator, FeedState>((ref) => FeedAggregator(ref));

class FeedAggregator extends StateNotifier<FeedState> {
  FeedAggregator(this._ref) : super(FeedState.initial()) {
    // Start/stop with session
    _ref.listen(authControllerProvider, (prev, next) {
      if (next.asData?.value != null) {
        _start();
      } else {
        _stop();
      }
    }, fireImmediately: true);
  }

  final Ref _ref;
  StreamSubscription<List<FeedItem>>? _matrixSub;

  void _start() {
    if (_matrixSub != null) return;
    final adapter = _ref.read(matrixFeedAdapterProvider);
    adapter.start();
    _matrixSub = adapter.updates.listen((items) {
      _merge(items);
    });
    state = state.copyWith(isLoading: false, error: null);
  }

  Future<void> _stop() async {
    await _matrixSub?.cancel();
    _matrixSub = null;
    await _ref.read(matrixFeedAdapterProvider).stop();
    state = FeedState.initial();
  }

  void _merge(List<FeedItem> batch, {int maxItems = 400}) {
    if (batch.isEmpty) return;
    final map = <String, FeedItem>{
      for (final i in state.items) i.id: i,
    };
    for (final i in batch) {
      map[i.id] = i;
    }
    final sorted = map.values.toList()
      ..sort((a, b) {
        final ta = a.timestamp?.millisecondsSinceEpoch ?? 0;
        final tb = b.timestamp?.millisecondsSinceEpoch ?? 0;
        return tb.compareTo(ta); // desc
      });
    if (sorted.length > maxItems) {
      sorted.removeRange(maxItems, sorted.length);
    }
    state = state.copyWith(items: sorted, isLoading: false, error: null);
  }
}

