import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/feed/feed_aggregator.dart';
import '../../../core/feed/models.dart';
import '../../../theme/messie_tokens.dart';

class UnifiedFeedScreen extends ConsumerWidget {
  const UnifiedFeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(feedAggregatorProvider);
    final spacing = MessieSpacing.of(context);
    final gutter = MessieSpacing.gutter(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Feed')),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: EdgeInsets.symmetric(horizontal: gutter, vertical: spacing.gap.md),
              itemCount: state.items.length,
              itemBuilder: (context, index) {
                final item = state.items[index];
                return _FeedCell(item: item);
              },
            ),
    );
  }
}

class _FeedCell extends StatelessWidget {
  const _FeedCell({required this.item});
  final FeedItem item;

  @override
  Widget build(BuildContext context) {
    final spacing = MessieSpacing.of(context);
    final colors = Theme.of(context).colorScheme;
    final icon = switch (item.module) {
      FeedModule.matrix => Icons.chat_bubble_outline_rounded,
      FeedModule.email => Icons.alternate_email_rounded,
      FeedModule.todo => Icons.checklist_rounded,
    };

    return Card(
      child: Padding(
        padding: EdgeInsets.all(spacing.gap.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: colors.onSurfaceVariant),
            SizedBox(width: spacing.gap.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title ?? item.threadId,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (item.body != null)
                    Padding(
                      padding: EdgeInsets.only(top: spacing.gap.xs),
                      child: Text(
                        item.body!,
                        style: Theme.of(context).textTheme.bodyMedium,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

