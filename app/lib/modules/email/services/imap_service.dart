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
    debugPrint('[imap] important: search "$searchCriteria" -> ids=${ids.length}');
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

  // Web/backend-inspired: fetch rich headers across multiple mailboxes in a single session.
  // Returns minimal headers for last [perBoxLimit] messages per mailbox.
  Future<List<MimeMessage>> prefetchRichHeadersMultiMailbox({
    required EmailAccountConfig account,
    int perBoxLimit = 1000,
  }) async {
    final client = await _connect(account);
    try {
      final boxes = await client.listMailboxes();
      // Debug: list all mailboxes discovered
      for (final m in boxes) {
        try {
          debugPrint('[imap] prefetch: discovered mailbox name=${m.name} path=${m.encodedPath} flags=${m.flags}');
        } catch (_) {}
      }
      Mailbox? inbox;
      Mailbox? allMail;
      final List<Mailbox> sentCandidates = [];

      // Helper: resolve by exact known names ignoring case
      Mailbox? byName(String wanted) {
        final w = wanted.toLowerCase();
        for (final m in boxes) {
          if (m.name.toLowerCase() == w) return m;
        }
        return null;
      }

      inbox = byName('INBOX');
      if (inbox == null) {
        for (final m in boxes) {
          if (m.name.toLowerCase() == 'inbox') { inbox = m; break; }
        }
      }
      allMail = byName('[Gmail]/All Mail');
      if (allMail == null) {
        for (final m in boxes) {
          final n = m.name.toLowerCase();
          final flagsStr = m.flags.toString().toLowerCase();
          final hasAllFlag = flagsStr.contains('\\all') || flagsStr.contains('specialuse=all') || flagsStr.contains('allmail');
          if (n.contains('all mail') || (n.contains('[gmail]') && n.contains('all mail')) || hasAllFlag) { allMail = m; break; }
        }
      }

      final knownSentNames = <String>{
        '[Gmail]/Sent Mail'.toLowerCase(),
        'Sent'.toLowerCase(),
        'Sent Items'.toLowerCase(),
        'Sent Mail'.toLowerCase(),
        'Sent Messages'.toLowerCase(),
      };
      for (final m in boxes) {
        final n = m.name.toLowerCase();
        final flagsStr = m.flags.toString().toLowerCase();
        final hasSentFlag = flagsStr.contains('\\sent') || flagsStr.contains('specialuse=sent');
        if (knownSentNames.contains(n) || n.contains('sent') || hasSentFlag) {
          sentCandidates.add(m);
        }
      }

      final targets = <Mailbox>[
        if (allMail != null) allMail,
        if (inbox != null) inbox,
        ...sentCandidates,
      ];

      // Gmail fallback: if children under [Gmail] weren't listed (e.g., server returns only
      // top-level or user unsubscribed), explicitly try known Gmail special folders.
      final bool isGmail =
          (account.provider == 'gmail') || account.imapHost.toLowerCase().contains('gmail');
      if (isGmail) {
        String sp = '/';
        // Ensure INBOX's separator if available
        if (inbox != null && inbox!.pathSeparator.isNotEmpty) {
          sp = inbox!.pathSeparator;
        }
        final gmailAll = '[Gmail]${sp}All Mail';
        final gmailSent = '[Gmail]${sp}Sent Mail';
        bool hasPath(String p) => targets.any((m) => m.encodedPath == p);
        if (!hasPath(gmailAll)) {
          targets.add(Mailbox(
            encodedName: gmailAll,
            encodedPath: gmailAll,
            flags: const [],
            pathSeparator: sp,
          ));
        }
        if (!hasPath(gmailSent)) {
          targets.add(Mailbox(
            encodedName: gmailSent,
            encodedPath: gmailSent,
            flags: const [],
            pathSeparator: sp,
          ));
        }
      }

      // Deduplicate by encodedPath to avoid selecting the same folder twice.
      final seenPaths = <String>{};
      final uniqueTargets = <Mailbox>[];
      for (final m in targets) {
        if (seenPaths.add(m.encodedPath)) uniqueTargets.add(m);
      }

      final all = <MimeMessage>[];
      for (final m in uniqueTargets) {
        debugPrint('[imap] prefetch: selecting mailbox=${m.name} path=${m.encodedPath}');
        if (inbox != null && m == inbox) {
          await client.selectInbox();
        } else {
          try {
            await client.selectMailbox(m);
          } catch (e) {
            debugPrint('[imap] prefetch: select failed for ${m.encodedPath}: $e');
            continue;
          }
        }
        final sr = await client.searchMessages(searchCriteria: _allQuery());
        final ids = _extractSequenceIds(sr);
        debugPrint('[imap] prefetch: mailbox=${m.name} ids=${ids.length}');
        if (ids.isEmpty) continue;
        final recent = ids.reversed.take(perBoxLimit).toList();
        final fetched = await client.fetchMessages(
          MessageSequence.fromIds(recent),
          'BODY.PEEK[HEADER.FIELDS (Message-ID In-Reply-To References Subject From Date)]',
        );
        final msgs = _messagesFromFetch(fetched);
        debugPrint('[imap] prefetch: mailbox=${m.name} fetched=${msgs.length}');
        all.addAll(msgs);
      }
      return all;
    } finally {
      await client.logout();
    }
  }

  // Probe: do we find any of these Message-IDs across typical mailboxes?
  Future<bool> existsAnyMessageIds({
    required EmailAccountConfig account,
    required List<String> messageIds,
    int maxProbe = 8,
  }) async {
    if (messageIds.isEmpty) return false;
    final client = await _connect(account);
    try {
      final boxes = await client.listMailboxes();
      Mailbox? inbox;
      Mailbox? allMail;
      final List<Mailbox> sentCandidates = [];
      for (final m in boxes) {
        final n = m.name.toLowerCase();
        if (n == 'inbox') inbox = m;
        if (n.contains('all mail') || (n.contains('[gmail]') && n.contains('all mail')) || m.isArchive) {
          allMail ??= m;
        }
        if (n.contains('sent')) {
          sentCandidates.add(m);
        }
      }
      final targets = <Mailbox>[
        if (allMail != null) allMail,
        if (inbox != null) inbox,
        ...sentCandidates,
      ];
      // Build combined OR criteria up to maxProbe
      String header(String v) => 'HEADER Message-ID "${v.trim()}"';
      String or2(String a, String b) => '(OR $a $b)';
      final probe = messageIds.take(maxProbe).toList();
      String criteria;
      if (probe.length == 1) {
        criteria = header(probe.first);
      } else {
        criteria = header(probe.first);
        for (var i = 1; i < probe.length; i++) {
          criteria = or2(criteria, header(probe[i]));
        }
      }
      for (final m in targets) {
        if (inbox != null && m == inbox) {
          await client.selectInbox();
        } else {
          await client.selectMailbox(m);
        }
        final sr = await client.searchMessages(searchCriteria: criteria);
        final ids = _extractSequenceIds(sr);
        if (ids.isNotEmpty) return true;
      }
      return false;
    } finally {
      await client.logout();
    }
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

  // Fast, IMAP-first, no-THREAD: search limited mailboxes (INBOX + Sent or All Mail) for
  // messages related to the anchor Message-ID, then expand one step via parsed headers.
  Future<List<MimeMessage>> fetchThreadByAnchorFast({
    required EmailAccountConfig account,
    required String anchorMessageId,
    int maxExpandMids = 20,
  }) async {
    final client = await _connect(account);

    // Resolve mailboxes: prefer All Mail on Gmail, otherwise INBOX + a 'Sent' mailbox.
    final mailboxes = await client.listMailboxes();
    Mailbox? inbox;
    Mailbox? allMail;
    Mailbox? sent;
    for (final m in mailboxes) {
      final n = m.name.toLowerCase();
      if (n == 'inbox') inbox = m;
      if (n.contains('all mail') || (n.contains('[gmail]') && n.contains('all mail'))) allMail = m;
      if (n.contains('sent')) sent ??= m;
    }

    final List<Mailbox> searchTargets = <Mailbox>[
      if (allMail != null) allMail,
      if (allMail == null && inbox != null) inbox,
      if (allMail == null && sent != null) sent,
    ];
    if (searchTargets.isEmpty && inbox == null) {
      // As a last fallback, try selecting INBOX logically
      await client.selectInbox();
      searchTargets.add(Mailbox( // virtual INBOX
        encodedName: 'INBOX',
        encodedPath: 'INBOX',
        flags: const [],
        pathSeparator: '/',
      ));
    }

    String norm(String v) => v.contains('<') ? v.trim() : '<${v.trim()}>';
    final anchor = norm(anchorMessageId);

    Future<List<int>> uidSearchMailbox(Mailbox m, String criteria) async {
      if (inbox != null && m == inbox) {
        await client.selectInbox();
      } else {
        await client.selectMailbox(m);
      }
      final sr = await client.uidSearchMessages(searchCriteria: criteria);
      return _extractSequenceIds(sr);
    }

    String or2(String a, String b) => '(OR $a $b)';
    String header(String name, String v) => 'HEADER $name "$v"';

    Future<List<MimeMessage>> fetchHeadersMailbox(Mailbox m, List<int> uids) async {
      if (uids.isEmpty) return const <MimeMessage>[];
      if (inbox != null && m == inbox) {
        await client.selectInbox();
      } else {
        await client.selectMailbox(m);
      }
      final fetched = await client.uidFetchMessages(
        MessageSequence.fromIds(uids, isUid: true),
        'BODY.PEEK[HEADER.FIELDS (Message-ID References In-Reply-To Subject From Date)]',
      );
      return _messagesFromFetch(fetched);
    }

    final Map<String, Set<int>> uidsPerBox = {};
    // Anchor is used to seed search criteria; a separate set of expanded IDs is computed later

    // Step 1: direct relations for anchor in every mailbox
    for (final m in searchTargets) {
      final crit = or2(or2(header('References', anchor), header('In-Reply-To', anchor)), header('Message-ID', anchor));
      final ids = await uidSearchMailbox(m, crit);
      uidsPerBox.putIfAbsent(m.encodedPath, () => <int>{}).addAll(ids);
    }

    // Step 2: expand mids from fetched headers
    final Set<String> newMids = {};
    for (final m in searchTargets) {
      final set = uidsPerBox[m.encodedPath];
      if (set == null || set.isEmpty) continue;
      final sample = set.toList()..sort();
      final sampleLast = sample.reversed.take(maxExpandMids).toList();
      final msgs = await fetchHeadersMailbox(m, sampleLast);
      for (final msg in msgs) {
        try {
          final rid = msg.decodeHeaderValue('message-id');
          if (rid != null && rid.trim().isNotEmpty) newMids.add(norm(rid));
          final refs = msg.decodeHeaderValue('references');
          if (refs != null && refs.trim().isNotEmpty) {
            final first = _firstMessageIdFromHeader(refs);
            if (first != null && first.isNotEmpty) newMids.add(first);
          }
          final irt = msg.decodeHeaderValue('in-reply-to');
          if (irt != null && irt.trim().isNotEmpty) {
            final parent = _firstMessageIdFromHeader(irt);
            if (parent != null && parent.isNotEmpty) newMids.add(parent);
          }
        } catch (_) {}
      }
    }

    final List<String> expandList = newMids.take(maxExpandMids).toList();
    if (expandList.isNotEmpty) {
      final combined = expandList
          .map((mid) => header('Message-ID', mid))
          .reduce((a, b) => or2(a, b));
      for (final m in searchTargets) {
        final ids = await uidSearchMailbox(m, combined);
        if (ids.isNotEmpty) {
          uidsPerBox.putIfAbsent(m.encodedPath, () => <int>{}).addAll(ids);
        }
      }
    }

    // Final fetch per mailbox
    final List<MimeMessage> all = [];
    for (final m in searchTargets) {
      final set = uidsPerBox[m.encodedPath];
      if (set == null || set.isEmpty) continue;
      final uids = set.toList()..sort();
      final msgs = await fetchHeadersMailbox(m, uids);
      all.addAll(msgs);
    }
    await client.logout();
    return all;
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
