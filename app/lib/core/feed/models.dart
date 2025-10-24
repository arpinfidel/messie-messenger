enum FeedModule { matrix, email, todo }

class FeedItem {
  const FeedItem({
    required this.id,
    required this.module,
    required this.threadId,
    required this.timestamp,
    this.isOwn = false,
    this.sender,
    this.title,
    this.body,
    this.extras = const {},
  });

  final String id; // canonical: module:threadId:itemId
  final FeedModule module;
  final String threadId; // roomId/emailThreadId/todoListId
  final DateTime? timestamp;
  final bool isOwn;
  final String? sender;
  final String? title;
  final String? body;
  final Map<String, Object?> extras;
}

class FeedState {
  const FeedState({
    required this.items,
    required this.isLoading,
    this.error,
  });

  factory FeedState.initial() => const FeedState(items: <FeedItem>[], isLoading: true);

  final List<FeedItem> items;
  final bool isLoading;
  final String? error;

  FeedState copyWith({List<FeedItem>? items, bool? isLoading, String? error}) {
    return FeedState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

