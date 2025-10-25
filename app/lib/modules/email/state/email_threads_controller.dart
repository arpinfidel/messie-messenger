import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/feed/module_types.dart';
import '../state/email_accounts_controller.dart';
import '../services/imap_service.dart';
import 'email_thread_loader.dart';
import 'package:enough_mail/enough_mail.dart' show MimeMessage;

/// Constants aligned with web app identifiers
const kEmailImportantId = 'email-important';
const kEmailAllMailId = 'email-inbox';
const kEmailThreadPrefix = 'email-thread:';

class EmailHeader {
  EmailHeader({
    required this.id,
    required this.subject,
    required this.from,
    required this.date,
    required this.threadBase,
    this.messageId,
    this.flagged = false,
    this.unseen = false,
    this.snippet,
    this.body,
  });
  final String id;
  final String subject;
  final String from;
  final DateTime date;
  final String threadBase;
  final String? messageId;
  final bool flagged;
  final bool unseen;
  final String? snippet;
  final String? body;
}

/// Temporary sample data until IMAP is wired.
class EmailHeadersBundle {
  EmailHeadersBundle({required this.all, required this.important});
  final List<EmailHeader> all;
  final List<EmailHeader> important;
}

final emailHeadersProvider = FutureProvider<EmailHeadersBundle>((ref) async {
  final accounts = await ref.watch(emailAccountsProvider.future);
  if (accounts.isEmpty) {
    return EmailHeadersBundle(all: const [], important: const []);
  }
  // Prefer an account that has OAuth2 configured (e.g., Gmail via XOAUTH2)
  final acct = accounts.firstWhere(
    (a) => a.authType == 'oauth2' && (a.oauthAccessToken ?? '').isNotEmpty && a.username.isNotEmpty,
    orElse: () => accounts.first,
  );
  // Ensure token is fresh before accessing IMAP
  final controller = ref.read(emailAccountsControllerProvider);
  var refreshed = await controller.ensureFreshAccessToken(acct);
  final svc = EmailImapService();
  try {
    final List<MimeMessage> allMsgs = await svc.fetchInboxHeaders(account: refreshed, limit: 200);
    final List<MimeMessage> importantMsgs = await svc.fetchImportantHeaders(account: refreshed, limit: 200);
    List<EmailHeader> map(List<MimeMessage> list) => list.map(_mapMimeToHeader).toList();
    return EmailHeadersBundle(all: map(allMsgs), important: map(importantMsgs));
  } catch (e) {
    debugPrint('[email] fetch failed: $e');
    final msg = e.toString().toLowerCase();
    if (msg.contains('authenticationfailed') || msg.contains('invalid credentials')) {
      try {
        debugPrint('[email] auth failed; forcing token refresh and retry');
        refreshed = await controller.ensureFreshAccessToken(refreshed, force: true);
        final List<MimeMessage> allMsgs = await svc.fetchInboxHeaders(account: refreshed, limit: 200);
        final List<MimeMessage> importantMsgs = await svc.fetchImportantHeaders(account: refreshed, limit: 200);
        List<EmailHeader> map(List<MimeMessage> list) => list.map(_mapMimeToHeader).toList();
        return EmailHeadersBundle(all: map(allMsgs), important: map(importantMsgs));
      } catch (_) {
        // fall through to empty bundle
      }
    }
    return EmailHeadersBundle(all: const [], important: const []);
  }
});

EmailHeader _mapMimeToHeader(MimeMessage m) {
  String subject = '';
  try { subject = (m.decodeSubject() ?? '').toString().trim(); } catch (_) {}
  String from = '';
  try {
    final f = m.from;
    if (f != null && f.isNotEmpty) { from = f.first.toString(); }
  } catch (_) {}
  DateTime date = DateTime.fromMillisecondsSinceEpoch(0);
  try { final d = m.decodeDate(); if (d != null) date = d; } catch (_) {}
  // Derive thread base id: references -> in-reply-to -> message-id
  String base = _deriveThreadBase(m) ?? subject;
  bool flagged = false; // Lacking portable flag API without version specifics
  bool unseen = false;  // Same here; treat as seen
  String preview = '';
  try { preview = (m.decodeTextPlainPart() ?? m.decodeTextHtmlPart() ?? '').toString(); } catch (_) {}
  return EmailHeader(
    id: '${subject}_${date.millisecondsSinceEpoch}',
    subject: subject,
    from: from,
    date: date,
    threadBase: base.isNotEmpty ? base : subject,
    messageId: _messageId(m),
    flagged: flagged,
    unseen: unseen,
    snippet: preview.isNotEmpty ? preview.substring(0, preview.length > 160 ? 160 : preview.length) : null,
    body: preview,
  );
}

String? _messageId(MimeMessage m) {
  try {
    final id = m.decodeHeaderValue('message-id');
    if (id != null && id.trim().isNotEmpty) return id.trim().toLowerCase();
  } catch (_) {}
  return null;
}

String? _deriveThreadBase(MimeMessage m) {
  String? refs;
  try { refs = m.decodeHeaderValue('references'); } catch (_) {}
  if (refs != null && refs.trim().isNotEmpty) {
    final first = _firstMessageIdFromHeader(refs);
    if (first != null && first.isNotEmpty) return first;
  }
  String? irt;
  try { irt = m.decodeHeaderValue('in-reply-to'); } catch (_) {}
  if (irt != null && irt.trim().isNotEmpty) {
    final reply = _firstMessageIdFromHeader(irt);
    if (reply != null && reply.isNotEmpty) return reply;
  }
  return _messageId(m);
}

String? _firstMessageIdFromHeader(String raw) {
  final text = raw.trim();
  // Try to find first <...>
  final start = text.indexOf('<');
  final end = text.indexOf('>', start + 1);
  if (start != -1 && end != -1 && end > start + 1) {
    return text.substring(start, end + 1).trim().toLowerCase();
  }
  // Fallback: take first token
  final parts = text.split(RegExp(r'\s+'));
  final token = parts.isNotEmpty ? parts.first : '';
  return token.trim().toLowerCase();
}

class _GroupedThread {
  _GroupedThread(this.baseId, this.messages);
  final String baseId;
  final List<EmailHeader> messages;
  DateTime get latestDate => messages.map((m) => m.date).reduce((a, b) => a.isAfter(b) ? a : b);
  EmailHeader get latest => messages.reduce((a, b) => a.date.isAfter(b.date) ? a : b);
  Set<String>? _seen; // dedupe cache
}

/// Aggregates email threads for the Home feed.
final emailHomeThreadsProvider = Provider<List<HomeThread>>((ref) {
  final bundle = ref.watch(emailHeadersProvider).maybeWhen(
        data: (b) => b,
        orElse: () => EmailHeadersBundle(all: const [], important: const []),
      );
  final emails = bundle.all;

  final grouped = <String, _GroupedThread>{};
  for (final m in emails) {
    final base = m.threadBase.trim().toLowerCase();
    if (base.isEmpty) continue;
    grouped.putIfAbsent(base, () => _GroupedThread(base, <EmailHeader>[]));
    final group = grouped[base]!;
    // Deduplicate by message-id or subject|timestamp
    final key = (m.messageId != null && m.messageId!.isNotEmpty)
        ? m.messageId!
        : '${m.subject.toLowerCase().trim()}|${m.date.millisecondsSinceEpoch}';
    group._seen ??= <String>{};
    if (group._seen!.contains(key)) continue;
    group._seen!.add(key);
    group.messages.add(m);
  }

  // Build per-thread items (suppress single non-reply like the web)
  final threadItems = <HomeThread>[];
  for (final g in grouped.values) {
    final msgs = g.messages..sort((a, b) => b.date.compareTo(a.date));
    if (msgs.isEmpty) continue;
    if (msgs.length < 2 && !msgs.first.subject.toLowerCase().startsWith('re:')) {
      continue;
    }
    final latest = msgs.first;
    threadItems.add(
      HomeThread(
        module: 'email',
        threadId: '$kEmailThreadPrefix${Uri.encodeComponent(g.baseId)}',
        name: latest.subject.isNotEmpty ? latest.subject : '(no subject)',
        bumpTs: latest.date.millisecondsSinceEpoch,
      ),
    );
  }

  // Aggregates
  final importantLatest = (bundle.important.isNotEmpty)
      ? bundle.important.map((e) => e.date).reduce((a, b) => a.isAfter(b) ? a : b)
      : null;
  final allLatest = emails.isEmpty ? null : emails.map((e) => e.date).reduce((a, b) => a.isAfter(b) ? a : b);

  final items = <HomeThread>[
    HomeThread(
      module: 'email',
      threadId: kEmailImportantId,
      name: 'Important',
      bumpTs: (importantLatest ?? DateTime.fromMillisecondsSinceEpoch(0)).millisecondsSinceEpoch,
    ),
    HomeThread(
      module: 'email',
      threadId: kEmailAllMailId,
      name: 'All Mail',
      bumpTs: (allLatest ?? DateTime.fromMillisecondsSinceEpoch(0)).millisecondsSinceEpoch,
    ),
    ...threadItems,
  ];

  items.sort((a, b) {
    final at = a.bumpTs ?? 0;
    final bt = b.bumpTs ?? 0;
    final cmp = bt.compareTo(at);
    if (cmp != 0) return cmp;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return items;
});

/// Detail data for Important and All Mail
final emailImportantProvider = Provider<List<EmailHeader>>((ref) {
  final bundle = ref.watch(emailHeadersProvider).maybeWhen(
        data: (b) => b,
        orElse: () => EmailHeadersBundle(all: const [], important: const []),
      );
  // Dedupe like web adapter does implicitly: prefer messageId when available
  final seen = <String>{};
  final result = <EmailHeader>[];
  for (final m in bundle.important) {
    final key = (m.messageId != null && m.messageId!.isNotEmpty)
        ? m.messageId!
        : '${m.subject.toLowerCase().trim()}|${m.date.millisecondsSinceEpoch}';
    if (seen.contains(key)) continue;
    seen.add(key);
    result.add(m);
  }
  result.sort((a, b) => b.date.compareTo(a.date));
  return result;
});

final emailAllMailProvider = Provider<List<EmailHeader>>((ref) {
  final bundle = ref.watch(emailHeadersProvider).maybeWhen(
        data: (b) => b,
        orElse: () => EmailHeadersBundle(all: const [], important: const []),
      );
  final sorted = bundle.all.toList()..sort((a, b) => b.date.compareTo(a.date));
  return sorted;
});

/// Detail data for a specific email thread
final emailThreadByIdProvider = Provider.family<List<EmailHeader>, String>((ref, threadId) {
  final emails = ref.watch(emailAllMailProvider);
  String base;
  if (threadId.startsWith(kEmailThreadPrefix)) {
    base = Uri.decodeComponent(threadId.substring(kEmailThreadPrefix.length));
  } else {
    base = threadId;
  }
  // Deduplicate within thread like the web app
  final seen = <String>{};
  final msgs = <EmailHeader>[];
  for (final e in emails) {
    if (e.threadBase != base) continue;
    final key = (e.messageId != null && e.messageId!.isNotEmpty)
        ? e.messageId!
        : '${e.subject.toLowerCase().trim()}|${e.date.millisecondsSinceEpoch}';
    if (seen.contains(key)) continue;
    seen.add(key);
    msgs.add(e);
  }
  msgs.sort((a, b) => b.date.compareTo(a.date));
  return msgs;
});

/// Merged thread messages: base list from inbox fetch plus any extra fetched on demand
final resolvedEmailThreadByIdProvider = Provider.family<List<EmailHeader>, String>((ref, threadId) {
  final base = ref.watch(emailThreadByIdProvider(threadId));
  String baseId;
  if (threadId.startsWith(kEmailThreadPrefix)) {
    baseId = Uri.decodeComponent(threadId.substring(kEmailThreadPrefix.length));
  } else {
    baseId = threadId;
  }
  final extrasMap = ref.watch(emailThreadExtraProvider);
  final extras = extrasMap[baseId] ?? const <EmailHeader>[];
  final seen = <String>{};
  final merged = <EmailHeader>[];
  for (final e in [...extras, ...base]) {
    final key = (e.messageId != null && e.messageId!.isNotEmpty)
        ? e.messageId!
        : '${e.subject.toLowerCase().trim()}|${e.date.millisecondsSinceEpoch}';
    if (seen.contains(key)) continue;
    seen.add(key);
    merged.add(e);
  }
  merged.sort((a, b) => b.date.compareTo(a.date));
  return merged;
});
