import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../main.dart';
import '../../../bridge/messie_bridge.dart';
import '../../../state/backup_controller.dart';
import '../../../state/verification_controller.dart';
import '../../../state/secure_secrets.dart';
import '../theme/theme_controller.dart';
import '../../../theme/messie_tokens.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Providers we need here
    final session = ref.watch(authControllerProvider).asData?.value;
    final pingState = ref.watch(pingProvider);
    final backupState = ref.watch(backupControllerProvider);
    final verifyState = ref.watch(verificationControllerProvider);
    final trustState = ref.watch(selfTrustProvider);

    // Keep trust state fresh after successful verification
    ref.listen<VerificationState>(verificationControllerProvider, (previous, next) {
      if (next.status == 'done' && !next.active) {
        ref.refresh(selfTrustProvider);
      }
    });

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final spacing = MessieSpacing.of(context);
    final surfaces = MessieSurfaces.of(context);
    final colors = MessieColors.of(context);
    final gutter = MessieSpacing.gutter(context);

    Future<void> _enableBackupFlow(BuildContext context) async {
      final messenger = ScaffoldMessenger.of(context);

      // 1) Bootstrap SSSS to obtain a recovery key
      final bootstrap = await rustSsssBootstrap(generateNewKey: true);
      if (!bootstrap.isOk || bootstrap.data?.generatedRecoveryKey == null) {
        messenger.showSnackBar(
          SnackBar(content: Text(bootstrap.error ?? 'Failed to create recovery key')),
        );
        return;
      }
      final recoveryKey = bootstrap.data!.generatedRecoveryKey!;

      // 2) Show the key and offer to copy/save
      final secrets = SecureSecrets();
      if (context.mounted) {
        await showDialog<void>(
          context: context,
          builder: (context) {
            return _RecoveryKeyDialog(
              recoveryKey: recoveryKey,
              onCopy: () async {
                await secrets.copyToClipboard(recoveryKey);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied recovery key')),
                  );
                }
              },
              onSave: () async {
                final ok = await secrets.saveRecoveryKey(recoveryKey);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(ok ? 'Saved securely' : 'Failed to save')),
                  );
                }
              },
            );
          },
        );
      }

      // 3) Enable backup on the server
      final enable = await rustEnableOnlineBackup(generateNew: true);
      if (!enable.isOk) {
        messenger.showSnackBar(
          SnackBar(content: Text(enable.error ?? 'Failed to enable backup')),
        );
        return;
      }
      messenger.showSnackBar(
        const SnackBar(content: Text('Key backup enabled')),
      );
      await ref.read(backupControllerProvider.notifier).refresh();
    }

    // Unified visibility rule for verification/restore affordances
    final bool showVerifyRestore =
        ((backupState.enabled != true) || (backupState.needsRecovery == true)) && (verifyState.status != 'done');

    // Account card (no logout, no recovery section)
    final accountCard = Card(
      child: Padding(
        padding: EdgeInsets.all(spacing.gap.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: colorScheme.primaryContainer,
                  child: Icon(
                    Icons.verified_user_rounded,
                    color: colorScheme.onPrimaryContainer,
                    size: 28,
                  ),
                ),
                SizedBox(width: spacing.gap.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session?.userId ?? 'Signed out',
                        style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      SizedBox(height: spacing.gap.xs),
                      Text(
                        session?.homeserverUrl ?? '',
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (session?.deviceId != null) ...[
              SizedBox(height: spacing.gap.xl),
              Row(
                children: [
                  Icon(Icons.devices_rounded, color: colorScheme.primary),
                  SizedBox(width: spacing.gap.sm),
                  Expanded(
                    child: Text(
                      'Device ID: ${session!.deviceId}',
                      style: textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ],
            if (trustState.hasValue && trustState.value != null) ...[
              SizedBox(height: spacing.gap.md),
              Wrap(
                spacing: spacing.gap.sm,
                runSpacing: spacing.gap.sm,
                children: [
                  Chip(
                    label: Text(trustState.value!.userVerified ? 'User verified' : 'User unverified'),
                    backgroundColor: trustState.value!.userVerified
                        ? colorScheme.primaryContainer
                        : colorScheme.surfaceVariant,
                    labelStyle: textTheme.labelSmall?.copyWith(
                      color: trustState.value!.userVerified
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (trustState.value!.deviceVerified != null)
                    Chip(
                      label: Text(trustState.value!.deviceVerified == true ? 'Device trusted' : 'Device unverified'),
                      backgroundColor: trustState.value!.deviceVerified == true
                          ? colorScheme.tertiaryContainer
                          : colorScheme.surfaceVariant,
                      labelStyle: textTheme.labelSmall?.copyWith(
                        color: trustState.value!.deviceVerified == true
                            ? colorScheme.onTertiaryContainer
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );

    // Security (Verification + Recovery) combined card
    final securityCard = Card(
      child: Padding(
        padding: EdgeInsets.all(spacing.gap.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Verification section
            Row(
              children: [
                Icon(Icons.verified_rounded, color: colorScheme.primary),
                SizedBox(width: spacing.gap.sm),
                Text('Device Verification', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                const Spacer(),
                IconButton(
                  tooltip: 'Refresh trust',
                  onPressed: () => ref.refresh(selfTrustProvider),
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            SizedBox(height: spacing.gap.md),
            if (!verifyState.active && verifyState.status == 'idle') ...[
              Text(
                'Verify this device using Short Authentication String (SAS).',
                style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
              SizedBox(height: spacing.gap.md),
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: () async {
                      await ref
                          .read(verificationControllerProvider.notifier)
                          .start(userId: session?.userId ?? '', deviceId: null);
                    },
                    icon: const Icon(Icons.verified_user_rounded),
                    label: const Text('Verify This Device'),
                  ),
                ],
              ),
            ] else ...[
              Row(
                children: [
                  Text('Status: ', style: textTheme.bodyMedium),
                  Text(verifyState.status, style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  if (verifyState.flowId != null) ...[
                    SizedBox(width: spacing.gap.md),
                    Expanded(
                      child: SelectableText(
                        'Flow: ${verifyState.flowId}',
                        style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ],
              ),
              if (verifyState.error != null) ...[
                SizedBox(height: spacing.gap.sm),
                Text(verifyState.error!, style: textTheme.bodySmall?.copyWith(color: colorScheme.error)),
              ],
              if (verifyState.emoji.isNotEmpty) ...[
                SizedBox(height: spacing.gap.md),
                Text('Compare these emoji on both devices:', style: textTheme.bodySmall),
                SizedBox(height: spacing.gap.sm),
                Wrap(
                  spacing: spacing.gap.md,
                  runSpacing: spacing.gap.sm,
                  children: verifyState.emoji.map((e) => Text(e, style: textTheme.headlineSmall)).toList(),
                ),
              ],
              SizedBox(height: spacing.gap.md),
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: verifyState.status == 'keys_exchanged' || verifyState.status == 'ready' || verifyState.status == 'requested'
                        ? () => ref.read(verificationControllerProvider.notifier).confirm()
                        : null,
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Confirm'),
                  ),
                  SizedBox(width: spacing.gap.sm),
                  OutlinedButton.icon(
                    onPressed: () => ref.read(verificationControllerProvider.notifier).cancel(),
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('Cancel'),
                  ),
                ],
              ),
            ],

            // Recovery & Backup section
            SizedBox(height: spacing.gap.xl),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.key_rounded, color: colorScheme.primary),
                    SizedBox(width: spacing.gap.sm),
                    Text('Recovery & Backup', style: textTheme.titleSmall),
                  ],
                ),
                Wrap(
                  spacing: spacing.gap.sm,
                  children: [
                    if (backupState.enabled == true)
                      Chip(
                        label: const Text('Backup enabled'),
                        backgroundColor: colorScheme.primaryContainer,
                        labelStyle: textTheme.labelSmall?.copyWith(color: colorScheme.onPrimaryContainer),
                      )
                    else if (backupState.existsOnServer == true)
                      Chip(
                        label: const Text('Needs recovery'),
                        backgroundColor: colorScheme.errorContainer,
                        labelStyle: textTheme.labelSmall?.copyWith(color: colorScheme.onErrorContainer),
                      )
                    else
                      const SizedBox.shrink(),
                  ],
                ),
              ],
            ),
            SizedBox(height: spacing.gap.md),
            if (backupState.enabled == false && backupState.existsOnServer != true)
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _enableBackupFlow(context),
                      icon: const Icon(Icons.cloud_upload_rounded),
                      label: const Text('Turn on Key Backup'),
                    ),
                  ),
                ],
              ),
            if (backupState.enabled == false && backupState.existsOnServer != true)
              SizedBox(height: spacing.gap.sm),
            if (showVerifyRestore)
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () async {
                        final controller = TextEditingController();
                        final result = await showDialog<bool>(
                          context: context,
                          builder: (context) {
                            return AlertDialog(
                              title: const Text('Restore from Recovery Key'),
                              content: TextField(
                                controller: controller,
                                maxLines: 2,
                                decoration: const InputDecoration(
                                  hintText: 'Enter your recovery key…',
                                ),
                                autofocus: true,
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(false),
                                  child: const Text('Cancel'),
                                ),
                                FilledButton(
                                  onPressed: () async {
                                    final raw = controller.text.trim();
                                    if (raw.isEmpty) {
                                      return;
                                    }
                                    var ok = await rustRecoverWithKey(recoveryKey: raw);
                                    if (!ok.isOk && raw.contains(' ')) {
                                      final compact = raw.replaceAll(RegExp('\\s+'), '');
                                      ok = await rustRecoverWithKey(recoveryKey: compact);
                                    }
                                    if (ok.isOk) {
                                      final secrets = SecureSecrets();
                                      final keyToSave = raw.isNotEmpty ? raw : null;
                                      if (keyToSave != null) {
                                        final saveOk = await secrets.saveRecoveryKey(keyToSave);
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                            content: Text(saveOk
                                                ? 'Recovery key saved securely'
                                                : 'Failed to save recovery key'),
                                          ));
                                        }
                                      }
                                    }
                                    if (context.mounted) {
                                      Navigator.of(context).pop(ok.isOk);
                                    }
                                  },
                                  child: const Text('Restore'),
                                ),
                              ],
                            );
                          },
                        );
                        if (result == true && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Recovery complete – backups enabled')),
                          );
                          await ref.read(backupControllerProvider.notifier).refresh();
                        }
                      },
                      icon: const Icon(Icons.lock_reset_rounded),
                      label: const Text('Restore from Recovery Key'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );

    final pingCard = Card(
      child: Padding(
        padding: EdgeInsets.all(spacing.gap.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Rust bridge status',
              style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            SizedBox(height: spacing.gap.md),
            pingState.when(
              data: (value) => Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: colors.success),
                  SizedBox(width: spacing.gap.sm),
                  Expanded(child: Text('Rust says: $value')),
                ],
              ),
              loading: () => Row(
                children: [
                  SizedBox(
                    width: spacing.gap.md,
                    height: spacing.gap.md,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.primary,
                    ),
                  ),
                  SizedBox(width: spacing.gap.sm),
                  const Text('Calling Rust…'),
                ],
              ),
              error: (error, _) => Row(
                children: [
                  Icon(Icons.error_outline, color: colorScheme.error),
                  SizedBox(width: spacing.gap.sm),
                  Expanded(child: Text('Failed to call Rust: $error')),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [surfaces.surface3, surfaces.surface1],
          ),
        ),
        child: ListView(
          padding: EdgeInsets.symmetric(
            horizontal: gutter,
            vertical: spacing.gap.xl,
          ),
          children: [
            accountCard,
            SizedBox(height: spacing.gap.xl),
            securityCard,
            SizedBox(height: spacing.gap.xl),
            pingCard,
          ],
        ),
      ),
    );
  }
}

class _RecoveryKeyDialog extends StatelessWidget {
  const _RecoveryKeyDialog({
    required this.recoveryKey,
    required this.onCopy,
    required this.onSave,
  });

  final String recoveryKey;
  final Future<void> Function() onCopy;
  final Future<void> Function() onSave;

  @override
  Widget build(BuildContext context) {
    final spacing = MessieSpacing.of(context);
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Your Recovery Key'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Save this key somewhere safe. It can decrypt your message history on new devices. Do not share it with anyone.',
            style: textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
          SizedBox(height: spacing.gap.md),
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceVariant,
              borderRadius: BorderRadius.circular(MessieRadii.of(context).md),
            ),
            child: Padding(
              padding: EdgeInsets.all(spacing.gap.md),
              child: SelectableText(
                recoveryKey,
                style: textTheme.bodyMedium?.copyWith(
                  fontFamily: 'monospace',
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        TextButton.icon(
          onPressed: () async {
            await onCopy();
          },
          icon: const Icon(Icons.copy_rounded),
          label: const Text('Copy'),
        ),
        FilledButton.icon(
          onPressed: () async {
            await onSave();
          },
          icon: const Icon(Icons.save_rounded),
          label: const Text('Save securely'),
        ),
      ],
    );
  }
}
