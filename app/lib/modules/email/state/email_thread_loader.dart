import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:enough_mail/enough_mail.dart' show MimeMessage;

import '../services/imap_service.dart';
import '../state/email_accounts_controller.dart';
import 'email_threads_controller.dart' show EmailHeader; // reuse model

final emailThreadExtraProvider = StateNotifierProvider<EmailThreadExtraController,
    Map<String, List<EmailHeader>>>((ref) => EmailThreadExtraController(ref));

class EmailThreadExtraController extends StateNotifier<Map<String, List<EmailHeader>>> {
  EmailThreadExtraController(this._ref) : super(HashMap<String, List<EmailHeader>>());
  final Ref _ref;

  Future<void> loadByBaseId(String baseId, {String? subjectHint, String? messageIdHint}) async {
    debugPrint('[email-thread-extra] start baseId=$baseId');
    final accounts = await _ref.read(emailAccountsProvider.future);
    if (accounts.isEmpty) return;
    final acct = accounts.firstWhere(
      (a) => a.authType == 'oauth2' && (a.oauthAccessToken ?? '').isNotEmpty && a.username.isNotEmpty,
      orElse: () => accounts.first,
    );
    final controller = _ref.read(emailAccountsControllerProvider);
    var acctRefreshed = await controller.ensureFreshAccessToken(acct);
    final svc = EmailImapService();
    // Strategy: resolve to a reliable Message-ID anchor and fetch by Message-ID references.
    final anchorMid = (messageIdHint != null && messageIdHint.trim().isNotEmpty)
        ? messageIdHint.trim()
        : (_looksLikeMessageId(baseId) ? baseId : '');
    List<EmailHeader> extraHeaders = <EmailHeader>[];
    if (anchorMid.isNotEmpty) {
      try {
        final byCrawl = await svc.fetchThreadByCrawl(
          account: acctRefreshed,
          anchorMessageId: anchorMid,
          limit: 300,
        );
        extraHeaders = byCrawl.map(_mapMimeToHeader).toList();
      } catch (e) {
        final msg = e.toString().toLowerCase();
        if (msg.contains('authenticationfailed') || msg.contains('invalid credentials')) {
          // Force refresh and retry once
          debugPrint('[email-thread-extra] auth failed; forcing token refresh and retry');
          acctRefreshed = await controller.ensureFreshAccessToken(acctRefreshed, force: true);
          final byCrawl = await svc.fetchThreadByCrawl(
            account: acctRefreshed,
            anchorMessageId: anchorMid,
            limit: 300,
          );
          extraHeaders = byCrawl.map(_mapMimeToHeader).toList();
        } else {
          rethrow;
        }
      }
    }

    // As a last resort (not archived claim), fetch recent headers and filter by derived thread base
    if (extraHeaders.length < 2) {
      debugPrint('[email-thread-extra] fallback recent+filter by base');
      final recent = await svc.fetchRecentHeadersAny(account: acctRefreshed, limit: 500);
      final List<EmailHeader> mappedRecent = recent.map(_mapMimeToHeader).toList();
      // Also include Sent mailbox so replies you sent appear in the thread
      try {
        final recentSent = await svc.fetchRecentHeadersFromNamedBox(
          account: acctRefreshed,
          nameContains: const ['sent'],
          limit: 300,
        );
        mappedRecent.addAll(recentSent.map(_mapMimeToHeader));
      } catch (_) {}
      final baseNormalized = baseId.trim().toLowerCase();
      extraHeaders = mappedRecent
          .where((h) => (h.threadBase.trim().toLowerCase() == baseNormalized))
          .toList();
    }
    final mapped = extraHeaders;
    debugPrint('[email-thread-extra] mapped=${mapped.length}');
    // Dedupe by messageId (if present) else subject|ts
    final seen = <String>{};
    final result = <EmailHeader>[];
    for (final m in mapped) {
      final key = (m.messageId != null && m.messageId!.isNotEmpty)
          ? m.messageId!
          : '${m.subject.toLowerCase().trim()}|${m.date.millisecondsSinceEpoch}';
      if (seen.contains(key)) continue;
      seen.add(key);
      result.add(m);
    }
    result.sort((a, b) => b.date.compareTo(a.date));
    state = {...state, baseId: result};
    debugPrint('[email-thread-extra] done baseId=$baseId merged=${result.length}');
  }

  bool _looksLikeMessageId(String s) {
    final t = s.trim();
    if (t.isEmpty) return false;
    final hasBrackets = t.startsWith('<') && t.endsWith('>');
    final hasAt = t.contains('@');
    return hasAt && (hasBrackets || RegExp(r'^[^\s@]+@[^\s@]+$').hasMatch(t));
  }

  // Subject fallback removed per request

  // Local copy of mapping logic to avoid restructuring files.
  EmailHeader _mapMimeToHeader(MimeMessage m) {
    String subject = '';
    try {
      subject = (m.decodeSubject() ?? '').toString().trim();
    } catch (_) {}
    String from = '';
    try {
      final f = m.from;
      if (f != null && f.isNotEmpty) {
        from = f.first.toString();
      }
    } catch (_) {}
    DateTime date = DateTime.fromMillisecondsSinceEpoch(0);
    try {
      final d = m.decodeDate();
      if (d != null) date = d;
    } catch (_) {}
    String? msgId;
    try {
      final id = m.decodeHeaderValue('message-id');
      if (id != null && id.trim().isNotEmpty) msgId = id.trim().toLowerCase();
    } catch (_) {}
    // Derive base from headers to keep parity with list view
    String base = _deriveThreadBase(m) ?? subject;
    String preview = '';
    try {
      preview = (m.decodeTextPlainPart() ?? m.decodeTextHtmlPart() ?? '').toString();
    } catch (_) {}
    return EmailHeader(
      id: '${subject}_${date.millisecondsSinceEpoch}',
      subject: subject,
      from: from,
      date: date,
      threadBase: base.isNotEmpty ? base : subject,
      messageId: msgId,
      snippet: preview.isNotEmpty
          ? preview.substring(0, preview.length > 160 ? 160 : preview.length)
          : null,
      body: preview,
    );
  }

  String? _deriveThreadBase(MimeMessage m) {
    String? refs;
    try {
      refs = m.decodeHeaderValue('references');
    } catch (_) {}
    if (refs != null && refs.trim().isNotEmpty) {
      final first = _firstMessageIdFromHeader(refs);
      if (first != null && first.isNotEmpty) return first;
    }
    String? irt;
    try {
      irt = m.decodeHeaderValue('in-reply-to');
    } catch (_) {}
    if (irt != null && irt.trim().isNotEmpty) {
      final reply = _firstMessageIdFromHeader(irt);
      if (reply != null && reply.isNotEmpty) return reply;
    }
    try {
      final id = m.decodeHeaderValue('message-id');
      if (id != null && id.trim().isNotEmpty) return id.trim().toLowerCase();
    } catch (_) {}
    return null;
  }

  String? _firstMessageIdFromHeader(String raw) {
    final text = raw.trim();
    final start = text.indexOf('<');
    final end = text.indexOf('>', start + 1);
    if (start != -1 && end != -1 && end > start + 1) {
      return text.substring(start, end + 1).trim().toLowerCase();
    }
    final parts = text.split(RegExp(r'\s+'));
    final token = parts.isNotEmpty ? parts.first : '';
    return token.trim().toLowerCase();
  }
}
