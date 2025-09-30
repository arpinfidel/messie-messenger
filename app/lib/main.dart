import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bridge/messie_bridge.dart';

final pingProvider = FutureProvider<String>((ref) async {
  return rustPing();
});

void main() {
  runApp(const ProviderScope(child: MessieApp()));
}

class MessieApp extends StatelessWidget {
  const MessieApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Messie',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.teal,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pingState = ref.watch(pingProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Messie Messenger'),
      ),
      body: Center(
        child: pingState.when(
          data: (value) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Flutter + Rust (flutter_rust_bridge)',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 16),
              Text('Rust says: $value'),
            ],
          ),
          loading: () => const CircularProgressIndicator(),
          error: (error, stackTrace) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning, color: Colors.amber, size: 48),
              const SizedBox(height: 16),
              Text('Failed to call Rust: $error'),
            ],
          ),
        ),
      ),
    );
  }
}
