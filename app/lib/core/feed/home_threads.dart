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
    final cmp = bt.compareTo(at);
    if (cmp != 0) return cmp;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return all;
});
