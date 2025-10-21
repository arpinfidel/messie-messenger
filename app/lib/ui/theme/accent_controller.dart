import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'colors.dart';

final accentControllerProvider =
    AsyncNotifierProvider<AccentController, MessieAccent>(AccentController.new);

class AccentController extends AsyncNotifier<MessieAccent> {
  static const _kAccentKey = 'messie.accent';

  @override
  Future<MessieAccent> build() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_kAccentKey);
    switch (stored) {
      case 'peach':
        return MessieAccent.peach;
      case 'violet':
        return MessieAccent.violet;
      case 'slate':
        return MessieAccent.slate;
      case 'aqua':
      default:
        return MessieAccent.aqua;
    }
  }

  Future<void> setAccent(MessieAccent accent) async {
    state = AsyncData(accent);
    final prefs = await SharedPreferences.getInstance();
    final value = switch (accent) {
      MessieAccent.aqua => 'aqua',
      MessieAccent.peach => 'peach',
      MessieAccent.violet => 'violet',
      MessieAccent.slate => 'slate',
    };
    await prefs.setString(_kAccentKey, value);
  }
}
