import 'dart:async'; // moved to neutral feed UI
import 'dart:io' show File, Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:messie_app/bridge/messie_bridge.dart';
import 'package:messie_app/l10n/app_localizations.dart';
import 'package:messie_app/modules/matrix/state/auth_view_model.dart';
import 'package:messie_app/modules/matrix/state/room_list_view_model.dart';
import 'package:messie_app/modules/matrix/state/selection.dart';
import 'package:messie_app/modules/matrix/state/timeline_view_model.dart';
import 'package:messie_app/theme/messie_tokens.dart';
import 'package:messie_app/ui/components/segmented_control.dart';
import 'package:messie_app/ui/core/back_esc/back_esc_policy.dart';
import 'package:messie_app/modules/matrix/services/profile_repository.dart';
import 'package:messie_app/modules/matrix/services/media_repository.dart';
import 'package:messie_app/core/feed/home_threads.dart';
import 'package:messie_app/core/feed/module_types.dart';
import 'package:messie_app/core/feed/module_registry.dart';
import 'package:messie_app/modules/todo/services/todo_repository.dart';
import 'package:messie_app/modules/todo/state/todo_threads_controller.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});
  static DateTime? _lastBackPress;
  static const Duration _exitInterval = Duration(seconds: 2);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<AsyncValue<MatrixSession?>>(authControllerProvider,
        (previous, next) {
      if (next.hasError) {
        final message = _errorMessage(next.error);
        if (message != null) {
          final messenger = ScaffoldMessenger.maybeOf(context);
          messenger?.showSnackBar(
            SnackBar(content: Text(message)),
          );
        }
      }
    });

    final authState = ref.watch(authControllerProvider);

    if (authState.isLoading && !authState.hasValue && !authState.hasError) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final session = authState.asData?.value;
    final errorText =
        authState.hasError ? _errorMessage(authState.error) : null;

    Widget content;
    if (session != null) {
      content = BackEscSurface(
        priority: SurfacePriority.route,
        onDismiss: () async {
          final popped = await Navigator.of(context).maybePop();
          return popped;
        },
        child: LoggedInView(session: session),
      );
    } else {
      content = BackEscSurface(
        priority: SurfacePriority.route,
        onDismiss: () async {
          final popped = await Navigator.of(context).maybePop();
          return popped;
        },
        child: LoginView(
          isProcessing: authState.isLoading,
          errorMessage: errorText,
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        // Avoid using BuildContext across the await boundary
        final policy = BackEscPolicy.of(context);
        final messenger = ScaffoldMessenger.maybeOf(context);
        final handled = await policy.handleBack();
        if (handled) return;

        final now = DateTime.now();
        final last = _lastBackPress;
        if (last != null && now.difference(last) <= _exitInterval) {
          if (Platform.isAndroid) {
            SystemNavigator.pop();
          }
          return;
        }
        _lastBackPress = now;
        messenger?.clearSnackBars();
        messenger?.showSnackBar(
          const SnackBar(
            content: Text('Press back again to exit'),
            duration: Duration(seconds: 2),
          ),
        );
      },
      child: content,
    );
  }

  String? _errorMessage(Object? error) {
    if (error == null) {
      return null;
    }
    if (error is AuthException) {
      return error.message;
    }
    return error.toString();
  }
}

class LoginView extends ConsumerStatefulWidget {
  const LoginView({
    super.key,
    required this.isProcessing,
    this.errorMessage,
  });

  final bool isProcessing;
  final String? errorMessage;

  @override
  ConsumerState<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends ConsumerState<LoginView> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _homeserverController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    // Default to local Synapse from Docker for Android emulator.
    _homeserverController = TextEditingController(text: 'http://10.0.2.2:8008');
    _usernameController = TextEditingController();
    _passwordController = TextEditingController();
  }

  @override
  void dispose() {
    _homeserverController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final spacing = MessieSpacing.of(context);
    final radii = MessieRadii.of(context);
    final surfaces = MessieSurfaces.of(context);
    final gutter = MessieSpacing.gutter(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: gutter,
                vertical: spacing.gap.xxl,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: surfaces.surface1,
                  borderRadius: BorderRadius.circular(radii.lg),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: spacing.gap.xl,
                    vertical: spacing.gap.xl,
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        CircleAvatar(
                          radius: 32,
                          backgroundColor: colorScheme.primaryContainer,
                          child: Icon(
                            Icons.bubble_chart_rounded,
                            color: colorScheme.onPrimaryContainer,
                            size: 36,
                          ),
                        ),
                        SizedBox(height: spacing.gap.xl),
                        Text(
                          'Welcome to Messie',
                          style: textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        SizedBox(height: spacing.gap.sm),
                        Text(
                          'Stay connected with an encrypted Matrix-first messenger.',
                          style: textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        SizedBox(height: spacing.gap.xl),
                        if (widget.errorMessage != null)
                          Container(
                            padding: EdgeInsets.all(spacing.gap.lg),
                            margin: EdgeInsets.only(bottom: spacing.gap.xl),
                            decoration: BoxDecoration(
                              color: colorScheme.errorContainer,
                              borderRadius: BorderRadius.circular(radii.lg),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.error_outline,
                                    color: colorScheme.onErrorContainer),
                                SizedBox(width: spacing.gap.sm),
                                Expanded(
                                  child: Text(
                                    widget.errorMessage!,
                                    style: textTheme.bodyMedium?.copyWith(
                                      color: colorScheme.onErrorContainer,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        TextFormField(
                          controller: _homeserverController,
                          decoration: const InputDecoration(
                            labelText: 'Homeserver URL',
                            hintText: 'https://matrix-client.matrix.org',
                            prefixIcon: Icon(Icons.public_rounded),
                          ),
                          enabled: !widget.isProcessing,
                          keyboardType: TextInputType.url,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Homeserver URL is required';
                            }
                            final trimmed = value.trim();
                            if (!trimmed.startsWith('http://') &&
                                !trimmed.startsWith('https://')) {
                              return 'Enter a valid URL starting with http or https';
                            }
                            return null;
                          },
                        ),
                        SizedBox(height: spacing.gap.lg),
                        TextFormField(
                          controller: _usernameController,
                          decoration: const InputDecoration(
                            labelText: 'Username or user ID',
                            hintText: '@user:matrix.org',
                            prefixIcon: Icon(Icons.person_outline_rounded),
                          ),
                          enabled: !widget.isProcessing,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Username is required';
                            }
                            return null;
                          },
                        ),
                        SizedBox(height: spacing.gap.lg),
                        TextFormField(
                          controller: _passwordController,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                            suffixIcon: IconButton(
                              icon: Icon(_obscurePassword
                                  ? Icons.visibility
                                  : Icons.visibility_off),
                              onPressed: widget.isProcessing
                                  ? null
                                  : () {
                                      setState(() {
                                        _obscurePassword = !_obscurePassword;
                                      });
                                    },
                            ),
                          ),
                          enabled: !widget.isProcessing,
                          obscureText: _obscurePassword,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return l10n?.login_passwordRequired ??
                                  'Password is required';
                            }
                            return null;
                          },
                        ),
                        SizedBox(height: spacing.gap.xxl),
                        FilledButton.icon(
                          onPressed: widget.isProcessing
                              ? null
                              : () => _submit(context),
                          icon: widget.isProcessing
                              ? SizedBox(
                                  width: spacing.gap.sm,
                                  height: spacing.gap.sm,
                                  child: const CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              : const Icon(Icons.login_rounded),
                          label: Text(widget.isProcessing
                              ? (l10n?.login_signingIn ?? 'Signing in…')
                              : (l10n?.login_signIn ?? 'Sign in securely')),
                        ),
                        SizedBox(height: spacing.gap.md),
                        Text(
                          l10n?.login_privacyNote ??
                              'Matrix credentials never leave your device.',
                          textAlign: TextAlign.center,
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit(BuildContext context) async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    FocusScope.of(context).unfocus();
    var homeserverText = _homeserverController.text.trim();

    // On Android emulator, rewrite localhost/127.0.0.1 to 10.0.2.2 and inform the user.
    try {
      final uri = Uri.parse(homeserverText);
      if (Platform.isAndroid &&
          (uri.host == 'localhost' || uri.host == '127.0.0.1')) {
        final rewritten = uri.replace(host: '10.0.2.2').toString();
        if (rewritten != homeserverText) {
          homeserverText = rewritten;
          _homeserverController.text = homeserverText;
          final messenger = ScaffoldMessenger.maybeOf(context);
          messenger?.showSnackBar(
            SnackBar(
              content: Text(
                  AppLocalizations.of(context)?.emulator_host_rewrite ??
                      'Using 10.0.2.2 to reach host from Android emulator'),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (_) {
      // If parse fails, proceed without rewrite.
    }

    await ref.read(authControllerProvider.notifier).login(
          homeserverUrl: homeserverText,
          username: _usernameController.text,
          password: _passwordController.text,
        );
  }
}

class LoggedInView extends ConsumerWidget {
  const LoggedInView({
    super.key,
    required this.session,
  });

  final MatrixSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Services are orchestrated by sessionCoordinatorProvider now.
    final roomListState = ref.watch(roomListControllerProvider);
    final timelineState = ref.watch(timelineControllerProvider);
    final selectedRoomId = ref.watch(selectedRoomIdProvider);
    final spacing = MessieSpacing.of(context);
    final gutter = MessieSpacing.gutter(context);

    void selectRoom(String roomId) {
      if (ref.read(selectedRoomIdProvider) == roomId) {
        return;
      }
      ref.read(selectedRoomIdProvider.notifier).state = roomId;
      ref.read(timelineControllerProvider.notifier).openRoom(roomId);
    }

    void closeRoom() {
      ref.read(selectedRoomIdProvider.notifier).state = null;
      ref.read(timelineControllerProvider.notifier).stop();
    }

    RoomPreview? selectedRoom;
    if (selectedRoomId != null) {
      for (final room in [
        ...roomListState.hpRooms,
        ...roomListState.lpRooms,
      ]) {
        if (room.roomId == selectedRoomId) {
          selectedRoom = room;
          break;
        }
      }
    }

    Widget buildTimelinePane({bool isMobile = false}) {
      return _TimelinePane(
        state: timelineState,
        selectedRoomId: selectedRoomId,
        room: selectedRoom,
        onClose: isMobile ? closeRoom : null,
      );
    }

    final isWide = MediaQuery.of(context).size.width >= 800;

    final roomListCard = Card(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Padding(
        padding: EdgeInsets.all(spacing.gap.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.only(bottom: spacing.gap.md),
              child: Text(
                'Chats',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            _RoomListSection(
              state: roomListState,
              selectedRoomId: selectedRoomId,
              onSelectRoom: selectRoom,
              onLoadMore: () =>
                  ref.read(roomListControllerProvider.notifier).loadMoreLp(),
              onResubscribe: () => ref
                  .read(roomListControllerProvider.notifier)
                  .resubscribeAll(),
            ),
          ],
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // Build main content for list/timeline
        late final Widget content;
        if (isWide) {
          content = Padding(
            padding: EdgeInsets.symmetric(
              horizontal: gutter,
              vertical: spacing.gap.xl,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 320,
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      roomListCard,
                    ],
                  ),
                ),
                SizedBox(width: spacing.gap.xl),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.all(spacing.gap.sm),
                    child: buildTimelinePane(),
                  ),
                ),
              ],
            ),
          );
        } else {
          content = AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: selectedRoomId == null
                ? ListView(
                    key: const ValueKey('mobile-list'),
                    padding: EdgeInsets.symmetric(
                      horizontal: gutter,
                      vertical: spacing.gap.xl,
                    ),
                    children: [
                      roomListCard,
                    ],
                  )
                : Column(
                    key: const ValueKey('mobile-timeline'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: EdgeInsets.all(spacing.gap.md),
                        child: Row(
                          children: [
                            IconButton(
                              icon:
                                  const Icon(Icons.arrow_back_ios_new_rounded),
                              tooltip: 'Close conversation',
                              onPressed: closeRoom,
                            ),
                            Expanded(
                              child: Text(
                                selectedRoom?.name ?? 'Conversation',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: gutter,
                            vertical: spacing.gap.md,
                          ),
                          child: buildTimelinePane(isMobile: true),
                        ),
                      ),
                    ],
                  ),
          );
        }

        // Keep AppBar on home list and wide layouts; hide on mobile chat
        final showAppBar = selectedRoomId == null || isWide;
        return Scaffold(
          appBar: showAppBar
              ? AppBar(
                  title: const Text('Messie'),
                  actions: [
                    PopupMenuButton<String>(
                      tooltip: 'Menu',
                      icon: const Icon(Icons.more_vert_rounded),
                      onSelected: (value) {
                        switch (value) {
                          case 'settings':
                            context.push('/settings');
                            break;
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem<String>(
                          value: 'settings',
                          child: Text('Settings'),
                        ),
                      ],
                    ),
                  ],
                )
              : null,
          body: SafeArea(child: content),
          floatingActionButton: FloatingActionButton(
            onPressed: () => _showCreateMenu(context, ref),
            tooltip: 'Create',
            child: const Icon(Icons.add_rounded),
          ),
        );
      },
    );
  }

  Future<void> _showCreateMenu(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.checklist_rounded),
                title: const Text('Create To‑Do List'),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await _createTodoListFlow(context, ref);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _createTodoListFlow(BuildContext context, WidgetRef ref) async {
    final titleController = TextEditingController();
    final descController = TextEditingController();
    final spacing = MessieSpacing.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New To‑Do List'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Title'),
              textInputAction: TextInputAction.next,
            ),
            SizedBox(height: spacing.gap.md),
            TextField(
              controller: descController,
              decoration:
                  const InputDecoration(labelText: 'Description (optional)'),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final title = titleController.text.trim();
    if (title.isEmpty) return;
    final desc = descController.text;

    final repo = ref.read(todoRepositoryProvider);
    final created = await repo.createList(title: title, description: desc);
    if (created == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to create to‑do list')),
        );
      }
      return;
    }

    // Refresh lists and navigate to the detail page of the new list
    ref.invalidate(todoListsStreamProvider);
    if (!context.mounted) return;
    context.pushNamed('todo_detail', pathParameters: {'listId': created.id});
  }
}

class _RoomListSection extends ConsumerWidget {
  const _RoomListSection({
    required this.state,
    required this.onLoadMore,
    required this.onResubscribe,
    required this.onSelectRoom,
    this.selectedRoomId,
  });

  final RoomListState state;
  final VoidCallback onLoadMore;
  final VoidCallback onResubscribe;
  final void Function(String roomId) onSelectRoom;
  final String? selectedRoomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final spacing = MessieSpacing.of(context);

    // Simple filter segmented control (visual only for now)
    Widget filters() {
      return Padding(
        padding: EdgeInsets.only(bottom: spacing.gap.md),
        child: MessieSegmentedControl<String>(
          value: 'all',
          // Remove 'unread' option since Synapse sliding sync doesn't provide counts
          segments: const ['all', 'favorites'],
          labelBuilder: (s) => Text(
            switch (s) {
              'favorites' => 'Favorites',
              _ => 'All',
            },
          ),
          onChanged: (_) {},
        ),
      );
    }

    if (state.isLoading) {
      return Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: spacing.gap.lg),
          child: const CircularProgressIndicator(),
        ),
      );
    }

    final children = <Widget>[];

    // Top filters
    children.add(filters());

    if (state.error != null) {
      children.add(
        Container(
          padding: EdgeInsets.all(spacing.gap.md),
          margin: EdgeInsets.only(bottom: spacing.gap.md),
          decoration: BoxDecoration(
            color: colors.errorContainer,
            borderRadius: BorderRadius.circular(MessieRadii.of(context).md),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_rounded, color: colors.onErrorContainer),
              SizedBox(width: spacing.gap.sm),
              Expanded(
                child: Text(
                  state.error!,
                  style: textTheme.bodyMedium?.copyWith(
                    color: colors.onErrorContainer,
                  ),
                ),
              ),
              IconButton(
                onPressed: onResubscribe,
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'Retry sync',
              ),
            ],
          ),
        ),
      );
    }

    final todoError = ref.watch(todoLastErrorProvider);
    if (todoError != null && todoError.isNotEmpty) {
      children.add(
        Container(
          padding: EdgeInsets.all(spacing.gap.md),
          margin: EdgeInsets.only(bottom: spacing.gap.md),
          decoration: BoxDecoration(
            color: colors.errorContainer,
            borderRadius: BorderRadius.circular(MessieRadii.of(context).md),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_rounded, color: colors.onErrorContainer),
              SizedBox(width: spacing.gap.sm),
              Expanded(
                child: Text(
                  'Todo sync issue: $todoError',
                  style: textTheme.bodyMedium?.copyWith(
                    color: colors.onErrorContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Source list comes from feed abstraction (multi‑module ready)
    final threads = ref.watch(homeThreadsProvider);
    if (threads.isEmpty) {
      children.add(Text(
        'No rooms yet.',
        style: textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
      ));
    } else {
      final registry = ref.read(threadActionsRegistryProvider);
      final nav = ref.read(threadNavigatorRegistryProvider);
      children.addAll(threads.map((thread) {
        final actions = registry.forModule(thread.module);
        return _RoomTile(
          room: thread,
          isActive: selectedRoomId == thread.threadId,
          onTap: () async => nav.navigate(context, ref, thread),
          onToggleMute: actions.supportsMute
              ? () async {
                  final ok = await actions.toggleMute(context, ref, thread);
                  if (!ok && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Failed to update mute state')),
                    );
                  }
                }
              : null,
        );
      }));
    }

    final canLoadMore = state.lpRooms.length < state.lpTotal;
    if (canLoadMore) {
      children.add(SizedBox(height: spacing.gap.md));
      children.add(
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: onLoadMore,
            icon: const Icon(Icons.expand_more_rounded),
            label: const Text('Load more conversations'),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

class _RoomTile extends StatelessWidget {
  const _RoomTile({
    required this.room,
    required this.onTap,
    this.isActive = false,
    this.onToggleMute,
  });

  final HomeThread room;
  final VoidCallback onTap;
  final bool isActive;
  final VoidCallback? onToggleMute;

  @override
  Widget build(BuildContext context) {
    final spacing = MessieSpacing.of(context);
    final scheme = Theme.of(context).colorScheme;
    final isMuted = room.isMuted;

    return Padding(
      padding: EdgeInsets.only(bottom: spacing.gap.sm),
      child: ListTile(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MessieRadii.of(context).md),
        ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: spacing.gap.md,
          vertical: spacing.gap.xs,
        ),
        leading: _AvatarPlaceholder(name: room.name, avatarUrl: room.avatarUrl),
        title: Text(room.name),
        selected: isActive,
        onTap: onTap,
        selectedTileColor: scheme.secondaryContainer,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (room.highlightCount > 0 || room.notificationCount > 0)
              _CountBadge(
                count: room.highlightCount > 0
                    ? room.highlightCount
                    : room.notificationCount,
                isHighlight: room.highlightCount > 0,
              ),
            SizedBox(
                width: room.highlightCount > 0 || room.notificationCount > 0
                    ? spacing.gap.sm
                    : 0),
            if (onToggleMute != null)
              IconButton(
                visualDensity: VisualDensity.compact,
                splashRadius: 18,
                icon: Icon(
                  isMuted
                      ? Icons.notifications_off_rounded
                      : Icons.notifications_none_rounded,
                ),
                tooltip:
                    isMuted ? 'Unmute notifications' : 'Mute notifications',
                onPressed: onToggleMute,
                color: Theme.of(context)
                    .colorScheme
                    .onSurfaceVariant
                    .withValues(alpha: 0.45),
              ),
          ],
        ),
      ),
    );
  }
}

class _AvatarPlaceholder extends ConsumerStatefulWidget {
  const _AvatarPlaceholder({required this.name, this.avatarUrl});

  final String name;
  final String? avatarUrl;

  @override
  ConsumerState<_AvatarPlaceholder> createState() => _AvatarPlaceholderState();
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count, this.isHighlight = false});
  final int count;
  final bool isHighlight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = isHighlight ? scheme.primary : scheme.secondaryContainer;
    final fg = isHighlight ? scheme.onPrimary : scheme.onSecondaryContainer;
    final text = count > 99 ? '99+' : '$count';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      constraints: const BoxConstraints(minWidth: 24, minHeight: 20),
      alignment: Alignment.center,
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: fg, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _SenderAvatar extends ConsumerStatefulWidget {
  const _SenderAvatar({required this.roomId, required this.userId});

  final String roomId;
  final String userId;

  @override
  ConsumerState<_SenderAvatar> createState() => _SenderAvatarState();
}

class _SenderName extends ConsumerStatefulWidget {
  const _SenderName({required this.roomId, required this.userId});

  final String roomId;
  final String userId;

  @override
  ConsumerState<_SenderName> createState() => _SenderNameState();
}

class _SenderNameState extends ConsumerState<_SenderName> {
  MemberProfileData? _profile;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _SenderName oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roomId != widget.roomId ||
        oldWidget.userId != widget.userId) {
      _load();
    }
  }

  Future<void> _load() async {
    final repo = ref.read(profileRepositoryProvider);
    final data =
        await repo.memberProfile(roomId: widget.roomId, userId: widget.userId);
    if (!mounted) return;
    setState(() {
      _profile = data;
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    String name = _profile?.displayName ?? widget.userId;
    // If userId looks like @local:server, collapse to local part for readability
    final at = name.indexOf(':');
    if (name.startsWith('@') && at > 1) {
      name = name.substring(1, at);
    }
    return Text(
      name,
      style: textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _SenderAvatarState extends ConsumerState<_SenderAvatar> {
  MemberProfileData? _profile;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _SenderAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roomId != widget.roomId ||
        oldWidget.userId != widget.userId) {
      _load();
    }
  }

  Future<void> _load() async {
    final repo = ref.read(profileRepositoryProvider);
    final data =
        await repo.memberProfile(roomId: widget.roomId, userId: widget.userId);
    if (!mounted) return;
    setState(() {
      _profile = data;
    });
  }

  @override
  Widget build(BuildContext context) {
    final name = _profile?.displayName ?? widget.userId;
    final url = _profile?.avatarUrl;
    return _AvatarPlaceholder(name: name, avatarUrl: url);
  }
}

class _AvatarPlaceholderState extends ConsumerState<_AvatarPlaceholder> {
  String? _httpUrl;
  String? _filePath;

  @override
  void didUpdateWidget(covariant _AvatarPlaceholder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.avatarUrl != widget.avatarUrl) {
      _resolve();
    }
  }

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    final repo = ref.read(mediaRepositoryProvider);
    final source =
        await repo.resolveAvatar(mxc: widget.avatarUrl, w: 96, h: 96);
    if (!mounted) return;
    setState(() {
      _filePath = source.filePath;
      _httpUrl = source.httpUrl;
    });
  }

  @override
  Widget build(BuildContext context) {
    final initials = _initials(widget.name);
    final colors = Theme.of(context).colorScheme;
    final url = _httpUrl;
    final filePath = _filePath;
    final session = ref.watch(authControllerProvider).asData?.value;
    final headers = session != null
        ? <String, String>{'Authorization': 'Bearer ${session.accessToken}'}
        : null;

    if (filePath != null &&
        filePath.isNotEmpty &&
        File(filePath).existsSync()) {
      return CircleAvatar(
        backgroundColor: colors.secondaryContainer,
        child: ClipOval(
          child: Image.file(
            File(filePath),
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Center(
                child: Text(
                  initials,
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(color: colors.onSecondaryContainer),
                ),
              );
            },
          ),
        ),
      );
    }
    if (url != null && url.isNotEmpty) {
      // Use Image.network with errorBuilder to avoid global image exceptions
      // when the thumbnail endpoint returns 404. Fallback to initials.
      return CircleAvatar(
        backgroundColor: colors.secondaryContainer,
        child: ClipOval(
          child: Image.network(
            url,
            headers: headers,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Center(
                child: Text(
                  initials,
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(color: colors.onSecondaryContainer),
                ),
              );
            },
          ),
        ),
      );
    }
    return CircleAvatar(
      backgroundColor: colors.secondaryContainer,
      child: Text(
        initials,
        style: Theme.of(context)
            .textTheme
            .labelLarge
            ?.copyWith(color: colors.onSecondaryContainer),
      ),
    );
  }

  String _initials(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '?';
    }
    final parts = trimmed.split(RegExp(r'\s+'));

    String takeFirstGrapheme(String s) {
      final chars = s.characters;
      if (chars.isEmpty) return '';
      return chars.first;
    }

    String takeSecondGrapheme(String s) {
      final chars = s.characters;
      if (chars.isEmpty) return '';
      final rest = chars.skip(1);
      if (rest.isEmpty) return '';
      return rest.first;
    }

    String result = '';
    // First initial from first word
    result += takeFirstGrapheme(parts.first);
    // Second initial from last word (if multiple), otherwise second grapheme of first word
    if (parts.length > 1) {
      result += takeFirstGrapheme(parts.last);
    } else {
      result += takeSecondGrapheme(parts.first);
    }
    return result.isEmpty ? '?' : result.toUpperCase();
  }
}

class _TimelinePane extends ConsumerStatefulWidget {
  const _TimelinePane({
    required this.state,
    required this.selectedRoomId,
    required this.room,
    this.onClose,
  });

  final TimelineState state;
  final String? selectedRoomId;
  final RoomPreview? room;
  final VoidCallback? onClose;

  @override
  ConsumerState<_TimelinePane> createState() => _TimelinePaneState();
}

class _TimelinePaneState extends ConsumerState<_TimelinePane> {
  late final ScrollController _controller;
  static const double _mobileTimelineHeight = 420;
  final TextEditingController _composer = TextEditingController();
  final FocusNode _composerFocus = FocusNode();
  TimelineItem? _replyTo;
  bool _showJumpToLatest = false;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
    _controller.addListener(_handleScroll);
  }

  void _handleScroll() {
    final state = widget.state;
    if (!mounted || !_controller.hasClients) {
      return;
    }
    // Show "Jump to latest" when user is scrolled away from bottom.
    final distanceFromBottom =
        _controller.position.maxScrollExtent - _controller.offset;
    final shouldShow = ref
        .read(timelineControllerProvider.notifier)
        .shouldShowJumpToLatest(distanceFromBottom);
    if (shouldShow != _showJumpToLatest) {
      setState(() {
        _showJumpToLatest = shouldShow;
      });
    }

    if (_controller.position.pixels <= 80 &&
        !state.isLoadingMore &&
        !state.reachedStart &&
        !state.isLoading) {
      ref.read(timelineControllerProvider.notifier).loadOlder();
    }
  }

  void _handleTimelineChange(TimelineState? previous, TimelineState next) {
    final change = next.lastChange;
    if (change == null) {
      return;
    }

    if (change.op == TimelineOp.prepend && _controller.hasClients) {
      final before = _controller.position.maxScrollExtent;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_controller.hasClients) return;
        final after = _controller.position.maxScrollExtent;
        final delta = after - before;
        if (delta > 0) {
          _controller.jumpTo(_controller.offset + delta);
        }
        ref.read(timelineControllerProvider.notifier).acknowledgeChange();
      });
      return;
    }

    if (change.op == TimelineOp.append && _controller.hasClients) {
      final distanceFromBottom =
          _controller.position.maxScrollExtent - _controller.offset;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_controller.hasClients) return;
        if (ref
            .read(timelineControllerProvider.notifier)
            .shouldAutoScrollToLatest(distanceFromBottom)) {
          _controller.animateTo(
            _controller.position.maxScrollExtent,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
          );
        }
        // Delegate read receipt behavior to ViewModel
        unawaited(ref
            .read(timelineControllerProvider.notifier)
            .maybeMarkReadAtBottom(distanceFromBottom));
        ref.read(timelineControllerProvider.notifier).acknowledgeChange();
      });
      return;
    }

    if (change.op == TimelineOp.reset && _controller.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_controller.hasClients) {
          _controller.jumpTo(_controller.position.maxScrollExtent);
        }
        ref.read(timelineControllerProvider.notifier).acknowledgeChange();
      });
      return;
    }

    ref.read(timelineControllerProvider.notifier).acknowledgeChange();
  }

  @override
  void dispose() {
    _composer.dispose();
    _composerFocus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<TimelineState>(
        timelineControllerProvider, _handleTimelineChange);

    final state = widget.state;
    final spacing = MessieSpacing.of(context);
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    if (widget.selectedRoomId == null) {
      return Center(
        child: Text(
          'Select a room to see messages.',
          style: textTheme.bodyMedium,
        ),
      );
    }

    if (state.isLoading && state.events.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final events = state.events;

    Future<void> sendMessage() async {
      final roomId = widget.selectedRoomId;
      final text = _composer.text.trim();
      if (roomId == null || text.isEmpty) return;
      final replyTo = _replyTo?.key.eventId;
      final messenger = ScaffoldMessenger.of(context);
      final ok = await ref
          .read(timelineControllerProvider.notifier)
          .sendText(roomId: roomId, body: text, replyTo: replyTo);
      if (!ok && mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Failed to send')),
        );
      }
      if (mounted) {
        _composer.clear();
        setState(() {
          _replyTo = null;
        });
      }
    }

    final built = LayoutBuilder(
      builder: (context, constraints) {
        final hasBoundedHeight = constraints.maxHeight.isFinite;

        Widget buildErrorBanner() {
          if (state.error == null) {
            return const SizedBox.shrink();
          }
          return Container(
            padding: EdgeInsets.all(spacing.gap.md),
            margin: EdgeInsets.only(bottom: spacing.gap.md),
            decoration: BoxDecoration(
              color: colors.errorContainer,
              borderRadius: BorderRadius.circular(MessieRadii.of(context).md),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_rounded,
                    color: colors.onErrorContainer, size: 20),
                SizedBox(width: spacing.gap.sm),
                Expanded(
                  child: Text(
                    state.error!,
                    style: textTheme.bodyMedium
                        ?.copyWith(color: colors.onErrorContainer),
                  ),
                ),
              ],
            ),
          );
        }

        Widget buildList() {
          if (events.isEmpty) {
            return Center(
              child: Text(
                'No messages yet.',
                style: textTheme.bodyMedium
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
            );
          }

          return ListView.builder(
            controller: _controller,
            padding: EdgeInsets.only(bottom: spacing.gap.lg),
            physics: hasBoundedHeight ? null : const ClampingScrollPhysics(),
            shrinkWrap: !hasBoundedHeight,
            itemCount: events.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                if (state.reachedStart) {
                  return Padding(
                    padding: EdgeInsets.only(bottom: spacing.gap.sm),
                    child: Text(
                      'Beginning of history',
                      textAlign: TextAlign.center,
                      style: textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  );
                }
                if (state.isLoadingMore) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  );
                }
                return const SizedBox(height: 12);
              }

              final item = events[index - 1];
              final roomId = widget.selectedRoomId!;
              return Padding(
                padding: EdgeInsets.only(bottom: spacing.gap.sm),
                child: item.isOwn
                    ? _TimelineBubble(
                        item: item,
                        onLongPress: () {
                          if (item.key.eventId != null) {
                            setState(() {
                              _replyTo = item;
                            });
                            _composerFocus.requestFocus();
                          }
                        },
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SenderAvatar(roomId: roomId, userId: item.sender),
                          SizedBox(width: spacing.gap.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: EdgeInsets.only(
                                      left: spacing.gap.xs,
                                      bottom: spacing.gap.xs),
                                  child: _SenderName(
                                      roomId: roomId, userId: item.sender),
                                ),
                                _TimelineBubble(
                                  item: item,
                                  onLongPress: () {
                                    if (item.key.eventId != null) {
                                      setState(() {
                                        _replyTo = item;
                                      });
                                      _composerFocus.requestFocus();
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
              );
            },
          );
        }

        final children = <Widget>[];
        if (widget.onClose == null && widget.room != null) {
          children.add(
            Padding(
              padding: EdgeInsets.only(bottom: spacing.gap.md),
              child: Text(
                widget.room!.name,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          );
        }

        // Surface timeline errors above the list
        children.add(buildErrorBanner());

        children.add(Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(MessieRadii.of(context).md),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(MessieRadii.of(context).md),
              child: Stack(
                children: [
                  Positioned.fill(child: buildList()),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: AnimatedOpacity(
                      opacity: _showJumpToLatest ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 180),
                      child: Card(
                        margin: EdgeInsets.zero,
                        child: IconButton(
                          tooltip: 'Jump to latest',
                          icon: const Icon(Icons.arrow_downward_rounded),
                          onPressed: () {
                            if (_controller.hasClients) {
                              _controller.animateTo(
                                _controller.position.maxScrollExtent,
                                duration: const Duration(milliseconds: 180),
                                curve: Curves.easeOut,
                              );
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ));

        children.add(
          Padding(
            padding: EdgeInsets.only(top: spacing.gap.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Material(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      side: BorderSide(
                          color: Theme.of(context).colorScheme.outlineVariant),
                      borderRadius:
                          BorderRadius.circular(MessieRadii.of(context).md),
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: spacing.gap.xl,
                        maxHeight: _TimelinePaneState._mobileTimelineHeight,
                      ),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: spacing.gap.md,
                          vertical: spacing.gap.xs,
                        ),
                        child: TextField(
                          focusNode: _composerFocus,
                          controller: _composer,
                          minLines: 1,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            hintText: 'Type a message',
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: spacing.gap.sm),
                FilledButton(
                  onPressed: sendMessage,
                  child: const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ),
        );

        return Column(
          mainAxisSize: hasBoundedHeight ? MainAxisSize.max : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        );
      },
    );

    // On mobile (when an explicit onClose is provided), intercept system back
    // to close the conversation instead of attempting to pop the root route.
    if (widget.onClose != null) {
      return BackEscSurface(
        priority: SurfacePriority.route,
        onDismiss: () async {
          widget.onClose?.call();
          return true;
        },
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) async {
            if (!didPop) {
              widget.onClose?.call();
            }
          },
          child: built,
        ),
      );
    }

    return built;
  }
}

class _TimelineBubble extends StatelessWidget {
  const _TimelineBubble({required this.item, this.onLongPress});

  final TimelineItem item;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final spacing = MessieSpacing.of(context);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Improve contrast: own = primaryContainer, others = surfaceContainer with outline.
    final bool isOwn = item.isOwn;
    final background =
        isOwn ? scheme.primaryContainer : scheme.surfaceContainer;
    final foreground = isOwn ? scheme.onPrimaryContainer : scheme.onSurface;

    final timestamp = item.timestamp != null
        ? TimeOfDay.fromDateTime(item.timestamp!.toLocal())
        : null;

    return Align(
      alignment: item.isOwn ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: GestureDetector(
          onLongPress: onLongPress,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(spacing.gap.md),
                topRight: Radius.circular(spacing.gap.md),
                bottomLeft:
                    Radius.circular(isOwn ? spacing.gap.md : spacing.gap.sm),
                bottomRight:
                    Radius.circular(isOwn ? spacing.gap.sm : spacing.gap.md),
              ),
              border: isOwn ? null : Border.all(color: scheme.outlineVariant),
            ),
            child: Padding(
              padding: EdgeInsets.all(spacing.gap.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.body ?? '[Unsupported message]',
                    style: textTheme.bodyMedium?.copyWith(color: foreground),
                  ),
                  if (timestamp != null)
                    Align(
                      alignment: Alignment.bottomRight,
                      child: Text(
                        timestamp.format(context),
                        style: textTheme.labelSmall?.copyWith(
                            color: foreground.withValues(alpha: 0.7)),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
