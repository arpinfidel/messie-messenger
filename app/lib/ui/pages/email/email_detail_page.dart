import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../modules/email/state/email_threads_controller.dart';

class EmailDetailPage extends ConsumerWidget {
  final String threadId;
  const EmailDetailPage({super.key, required this.threadId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    late final String title;
    if (threadId == kEmailImportantId) {
      title = 'Important';
    } else if (threadId == kEmailAllMailId) {
      title = 'All Mail';
    } else {
      title = 'Email Thread';
    }

    List<EmailHeader> messages;
    if (threadId == kEmailImportantId) {
      messages = ref.watch(emailImportantProvider);
    } else if (threadId == kEmailAllMailId) {
      messages = ref.watch(emailAllMailProvider);
    } else {
      messages = ref.watch(emailThreadByIdProvider(threadId));
    }

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemBuilder: (context, index) {
          final m = messages[index];
          return _EmailTile(message: m);
        },
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemCount: messages.length,
      ),
    );
  }
}

class _EmailTile extends StatefulWidget {
  final EmailHeader message;
  const _EmailTile({required this.message});

  @override
  State<_EmailTile> createState() => _EmailTileState();
}

class _EmailTileState extends State<_EmailTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final m = widget.message;
    return InkWell(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    m.subject.isNotEmpty ? m.subject : '(no subject)',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                if (m.flagged)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Icon(Icons.label_important_rounded, size: 16, color: Theme.of(context).colorScheme.primary),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(m.from, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            if (!_expanded) ...[
              const SizedBox(height: 4),
              Text(
                m.snippet ?? (m.body ?? ''),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ] else ...[
              const SizedBox(height: 8),
              Text(m.body ?? m.snippet ?? '(no preview)'),
            ],
          ],
        ),
      ),
    );
  }
}
