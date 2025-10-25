import 'package:go_router/go_router.dart';

import 'package:messie_app/ui/pages/feed/home_screen.dart' show HomeScreen;
import '../settings/settings_screen.dart';
import '../pages/chats/chats_page.dart';
import '../pages/settings/connections/connections_list_page.dart';
import '../pages/settings/connections/provider_detail_page.dart';
import '../pages/settings/theme_demo_page.dart';
import '../pages/todo/todo_detail_page.dart';
import '../pages/email/email_detail_page.dart';
import '../pages/settings/connections/email_setup_page.dart';
import '../pages/settings/connections/email_gmail_connect_page.dart';
import '../pages/settings/connections/email_imap_oauth_connect_page.dart';

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
        path: '/settings/connections/email-setup',
        name: 'email_setup',
        builder: (context, state) => const EmailSetupPage(),
      ),
      GoRoute(
        path: '/settings/connections/email-gmail',
        name: 'email_gmail',
        builder: (context, state) => const EmailGmailConnectPage(),
      ),
      GoRoute(
        path: '/settings/connections/email-imap-oauth/:providerId',
        name: 'email_imap_oauth',
        builder: (context, state) {
          final providerId = state.pathParameters['providerId'] ?? '';
          return EmailImapOAuthConnectPage(providerId: providerId);
        },
      ),
      GoRoute(
        path: '/settings/connections/provider',
        name: 'provider_detail',
        builder: (context, state) {
          String provider = 'whatsapp';
          final extra = state.extra;
          if (extra is String) {
            provider = extra;
          } else if (extra is Map) {
            provider = (extra['provider'] as String?) ?? provider;
          }
          return ProviderDetailPage(provider: provider);
        },
      ),
      
      GoRoute(
        path: '/settings/theme-demo',
        name: 'theme_demo',
        builder: (context, state) => const ThemeDemoPage(),
      ),
      GoRoute(
        path: '/todo/:listId',
        name: 'todo_detail',
        builder: (context, state) {
          final listId = state.pathParameters['listId'] ?? '';
          return TodoDetailPage(listId: listId);
        },
      ),
      GoRoute(
        path: '/email/:threadId',
        name: 'email_detail',
        builder: (context, state) {
          final threadId = state.pathParameters['threadId'] ?? '';
          return EmailDetailPage(threadId: threadId);
        },
      ),
      // no separate feed route; feed abstraction is integrated into Home
    ],
    // Reserved for deep links and state restoration later
    debugLogDiagnostics: false,
  );
}
