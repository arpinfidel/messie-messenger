import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';

import 'package:messie_app/bridge/messie_bridge.dart';

/// Sort helper matching home feed ordering: by ts desc, then by name asc.
List<String> _orderByTs(List<({String name, int? ts})> rows) {
  final copy = List.of(rows);
  copy.sort((a, b) {
    final at = a.ts ?? 0;
    final bt = b.ts ?? 0;
    final cmp = bt.compareTo(at);
    if (cmp != 0) return cmp;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return copy.map((e) => e.name).toList(growable: false);
}

void main() {
  group('Home order consistency', () {
    test('Matrix summaries: bumpTs (latest_event_ts) matches timestamp ordering', () async {
      // Sample sliding-sync like summaries. latest_event_ts is the real event time.
      final samples = [
        {
          'room_id': '!a:hs',
          'name': 'Zeta',
          'latest_event_ts': 1000,
          'bump_ts': 90, // recency score (irrelevant for order when latest_event_ts exists)
          'notification_count': 0,
          'highlight_count': 0,
          'is_marked_unread': false,
          'is_muted': false,
        },
        {
          'room_id': '!b:hs',
          'name': 'Alpha',
          'latest_event_ts': 1500,
          'bump_ts': 110,
          'notification_count': 0,
          'highlight_count': 0,
          'is_marked_unread': false,
          'is_muted': false,
        },
        {
          'room_id': '!c:hs',
          'name': 'Beta',
          // Back-compat snapshot: real ts stored in bump_ts with a recency key present.
          'latest_event_ts': null,
          'bump_ts': 1400,
          'recency': 777, // indicates legacy layout in our parser
          'notification_count': 0,
          'highlight_count': 0,
          'is_marked_unread': false,
          'is_muted': false,
        },
        {
          'room_id': '!d:hs',
          'name': 'Charlie',
          // Tie on latest_event_ts with Alpha; name ascending breaks the tie
          'latest_event_ts': 1500,
          'bump_ts': 70,
          'notification_count': 0,
          'highlight_count': 0,
          'is_marked_unread': false,
          'is_muted': false,
        },
      ];

      // Expected order using the ground-truth timestamps (with legacy fallback)
      final expected = _orderByTs(samples.map((m) {
        final int? ts = (m['latest_event_ts'] as num?)?.toInt() ??
            // Legacy snapshot: when latest_event_ts was absent, we used bump_ts
            // as the real timestamp if a 'recency' key was present.
            (m.containsKey('recency') ? (m['bump_ts'] as num?)?.toInt() : null);
        return (name: m['name'] as String, ts: ts);
      }).toList(growable: false));

      // Parse via our bridge mapping; bumpTs must match latest_event_ts semantics
      final mapped = samples
          .map((m) => RoomOverviewData.fromJson(m))
          .map((r) => (name: r.name, ts: r.bumpTs))
          .toList(growable: false);

      final actual = _orderByTs(mapped);

      // ---- Diagnostics ----
      // Show inputs, mapped ts, and both orders to prove equivalence
      const bool kFeedLog = bool.fromEnvironment('FEED_TEST_LOG', defaultValue: false);
      void log(String msg) { if (kFeedLog) debugPrint(msg); }
      log('[feed-test] input summaries:');
      for (final m in samples) {
        final lt = m['latest_event_ts'];
        final bt = m['bump_ts'];
        final rc = m['recency'];
        log('  name=${m['name']} latest_event_ts=$lt bump_ts=$bt recency=$rc');
      }
      log('[feed-test] mapped bumpTs:');
      for (final r in mapped) {
        log('  name=${r.name} ts=${r.ts}');
      }
      log('[feed-test] expected order: ${expected.join(' > ')}');
      log('[feed-test] actual   order: ${actual.join(' > ')}');
      expect(actual, expected);
    });
  });
}
