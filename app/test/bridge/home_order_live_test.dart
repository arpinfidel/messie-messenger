// ignore_for_file: unnecessary_library_name
@Timeout(Duration(minutes: 3))
library home_order_live_test;

import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';

import 'package:messie_app/bridge/messie_bridge.dart';

String _env(String name, {String? fallback}) {
  return Platform.environment[name] ?? fallback ?? '';
}

Future<Map<String, dynamic>> _waitForPayload(
  Stream<dynamic> stream,
  Set<String> kinds, {
  Duration timeout = const Duration(seconds: 45),
  String label = 'stream',
}) async {
  final end = DateTime.now().add(timeout);
  await for (final message in stream) {
    if (DateTime.now().isAfter(end)) {
      throw TimeoutException('Timed out on $label', timeout);
    }
    if (message is! String) continue;
    try {
      final decoded = jsonDecode(message) as Map<String, dynamic>;
      final kind = (decoded['kind'] as String?) ?? '';
      if (kinds.contains(kind)) return decoded;
    } catch (_) {}
  }
  throw StateError('Stream closed before payload on $label');
}

List<Map<String, dynamic>> _summariesFromPayload(Map<String, dynamic> p) {
  final raw = p['summaries'];
  if (raw is List) {
    return raw.cast<Map<dynamic, dynamic>>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
  }
  if (raw is Map) {
    return raw.values
        .cast<Map<dynamic, dynamic>>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
  }
  return const <Map<String, dynamic>>[];
}

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
  TestWidgetsFlutterBinding.ensureInitialized();

  // Minimal logging by default; enable with --dart-define=FEED_TEST_LOG=true
  const bool kFeedLog = bool.fromEnvironment('FEED_TEST_LOG', defaultValue: false);
  void log(String msg) { if (kFeedLog) debugPrint(msg); }

  group('Home order matches latest_event_ts on live Synapse', () {
    const handle = 'order-live';
    late String storePath;

    setUpAll(() async {
      storePath = _env(
        'MESSIE_BRIDGE_STORE_PATH',
        fallback: '${Directory.systemTemp.path}/messie_bridge_home_order',
      );
      final dir = Directory(storePath);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      dir.createSync(recursive: true);

      final login = await rustRestoreOrLogin(
        homeserverUrl: _env('MESSIE_MATRIX_HOMESERVER', fallback: 'http://127.0.0.1:8008'),
        username: _env('MESSIE_MATRIX_USERNAME', fallback: 'bridge-tester'),
        password: _env('MESSIE_MATRIX_PASSWORD', fallback: 'bridgeTesterPass!'),
        basePath: storePath,
      );
      expect(login.isOk, isTrue, reason: login.error);

      final sync = await rustStartSlidingSync(
        handle: handle,
        hpSize: 24,
        lpBatch: 120,
        hpTimeline: 20,
        lpTimeline: 8,
      );
      expect(sync.isOk, isTrue, reason: sync.error);
    });

    test('relative order by bumpTs equals latest_event_ts', () async {
      final port = ReceivePort('home_order_live');
      final stream = port.asBroadcastStream();
      final reg = await rustRoomListStream(handle: handle, port: port.sendPort);
      expect(reg.isOk, isTrue, reason: reg.error);
      // Nudge the server by explicitly (re)subscribing to a window of rooms so
      // we get a timely update even on quiet homeservers.
      final joined = await rustListJoinedRooms();
      expect(joined.isOk, isTrue, reason: joined.error);
      final ids = joined.data!.rooms;
      if (ids.isNotEmpty) {
        final sub = await rustSlidingSyncSubscribeRooms(
          handle: handle,
          roomIds: ids.take(64).toList(growable: false),
          reset: false,
        );
        expect(sub.isOk, isTrue, reason: sub.error);
      }
      // Wait until we have a reasonable number of summaries with real timestamps.
      // Sliding Sync may emit an early snapshot without latest_event_ts; give it
      // several updates to settle.
      Map<String, dynamic> payload;
      List<Map<String, dynamic>> summaries = const [];
      DateTime end = DateTime.now().add(const Duration(seconds: 90));
      int nonNullTs = 0;
      do {
        payload = await _waitForPayload(
          stream,
          const {'sliding_sync_update'},
          timeout: const Duration(seconds: 20),
          label: 'room-list',
        );
        summaries = _summariesFromPayload(payload);
        nonNullTs = summaries
            .map<int?>((s) => (s['latest_event_ts'] as num?)?.toInt())
            .whereType<int>()
            .length;
        // Small settle delay before checking the next update
        if (nonNullTs < 10) {
          await Future<void>.delayed(const Duration(milliseconds: 300));
        }
      } while (nonNullTs < 10 && DateTime.now().isBefore(end));
      port.close();

      expect(summaries, isNotEmpty, reason: 'no summaries in payload');
      log('[order-live] summaries=${summaries.length} realTs(non-null)=$nonNullTs');

      // Map to combined rows including all timestamp variants we care about.
      final rows = <({
        String id,
        String name,
        int? realTs,      // latest_event_ts (origin_server_ts)
        int? recencyBump, // bump_ts from summary (recency score)
        int? mappedTs,    // bumpTs after our Dart mapping
      })>[];
      for (final s in summaries) {
        final id = (s['room_id'] as String?) ?? '';
        final name = (s['name'] as String?) ?? '';
        if (name.isEmpty || id.isEmpty) continue;
        final realTs = (s['latest_event_ts'] as num?)?.toInt();
        final recency = (s['bump_ts'] as num?)?.toInt();
        final mapped = RoomOverviewData.fromJson(s);
        rows.add((id: id, name: name, realTs: realTs, recencyBump: recency, mappedTs: mapped.bumpTs));
      }

      int _score(int? v) => v ?? 0;

      List<String> sortNamesBy(int? Function(({String id, String name, int? realTs, int? recencyBump, int? mappedTs}) r) pickTs) {
        final copy = List.of(rows);
        copy.sort((a, b) {
          final at = _score(pickTs(a));
          final bt = _score(pickTs(b));
          final cmp = bt.compareTo(at);
          if (cmp != 0) return cmp;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
        return copy.map((e) => e.name).toList(growable: false);
      }

      // Relative orders for comparison (evaluate only on rows with real ts)
      final filtered = rows.where((r) => r.realTs != null).toList(growable: false);
      expect(filtered, isNotEmpty,
          reason: 'No rows contained latest_event_ts; the server may not have emitted message timelines yet.');

      List<String> orderNamesBy(
          List<({String id, String name, int? realTs, int? recencyBump, int? mappedTs})> source,
          int? Function(({String id, String name, int? realTs, int? recencyBump, int? mappedTs}) r)
              pick) {
        final copy = List.of(source);
        copy.sort((a, b) {
          final at = _score(pick(a));
          final bt = _score(pick(b));
          final cmp = bt.compareTo(at);
          if (cmp != 0) return cmp;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
        return copy.map((e) => e.name).toList(growable: false);
      }

      final expectedOrder = orderNamesBy(filtered, (r) => r.realTs);
      final actualOrder = orderNamesBy(filtered, (r) => r.mappedTs);
      final recencyOrder = sortNamesBy((r) => r.recencyBump); // diagnostic: bump_ts (Matrix recency)

      // ---- Diagnostics: dump top 30 rows with both timestamps ----
      List<String> _fmtTop(List<({String id, String name, int? realTs, int? recencyBump, int? mappedTs})> list) {
        return list.take(30).map((r) => '${r.name} real=${r.realTs ?? '-'} mapped=${r.mappedTs ?? '-'} recency=${r.recencyBump ?? '-'}').toList();
      }

      final topByReal = List.of(rows)..sort((a, b) => _score(b.realTs).compareTo(_score(a.realTs)) == 0
          ? a.name.toLowerCase().compareTo(b.name.toLowerCase())
          : _score(b.realTs).compareTo(_score(a.realTs)));
      final topByMapped = List.of(rows)..sort((a, b) => _score(b.mappedTs).compareTo(_score(a.mappedTs)) == 0
          ? a.name.toLowerCase().compareTo(b.name.toLowerCase())
          : _score(b.mappedTs).compareTo(_score(a.mappedTs)));
      final topByRecency = List.of(rows)..sort((a, b) => _score(b.recencyBump).compareTo(_score(a.recencyBump)) == 0
          ? a.name.toLowerCase().compareTo(b.name.toLowerCase())
          : _score(b.recencyBump).compareTo(_score(a.recencyBump)));

      log('[order-live] top by latest_event_ts:');
      for (final line in _fmtTop(topByReal)) { log('  $line'); }
      log('[order-live] top by mapped bumpTs (used by Home):');
      for (final line in _fmtTop(topByMapped)) { log('  $line'); }
      log('[order-live] top by bump_ts (recency):');
      for (final line in _fmtTop(topByRecency)) { log('  $line'); }

      // Show relative order heads for a quick glance
      log('[order-live] expected (by latest_event_ts) =${expectedOrder.take(20).join(' | ')}');
      log('[order-live] actual   (by mapped bumpTs ) =${actualOrder.take(20).join(' | ')}');
      log('[order-live] recency  (by bump_ts)        =${recencyOrder.take(20).join(' | ')}');

      expect(actualOrder, equals(expectedOrder));
    });
  });
}
