import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:enough_mail/enough_mail.dart' show MimeMessage;

import '../services/imap_service.dart';
import '../state/email_accounts_controller.dart';
import 'email_threads_controller.dart' show EmailHeader; // reuse model

final emailThreadExtraProvider = StateNotifierProvider<EmailThreadExtraController,
    Map<String, List<EmailHeader>>>((ref) => EmailThreadExtraController(ref));

// Completeness flags per thread baseId. true => complete, false => likely incomplete
final emailThreadCompleteProvider = StateProvider<Map<String, bool>>((ref) => {});

class EmailThreadExtraController extends StateNotifier<Map<String, List<EmailHeader>>> {
  EmailThreadExtraController(this._ref) : super(HashMap<String, List<EmailHeader>>());
  final Ref _ref;
  bool _warmed = false;

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

    // Web/backend-inspired: prefetch rich headers across All Mail/INBOX/Sent in one session,
    // group into threads, cache them, and compute completeness.
    if (!_warmed) {
      debugPrint('[email-thread-extra] warm cache via multi-mailbox prefetch');
      try {
        final msgs = await svc.prefetchRichHeadersMultiMailbox(account: acctRefreshed, perBoxLimit: 1000);
        // Group by derived thread base id (lowercase)
        final rawGroups = <String, List<MimeMessage>>{};
        for (final m in msgs) {
          final base = _deriveThreadBase(m)?.trim().toLowerCase();
          if (base == null || base.isEmpty) continue;
          (rawGroups[base] ??= <MimeMessage>[]).add(m);
        }
        // Map each group to EmailHeader list with dedupe + sort
        final nextState = {...state};
        final completeMap = {..._ref.read(emailThreadCompleteProvider)};
        rawGroups.forEach((base, list) {
          // Build EmailHeader list
          final seen = <String>{};
          final mappedList = <EmailHeader>[];
          for (final mm in list) {
            final h = _mapMimeToHeader(mm);
            final key = (h.messageId != null && h.messageId!.isNotEmpty)
                ? h.messageId!
                : '${h.subject.toLowerCase().trim()}|${h.date.millisecondsSinceEpoch}';
            if (seen.add(key)) mappedList.add(h);
          }
          mappedList.sort((a, b) => b.date.compareTo(a.date));
          nextState[base] = mappedList;

          // Completeness (naive): expect (refs/in-reply-to/self) minus have (self ids) is empty?
          final have = <String>{};
          final expect = <String>{};
          for (final mm in list) {
            final mid = _normalizeMid(_tryHeader(mm, 'message-id'));
            if (mid != null) have.add(mid);
            final refsRaw = _tryHeader(mm, 'references');
            if (refsRaw != null && refsRaw.trim().isNotEmpty) {
              for (final r in _extractMessageIds(refsRaw)) {
                final nm = _normalizeMid(r);
                if (nm != null) expect.add(nm);
              }
            }
            final irtRaw = _tryHeader(mm, 'in-reply-to');
            if (irtRaw != null && irtRaw.trim().isNotEmpty) {
              final nm = _normalizeMid(irtRaw);
              if (nm != null) expect.add(nm);
            }
            if (mid != null) expect.add(mid);
          }
          final missing = expect.difference(have);
          completeMap[base] = missing.isEmpty;
        });
        state = nextState;
        _ref.read(emailThreadCompleteProvider.notifier).state = completeMap;
        _warmed = true;
      } catch (e) {
        final msg = e.toString().toLowerCase();
        if (msg.contains('authenticationfailed') || msg.contains('invalid credentials')) {
          debugPrint('[email-thread-extra] auth failed; forcing token refresh and retry');
          acctRefreshed = await controller.ensureFreshAccessToken(acctRefreshed, force: true);
          final msgs = await svc.prefetchRichHeadersMultiMailbox(account: acctRefreshed, perBoxLimit: 1000);
          final rawGroups = <String, List<MimeMessage>>{};
          for (final m in msgs) {
            final base = _deriveThreadBase(m)?.trim().toLowerCase();
            if (base == null || base.isEmpty) continue;
            (rawGroups[base] ??= <MimeMessage>[]).add(m);
          }
          final nextState = {...state};
          final completeMap = {..._ref.read(emailThreadCompleteProvider)};
          rawGroups.forEach((base, list) {
            final seen = <String>{};
            final mappedList = <EmailHeader>[];
            for (final mm in list) {
              final h = _mapMimeToHeader(mm);
              final key = (h.messageId != null && h.messageId!.isNotEmpty)
                  ? h.messageId!
                  : '${h.subject.toLowerCase().trim()}|${h.date.millisecondsSinceEpoch}';
              if (seen.add(key)) mappedList.add(h);
            }
            mappedList.sort((a, b) => b.date.compareTo(a.date));
            nextState[base] = mappedList;

            final have = <String>{};
            final expect = <String>{};
            for (final mm in list) {
              final mid = _normalizeMid(_tryHeader(mm, 'message-id'));
              if (mid != null) have.add(mid);
              final refsRaw = _tryHeader(mm, 'references');
              if (refsRaw != null && refsRaw.trim().isNotEmpty) {
                for (final r in _extractMessageIds(refsRaw)) {
                  final nm = _normalizeMid(r);
                  if (nm != null) expect.add(nm);
                }
              }
              final irtRaw = _tryHeader(mm, 'in-reply-to');
              if (irtRaw != null && irtRaw.trim().isNotEmpty) {
                final nm = _normalizeMid(irtRaw);
                if (nm != null) expect.add(nm);
              }
              if (mid != null) expect.add(mid);
            }
            final missing = expect.difference(have);
            completeMap[base] = missing.isEmpty;
          });
          state = nextState;
          _ref.read(emailThreadCompleteProvider.notifier).state = completeMap;
          _warmed = true;
        } else {
          rethrow;
        }
      }
    }

    // Ensure requested baseId is present in state (normalize to our key form)
    final baseKey = baseId.trim().toLowerCase();
    final current = state[baseKey] ?? const <EmailHeader>[];
    debugPrint('[email-thread-extra] mapped=${current.length}');
    // store under provided key too for convenience (if different)
    state = {...state, baseKey: current};

    // If naive completeness says incomplete, do one cheap probe for missing ancestors.
    final completeMap = {..._ref.read(emailThreadCompleteProvider)};
    final isComplete = completeMap[baseKey] ?? false;
    if (!isComplete) {
      // Derive missing set from current group by comparing references+irt vs have
      final have = <String>{};
      final expect = <String>{};
      // We lack MimeMessage bodies now; reconstruct from EmailHeader (limited). Use baseKey only as a minimal expectation.
      for (final h in current) {
        final mid = _normalizeMid(h.messageId);
        if (mid != null) have.add(mid);
        final baseNorm = _normalizeMid(h.threadBase);
        if (baseNorm != null) expect.add(baseNorm);
      }
      final missing = expect.difference(have).toList();
      if (missing.isNotEmpty) {
        final found = await svc.existsAnyMessageIds(account: acctRefreshed, messageIds: missing, maxProbe: 8);
        completeMap[baseKey] = !found;
        _ref.read(emailThreadCompleteProvider.notifier).state = completeMap;
      }
    }
    debugPrint('[email-thread-extra] done baseId=$baseId merged=${current.length} complete=${_ref.read(emailThreadCompleteProvider)[baseKey]}');
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

  // Extract all <...> message-ids from a header value.
  List<String> _extractMessageIds(String s) {
    final ids = <String>[];
    int start = -1;
    for (var i = 0; i < s.length; i++) {
      final ch = s.codeUnitAt(i);
      if (ch == '<'.codeUnitAt(0)) {
        start = i + 1;
      } else if (ch == '>'.codeUnitAt(0)) {
        if (start >= 0 && i > start) {
          final id = s.substring(start, i).trim();
          if (id.isNotEmpty) ids.add(id);
          start = -1;
        }
      }
    }
    return ids;
  }

  String? _tryHeader(MimeMessage m, String name) {
    try {
      final v = m.decodeHeaderValue(name);
      return (v != null && v.trim().isNotEmpty) ? v : null;
    } catch (_) {
      return null;
    }
  }

  String? _normalizeMid(String? s) {
    if (s == null) return null;
    var t = s.trim().toLowerCase();
    if (t.isEmpty) return null;
    if (t.startsWith('<') && t.endsWith('>')) {
      t = t.substring(1, t.length - 1).trim();
    }
    return t;
  }
}
