import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:isolate';
import 'dart:ffi'; // for SendPort.nativePort extension

import 'package:flutter_test/flutter_test.dart';
import 'package:test_api/test_api.dart' show Timeout; // enable @Timeout
import 'package:messie_app/bridge_v2/messie_bridge_v2.dart' as v2;

class _Env {
  final String hs;
  final String user;
  final String pass;
  final String base;
  _Env(this.hs, this.user, this.pass, this.base);
}

_Env? _loadEnv() {
  final env = Platform.environment;
  final hs = env['MESSIE_MATRIX_HOMESERVER'];
  final user = env['MESSIE_MATRIX_USERNAME'];
  final pass = env['MESSIE_MATRIX_PASSWORD'];
  final base = env['MESSIE_MATRIX_STORE_BASE'] ??
      Directory.systemTemp.createTempSync('messie_v2').path;
  if (hs == null || user == null || pass == null) return null;
  return _Env(hs, user, pass, base);
}

Map<String, dynamic> _parse(String jsonStr) =>
    json.decode(jsonStr) as Map<String, dynamic>;

@Timeout(Duration(minutes: 3))
void main() {
  final env = _loadEnv();
  if (env == null) {
    test('skipped - env not set', () {
      expect(true, isTrue, reason: 'Set MESSIE_MATRIX_* env to run');
    }, skip: true);
    return;
  }

  // Auto-build peer image if needed
  Future<bool> dockerReady() async {
    try {
      final v = await Process.run('docker', ['--version']);
      if (v.exitCode != 0) return false;

      // Check if image exists
      final inspect = await Process.run(
          'docker', ['image', 'inspect', 'messie-matrix-peer:latest']);
      if (inspect.exitCode == 0) return true;

      // Image doesn't exist, try to build it
      print('Building messie-matrix-peer:latest image...');
      final build = await Process.run('make', ['matrix-verify-peer-image'],
          workingDirectory: '..');
      if (build.exitCode != 0) {
        print('Failed to build peer image: ${build.stderr}');
        return false;
      }

      // Verify it was built
      final recheck = await Process.run(
          'docker', ['image', 'inspect', 'messie-matrix-peer:latest']);
      return recheck.exitCode == 0;
    } catch (e) {
      print('Docker setup error: $e');
      return false;
    }
  }

  final dockerOkFuture = dockerReady();

  group('v2 SAS verification smoke', () {
    Future<
        (
          String peerName,
          String dockerServerUrl,
          String peerInfoPath,
          int launchTs
        )> startPeerDocker(_Env env, {String? deviceName}) async {
      // Align with v1: run dockerized peer helper
      var dockerServerUrl =
          env.hs.replaceFirst('127.0.0.1', 'host.docker.internal');
      dockerServerUrl =
          dockerServerUrl.replaceFirst('localhost', 'host.docker.internal');
      // Determine state dir mount (to provide recovery key and receive peer info)
      var stateFile = Platform.environment['MESSIE_SEED_STATE_FILE'] ??
          '../scripts/matrix/.state/seed_state.json';
      var stateDir = File(stateFile).parent.absolute.path;
      if (!File('$stateDir/recovery_key.json').existsSync()) {
        final alt =
            File('../scripts/matrix/scripts/matrix/.state/seed_state.json')
                .parent
                .absolute
                .path;
        if (Directory(alt).existsSync() &&
            File('$alt/recovery_key.json').existsSync()) {
          stateDir = alt;
        }
      }
      final peerName = Platform.environment['MESSIE_SAS_PEER_CONTAINER'] ??
          'messie-matrix-peer';
      // Clean any previous container
      await Process.run('docker', ['rm', '-f', peerName]);
      final peerInfoPath = '$stateDir/sas_peer.json';
      final launchTs = DateTime.now().millisecondsSinceEpoch;
      final started = await Process.run('docker', [
        'run',
        '-d',
        '--name',
        peerName,
        '--network',
        'host',
        '-e',
        'RECOVERY_KEY_PATH=/state/recovery_key.json',
        '-e',
        'PEER_INFO_PATH=/state/sas_peer.json',
        '-v',
        '$stateDir:/state',
        'messie-matrix-peer:latest',
        '--server-url',
        dockerServerUrl,
        '--username',
        env.user,
        '--password',
        env.pass,
        '--device-name',
        deviceName ?? 'Messie SAS Peer (test)',
      ]);
      if (started.exitCode != 0) {
        throw StateError(
            'Failed to start peer container: ${started.stderr}\n${started.stdout}');
      }
      return (peerName, dockerServerUrl, peerInfoPath, launchTs);
    }

    Future<Map<String, dynamic>> waitForSasStates(Stream<dynamic> stream,
        {Duration timeout = const Duration(seconds: 90)}) async {
      final end = DateTime.now().add(timeout);
      var sawKeys = false;
      await for (final message in stream) {
        if (DateTime.now().isAfter(end)) {
          throw TimeoutException(
              'Timed out waiting for SAS completion', timeout);
        }
        if (message is! String) continue;
        try {
          final decoded = json.decode(message) as Map<String, dynamic>;
          if (decoded['kind'] != 'sas_update') continue;
          final state = (decoded['state'] as String?) ?? '';
          if (state == 'keys_exchanged') sawKeys = true;
          if (state == 'done') {
            if (!sawKeys)
              throw StateError('SAS finished without keys_exchanged');
            return decoded;
          }
        } catch (_) {}
      }
      throw StateError('Stream closed before SAS completion');
    }

    Future<String> waitForPeerReadyDevice(String jsonPath,
        {required int minTimestamp,
        Duration timeout = const Duration(seconds: 90)}) async {
      final end = DateTime.now().add(timeout);
      while (DateTime.now().isBefore(end)) {
        final f = File(jsonPath);
        if (f.existsSync()) {
          try {
            final obj =
                json.decode(await f.readAsString()) as Map<String, dynamic>;
            final did = obj['device_id'] as String?;
            final ready = obj['ready'] as bool?;
            final ts = (obj['ts'] is num) ? (obj['ts'] as num).toInt() : -1;
            if (did != null &&
                did.isNotEmpty &&
                ready == true &&
                ts >= minTimestamp) {
              return did;
            }
          } catch (_) {}
        }
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      throw StateError('Peer not ready with fresh device id at $jsonPath');
    }

    test('request + observe + finish with peer', () async {
      final dockerOk = await dockerOkFuture;
      if (!dockerOk) {
        expect(true, isTrue,
            reason:
                'Docker or peer image not available; run `make matrix-verify-peer-image`');
        return;
      }
      final resNew = v2.clientCreate(homeserverUrl: env.hs, basePath: env.base);
      expect(resNew.success, isTrue, reason: 'client_create failed');
      final client = resNew.handle;

      final resLogin = v2.clientLogin(
          handle: client, username: env.user, password: env.pass);
      expect(resLogin.success, isTrue, reason: 'login failed');
      final userId = resLogin.userId!;

      final (peerName, dockerUrl, peerInfoPath, launchTs) =
          await startPeerDocker(env);
      addTearDown(() async {
        await Process.run('docker', ['rm', '-f', peerName]);
      });
      try {
        final deviceId =
            await waitForPeerReadyDevice(peerInfoPath, minTimestamp: launchTs);
        final start = v2.sasRequest(
            clientHandle: client, userId: userId, deviceId: deviceId);
        print('SAS request result: $start');
        expect(start.success, isTrue, reason: 'sas_request failed: $start');

        final sasHandle =
            start.handle; // 0 can be a valid handle in our registry
        final port = ReceivePort('v2_sas');
        final nativePort = port.sendPort.nativePort;
        print('Flutter: Using port $nativePort');
        final observed =
            v2.sasStartStreaming(sasHandle: sasHandle, port: nativePort);
        print('Observe SAS started: $observed');
        expect(observed, isTrue, reason: 'sas_start_streaming failed');

        var sawKeys = false;
        var cancelled = false;
        final sasCompleted = Completer<bool>();
        final sub = port.listen((dynamic message) {
          if (message is! String) return;
          try {
            final decoded = json.decode(message) as Map<String, dynamic>;
            if (decoded['kind'] != 'sas_update') return;
            final state = (decoded['state'] as String?) ?? '';
            print('SAS state: $state');
            if (state == 'keys_exchanged') {
              sawKeys = true;
              v2.sasConfirm(sasHandle: sasHandle);
            } else if (state == 'done') {
              if (!sasCompleted.isCompleted) sasCompleted.complete(sawKeys);
            } else if (state == 'cancelled') {
              cancelled = true;
              final reason = decoded['cancel'] as String?;
              if (reason != null && reason.isNotEmpty) {
                print('SAS cancelled: $reason');
              } else {
                print('SAS cancelled');
              }
              if (!sasCompleted.isCompleted) sasCompleted.complete(false);
            }
          } catch (e) {
            print('Parse error: $e');
          }
        }, onError: (error) {
          print('Port error: $error');
          if (!sasCompleted.isCompleted) sasCompleted.complete(false);
        });

        final ok = await sasCompleted.future.timeout(
          const Duration(seconds: 30),
          onTimeout: () => false,
        );
        await sub.cancel();
        port.close();
        v2.sasFree(sasHandle: sasHandle);

        if (cancelled) {
          fail('SAS cancelled');
        }
        expect(ok, isTrue,
            reason: 'SAS verification should complete successfully');
        expect(sawKeys, isTrue,
            reason: 'Should have seen keys_exchanged state');
      } finally {
        await Process.run('docker', ['rm', '-f', peerName]);
      }
    });
  });
}
