import 'package:flutter_riverpod/flutter_riverpod.dart';

class SelectedThread {
  const SelectedThread({required this.module, required this.threadId});
  final String module;
  final String threadId;
}

final selectedThreadProvider = StateProvider<SelectedThread?>((ref) => null);

