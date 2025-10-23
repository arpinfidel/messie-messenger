import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:messie_app/bridge/messie_bridge.dart';
import 'package:messie_app/modules/matrix/state/auth_view_model.dart';
import 'package:messie_app/modules/matrix/state/backup_view_model.dart';
import 'package:messie_app/modules/matrix/state/verification_view_model.dart';
import 'package:messie_app/modules/matrix/state/ping.dart';
import 'package:messie_app/modules/matrix/state/trust_state.dart';
import 'package:messie_app/state/secure_secrets.dart';
import 'package:messie_app/theme/messie_tokens.dart';
import 'package:messie_app/ui/settings/settings_registry.dart';

// Contribute Matrix sections to the registry
final matrixModuleSettingsProvider = Provider<List<SettingsSection>>((ref) {
  return <SettingsSection>[
    SettingsSection(
      id: 'matrix.account',
      title: 'Account',
      order: 10,
      builder: _buildAccountSection,
    ),
    SettingsSection(
      id: 'matrix.security',
      title: 'Security',
      order: 20,
      builder: _buildSecuritySection,
    ),
    SettingsSection(
      id: 'dev.tools',
      title: 'Developer',
      order: 90,
      builder: _buildDeveloperSection,
    ),
  ];
});

Widget _buildAccountSection(BuildContext context, WidgetRef ref) {
  final session = ref.watch(authControllerProvider).asData?.value;
  final trustState = ref.watch(selfTrustProvider);
  final spacing = MessieSpacing.of(context);
  final colorScheme = Theme.of(context).colorScheme;
  final textTheme = Theme.of(context).textTheme;
  return Card(
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
                  child: Text('Device ID: ${session!.deviceId}', style: textTheme.bodyMedium),
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
                      : colorScheme.surfaceContainerHighest,
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
                        : colorScheme.surfaceContainerHighest,
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
}

Widget _buildSecuritySection(BuildContext context, WidgetRef ref) {
  final session = ref.watch(authControllerProvider).asData?.value;
  final backupState = ref.watch(backupControllerProvider);
  final verifyState = ref.watch(verificationControllerProvider);
  // Keep trust state fresh after successful verification
  ref.listen<VerificationState>(verificationControllerProvider, (previous, next) {
    if (next.status == 'done' && !next.active) {
      ref.invalidate(selfTrustProvider);
    }
  });

  final spacing = MessieSpacing.of(context);
  final colorScheme = Theme.of(context).colorScheme;
  final textTheme = Theme.of(context).textTheme;

  Future<void> enableBackupFlow() async {
    final messenger = ScaffoldMessenger.of(context);
    final secrets = SecureSecrets();
    final bootstrap = await rustSsssBootstrap(generateNewKey: true);
    if (!bootstrap.isOk || bootstrap.data?.generatedRecoveryKey == null) {
      messenger.showSnackBar(
        SnackBar(content: Text(bootstrap.error ?? 'Failed to create recovery key')),
      );
      return;
    }
    final recoveryKey = bootstrap.data!.generatedRecoveryKey!;
    if (context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (context) {
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
                    color: colors.surfaceContainerHighest,
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
                  await secrets.copyToClipboard(recoveryKey);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Copied recovery key')),
                    );
                  }
                },
                icon: const Icon(Icons.copy_rounded),
                label: const Text('Copy'),
              ),
              FilledButton.icon(
                onPressed: () async {
                  final ok = await secrets.saveRecoveryKey(recoveryKey);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(ok ? 'Saved securely' : 'Failed to save')),
                    );
                  }
                },
                icon: const Icon(Icons.save_rounded),
                label: const Text('Save securely'),
              ),
            ],
          );
        },
      );
    }
    final enable = await rustEnableOnlineBackup(generateNew: true);
    if (!enable.isOk) {
      messenger.showSnackBar(
        SnackBar(content: Text(enable.error ?? 'Failed to enable backup')),
      );
      return;
    }
    messenger.showSnackBar(const SnackBar(content: Text('Key backup enabled')));
    await ref.read(backupControllerProvider.notifier).refresh();
  }

  final showVerifyRestore =
      ((backupState.enabled != true) || (backupState.needsRecovery == true)) && (verifyState.status != 'done');

  return Card(
    child: Padding(
      padding: EdgeInsets.all(spacing.gap.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Device verification', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    SizedBox(height: spacing.gap.xs),
                    Text(
                      'Verify this device using SAS to protect against imposters.',
                      style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: (session == null || verifyState.active)
                    ? null
                    : () async {
                        await ref
                            .read(verificationControllerProvider.notifier)
                            .start(userId: session.userId, deviceId: session.deviceId);
                      },
                icon: verifyState.active
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.verified_user_rounded),
                label: Text(verifyState.active ? 'Verifying…' : 'Verify now'),
              ),
            ],
          ),
          if (verifyState.error != null) ...[
            SizedBox(height: spacing.gap.sm),
            Text(verifyState.error!, style: textTheme.bodySmall?.copyWith(color: colorScheme.error)),
          ],
          if (verifyState.emoji.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: verifyState.emoji
                  .map((e) => Chip(label: Text(e), visualDensity: VisualDensity.compact))
                  .toList(),
            ),
          ],
          if (verifyState.status == 'done') ...[
            const SizedBox(height: 8),
            const Text('Verification complete. This device is now trusted.'),
          ],
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Key backup & recovery', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    SizedBox(height: spacing.gap.xs),
                    Text(
                      'Keep your encrypted messages safe. Generate and store a recovery key, then enable backup.',
                      style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: spacing.gap.sm),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (backupState.enabled == true)
                          ? 'Backup is enabled'
                          : (backupState.existsOnServer == true)
                              ? 'Backup available on server'
                              : 'Backup is not enabled',
                      style: textTheme.bodyMedium,
                    ),
                    SizedBox(height: spacing.gap.xs),
                    Text(
                      'Recovery state: ${backupState.recoveryState ?? '(unknown)'}',
                      style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: (session == null) ? null : () => enableBackupFlow(),
                icon: const Icon(Icons.enhanced_encryption_rounded),
                label: const Text('Enable backup'),
              ),
            ],
          ),
          if (showVerifyRestore) ...[
            SizedBox(height: spacing.gap.sm),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Have a recovery key?', style: textTheme.bodyMedium),
                      SizedBox(height: spacing.gap.xs),
                      Text(
                        'If you previously saved your recovery key, you can restore access to encrypted messages.',
                        style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: (session == null)
                      ? null
                      : () async {
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
                              const SnackBar(content: Text('Recovery attempted')),
                            );
                            await ref.read(backupControllerProvider.notifier).refresh();
                          }
                        },
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('Use recovery key'),
                ),
              ],
            ),
          ],
        ],
      ),
    ),
  );
}

Widget _buildDeveloperSection(BuildContext context, WidgetRef ref) {
  final spacing = MessieSpacing.of(context);
  final textTheme = Theme.of(context).textTheme;
  final pingState = ref.watch(pingProvider);
  return Card(
    child: Padding(
      padding: EdgeInsets.all(spacing.gap.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Developer', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          SizedBox(height: spacing.gap.sm),
          Row(
            children: [
              const Expanded(child: Text('Rust bridge ping test')),
              ElevatedButton(
                onPressed: () => ref.refresh(pingProvider),
                child: const Text('Ping'),
              ),
            ],
          ),
          SizedBox(height: spacing.gap.sm),
          Text(pingState.when(
            data: (v) => 'pong: $v',
            error: (e, _) => 'error: $e',
            loading: () => 'pinging…',
          )),
        ],
      ),
    ),
  );
}
