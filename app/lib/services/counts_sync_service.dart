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
  bool _didBaseline = false;

  void start({required String homeserverUrl, required String accessToken, required String userId}) {
    final credsChanged = _hs != homeserverUrl || _token != accessToken || _userId != userId;
    if (credsChanged) {
      _since = null; // reset since on credential change
      _filterId = null; // recreate filter for new user/session
      _didBaseline = false;
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
        // Always perform a baseline snapshot first to align unread counters at startup.
        // Ignore any persisted since for the first request.
        if (!_didBaseline) {
          // Ensure filter exists first to keep payload minimal
          if (_filterId == null && _userId != null) {
            // Load any persisted filter and its spec; recreate if spec changed
            final persistedId =
                await _loadPersistedFilter(userId: _userId!, homeserverUrl: _hs!);
            final persistedSpec = await _loadPersistedFilterSpec(
                userId: _userId!, homeserverUrl: _hs!);
            final currentSpec = _filterSpecString();
            if (persistedId != null && persistedId.isNotEmpty &&
                persistedSpec == currentSpec) {
              _filterId = persistedId;
            } else {
              _filterId = await _ensureFilter(
                  hs: _hs!, token: _token!, userId: _userId!);
              if (_filterId != null && _filterId!.isNotEmpty) {
                await _persistFilter(
                  userId: _userId!,
                  homeserverUrl: _hs!,
                  filterId: _filterId!,
                );
                await _persistFilterSpec(
                  userId: _userId!,
                  homeserverUrl: _hs!,
                  spec: currentSpec,
                );
              }
            }
          }
          final snap = await _syncOnce(
            hs: _hs!,
            token: _token!,
            since: null,
            timeoutMs: 0,
            filterId: _filterId,
            fullState: true,
          );
          _since = snap.$3;
          if (_since != null && _userId != null) {
            await _persistSince(userId: _userId!, homeserverUrl: _hs!, since: _since!);
          }
          final baseline = snap.$1;
          if (baseline.isNotEmpty) {
            final next = Map<String, UnreadCounts>.from(state);
            next.addAll(baseline);
            state = next;
          }
          _didBaseline = true;
          backoffMs = 500; // reset and continue to long-poll
          continue;
        }

        // Load persisted since after baseline if not already set
        if (_since == null && _userId != null) {
          _since = await _loadPersistedSince(userId: _userId!, homeserverUrl: _hs!);
        }
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
        if (_since != null && _userId != null) {
          await _persistSince(userId: _userId!, homeserverUrl: _hs!, since: _since!);
        }
        final updates = res.$1;
        if (updates.isNotEmpty) {
          final next = Map<String, UnreadCounts>.from(state);
          next.addAll(updates);
          state = next;
        }
        backoffMs = 500; // reset
      } catch (e) {
        if (e is _SyncHttpError) {
          debugPrint('[CountsSync] http ${e.statusCode}: ${e.body}');
          if (e.statusCode == 401) {
            // Token invalid; pause briefly and retry. Auth controller will refresh if needed.
          } else if (e.statusCode == 400) {
            // Possibly invalid filter; clear and recreate next loop.
            if (_filterId != null && _userId != null) {
              await _persistFilter(userId: _userId!, homeserverUrl: _hs!, filterId: '');
              await _persistFilterSpec(userId: _userId!, homeserverUrl: _hs!, spec: '');
            }
            _filterId = null;
            _didBaseline = false; // force baseline again after recreating filter
          }
        } else {
          debugPrint('[CountsSync] error: $e');
        }
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
    bool fullState = false,
  }) async {
    final qp = <String, String>{};
    if (since != null && since.isNotEmpty) qp['since'] = since;
    if (timeoutMs > 0) qp['timeout'] = '$timeoutMs';
    if (filterId != null && filterId.isNotEmpty) qp['filter'] = filterId;
    if (fullState) qp['full_state'] = 'true';
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
        throw _SyncHttpError(resp.statusCode, text);
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
        final filter = _filterSpec();
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

  Map<String, dynamic> _filterSpec() {
    // Lightweight filter: include just enough to trigger unread changes across devices.
    return {
      'event_fields': <String>[],
      'account_data': {'types': <String>[]},
      'presence': {'types': <String>[]},
      'room': {
        'timeline': {'limit': 0},
        // Include read receipts so the server sends updates when reads happen elsewhere
        'ephemeral': {
          'types': <String>['m.receipt']
        },
        // Include fully_read changes which also reflect read progress
        'account_data': {
          'types': <String>['m.fully_read']
        },
        'state': {
          'lazy_load_members': true,
          'types': <String>[],
        },
      },
    };
  }

  String _filterSpecString() => json.encode(_filterSpec());

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

  Future<void> _persistFilterSpec({
    required String userId,
    required String homeserverUrl,
    required String spec,
  }) async {
    try {
      await _secure.write(
        key: _filterSpecKey(userId: userId, homeserverUrl: homeserverUrl),
        value: spec,
      );
    } catch (_) {}
  }

  Future<String?> _loadPersistedFilterSpec({
    required String userId,
    required String homeserverUrl,
  }) async {
    try {
      return await _secure.read(
        key: _filterSpecKey(userId: userId, homeserverUrl: homeserverUrl),
      );
    } catch (_) {
      return null;
    }
  }

  String _filterSpecKey({required String userId, required String homeserverUrl}) =>
      'messie.counts.filter.spec.$userId@$homeserverUrl';

  Future<void> _persistSince({
    required String userId,
    required String homeserverUrl,
    required String since,
  }) async {
    try {
      await _secure.write(
        key: _sinceKey(userId: userId, homeserverUrl: homeserverUrl),
        value: since,
      );
    } catch (_) {}
  }

  Future<String?> _loadPersistedSince({
    required String userId,
    required String homeserverUrl,
  }) async {
    try {
      return await _secure.read(
        key: _sinceKey(userId: userId, homeserverUrl: homeserverUrl),
      );
    } catch (_) {
      return null;
    }
  }

  String _sinceKey({required String userId, required String homeserverUrl}) =>
      'messie.counts.since.$userId@$homeserverUrl';
}

class _SyncHttpError implements Exception {
  _SyncHttpError(this.statusCode, this.body);
  final int statusCode;
  final String body;
  @override
  String toString() => 'SyncHttpError($statusCode): $body';
}
