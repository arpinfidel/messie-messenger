import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'module_registry.dart';
import 'module_types.dart';

// HomeThread model moved to module_types.dart for reuse by modules

// ---- Module thread adapters ----

/// Aggregated Home threads from all registered modules, sorted by bumpTs desc then name.
/// This is the immediate (non-debounced) source.
final rawHomeThreadsProvider = Provider<List<HomeThread>>((ref) {
  final modules = ref.watch(moduleRegistryProvider);
  final all = <HomeThread>[];
  for (final m in modules) {
    all.addAll(m.provideThreads(ref));
  }
  all.sort((a, b) {
    final at = a.bumpTs ?? 0;
    final bt = b.bumpTs ?? 0;
    final cmp = bt.compareTo(at); // newest first
    if (cmp != 0) return cmp;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  // Debug: log first few items to verify ordering
  assert(() {
    String fmtTs(int? v) => v == null ? '-' : v.toString();
    final preview = all.take(12).map((t) {
      return '${t.module}:${t.name} ts=${fmtTs(t.bumpTs)}';
    }).join(' | ');
    // ignore: avoid_print
    print('[home] ordered=${all.length} first=${preview}');
    return true;
  }());
  return all;
});

/// Trailing debounce of Home threads so rapid module updates don't thrash the UI.
/// Publishes updates 250ms after the latest change (no leading call).
class _HomeThreadsDebouncer extends StateNotifier<List<HomeThread>> {
  _HomeThreadsDebouncer(this._ref) : super(const <HomeThread>[]) {
    // Schedule initial publish after debounce window
    _schedule(_ref.read(rawHomeThreadsProvider));
    // Listen for changes in the raw provider and debounce updates
    _sub = _ref.listen<List<HomeThread>>(rawHomeThreadsProvider, (prev, next) {
      _schedule(next);
    });
  }

  final Ref _ref;
  Timer? _timer;
  ProviderSubscription<List<HomeThread>>? _sub;

  void _schedule(List<HomeThread> value) {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 250), () {
      state = value;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sub?.close();
    super.dispose();
  }
}

/// Debounced Home threads provider consumed by the UI.
final homeThreadsProvider =
    StateNotifierProvider<_HomeThreadsDebouncer, List<HomeThread>>(
  (ref) => _HomeThreadsDebouncer(ref),
);
