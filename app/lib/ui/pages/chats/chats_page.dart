import 'package:flutter/material.dart';
import '../../components/empty_state.dart';

class ChatsPage extends StatelessWidget {
  const ChatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chats')),
      body: const MessieEmptyState(
        icon: Icons.chat_bubble_outline,
        title: 'No Chats Yet',
        message: 'Your chats will appear here once you connect a service.',
      ),
    );
  }
}

