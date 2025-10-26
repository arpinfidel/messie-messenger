import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'module_registry.dart';
import 'module_types.dart';

// HomeThread model moved to module_types.dart for reuse by modules

// ---- Module thread adapters ----

/// Aggregated Home threads from all registered modules, sorted by bumpTs desc then name.
final homeThreadsProvider = Provider<List<HomeThread>>((ref) {
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
