import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show consolidateHttpClientResponseBytes, debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../bridge/messie_bridge.dart';
import '../state/auth_view_model.dart';

final mediaRepositoryProvider = Provider<MediaRepository>((ref) {
  return MediaRepository(ref);
});

class AvatarSource {
  const AvatarSource({this.filePath, this.httpUrl});
  final String? filePath;
  final String? httpUrl;
  bool get hasFile => filePath != null && filePath!.isNotEmpty;
  bool get hasHttp => httpUrl != null && httpUrl!.isNotEmpty;
}

class MediaRepository {
  MediaRepository(this._ref);
  final Ref _ref;

  Future<AvatarSource> resolveAvatar({
    required String? mxc,
    int w = 96,
    int h = 96,
  }) async {
    try {
      if (mxc == null || mxc.isEmpty || !mxc.startsWith('mxc://')) {
        return const AvatarSource();
      }
      final httpRes = await rustMxcToHttp(mxc: mxc, w: w, h: h);
      if (!httpRes.isOk || httpRes.data == null) {
        return const AvatarSource();
      }
      final httpUrl = httpRes.data!;
      final dir = await getApplicationSupportDirectory();
      final cacheDir = Directory(p.join(dir.path, 'messie', 'media', 'avatars'));
      try {
        await cacheDir.create(recursive: true);
      } catch (_) {}
      final key = _avatarCacheKey(mxc, w: w, h: h);
      final target = File(p.join(cacheDir.path, key));
      if (await target.exists()) {
        return AvatarSource(filePath: target.path);
      }
      // Download with optional auth header
      final session = _ref.read(authControllerProvider).asData?.value;
      try {
        final client = HttpClient();
        final uri = Uri.parse(httpUrl);
        final req = await client.getUrl(uri);
        if (session != null) {
          req.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${session.accessToken}');
        }
        final resp = await req.close();
        if (resp.statusCode == 200) {
          final bytes = await consolidateHttpClientResponseBytes(resp);
          await target.writeAsBytes(bytes, flush: true);
          client.close(force: true);
          return AvatarSource(filePath: target.path);
        } else {
          client.close(force: true);
          return AvatarSource(httpUrl: httpUrl);
        }
      } catch (e) {
        debugPrint('Avatar download failed: $e');
        return AvatarSource(httpUrl: httpUrl);
      }
    } catch (_) {
      return const AvatarSource();
    }
  }

  String _avatarCacheKey(String mxc, {required int w, required int h}) {
    final base = mxc.replaceAll('mxc://', '');
    final size = 'w${w}h$h';
    final sanitized = base.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    return '${sanitized}_$size';
  }
}

