import 'package:enough_mail/enough_mail.dart'
    show
        ImapClient,
        MimeMessage,
        Mailbox,
        SearchImapResult,
        FetchImapResult,
        MessageSequence;
import '../services/email_account.dart';

class EmailImapService {
  Future<List<MimeMessage>> fetchInboxHeaders({
    required EmailAccountConfig account,
    int limit = 200,
  }) async {
    final ImapClient imapClient = await _connect(account);

    await imapClient.selectInbox();
    // Fetch recent message headers using searchMessages
    final SearchImapResult sr =
        await imapClient.searchMessages(searchCriteria: _allQuery());
    final List<int> ids = _extractSequenceIds(sr);
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
      final List<Mailbox> mailboxes = await imapClient.listMailboxes();
      Mailbox? allMail;
      for (final Mailbox m in mailboxes) {
        final name = m.name.toLowerCase();
        if (name.contains('all mail') || (name.contains('[gmail]') && name.contains('all mail'))) {
          allMail = m;
          break;
        }
      }
      if (allMail != null) {
        await imapClient.selectMailbox(allMail);
      } else {
        await imapClient.selectInbox();
      }
      searchCriteria = 'X-GM-RAW "is:important"';
    } else {
      // Non-Gmail: emulate Important via FLAGGED in INBOX
      await imapClient.selectInbox();
      searchCriteria = _flaggedQuery();
    }

    final SearchImapResult sr =
        await imapClient.searchMessages(searchCriteria: searchCriteria);
    final List<int> ids = _extractSequenceIds(sr);
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
    await imapClient.logout();
    return messages;
  }

  Future<ImapClient> _connect(EmailAccountConfig account) async {
    final imapClient = ImapClientFactory.create();
    await imapClient.connectToServer(account.imapHost, account.imapPort,
        isSecure: account.imapSecure);
    if (account.authType == 'oauth2' &&
        (account.oauthAccessToken ?? '').isNotEmpty) {
      await imapClient.authenticateWithOAuth2(
          account.username, account.oauthAccessToken!);
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
}

class ImapClientFactory {
  static ImapClient create() => ImapClient(isLogEnabled: false);
}

// Deliberately avoid importing the external Mailbox type to keep this file
// working across enough_mail minor API differences.
