import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'l10n/app_localizations.dart';
import 'modules/matrix/state/session_coordinator.dart';
import 'services/migrations.dart';
import 'ui/core/back_esc/back_esc_host.dart';
import 'ui/core/input/input_caps.dart';
import 'ui/core/layout/app_layout.dart';
import 'ui/navigation/app_router.dart';
import 'ui/theme/accent_controller.dart';
import 'ui/theme/colors.dart' show MessieAccent;
import 'ui/theme/theme.dart' as messie_theme;
import 'ui/theme/theme_controller.dart';

// Re-exports for external access to providers
export 'modules/matrix/state/auth_view_model.dart';
export 'modules/matrix/state/ping.dart';
export 'modules/matrix/state/trust_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Run storage migrations before any session-dependent services start.
  await MigrationManager().run();
  runApp(const ProviderScope(child: MessieApp()));
}

// providers moved to state/ping.dart and state/trust_state.dart

class MessieApp extends ConsumerWidget {
  const MessieApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Ensure session-driven services are started/stopped centrally.
    ref.watch(sessionCoordinatorProvider);
    final themeMode = ref.watch(themeControllerProvider).maybeWhen(
          data: (m) => m,
          orElse: () => ThemeMode.system,
        );
    final accent = ref.watch(accentControllerProvider).maybeWhen(
          data: (a) => a,
          orElse: () => MessieAccent.aqua,
        );

    return MaterialApp.router(
      title: 'Messie',
      theme: messie_theme.MessieThemeBuilder.build(
        brightness: Brightness.light,
        accent: accent,
      ),
      darkTheme: messie_theme.MessieThemeBuilder.build(
        brightness: Brightness.dark,
        accent: accent,
      ),
      themeMode: themeMode,
      debugShowCheckedModeBanner: false,
      routerConfig: buildAppRouter(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => BackEscHost(
        child: AppLayout(
          child: InputCaps(
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}

// Matrix HomeScreen and related widgets moved to modules/matrix/ui/home_screen.dart

