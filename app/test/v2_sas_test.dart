import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:isolate';
import 'dart:ffi'; // for SendPort.nativePort extension

import 'package:flutter_test/flutter_test.dart';
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
  final base = env['MESSIE_MATRIX_STORE_BASE'] ?? Directory.systemTemp.createTempSync('messie_v2').path;
  if (hs == null || user == null || pass == null) return null;
  return _Env(hs, user, pass, base);
}

Map<String, dynamic> _parse(String jsonStr) => json.decode(jsonStr) as Map<String, dynamic>;

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
  Future<bool> _dockerReady() async {
    try {
      final v = await Process.run('docker', ['--version']);
      if (v.exitCode != 0) return false;

      // Check if image exists
      final inspect = await Process.run('docker', ['image', 'inspect', 'messie-matrix-peer:latest']);
      if (inspect.exitCode == 0) return true;

      // Image doesn't exist, try to build it
      print('Building messie-matrix-peer:latest image...');
      final build = await Process.run('make', ['matrix-verify-peer-image'], workingDirectory: '..');
      if (build.exitCode != 0) {
        print('Failed to build peer image: ${build.stderr}');
        return false;
      }

      // Verify it was built
      final recheck = await Process.run('docker', ['image', 'inspect', 'messie-matrix-peer:latest']);
      return recheck.exitCode == 0;
    } catch (e) {
      print('Docker setup error: $e');
      return false;
    }
  }
  final dockerOkFuture = _dockerReady();

  group('v2 SAS verification smoke', () {
    Future<(String peerName, String dockerServerUrl, String peerInfoPath, int launchTs)> _startPeerDocker(_Env env, {String? deviceName}) async {
      // Align with v1: run dockerized peer helper
      var dockerServerUrl = env.hs.replaceFirst('127.0.0.1', 'host.docker.internal');
      dockerServerUrl = dockerServerUrl.replaceFirst('localhost', 'host.docker.internal');
      // Determine state dir mount (to provide recovery key and receive peer info)
      var stateFile = Platform.environment['MESSIE_SEED_STATE_FILE'] ?? '../scripts/matrix/.state/seed_state.json';
      var stateDir = File(stateFile).parent.absolute.path;
      if (!File('$stateDir/recovery_key.json').existsSync()) {
        final alt = File('../scripts/matrix/scripts/matrix/.state/seed_state.json').parent.absolute.path;
        if (Directory(alt).existsSync() && File('$alt/recovery_key.json').existsSync()) {
          stateDir = alt;
        }
      }
      final peerName = Platform.environment['MESSIE_SAS_PEER_CONTAINER'] ?? 'messie-matrix-peer';
      // Clean any previous container
      await Process.run('docker', ['rm', '-f', peerName]);
      final peerInfoPath = '$stateDir/sas_peer.json';
      final launchTs = DateTime.now().millisecondsSinceEpoch;
      final started = await Process.run('docker', [
        'run', '-d', '--name', peerName, '--network', 'host',
        '-e', 'RECOVERY_KEY_PATH=/state/recovery_key.json',
        '-e', 'PEER_INFO_PATH=/state/sas_peer.json',
        '-v', '$stateDir:/state',
        'messie-matrix-peer:latest',
        '--server-url', dockerServerUrl,
        '--username', env.user,
        '--password', env.pass,
        '--device-name', deviceName ?? 'Messie SAS Peer (test)',
      ]);
      if (started.exitCode != 0) {
        throw StateError('Failed to start peer container: ${started.stderr}\n${started.stdout}');
      }
      return (peerName, dockerServerUrl, peerInfoPath, launchTs);
    }

    Future<Map<String, dynamic>> _waitForSasStates(Stream<dynamic> stream,
        {Duration timeout = const Duration(seconds: 90)}) async {
      final end = DateTime.now().add(timeout);
      var sawKeys = false;
      await for (final message in stream) {
        if (DateTime.now().isAfter(end)) {
          throw TimeoutException('Timed out waiting for SAS completion', timeout);
        }
        if (message is! String) continue;
        try {
          final decoded = json.decode(message) as Map<String, dynamic>;
          if (decoded['kind'] != 'sas_update') continue;
          final state = (decoded['state'] as String?) ?? '';
          if (state == 'keys_exchanged') sawKeys = true;
          if (state == 'done') {
            if (!sawKeys) throw StateError('SAS finished without keys_exchanged');
            return decoded;
          }
        } catch (_) {}
      }
      throw StateError('Stream closed before SAS completion');
    }
    Future<String> _waitForPeerReadyDevice(String jsonPath, {required int minTimestamp, Duration timeout = const Duration(seconds: 90)}) async {
      final end = DateTime.now().add(timeout);
      while (DateTime.now().isBefore(end)) {
        final f = File(jsonPath);
        if (f.existsSync()) {
          try {
            final obj = json.decode(await f.readAsString()) as Map<String, dynamic>;
            final did = obj['device_id'] as String?;
            final ready = obj['ready'] as bool?;
            final ts = (obj['ts'] is num) ? (obj['ts'] as num).toInt() : -1;
            if (did != null && did.isNotEmpty && ready == true && ts >= minTimestamp) {
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
        expect(true, isTrue, reason: 'Docker or peer image not available; run `make matrix-verify-peer-image`');
        return;
      }
      final resNew = v2.clientCreate(homeserverUrl: env.hs, basePath: env.base);
      expect(resNew.success, isTrue, reason: 'client_create failed');
      final client = resNew.handle;

      final resLogin = v2.clientLogin(handle: client, username: env.user, password: env.pass);
      expect(resLogin.success, isTrue, reason: 'login failed');
      final userId = resLogin.userId!;

      final (peerName, dockerUrl, peerInfoPath, launchTs) = await _startPeerDocker(env);
      addTearDown(() async { await Process.run('docker', ['rm', '-f', peerName]); });
      try {
        final deviceId = await _waitForPeerReadyDevice(peerInfoPath, minTimestamp: launchTs);
        // Start SAS targeted to the peer device
        print('Starting SAS verification for user: $userId, device: $deviceId');
        final start = v2.sasRequest(clientHandle: client, userId: userId, deviceId: deviceId);
        print('SAS request result: $start');
        expect(start.success, isTrue, reason: 'sas_request failed: $start');
        final sasHandle = start.handle; // 0 can be a valid handle in our registry

        final port = ReceivePort('v2_sas');
        final stream = port.asBroadcastStream();
        final nativePort = port.sendPort.nativePort;
        print('Flutter: Using port $nativePort');
        final observed = v2.sasStartStreaming(sasHandle: sasHandle, port: nativePort);
        print('Observe SAS started: $observed');
        expect(observed, isTrue, reason: 'sas_start_streaming failed');

        // Wait for keys_exchanged followed by done
        print('Waiting for SAS state changes...');
        var sawKeys = false;
        var messageCount = 0;

        // Listen to the port and handle messages immediately
        Completer<bool> sasCompleted = Completer<bool>();

        port.listen((dynamic message) {
          if (message is String) {
            try {
              final decoded = json.decode(message) as Map<String, dynamic>;
              if (decoded['kind'] == 'sas_update') {
                final state = (decoded['state'] as String?) ?? '';
                print('SAS state: $state');

                if (state == 'keys_exchanged') {
                  sawKeys = true;
                  print('Confirming SAS...');
                  // Confirm immediately when keys are exchanged
                  v2.sasConfirm(sasHandle: sasHandle);
                } else if (state == 'done') {
                  print('SAS done - sawKeys: $sawKeys');
                  if (!sasCompleted.isCompleted) {
                    if (sawKeys) {
                      sasCompleted.complete(true);
                    } else {
                      sasCompleted.complete(false);
                    }
                  }
                } else if (state == 'cancelled') {
                  print('SAS cancelled');
                  // Don't complete immediately on cancelled - wait for done
                  // The cancelled state might be a transient state before done
                }
              }
            } catch (e) {
              print('Parse error: $e');
            }
          }
        }, onError: (error) {
          print('Port error: $error');
          sasCompleted.complete(false);
        });

        // Wait for SAS to complete or timeout
        final success = await sasCompleted.future.timeout(
          const Duration(seconds: 25),
          onTimeout: () => false,
        );

        expect(success, isTrue, reason: 'SAS verification should complete successfully');
        expect(sawKeys, isTrue, reason: 'Should have seen keys_exchanged state');
        port.close();
        // Free typed SAS handle after use
        v2.sasFree(sasHandle: sasHandle);
      } finally {
        await Process.run('docker', ['rm', '-f', peerName]);
      }
    });
  });
}
