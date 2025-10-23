import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class UnreadCounts {
  const UnreadCounts(this.notification, this.highlight);
  final int notification;
  final int highlight;
}

final countsSyncProvider =
    StateNotifierProvider<CountsSyncService, Map<String, UnreadCounts>>(
  (ref) => CountsSyncService(),
);

class CountsSyncService extends StateNotifier<Map<String, UnreadCounts>> {
  CountsSyncService() : super(const <String, UnreadCounts>{});

  String? _hs;
  String? _token;
  String? _userId;
  String? _since;
  String? _filterId;
  bool _running = false;
  Future<void>? _task;
  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  void start({required String homeserverUrl, required String accessToken, required String userId}) {
    final credsChanged = _hs != homeserverUrl || _token != accessToken || _userId != userId;
    if (credsChanged) {
      _since = null; // reset since on credential change
      _filterId = null; // recreate filter for new user/session
    }
    if (_running && !credsChanged) return;
    _hs = homeserverUrl;
    _token = accessToken;
    _userId = userId;
    _running = true;
    _task ??= _loop();
  }

  void stop() {
    _running = false;
    _task = null;
  }

  Future<void> _loop() async {
    var backoffMs = 500;
    while (_running) {
      try {
        // Load or create a lightweight filter to minimize payload.
        if (_filterId == null && _userId != null) {
          _filterId = await _loadPersistedFilter(userId: _userId!, homeserverUrl: _hs!);
          _filterId ??=
              await _ensureFilter(hs: _hs!, token: _token!, userId: _userId!);
          if (_filterId != null && _filterId!.isNotEmpty) {
            await _persistFilter(
              userId: _userId!,
              homeserverUrl: _hs!,
              filterId: _filterId!,
            );
          }
        }
        final res = await _syncOnce(
          hs: _hs!,
          token: _token!,
          since: _since,
          timeoutMs: _since == null ? 0 : 30000,
          filterId: _filterId,
        );
        _since = res.$3;
        final updates = res.$1;
        if (updates.isNotEmpty) {
          final next = Map<String, UnreadCounts>.from(state);
          next.addAll(updates);
          state = next;
        }
        backoffMs = 500; // reset
      } catch (e) {
        debugPrint('[CountsSync] error: $e');
        await Future<void>.delayed(Duration(milliseconds: backoffMs));
        backoffMs = (backoffMs * 2).clamp(500, 8000);
      }
    }
  }

  // Returns (roomId->UnreadCounts, presentRoomIds, nextBatch)
  Future<(Map<String, UnreadCounts>, Set<String>, String)> _syncOnce({
    required String hs,
    required String token,
    String? since,
    int timeoutMs = 0,
    String? filterId,
  }) async {
    final qp = <String, String>{};
    if (since != null && since.isNotEmpty) qp['since'] = since;
    if (timeoutMs > 0) qp['timeout'] = '$timeoutMs';
    if (filterId != null && filterId.isNotEmpty) qp['filter'] = filterId;
    final uri = Uri.parse(hs).replace(
      path: '/_matrix/client/v3/sync',
      queryParameters: qp.isEmpty ? null : qp,
    );
    final client = HttpClient();
    try {
      final req = await client.getUrl(uri);
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final resp = await req.close();
      final text = await utf8.decoder.bind(resp).join();
      if (resp.statusCode != 200) {
        throw Exception('sync GET failed: ${resp.statusCode} $text');
      }
      final body = json.decode(text) as Map<String, dynamic>;
      final next = (body['next_batch'] as String?) ?? '';
      final rooms = (body['rooms'] as Map?) ?? const {};
      final join = (rooms['join'] as Map?) ?? const {};
      final present = <String>{...join.keys.map((k) => k.toString())};
      final updates = <String, UnreadCounts>{};
      join.forEach((key, value) {
        final room = value as Map<String, dynamic>?;
        if (room == null) return;
        final unread = (room['unread_notifications'] as Map?) ?? const {};
        final n = (unread['notification_count'] as num?)?.toInt() ?? 0;
        final h = (unread['highlight_count'] as num?)?.toInt() ?? 0;
        updates[key.toString()] = UnreadCounts(n, h);
      });
      return (updates, present, next);
    } finally {
      client.close(force: true);
    }
  }

  /// Ensure a minimal filter exists on the homeserver for the given user, to
  /// reduce /sync payload to only unread counters and minimal state.
  Future<String?> _ensureFilter({required String hs, required String token, required String userId}) async {
    try {
      final uri = Uri.parse(hs).replace(
        path: '/_matrix/client/v3/user/${Uri.encodeComponent(userId)}/filter',
      );
      final client = HttpClient();
      try {
        final req = await client.postUrl(uri);
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
        req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
        // Lightweight filter: no presence, no account data, no ephemeral, no timeline, lazy-load members.
        final filter = {
          'event_fields': <String>[],
          'account_data': {'types': <String>[]},
          'presence': {'types': <String>[]},
          'room': {
            'timeline': {'limit': 0},
            'ephemeral': {'types': <String>[]},
            'account_data': {'types': <String>[]},
            'state': {
              'lazy_load_members': true,
              'types': <String>[],
            },
          },
        };
        req.add(utf8.encode(json.encode(filter)));
        final resp = await req.close();
        final text = await utf8.decoder.bind(resp).join();
        if (resp.statusCode != 200) {
          debugPrint('[CountsSync] filter create failed: ${resp.statusCode} $text');
          return null;
        }
        final obj = json.decode(text) as Map<String, dynamic>;
        final fid = obj['filter_id'] as String?;
        return fid;
      } finally {
        client.close(force: true);
      }
    } catch (e) {
      debugPrint('[CountsSync] ensureFilter error: $e');
      return null;
    }
  }

  String _filterKey({required String userId, required String homeserverUrl}) {
    return 'messie.counts.filter.$userId@$homeserverUrl';
  }

  Future<void> _persistFilter({
    required String userId,
    required String homeserverUrl,
    required String filterId,
  }) async {
    try {
      await _secure.write(
        key: _filterKey(userId: userId, homeserverUrl: homeserverUrl),
        value: filterId,
      );
    } catch (_) {}
  }

  Future<String?> _loadPersistedFilter({
    required String userId,
    required String homeserverUrl,
  }) async {
    try {
      return await _secure.read(
        key: _filterKey(userId: userId, homeserverUrl: homeserverUrl),
      );
    } catch (_) {
      return null;
    }
  }
}
