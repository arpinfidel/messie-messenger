import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Global selection state for the active thread/room.
/// Kept in state layer so views remain side‑effect free.
final selectedRoomIdProvider = StateProvider<String?>((ref) => null);

