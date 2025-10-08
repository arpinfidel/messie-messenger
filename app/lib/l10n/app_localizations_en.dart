// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Messie';

  @override
  String get login_signIn => 'Sign in securely';

  @override
  String get login_signingIn => 'Signing in…';

  @override
  String get login_passwordRequired => 'Password is required';

  @override
  String get emulator_host_rewrite => 'Using 10.0.2.2 to reach host from Android emulator';

  @override
  String get login_privacyNote => 'Matrix credentials never leave your device.';

  @override
  String messages_count(num howMany) {
    String _temp0 = intl.Intl.pluralLogic(
      howMany,
      locale: localeName,
      other: '$howMany messages',
      one: '1 message',
      zero: 'No messages',
    );
    return '$_temp0';
  }
}
