import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../bridge/messie_bridge.dart';

final pingProvider = FutureProvider<String>((ref) async {
  return rustPing();
});

