import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../main.dart' show HomeScreen; // Reuse existing root screen for now.
import '../settings/settings_screen.dart';
import '../../screens/connections_screen.dart';

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
      GoRoute(
        path: '/connections',
        name: 'connections',
        builder: (context, state) => const ConnectionsScreen(),
      ),
    ],
    // Reserved for deep links and state restoration later
    debugLogDiagnostics: false,
  );
}
