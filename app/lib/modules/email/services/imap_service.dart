import 'package:flutter/foundation.dart' show debugPrint;
import 'package:enough_mail/enough_mail.dart'
    show
        ImapClient,
        MimeMessage,
        Mailbox,
        SearchImapResult,
        FetchImapResult,
        MessageSequence,
        SequenceNode;
import '../services/email_account.dart';

class EmailImapService {
  Future<List<MimeMessage>> fetchInboxHeaders({
    required EmailAccountConfig account,
    int limit = 200,
  }) async {
    final ImapClient imapClient = await _connect(account);

    // For Gmail accounts, "All Mail" holds the full conversation history.
    // Selecting INBOX would miss archived messages in a thread.
    final bool isGmail =
        (account.provider == 'gmail') || account.imapHost.toLowerCase().contains('gmail');
    if (isGmail) {
      debugPrint('[imap] inbox-headers: selecting Gmail All Mail');
      final List<Mailbox> mailboxes = await imapClient.listMailboxes();
      Mailbox? allMail;
      for (final Mailbox m in mailboxes) {
        final name = m.name.toLowerCase();
        final looksAllMail = name.contains('all mail') ||
            (name.contains('[gmail]') && name.contains('all mail')) ||
            m.isArchive; // Gmail All Mail typically marked as Archive
        if (looksAllMail) { allMail = m; break; }
      }
      if (allMail != null) {
        debugPrint('[imap] inbox-headers: selecting mailbox=${allMail.name}');
        await imapClient.selectMailbox(allMail);
      } else {
        debugPrint('[imap] inbox-headers: All Mail not found; falling back to INBOX');
        await imapClient.selectInbox();
      }
    } else {
      debugPrint('[imap] inbox-headers: non-Gmail; selecting INBOX');
      await imapClient.selectInbox();
    }
    // Fetch recent message headers using searchMessages
    final SearchImapResult sr =
        await imapClient.searchMessages(searchCriteria: _allQuery());
    final List<int> ids = _extractSequenceIds(sr);
    debugPrint('[imap] inbox-headers: found ids=${ids.length}');
    if (ids.isEmpty) {
      await imapClient.logout();
      return const <MimeMessage>[];
    }
    final recent = ids.reversed.take(limit).toList();
    final FetchImapResult fetched = await imapClient.fetchMessages(
      MessageSequence.fromIds(recent),
      'BODY.PEEK[HEADER]',
    );
    final messages = _messagesFromFetch(fetched);
    debugPrint('[imap] inbox-headers: fetched messages=${messages.length}');
    await imapClient.logout();
    return messages;
  }

  Future<List<MimeMessage>> fetchImportantHeaders({
    required EmailAccountConfig account,
    int limit = 200,
  }) async {
    final ImapClient imapClient = await _connect(account);

    // Gmail: use X-GM-RAW is:important against All Mail for correct semantics
    final bool isGmail =
        (account.provider == 'gmail') || account.imapHost.toLowerCase().contains('gmail');
    String searchCriteria;
    if (isGmail) {
      debugPrint('[imap] important: using X-GM-RAW is:important');
      final List<Mailbox> mailboxes = await imapClient.listMailboxes();
      Mailbox? allMail;
      for (final Mailbox m in mailboxes) {
        final name = m.name.toLowerCase();
        final looksAllMail = name.contains('all mail') ||
            (name.contains('[gmail]') && name.contains('all mail')) ||
            m.isArchive;
        if (looksAllMail) { allMail = m; break; }
      }
      if (allMail != null) {
        debugPrint('[imap] important: selecting mailbox=${allMail.name}');
        await imapClient.selectMailbox(allMail);
      } else {
        debugPrint('[imap] important: All Mail not found; using INBOX');
        await imapClient.selectInbox();
      }
      searchCriteria = 'X-GM-RAW "is:important"';
    } else {
      // Non-Gmail: emulate Important via FLAGGED in INBOX
      debugPrint('[imap] important: non-Gmail -> INBOX + FLAGGED');
      await imapClient.selectInbox();
      searchCriteria = _flaggedQuery();
    }

    final SearchImapResult sr =
        await imapClient.searchMessages(searchCriteria: searchCriteria);
    final List<int> ids = _extractSequenceIds(sr);
    debugPrint('[imap] important: search "${searchCriteria}" -> ids=${ids.length}');
    if (ids.isEmpty) {
      await imapClient.logout();
      return const <MimeMessage>[];
    }
    final recent = ids.reversed.take(limit).toList();
    final FetchImapResult fetched = await imapClient.fetchMessages(
      MessageSequence.fromIds(recent),
      'BODY.PEEK[HEADER]',
    );
    final messages = _messagesFromFetch(fetched);
    debugPrint('[imap] important: fetched messages=${messages.length}');
    await imapClient.logout();
    return messages;
  }

  // Fetch recent headers from the best mailbox (Gmail→All Mail, else INBOX)
  Future<List<MimeMessage>> fetchRecentHeadersAny({
    required EmailAccountConfig account,
    int limit = 500,
  }) async {
    final ImapClient imapClient = await _connect(account);
    final bool isGmail =
        (account.provider == 'gmail') || account.imapHost.toLowerCase().contains('gmail');
    if (isGmail) {
      final List<Mailbox> mailboxes = await imapClient.listMailboxes();
      Mailbox? allMail;
      for (final Mailbox m in mailboxes) {
        final name = m.name.toLowerCase();
        final looksAllMail = name.contains('all mail') ||
            (name.contains('[gmail]') && name.contains('all mail')) ||
            m.isArchive;
        if (looksAllMail) { allMail = m; break; }
      }
      if (allMail != null) {
        await imapClient.selectMailbox(allMail);
      } else {
        await imapClient.selectInbox();
      }
    } else {
      await imapClient.selectInbox();
    }
    final SearchImapResult sr = await imapClient.searchMessages(searchCriteria: _allQuery());
    final ids = _extractSequenceIds(sr);
    if (ids.isEmpty) {
      await imapClient.logout();
      return const <MimeMessage>[];
    }
    final recent = ids.reversed.take(limit).toList();
    final fetched = await imapClient.fetchMessages(
      MessageSequence.fromIds(recent),
      'BODY.PEEK[HEADER]',
    );
    final messages = _messagesFromFetch(fetched);
    await imapClient.logout();
    return messages;
  }

  // Fetch recent headers from a mailbox whose name contains one of the given tokens (case-insensitive).
  Future<List<MimeMessage>> fetchRecentHeadersFromNamedBox({
    required EmailAccountConfig account,
    required List<String> nameContains,
    int limit = 300,
  }) async {
    final ImapClient imapClient = await _connect(account);
    final List<Mailbox> mailboxes = await imapClient.listMailboxes();
    Mailbox? target;
    for (final Mailbox m in mailboxes) {
      final name = m.name.toLowerCase();
      for (final token in nameContains) {
        if (name.contains(token.toLowerCase())) { target = m; break; }
      }
      if (target != null) break;
    }
    if (target == null) {
      await imapClient.logout();
      return const <MimeMessage>[];
    }
    await imapClient.selectMailbox(target);
    final SearchImapResult sr = await imapClient.searchMessages(searchCriteria: _allQuery());
    final ids = _extractSequenceIds(sr);
    if (ids.isEmpty) {
      await imapClient.logout();
      return const <MimeMessage>[];
    }
    final recent = ids.reversed.take(limit).toList();
    final fetched = await imapClient.fetchMessages(
      MessageSequence.fromIds(recent),
      'BODY.PEEK[HEADER]',
    );
    final messages = _messagesFromFetch(fetched);
    await imapClient.logout();
    return messages;
  }

  Future<ImapClient> _connect(EmailAccountConfig account) async {
    final imapClient = ImapClientFactory.create();
    await imapClient.connectToServer(account.imapHost, account.imapPort,
        isSecure: account.imapSecure);
    if (account.authType == 'oauth2' &&
        (account.oauthAccessToken ?? '').isNotEmpty) {
      // Gmail expects the email address as the IMAP username for XOAUTH2.
      final userForAuth = (account.provider == 'gmail' && (account.email).isNotEmpty)
          ? account.email
          : account.username;
      try {
        debugPrint('[imap] auth XOAUTH2 user=$userForAuth host=${account.imapHost}');
        await imapClient.authenticateWithOAuth2(userForAuth, account.oauthAccessToken!);
      } catch (e) {
        debugPrint('[imap] auth XOAUTH2 failed: $e');
        rethrow;
      }
    } else {
      await imapClient.login(account.username, account.password ?? '');
    }
    return imapClient;
  }

  String _allQuery() => 'ALL';

  String _flaggedQuery() => 'FLAGGED';

  List<int> _extractSequenceIds(SearchImapResult sr) {
    final seq = sr.matchingSequence;
    if (seq == null || seq.isEmpty) return const <int>[];
    return seq.toList();
  }

  List<MimeMessage> _messagesFromFetch(FetchImapResult result) =>
      List<MimeMessage>.from(result.messages);

  Future<List<MimeMessage>> fetchThreadByBaseMessageId({
    required EmailAccountConfig account,
    required String baseMessageId,
    int limit = 200,
  }) async {
    final ImapClient imapClient = await _connect(account);

    // Select appropriate mailbox (Gmail → All Mail; otherwise INBOX)
    final bool isGmail =
        (account.provider == 'gmail') || account.imapHost.toLowerCase().contains('gmail');
    if (isGmail) {
      debugPrint('[imap] thread-by-mid: Gmail: selecting All Mail');
      final List<Mailbox> mailboxes = await imapClient.listMailboxes();
      Mailbox? allMail;
      for (final Mailbox m in mailboxes) {
        final name = m.name.toLowerCase();
        final looksAllMail = name.contains('all mail') ||
            (name.contains('[gmail]') && name.contains('all mail')) ||
            m.isArchive;
        if (looksAllMail) { allMail = m; break; }
      }
      if (allMail != null) {
        debugPrint('[imap] thread-by-mid: using mailbox=${allMail.name}');
        await imapClient.selectMailbox(allMail);
      } else {
        debugPrint('[imap] thread-by-mid: All Mail not found; using INBOX');
        await imapClient.selectInbox();
      }
    } else {
      debugPrint('[imap] thread-by-mid: non-Gmail -> INBOX');
      await imapClient.selectInbox();
    }

    // Ensure the message-id is wrapped in <...>
    String mid = baseMessageId.trim();
    if (!mid.contains('<')) {
      mid = '<$mid>';
    }
    debugPrint('[imap] thread-by-mid: baseMessageId=$mid');

    // Search by References/In-Reply-To/Message-ID and union the results
    final idsSet = <int>{};
    Future<void> addMatches(String criteria) async {
      final SearchImapResult sr = await imapClient.searchMessages(searchCriteria: criteria);
      idsSet.addAll(_extractSequenceIds(sr));
    }
    await addMatches('HEADER References "$mid"');
    await addMatches('HEADER In-Reply-To "$mid"');
    await addMatches('HEADER Message-ID "$mid"');
    debugPrint('[imap] thread-by-mid: union ids=${idsSet.length}');

    // Gmail-specific fallback: X-GM-RAW rfc822msgid:<id>
    if (idsSet.isEmpty && isGmail) {
      final rawCrit = 'X-GM-RAW "rfc822msgid:$mid"';
      debugPrint('[imap] thread-by-mid: trying Gmail RAW: $rawCrit');
      final srRaw = await imapClient.searchMessages(searchCriteria: rawCrit);
      final rawIds = _extractSequenceIds(srRaw);
      debugPrint('[imap] thread-by-mid: Gmail RAW ids=${rawIds.length}');
      idsSet.addAll(rawIds);
    }

    if (idsSet.isEmpty) {
      await imapClient.logout();
      return const <MimeMessage>[];
    }

    final ids = idsSet.toList()..sort();
    final recent = ids.reversed.take(limit).toList();
    final FetchImapResult fetched = await imapClient.fetchMessages(
      MessageSequence.fromIds(recent),
      'BODY.PEEK[HEADER]',
    );
    final messages = _messagesFromFetch(fetched);
    debugPrint('[imap] thread-by-mid: fetched messages=${messages.length}');
    await imapClient.logout();
    return messages;
  }

  // Single-attempt robust fetch using IMAP THREAD (REFERENCES) anchored by a known Message-ID.
  Future<List<MimeMessage>> fetchThreadByReferencesThreading({
    required EmailAccountConfig account,
    required String anchorMessageId,
    int sinceDays = 365,
  }) async {
    final ImapClient imapClient = await _connect(account);

    // Select mailbox
    final bool isGmail =
        (account.provider == 'gmail') || account.imapHost.toLowerCase().contains('gmail');
    if (isGmail) {
      final List<Mailbox> mailboxes = await imapClient.listMailboxes();
      Mailbox? allMail;
      for (final Mailbox m in mailboxes) {
        final name = m.name.toLowerCase();
        final looksAllMail = name.contains('all mail') ||
            (name.contains('[gmail]') && name.contains('all mail')) ||
            m.isArchive;
        if (looksAllMail) {
          allMail = m;
          break;
        }
      }
      if (allMail != null) {
        await imapClient.selectMailbox(allMail);
      } else {
        await imapClient.selectInbox();
      }
    } else {
      await imapClient.selectInbox();
    }

    // Find an anchor UID by Message-ID headers (UID SEARCH)
    String mid = anchorMessageId.trim();
    if (!mid.contains('<')) mid = '<$mid>';
    final SearchImapResult srUid = await imapClient.uidSearchMessages(
      searchCriteria:
          '(HEADER Message-ID "$mid" OR (HEADER References "$mid" HEADER In-Reply-To "$mid"))',
    );
    final List<int> anchorUids = _extractSequenceIds(srUid);
    if (anchorUids.isEmpty) {
      await imapClient.logout();
      return const <MimeMessage>[];
    }
    final int anchorUid = anchorUids.last; // newest match

    // Build threads (UID-based) and find the node that contains the anchor UID
    final DateTime since = DateTime.now().subtract(Duration(days: sinceDays));
    final SequenceNode root = await imapClient.threadMessages(
      since: since,
      method: 'REFERENCES',
      charset: 'UTF-8',
      threadUids: true,
    );

    List<int> threadUids = _findThreadUids(root, anchorUid);
    if (threadUids.isEmpty) {
      await imapClient.logout();
      return const <MimeMessage>[];
    }

    // Fetch all headers for the thread UIDs
    final FetchImapResult fetched = await imapClient.uidFetchMessages(
      MessageSequence.fromIds(threadUids, isUid: true),
      'BODY.PEEK[HEADER]',
    );
    final messages = _messagesFromFetch(fetched);
    await imapClient.logout();
    return messages;
  }

  // Crawl the References/In-Reply-To graph starting from an anchor Message-ID.
  // Robust across providers without relying on IMAP THREAD.
  Future<List<MimeMessage>> fetchThreadByCrawl({
    required EmailAccountConfig account,
    required String anchorMessageId,
    int maxHops = 64,
    int limit = 300,
  }) async {
    final ImapClient imapClient = await _connect(account);

    // Select mailbox (prefer All Mail on Gmail)
    final bool isGmail =
        (account.provider == 'gmail') || account.imapHost.toLowerCase().contains('gmail');
    if (isGmail) {
      final List<Mailbox> mailboxes = await imapClient.listMailboxes();
      Mailbox? allMail;
      for (final Mailbox m in mailboxes) {
        final name = m.name.toLowerCase();
        final looksAllMail = name.contains('all mail') ||
            (name.contains('[gmail]') && name.contains('all mail')) ||
            m.isArchive;
        if (looksAllMail) { allMail = m; break; }
      }
      if (allMail != null) {
        await imapClient.selectMailbox(allMail);
      } else {
        await imapClient.selectInbox();
      }
    } else {
      await imapClient.selectInbox();
    }

    String norm(String mid) {
      var v = mid.trim();
      if (!v.contains('<')) v = '<$v>';
      return v;
    }

    // Helper to UID search criteria and return ids
    Future<List<int>> uidSearch(String criteria) async {
      final SearchImapResult sr = await imapClient.uidSearchMessages(searchCriteria: criteria);
      return _extractSequenceIds(sr);
    }

    // BFS over message-ids
    final seenMids = <String>{};
    final seenUids = <int>{};
    final queue = <String>[norm(anchorMessageId)];
    int hops = 0;
    while (queue.isNotEmpty && hops < maxHops && seenUids.length < limit) {
      final mid = queue.removeAt(0);
      if (seenMids.contains(mid)) continue;
      seenMids.add(mid);

      // 1) Fetch the message itself by its Message-ID
      final idsSelf = await uidSearch('HEADER Message-ID "$mid"');
      seenUids.addAll(idsSelf);

      // 2) Find messages that reference this mid (children)
      final idsRef = await uidSearch('HEADER References "$mid"');
      final idsIrt = await uidSearch('HEADER In-Reply-To "$mid"');
      seenUids.addAll(idsRef);
      seenUids.addAll(idsIrt);

      // Fetch headers for newly found UIDs (bounded) to discover more mids
      final current = seenUids.toList()..sort();
      final sample = current.reversed.take(20).toList();
      if (sample.isNotEmpty) {
        final fetched = await imapClient.uidFetchMessages(
          MessageSequence.fromIds(sample, isUid: true),
          'BODY.PEEK[HEADER]',
        );
        final messages = _messagesFromFetch(fetched);
        for (final m in messages) {
          try {
            final msgId = m.decodeHeaderValue('message-id');
            if (msgId != null && msgId.trim().isNotEmpty) {
              final n = norm(msgId);
              if (!seenMids.contains(n)) queue.add(n);
            }
            final refs = m.decodeHeaderValue('references');
            if (refs != null && refs.trim().isNotEmpty) {
              final first = _firstMessageIdFromHeader(refs);
              if (first != null && first.isNotEmpty && !seenMids.contains(first)) queue.add(first);
            }
            final irt = m.decodeHeaderValue('in-reply-to');
            if (irt != null && irt.trim().isNotEmpty) {
              final parent = _firstMessageIdFromHeader(irt);
              if (parent != null && parent.isNotEmpty && !seenMids.contains(parent)) queue.add(parent);
            }
          } catch (_) {}
        }
      }
      hops++;
    }

    if (seenUids.isEmpty) {
      await imapClient.logout();
      return const <MimeMessage>[];
    }
    final all = seenUids.toList()..sort();
    final limited = all.reversed.take(limit).toList();
    final fetchedAll = await imapClient.uidFetchMessages(
      MessageSequence.fromIds(limited, isUid: true),
      'BODY.PEEK[HEADER]',
    );
    final result = _messagesFromFetch(fetchedAll);
    await imapClient.logout();
    return result;
  }

  // Extract first <id> from a References/In-Reply-To value
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

  // Traverses a SequenceNode tree and finds the list of UIDs in the thread that contains [anchorUid].
  List<int> _findThreadUids(SequenceNode root, int anchorUid) {
    // If the root is a container, inspect children threads.
    List<int> containing = _collectIfContains(root, anchorUid);
    return containing;
  }

  List<int> _collectIfContains(SequenceNode node, int uid) {
    // Collect ids in this subtree
    final ids = <int>[];
    void collect(SequenceNode n) {
      if (n.hasId) ids.add(n.id);
      for (final child in n.children) {
        collect(child);
      }
    }

    bool contains(SequenceNode n) {
      if (n.hasId && n.id == uid) return true;
      for (final c in n.children) {
        if (contains(c)) return true;
      }
      return false;
    }

    if (contains(node)) {
      collect(node);
      return ids;
    }
    for (final c in node.children) {
      if (contains(c)) {
        final sub = _collectIfContains(c, uid);
        if (sub.isNotEmpty) return sub;
      }
    }
    return const <int>[];
  }

  Future<List<MimeMessage>> fetchThreadBySubject({
    required EmailAccountConfig account,
    required String subject,
    int limit = 200,
  }) async {
    final ImapClient imapClient = await _connect(account);
    // Prefer All Mail for Gmail to see the full conversation
    final bool isGmail =
        (account.provider == 'gmail') || account.imapHost.toLowerCase().contains('gmail');
    if (isGmail) {
      debugPrint('[imap] thread-by-subject: Gmail: selecting All Mail');
      final List<Mailbox> mailboxes = await imapClient.listMailboxes();
      Mailbox? allMail;
      for (final Mailbox m in mailboxes) {
        final name = m.name.toLowerCase();
        final looksAllMail = name.contains('all mail') ||
            (name.contains('[gmail]') && name.contains('all mail')) ||
            m.isArchive;
        if (looksAllMail) { allMail = m; break; }
      }
      if (allMail != null) {
        debugPrint('[imap] thread-by-subject: using mailbox=${allMail.name}');
        await imapClient.selectMailbox(allMail);
      } else {
        debugPrint('[imap] thread-by-subject: All Mail not found; using INBOX');
        await imapClient.selectInbox();
      }
    } else {
      debugPrint('[imap] thread-by-subject: non-Gmail -> INBOX');
      await imapClient.selectInbox();
    }

    // Strip common prefixes like 'Re:' for broader matching
    final sub = subject.trim().replaceFirst(RegExp(r'^re:\s*', caseSensitive: false), '');
    final crit = 'SUBJECT "${sub.replaceAll('"', '\\"')}"';
    debugPrint('[imap] thread-by-subject: criteria=$crit');
    final SearchImapResult sr = await imapClient.searchMessages(searchCriteria: crit);
    final ids = _extractSequenceIds(sr);
    debugPrint('[imap] thread-by-subject: found ids=${ids.length}');
    if (ids.isEmpty) {
      await imapClient.logout();
      return const <MimeMessage>[];
    }
    final recent = ids.reversed.take(limit).toList();
    final FetchImapResult fetched = await imapClient.fetchMessages(
      MessageSequence.fromIds(recent),
      'BODY.PEEK[HEADER]',
    );
    final messages = _messagesFromFetch(fetched);
    debugPrint('[imap] thread-by-subject: fetched messages=${messages.length}');
    await imapClient.logout();
    return messages;
  }
}

class ImapClientFactory {
  static ImapClient create() => ImapClient(isLogEnabled: false);
}

// Deliberately avoid importing the external Mailbox type to keep this file
// working across enough_mail minor API differences.
