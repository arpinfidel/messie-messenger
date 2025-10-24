import 'package:go_router/go_router.dart';

import 'package:messie_app/modules/matrix/ui/home_screen.dart' show HomeScreen;
import '../settings/settings_screen.dart';
import '../pages/chats/chats_page.dart';
import '../pages/settings/connections/connections_list_page.dart';
import '../pages/settings/connections/provider_detail_page.dart';
import '../pages/settings/theme_demo_page.dart';

GoRouter buildAppRouter() {
  return GoRouter(
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        name: 'home',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/settings',
        name: 'settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      // New UI demo routes (non-breaking):
      GoRoute(
        path: '/chats',
        name: 'chats',
        builder: (context, state) => const ChatsPage(),
      ),
      GoRoute(
        path: '/settings/connections',
        name: 'connections_list',
        builder: (context, state) => const ConnectionsListPage(),
      ),
      GoRoute(
        path: '/settings/connections/provider',
        name: 'provider_detail',
        builder: (context, state) {
          final provider = state.extra as String? ?? 'provider';
          return ProviderDetailPage(provider: provider);
        },
      ),
      GoRoute(
        path: '/settings/theme-demo',
        name: 'theme_demo',
        builder: (context, state) => const ThemeDemoPage(),
      ),
      // no separate feed route; feed abstraction is integrated into Home
    ],
    // Reserved for deep links and state restoration later
    debugLogDiagnostics: false,
  );
}
