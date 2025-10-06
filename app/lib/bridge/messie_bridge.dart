import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:isolate';
import 'dart:io';

import 'package:ffi/ffi.dart'; // Utf8, toNativeUtf8, toDartString, calloc

typedef _PointerUtf8 = ffi.Pointer<Utf8>;

// ---- FFI signature typedefs (avoid parser confusion with inline function types) ----
typedef _NativePing = _PointerUtf8 Function();
typedef _DartPing = _PointerUtf8 Function();

typedef _NativeInitClient = _PointerUtf8 Function(_PointerUtf8, _PointerUtf8);
typedef _DartInitClient = _PointerUtf8 Function(_PointerUtf8, _PointerUtf8);

typedef _NativeRestoreOrLogin = _PointerUtf8 Function(
    _PointerUtf8, _PointerUtf8, _PointerUtf8, _PointerUtf8);
typedef _DartRestoreOrLogin = _PointerUtf8 Function(
    _PointerUtf8, _PointerUtf8, _PointerUtf8, _PointerUtf8);

typedef _NativeLogout = _PointerUtf8 Function(_PointerUtf8);
typedef _DartLogout = _PointerUtf8 Function(_PointerUtf8);
typedef _NativeRecoverWithKey = _PointerUtf8 Function(_PointerUtf8);
typedef _DartRecoverWithKey = _PointerUtf8 Function(_PointerUtf8);
typedef _NativeDownloadRoomKeys = _PointerUtf8 Function(_PointerUtf8);
typedef _DartDownloadRoomKeys = _PointerUtf8 Function(_PointerUtf8);
typedef _NativeDumpRoomCrypto = _PointerUtf8 Function(_PointerUtf8);
typedef _DartDumpRoomCrypto = _PointerUtf8 Function(_PointerUtf8);
typedef _NativeBackupStatus = _PointerUtf8 Function();
typedef _DartBackupStatus = _PointerUtf8 Function();
typedef _NativeImportRecoveryKey = _PointerUtf8 Function(_PointerUtf8);
typedef _DartImportRecoveryKey = _PointerUtf8 Function(_PointerUtf8);
typedef _NativeBackupStatusStream = _PointerUtf8 Function(_PointerUtf8, ffi.Int64);
typedef _DartBackupStatusStream = _PointerUtf8 Function(_PointerUtf8, int);
typedef _NativeEnableOnlineBackup = _PointerUtf8 Function(ffi.Uint8);
typedef _DartEnableOnlineBackup = _PointerUtf8 Function(int);
typedef _NativeExportRecoveryKey = _PointerUtf8 Function();
typedef _DartExportRecoveryKey = _PointerUtf8 Function();
typedef _NativeSsssImportRecoveryKey = _PointerUtf8 Function(_PointerUtf8);
typedef _DartSsssImportRecoveryKey = _PointerUtf8 Function(_PointerUtf8);
typedef _NativeSsssBootstrap = _PointerUtf8 Function(ffi.Uint8, _PointerUtf8);
typedef _DartSsssBootstrap = _PointerUtf8 Function(int, _PointerUtf8);
typedef _NativeSsssExportRecoveryKey = _PointerUtf8 Function();
typedef _DartSsssExportRecoveryKey = _PointerUtf8 Function();

typedef _NativeRequestSasVerification = _PointerUtf8 Function(_PointerUtf8, _PointerUtf8);
typedef _DartRequestSasVerification = _PointerUtf8 Function(_PointerUtf8, _PointerUtf8);
typedef _NativeObserveSas = _PointerUtf8 Function(_PointerUtf8, ffi.Int64);
typedef _DartObserveSas = _PointerUtf8 Function(_PointerUtf8, int);
typedef _NativeConfirmSas = _PointerUtf8 Function(_PointerUtf8);
typedef _DartConfirmSas = _PointerUtf8 Function(_PointerUtf8);
typedef _NativeCancelSas = _PointerUtf8 Function(_PointerUtf8);
typedef _DartCancelSas = _PointerUtf8 Function(_PointerUtf8);
typedef _NativeTrustState = _PointerUtf8 Function(_PointerUtf8, _PointerUtf8);
typedef _DartTrustState = _PointerUtf8 Function(_PointerUtf8, _PointerUtf8);

typedef _NativeStartSlidingSync = _PointerUtf8 Function(
    _PointerUtf8, ffi.Uint32, ffi.Uint32, ffi.Uint32, ffi.Uint32);
typedef _DartStartSlidingSync = _PointerUtf8 Function(
    _PointerUtf8, int, int, int, int);

typedef _NativeRoomListStream = _PointerUtf8 Function(_PointerUtf8, ffi.Int64);
typedef _DartRoomListStream = _PointerUtf8 Function(_PointerUtf8, int);
typedef _NativeListJoinedRooms = _PointerUtf8 Function();
typedef _DartListJoinedRooms = _PointerUtf8 Function();
typedef _NativeRoomOverview = _PointerUtf8 Function(_PointerUtf8);
typedef _DartRoomOverview = _PointerUtf8 Function(_PointerUtf8);

typedef _NativeOpenRoom = _PointerUtf8 Function(_PointerUtf8, _PointerUtf8);
typedef _DartOpenRoom = _PointerUtf8 Function(_PointerUtf8, _PointerUtf8);

typedef _NativeTimelineStream = _PointerUtf8 Function(
    _PointerUtf8, _PointerUtf8, ffi.Int64);
typedef _DartTimelineStream = _PointerUtf8 Function(
    _PointerUtf8, _PointerUtf8, int);

typedef _NativeLoadBackward = _PointerUtf8 Function(
    _PointerUtf8, _PointerUtf8, ffi.Uint32);
typedef _DartLoadBackward = _PointerUtf8 Function(
    _PointerUtf8, _PointerUtf8, int);

typedef _NativeFreeString = ffi.Void Function(_PointerUtf8);
typedef _DartFreeString = void Function(_PointerUtf8);

typedef _NativePostCObjectFn
    = ffi.NativeFunction<ffi.Int8 Function(ffi.Int64, ffi.Pointer<ffi.Void>)>;
typedef _NativeStoreDartPostCObject = ffi.Void Function(
    ffi.Pointer<_NativePostCObjectFn>);
typedef _DartStoreDartPostCObject = void Function(
    ffi.Pointer<_NativePostCObjectFn>);

ffi.DynamicLibrary? _sharedLibrary;
bool _postCObjectRegistered = false;

ffi.DynamicLibrary _loadLibrary(_LibraryConfig config) {
  return _sharedLibrary ??= config.open();
}

void _ensurePostCObjectRegistered(_LibraryConfig config) {
  if (_postCObjectRegistered) {
    return;
  }
  final library = _loadLibrary(config);
  final store = library.lookupFunction<_NativeStoreDartPostCObject,
      _DartStoreDartPostCObject>('messie_ffi_store_dart_post_cobject');
  store(ffi.NativeApi.postCObject.cast<_NativePostCObjectFn>());
  _postCObjectRegistered = true;
}

Future<String> rustPing() {
  final config = _LibraryConfig.detect();
  _ensurePostCObjectRegistered(config);
  return Isolate.run(() => _pingIsolate(config));
}

Future<RustResult<InitClientData>> rustInitClient({
  required String homeserverUrl,
  required String basePath,
}) {
  final config = _LibraryConfig.detect();
  _ensurePostCObjectRegistered(config);
  final args = _InitArgs(config, homeserverUrl, basePath);
  return Isolate.run(() => _initClientIsolate(args));
}

Future<RustResult<LoginData>> rustRestoreOrLogin({
  required String homeserverUrl,
  required String username,
  required String password,
  required String basePath,
}) {
  final config = _LibraryConfig.detect();
  _ensurePostCObjectRegistered(config);
  final args = _RestoreArgs(
    config,
    homeserverUrl,
    username,
    password,
    basePath,
  );
  return Isolate.run(() => _restoreOrLoginIsolate(args));
}

Future<RustResult<Unit>> rustLogout({required String basePath}) {
  final config = _LibraryConfig.detect();
  _ensurePostCObjectRegistered(config);
  final args = _LogoutArgs(config, basePath);
  return Isolate.run(() => _logoutIsolate(args));
}

Future<RustResult<Unit>> rustRecoverWithKey({required String recoveryKey}) {
  final config = _LibraryConfig.detect();
  _ensurePostCObjectRegistered(config);
  final args = _RecoverArgs(config, recoveryKey);
  return Isolate.run(() => _recoverWithKeyIsolate(args));
}

Future<RustResult<Unit>> rustDownloadRoomKeysForRoom({
  required String roomId,
}) {
  final config = _LibraryConfig.detect();
  _ensurePostCObjectRegistered(config);
  final args = _DownloadRoomKeysArgs(config, roomId);
  return Isolate.run(() => _downloadRoomKeysIsolate(args));
}

Future<RustResult<Unit>> rustDumpRoomCrypto({required String roomId}) {
  final config = _LibraryConfig.detect();
  _ensurePostCObjectRegistered(config);
  final args = _DumpRoomCryptoArgs(config, roomId);
  return Isolate.run(() => _dumpRoomCryptoIsolate(args));
}

Future<RustResult<BackupStatusData>> rustBackupStatus() {
  final config = _LibraryConfig.detect();
  _ensurePostCObjectRegistered(config);
  return Isolate.run(() => _backupStatusIsolate(config));
}

Future<RustResult<Unit>> rustImportRecoveryKey({required String recoveryKey}) {
  final config = _LibraryConfig.detect();
  _ensurePostCObjectRegistered(config);
  final args = _RecoverArgs(config, recoveryKey);
  return Isolate.run(() => _importRecoveryKeyIsolate(args));
}

Future<RustResult<AckData>> rustBackupStatusStream({
  required String handle,
  required SendPort port,
}) {
  final config = _LibraryConfig.detect();
  _ensurePostCObjectRegistered(config);
  final args = _RoomListStreamArgs(config, handle, port.nativePort);
  return Isolate.run(() => _backupStatusStreamIsolate(args));
}

Future<RustResult<EnableBackupData>> rustEnableOnlineBackup({required bool generateNew}) {
  final config = _LibraryConfig.detect();
  _ensurePostCObjectRegistered(config);
  final args = _EnableBackupArgs(config, generateNew);
  return Isolate.run(() => _enableOnlineBackupIsolate(args));
}

Future<RustResult<ExportRecoveryKeyData>> rustExportRecoveryKey() {
  final config = _LibraryConfig.detect();
  _ensurePostCObjectRegistered(config);
  return Isolate.run(() => _exportRecoveryKeyIsolate(config));
}

Future<RustResult<Unit>> rustSsssImportRecoveryKey({required String recoveryKeyBech32}) {
  final config = _LibraryConfig.detect();
  _ensurePostCObjectRegistered(config);
  final args = _RecoverArgs(config, recoveryKeyBech32);
  return Isolate.run(() => _ssssImportRecoveryKeyIsolate(args));
}

Future<RustResult<SsssBootstrapData>> rustSsssBootstrap({required bool generateNewKey, String? passphrase}) {
  final config = _LibraryConfig.detect();
  _ensurePostCObjectRegistered(config);
  final args = _SsssBootstrapArgs(config, generateNewKey, passphrase ?? '');
  return Isolate.run(() => _ssssBootstrapIsolate(args));
}

Future<RustResult<ExportRecoveryKeyData>> rustSsssExportRecoveryKey() {
  final config = _LibraryConfig.detect();
  _ensurePostCObjectRegistered(config);
  return Isolate.run(() => _ssssExportRecoveryKeyIsolate(config));
}

Future<RustResult<StartSasData>> rustRequestSasVerification({
  required String userId,
  String? deviceId,
}) {
  final config = _LibraryConfig.detect();
  _ensurePostCObjectRegistered(config);
  final args = _RequestSasArgs(config, userId, deviceId ?? '');
  return Isolate.run(() => _requestSasIsolate(args));
}

Future<RustResult<AckData>> rustObserveSas({
  required String flowId,
  required SendPort port,
}) {
  final config = _LibraryConfig.detect();
  _ensurePostCObjectRegistered(config);
  final args = _ObserveSasArgs(config, flowId, port.nativePort);
  return Isolate.run(() => _observeSasIsolate(args));
}

Future<RustResult<Unit>> rustConfirmSas({required String flowId}) {
  final config = _LibraryConfig.detect();
  _ensurePostCObjectRegistered(config);
  final args = _FlowIdArgs(config, flowId);
  return Isolate.run(() => _confirmSasIsolate(args));
}

Future<RustResult<Unit>> rustCancelSas({required String flowId}) {
  final config = _LibraryConfig.detect();
  _ensurePostCObjectRegistered(config);
  final args = _FlowIdArgs(config, flowId);
  return Isolate.run(() => _cancelSasIsolate(args));
}

Future<RustResult<TrustStateData>> rustTrustState({
  required String userId,
  String? deviceId,
}) {
  final config = _LibraryConfig.detect();
  _ensurePostCObjectRegistered(config);
  final args = _TrustStateArgs(config, userId, deviceId ?? '');
  return Isolate.run(() => _trustStateIsolate(args));
}

Future<RustResult<StartSlidingSyncData>> rustStartSlidingSync({
  required String handle,
  required int hpSize,
  required int lpBatch,
  required int hpTimeline,
  required int lpTimeline,
}) {
  final config = _LibraryConfig.detect();
  _ensurePostCObjectRegistered(config);
  final args = _StartSyncArgs(
    config,
    handle,
    hpSize,
    lpBatch,
    hpTimeline,
    lpTimeline,
  );
  return Isolate.run(() => _startSlidingSyncIsolate(args));
}

Future<RustResult<AckData>> rustRoomListStream({
  required String handle,
  required SendPort port,
}) {
  final config = _LibraryConfig.detect();
  _ensurePostCObjectRegistered(config);
  final args = _RoomListStreamArgs(
    config,
    handle,
    port.nativePort,
  );
  return Isolate.run(() => _roomListStreamIsolate(args));
}

Future<RustResult<ListRoomsData>> rustListJoinedRooms() {
  final config = _LibraryConfig.detect();
  _ensurePostCObjectRegistered(config);
  return Isolate.run(() => _listJoinedRoomsIsolate(config));
}

Future<RustResult<RoomOverviewData>> rustRoomOverview({
  required String roomId,
}) {
  final config = _LibraryConfig.detect();
  _ensurePostCObjectRegistered(config);
  final args = _RoomOverviewArgs(config, roomId);
  return Isolate.run(() => _roomOverviewIsolate(args));
}

Future<RustResult<OpenRoomData>> rustOpenRoom({
  required String handle,
  required String roomId,
}) {
  final config = _LibraryConfig.detect();
  _ensurePostCObjectRegistered(config);
  final args = _RoomHandleArgs(config, handle, roomId);
  return Isolate.run(() => _openRoomIsolate(args));
}

Future<RustResult<AckData>> rustTimelineStream({
  required String handle,
  required String roomId,
  required SendPort port,
}) {
  final config = _LibraryConfig.detect();
  _ensurePostCObjectRegistered(config);
  final args = _TimelineStreamArgs(
    config,
    handle,
    roomId,
    port.nativePort,
  );
  return Isolate.run(() => _timelineStreamIsolate(args));
}

Future<RustResult<LoadBackwardData>> rustLoadBackward({
  required String handle,
  required String roomId,
  required int limit,
}) {
  final config = _LibraryConfig.detect();
  _ensurePostCObjectRegistered(config);
  final args = _LoadBackwardArgs(config, handle, roomId, limit);
  return Isolate.run(() => _loadBackwardIsolate(args));
}

String _pingIsolate(_LibraryConfig config) {
  final bindings = _RustBindings(_loadLibrary(config));
  return bindings.ping();
}

RustResult<InitClientData> _initClientIsolate(_InitArgs args) {
  final bindings = _RustBindings(_loadLibrary(args.config));
  return bindings.initClient(args.homeserverUrl, args.basePath);
}

RustResult<LoginData> _restoreOrLoginIsolate(_RestoreArgs args) {
  final bindings = _RustBindings(_loadLibrary(args.config));
  return bindings.restoreOrLogin(
    args.homeserverUrl,
    args.username,
    args.password,
    args.basePath,
  );
}

RustResult<Unit> _logoutIsolate(_LogoutArgs args) {
  final bindings = _RustBindings(_loadLibrary(args.config));
  return bindings.logout(args.basePath);
}

RustResult<Unit> _recoverWithKeyIsolate(_RecoverArgs args) {
  final bindings = _RustBindings(_loadLibrary(args.config));
  return bindings.recoverWithKey(args.recoveryKey);
}

RustResult<Unit> _downloadRoomKeysIsolate(_DownloadRoomKeysArgs args) {
  final bindings = _RustBindings(_loadLibrary(args.config));
  return bindings.downloadRoomKeysForRoom(args.roomId);
}

RustResult<Unit> _dumpRoomCryptoIsolate(_DumpRoomCryptoArgs args) {
  final bindings = _RustBindings(_loadLibrary(args.config));
  return bindings.dumpRoomCrypto(args.roomId);
}

RustResult<BackupStatusData> _backupStatusIsolate(_LibraryConfig config) {
  final bindings = _RustBindings(_loadLibrary(config));
  return bindings.backupStatus();
}

RustResult<Unit> _importRecoveryKeyIsolate(_RecoverArgs args) {
  final bindings = _RustBindings(_loadLibrary(args.config));
  return bindings.importRecoveryKey(args.recoveryKey);
}

RustResult<AckData> _backupStatusStreamIsolate(_RoomListStreamArgs args) {
  final bindings = _RustBindings(_loadLibrary(args.config));
  return bindings.backupStatusStream(args.handle, args.nativePort);
}

RustResult<EnableBackupData> _enableOnlineBackupIsolate(_EnableBackupArgs args) {
  final bindings = _RustBindings(_loadLibrary(args.config));
  return bindings.enableOnlineBackup(args.generateNew);
}

RustResult<ExportRecoveryKeyData> _exportRecoveryKeyIsolate(_LibraryConfig config) {
  final bindings = _RustBindings(_loadLibrary(config));
  return bindings.exportRecoveryKey();
}

RustResult<Unit> _ssssImportRecoveryKeyIsolate(_RecoverArgs args) {
  final bindings = _RustBindings(_loadLibrary(args.config));
  return bindings.ssssImportRecoveryKey(args.recoveryKey);
}

RustResult<SsssBootstrapData> _ssssBootstrapIsolate(_SsssBootstrapArgs args) {
  final bindings = _RustBindings(_loadLibrary(args.config));
  return bindings.ssssBootstrap(args.generateNewKey, args.passphrase);
}

RustResult<ExportRecoveryKeyData> _ssssExportRecoveryKeyIsolate(_LibraryConfig config) {
  final bindings = _RustBindings(_loadLibrary(config));
  return bindings.ssssExportRecoveryKey();
}

RustResult<StartSlidingSyncData> _startSlidingSyncIsolate(_StartSyncArgs args) {
  final bindings = _RustBindings(_loadLibrary(args.config));
  return bindings.startSlidingSync(
    args.handle,
    args.hpSize,
    args.lpBatch,
    args.hpTimeline,
    args.lpTimeline,
  );
}

RustResult<AckData> _roomListStreamIsolate(_RoomListStreamArgs args) {
  final bindings = _RustBindings(_loadLibrary(args.config));
  return bindings.roomListStream(args.handle, args.nativePort);
}

RustResult<ListRoomsData> _listJoinedRoomsIsolate(_LibraryConfig config) {
  final bindings = _RustBindings(_loadLibrary(config));
  return bindings.listJoinedRooms();
}

RustResult<RoomOverviewData> _roomOverviewIsolate(_RoomOverviewArgs args) {
  final bindings = _RustBindings(_loadLibrary(args.config));
  return bindings.roomOverview(args.roomId);
}

RustResult<OpenRoomData> _openRoomIsolate(_RoomHandleArgs args) {
  final bindings = _RustBindings(_loadLibrary(args.config));
  return bindings.openRoom(args.handle, args.roomId);
}

RustResult<AckData> _timelineStreamIsolate(_TimelineStreamArgs args) {
  final bindings = _RustBindings(_loadLibrary(args.config));
  return bindings.timelineStream(args.handle, args.roomId, args.nativePort);
}

RustResult<LoadBackwardData> _loadBackwardIsolate(_LoadBackwardArgs args) {
  final bindings = _RustBindings(_loadLibrary(args.config));
  return bindings.loadBackward(args.handle, args.roomId, args.limit);
}

RustResult<StartSasData> _requestSasIsolate(_RequestSasArgs args) {
  final bindings = _RustBindings(_loadLibrary(args.config));
  return bindings.requestSasVerification(args.userId,
      deviceId: args.deviceId.isEmpty ? null : args.deviceId);
}

RustResult<AckData> _observeSasIsolate(_ObserveSasArgs args) {
  final bindings = _RustBindings(_loadLibrary(args.config));
  return bindings.observeSas(args.flowId, args.nativePort);
}

RustResult<Unit> _confirmSasIsolate(_FlowIdArgs args) {
  final bindings = _RustBindings(_loadLibrary(args.config));
  return bindings.confirmSas(args.flowId);
}

RustResult<Unit> _cancelSasIsolate(_FlowIdArgs args) {
  final bindings = _RustBindings(_loadLibrary(args.config));
  return bindings.cancelSas(args.flowId);
}

RustResult<TrustStateData> _trustStateIsolate(_TrustStateArgs args) {
  final bindings = _RustBindings(_loadLibrary(args.config));
  return bindings.trustState(args.userId,
      deviceId: args.deviceId.isEmpty ? null : args.deviceId);
}

class RustResult<T> {
  const RustResult({
    required this.ok,
    this.data,
    this.error,
  });

  final bool ok;
  final T? data;
  final String? error;

  bool get isOk => ok;
}

class BackupStatusData {
  const BackupStatusData({
    required this.enabled,
    required this.existsOnServer,
    this.recoveryState,
    this.needsRecovery,
  });

  factory BackupStatusData.fromJson(Map<String, dynamic> json) {
    return BackupStatusData(
      enabled: json['enabled'] as bool? ?? false,
      existsOnServer: json['exists_on_server'] as bool? ?? false,
      recoveryState: json['recovery_state'] as String?,
      needsRecovery: json['needs_recovery'] as bool?,
    );
  }

  final bool enabled;
  final bool existsOnServer;
  final String? recoveryState;
  final bool? needsRecovery;
}

class EnableBackupData {
  const EnableBackupData({
    required this.enabled,
    required this.existsOnServer,
    this.generatedRecoveryKey,
  });

  factory EnableBackupData.fromJson(Map<String, dynamic> json) {
    return EnableBackupData(
      enabled: json['enabled'] as bool? ?? false,
      existsOnServer: json['exists_on_server'] as bool? ?? false,
      generatedRecoveryKey: json['generated_recovery_key'] as String?,
    );
  }

  final bool enabled;
  final bool existsOnServer;
  final String? generatedRecoveryKey;
}

class ExportRecoveryKeyData {
  const ExportRecoveryKeyData({this.recoveryKey});

  factory ExportRecoveryKeyData.fromJson(Map<String, dynamic> json) {
    return ExportRecoveryKeyData(recoveryKey: json['recovery_key'] as String?);
  }

  final String? recoveryKey;
}

class StartSasData {
  const StartSasData({required this.flowId});
  final String flowId;

  factory StartSasData.fromJson(Map<String, dynamic> json) {
    return StartSasData(flowId: (json['flow_id'] as String?) ?? '');
  }
}

class TrustStateData {
  const TrustStateData({
    required this.userVerified,
    this.deviceVerified,
    this.deviceExists,
  });

  factory TrustStateData.fromJson(Map<String, dynamic> json) {
    return TrustStateData(
      userVerified: json['user_verified'] as bool? ?? false,
      deviceVerified: json['device_verified'] as bool?,
      deviceExists: json['device_exists'] as bool?,
    );
  }

  final bool userVerified;
  final bool? deviceVerified;
  final bool? deviceExists;
}

class SsssBootstrapData {
  const SsssBootstrapData({this.generatedRecoveryKey});

  factory SsssBootstrapData.fromJson(Map<String, dynamic> json) {
    return SsssBootstrapData(
      generatedRecoveryKey: json['generated_recovery_key'] as String?,
    );
  }

  final String? generatedRecoveryKey;
}

class _SsssBootstrapArgs {
  const _SsssBootstrapArgs(this.config, this.generateNewKey, this.passphrase);

  final _LibraryConfig config;
  final bool generateNewKey;
  final String passphrase;
}

class _EnableBackupArgs {
  const _EnableBackupArgs(this.config, this.generateNew);

  final _LibraryConfig config;
  final bool generateNew;
}

class InitClientData {
  const InitClientData({
    required this.userId,
    required this.homeserverUrl,
    this.deviceId,
  });

  factory InitClientData.fromJson(Map<String, dynamic> json) {
    return InitClientData(
      userId: json['user_id'] as String,
      homeserverUrl: json['homeserver_url'] as String,
      deviceId: json['device_id'] as String?,
    );
  }

  final String userId;
  final String homeserverUrl;
  final String? deviceId;
}

class LoginData {
  const LoginData({
    required this.userId,
    required this.homeserverUrl,
    required this.accessToken,
    required this.didRestore,
    this.deviceId,
  });

  factory LoginData.fromJson(Map<String, dynamic> json) {
    return LoginData(
      userId: json['user_id'] as String,
      homeserverUrl: json['homeserver_url'] as String,
      accessToken: json['access_token'] as String,
      didRestore: json['did_restore'] as bool? ?? false,
      deviceId: json['device_id'] as String?,
    );
  }

  final String userId;
  final String homeserverUrl;
  final String accessToken;
  final bool didRestore;
  final String? deviceId;
}

class StartSlidingSyncData {
  const StartSlidingSyncData({required this.started});

  factory StartSlidingSyncData.fromJson(Map<String, dynamic> json) {
    return StartSlidingSyncData(started: json['started'] as bool? ?? false);
  }

  final bool started;
}

class ListRoomsData {
  const ListRoomsData({required this.rooms});

  factory ListRoomsData.fromJson(Map<String, dynamic> json) {
    final rawRooms = json['rooms'];
    final rooms = rawRooms is List
        ? rawRooms.map((value) => value.toString()).toList()
        : const <String>[];
    return ListRoomsData(rooms: rooms);
  }

  final List<String> rooms;
}

class AckData {
  const AckData({required this.ok});

  factory AckData.fromJson(Map<String, dynamic> json) {
    return AckData(ok: json['ok'] as bool? ?? false);
  }

  final bool ok;
}

class OpenRoomData {
  const OpenRoomData({required this.roomId, required this.initialized});

  factory OpenRoomData.fromJson(Map<String, dynamic> json) {
    return OpenRoomData(
      roomId: json['room_id'] as String? ?? '',
      initialized: json['initialized'] as bool? ?? false,
    );
  }

  final String roomId;
  final bool initialized;
}

class LoadBackwardData {
  const LoadBackwardData({required this.reachedStart, required this.events});

  factory LoadBackwardData.fromJson(Map<String, dynamic> json) {
    final rawEvents = json['events'];
    final events = rawEvents is List
        ? rawEvents.map((value) => value as String).toList()
        : const <String>[];
    return LoadBackwardData(
      reachedStart: json['reached_start'] as bool? ?? false,
      events: events,
    );
  }

  final bool reachedStart;
  final List<String> events;
}

class RoomOverviewData {
  const RoomOverviewData({
    required this.roomId,
    required this.name,
    required this.avatarUrl,
    required this.bumpTs,
    required this.notificationCount,
    required this.highlightCount,
    required this.isMarkedUnread,
  });

  factory RoomOverviewData.fromJson(Map<String, dynamic> json) {
    return RoomOverviewData(
      roomId: json['room_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
      bumpTs: (json['bump_ts'] as num?)?.toInt(),
      notificationCount: (json['notification_count'] as num?)?.toInt() ?? 0,
      highlightCount: (json['highlight_count'] as num?)?.toInt() ?? 0,
      isMarkedUnread: json['is_marked_unread'] == true,
    );
  }

  final String roomId;
  final String name;
  final String? avatarUrl;
  final int? bumpTs;
  final int notificationCount;
  final int highlightCount;
  final bool isMarkedUnread;
}

class _RustBindings {
  _RustBindings(ffi.DynamicLibrary library)
      : _library = library,
        _ping =
            library.lookupFunction<_NativePing, _DartPing>('messie_ffi_ping'),
        _initClient =
            library.lookupFunction<_NativeInitClient, _DartInitClient>(
                'messie_ffi_init_client'),
        _restoreOrLogin =
            library.lookupFunction<_NativeRestoreOrLogin, _DartRestoreOrLogin>(
                'messie_ffi_restore_or_login'),
        _logout = library
            .lookupFunction<_NativeLogout, _DartLogout>('messie_ffi_logout'),
        _recoverWithKey =
            library.lookupFunction<_NativeRecoverWithKey, _DartRecoverWithKey>(
                'messie_ffi_recover_with_key'),
        _downloadRoomKeys = library.lookupFunction<_NativeDownloadRoomKeys,
            _DartDownloadRoomKeys>('messie_ffi_download_room_keys_for_room'),
        _dumpRoomCrypto =
            library.lookupFunction<_NativeDumpRoomCrypto, _DartDumpRoomCrypto>(
                'messie_ffi_dump_room_crypto'),
        _startSlidingSync = library.lookupFunction<_NativeStartSlidingSync,
            _DartStartSlidingSync>('messie_ffi_start_sliding_sync'),
        _roomListStream =
            library.lookupFunction<_NativeRoomListStream, _DartRoomListStream>(
                'messie_ffi_room_list_stream'),
        _listJoinedRooms = library.lookupFunction<_NativeListJoinedRooms,
            _DartListJoinedRooms>('messie_ffi_list_joined_rooms'),
        _roomOverview =
            library.lookupFunction<_NativeRoomOverview, _DartRoomOverview>(
                'messie_ffi_room_overview'),
        _openRoom = library.lookupFunction<_NativeOpenRoom, _DartOpenRoom>(
            'messie_ffi_open_room'),
        _timelineStream =
            library.lookupFunction<_NativeTimelineStream, _DartTimelineStream>(
                'messie_ffi_timeline_stream'),
        _loadBackward =
            library.lookupFunction<_NativeLoadBackward, _DartLoadBackward>(
                'messie_ffi_load_backward'),
        _freeString =
            library.lookupFunction<_NativeFreeString, _DartFreeString>(
                'messie_ffi_free_string');

  final ffi.DynamicLibrary _library;
  final _DartPing _ping;
  final _DartInitClient _initClient;
  final _DartRestoreOrLogin _restoreOrLogin;
  final _DartLogout _logout;
  final _DartRecoverWithKey _recoverWithKey;
  final _DartDownloadRoomKeys _downloadRoomKeys;
  final _DartDumpRoomCrypto _dumpRoomCrypto;
  _DartBackupStatus? _backupStatusOpt;
  _DartImportRecoveryKey? _importRecoveryKeyOpt;
  _DartBackupStatusStream? _backupStatusStreamOpt;
  _DartEnableOnlineBackup? _enableOnlineBackupOpt;
  _DartExportRecoveryKey? _exportRecoveryKeyOpt;
  _DartSsssImportRecoveryKey? _ssssImportRecoveryKeyOpt;
  _DartSsssBootstrap? _ssssBootstrapOpt;
  _DartSsssExportRecoveryKey? _ssssExportRecoveryKeyOpt;
  _DartRequestSasVerification? _requestSasOpt;
  _DartObserveSas? _observeSasOpt;
  _DartConfirmSas? _confirmSasOpt;
  _DartCancelSas? _cancelSasOpt;
  _DartTrustState? _trustStateOpt;
  final _DartStartSlidingSync _startSlidingSync;
  final _DartRoomListStream _roomListStream;
  final _DartListJoinedRooms _listJoinedRooms;
  final _DartRoomOverview _roomOverview;
  final _DartOpenRoom _openRoom;
  final _DartTimelineStream _timelineStream;
  final _DartLoadBackward _loadBackward;
  final _DartFreeString _freeString;

  String ping() => _stringFromPointer(_ping());

  RustResult<InitClientData> initClient(String homeserverUrl, String basePath) {
    final hsPtr = homeserverUrl.toNativeUtf8();
    final basePtr = basePath.toNativeUtf8();
    try {
      final result = _stringFromPointer(_initClient(hsPtr, basePtr));
      return _parse(result,
          (json) => InitClientData.fromJson(json as Map<String, dynamic>));
    } finally {
      calloc.free(hsPtr);
      calloc.free(basePtr);
    }
  }

  RustResult<LoginData> restoreOrLogin(
    String homeserverUrl,
    String username,
    String password,
    String basePath,
  ) {
    final hsPtr = homeserverUrl.toNativeUtf8();
    final userPtr = username.toNativeUtf8();
    final passPtr = password.toNativeUtf8();
    final basePtr = basePath.toNativeUtf8();
    try {
      final result =
          _stringFromPointer(_restoreOrLogin(hsPtr, userPtr, passPtr, basePtr));
      return _parse(
          result, (json) => LoginData.fromJson(json as Map<String, dynamic>));
    } finally {
      calloc.free(hsPtr);
      calloc.free(userPtr);
      calloc.free(passPtr);
      calloc.free(basePtr);
    }
  }

  RustResult<Unit> logout(String basePath) {
    final basePtr = basePath.toNativeUtf8();
    try {
      final result = _stringFromPointer(_logout(basePtr));
      return _parse(result, (_) => Unit.instance);
    } finally {
      calloc.free(basePtr);
    }
  }

  RustResult<Unit> recoverWithKey(String recoveryKey) {
    final keyPtr = recoveryKey.toNativeUtf8();
    try {
      final result = _stringFromPointer(_recoverWithKey(keyPtr));
      return _parse(result, (_) => Unit.instance);
    } finally {
      calloc.free(keyPtr);
    }
  }

  RustResult<Unit> importRecoveryKey(String recoveryKey) {
    try {
      _importRecoveryKeyOpt ??= _library.lookupFunction<_NativeImportRecoveryKey, _DartImportRecoveryKey>(
          'messie_ffi_import_recovery_key');
    } catch (e) {
      return const RustResult(ok: false, data: null, error: 'import_recovery_key not available in FFI');
    }
    final keyPtr = recoveryKey.toNativeUtf8();
    try {
      final result = _stringFromPointer(_importRecoveryKeyOpt!(keyPtr));
      return _parse(result, (_) => Unit.instance);
    } finally {
      calloc.free(keyPtr);
    }
  }

  RustResult<Unit> downloadRoomKeysForRoom(String roomId) {
    final roomPtr = roomId.toNativeUtf8();
    try {
      final result = _stringFromPointer(_downloadRoomKeys(roomPtr));
      return _parse(result, (_) => Unit.instance);
    } finally {
      calloc.free(roomPtr);
    }
  }

  RustResult<Unit> dumpRoomCrypto(String roomId) {
    final roomPtr = roomId.toNativeUtf8();
    try {
      final result = _stringFromPointer(_dumpRoomCrypto(roomPtr));
      return _parse(result, (_) => Unit.instance);
    } finally {
      calloc.free(roomPtr);
    }
  }

  RustResult<BackupStatusData> backupStatus() {
    try {
      _backupStatusOpt ??= _library.lookupFunction<_NativeBackupStatus, _DartBackupStatus>(
          'messie_ffi_backup_status');
    } catch (e) {
      return const RustResult(ok: false, data: null, error: 'backup_status not available in FFI');
    }
    final result = _stringFromPointer(_backupStatusOpt!());
    return _parse(
        result, (json) => BackupStatusData.fromJson(json as Map<String, dynamic>));
  }

  RustResult<AckData> backupStatusStream(String handle, int nativePort) {
    try {
      _backupStatusStreamOpt ??= _library.lookupFunction<_NativeBackupStatusStream, _DartBackupStatusStream>(
          'messie_ffi_backup_status_stream');
    } catch (e) {
      return const RustResult(ok: false, data: null, error: 'backup_status_stream not available in FFI');
    }
    final handlePtr = handle.toNativeUtf8();
    try {
      final result = _stringFromPointer(_backupStatusStreamOpt!(handlePtr, nativePort));
      return _parse(result, (json) => AckData.fromJson(json as Map<String, dynamic>));
    } finally {
      calloc.free(handlePtr);
    }
  }

  RustResult<EnableBackupData> enableOnlineBackup(bool generateNew) {
    try {
      _enableOnlineBackupOpt ??= _library.lookupFunction<_NativeEnableOnlineBackup, _DartEnableOnlineBackup>(
          'messie_ffi_enable_online_backup');
    } catch (e) {
      return const RustResult(ok: false, data: null, error: 'enable_online_backup not available in FFI');
    }
    final flag = generateNew ? 1 : 0;
    final result = _stringFromPointer(_enableOnlineBackupOpt!(flag));
    return _parse(result, (json) => EnableBackupData.fromJson(json as Map<String, dynamic>));
  }

  RustResult<ExportRecoveryKeyData> exportRecoveryKey() {
    try {
      _exportRecoveryKeyOpt ??= _library.lookupFunction<_NativeExportRecoveryKey, _DartExportRecoveryKey>(
          'messie_ffi_export_recovery_key');
    } catch (e) {
      return const RustResult(ok: false, data: null, error: 'export_recovery_key not available in FFI');
    }
    final result = _stringFromPointer(_exportRecoveryKeyOpt!());
    return _parse(result, (json) => ExportRecoveryKeyData.fromJson(json as Map<String, dynamic>));
  }

  RustResult<Unit> ssssImportRecoveryKey(String recoveryKeyBech32) {
    try {
      _ssssImportRecoveryKeyOpt ??= _library.lookupFunction<_NativeSsssImportRecoveryKey, _DartSsssImportRecoveryKey>(
          'messie_ffi_ssss_import_recovery_key');
    } catch (e) {
      return const RustResult(ok: false, data: null, error: 'ssss_import_recovery_key not available in FFI');
    }
    final keyPtr = recoveryKeyBech32.toNativeUtf8();
    try {
      final result = _stringFromPointer(_ssssImportRecoveryKeyOpt!(keyPtr));
      return _parse(result, (_) => Unit.instance);
    } finally {
      calloc.free(keyPtr);
    }
  }

  RustResult<SsssBootstrapData> ssssBootstrap(bool generateNewKey, String? passphrase) {
    try {
      _ssssBootstrapOpt ??= _library.lookupFunction<_NativeSsssBootstrap, _DartSsssBootstrap>(
          'messie_ffi_ssss_bootstrap');
    } catch (e) {
      return const RustResult(ok: false, data: null, error: 'ssss_bootstrap not available in FFI');
    }
    final passPtr = (passphrase ?? '').toNativeUtf8();
    try {
      final flag = generateNewKey ? 1 : 0;
      final result = _stringFromPointer(_ssssBootstrapOpt!(flag, passPtr));
      return _parse(result, (json) => SsssBootstrapData.fromJson(json as Map<String, dynamic>));
    } finally {
      calloc.free(passPtr);
    }
  }

  RustResult<ExportRecoveryKeyData> ssssExportRecoveryKey() {
    try {
      _ssssExportRecoveryKeyOpt ??= _library.lookupFunction<_NativeSsssExportRecoveryKey, _DartSsssExportRecoveryKey>(
          'messie_ffi_ssss_export_recovery_key');
    } catch (e) {
      return const RustResult(ok: false, data: null, error: 'ssss_export_recovery_key not available in FFI');
    }
    final result = _stringFromPointer(_ssssExportRecoveryKeyOpt!());
    return _parse(result, (json) => ExportRecoveryKeyData.fromJson(json as Map<String, dynamic>));
  }

  RustResult<StartSasData> requestSasVerification(String userId, {String? deviceId}) {
    try {
      _requestSasOpt ??= _library.lookupFunction<_NativeRequestSasVerification, _DartRequestSasVerification>(
          'messie_ffi_request_sas_verification');
    } catch (e) {
      return const RustResult(ok: false, data: null, error: 'request_sas_verification not available in FFI');
    }
    final userPtr = userId.toNativeUtf8();
    final devicePtr = (deviceId ?? '').toNativeUtf8();
    try {
      final result = _stringFromPointer(_requestSasOpt!(userPtr, devicePtr));
      return _parse(result, (json) => StartSasData.fromJson(json as Map<String, dynamic>));
    } finally {
      calloc.free(userPtr);
      calloc.free(devicePtr);
    }
  }

  RustResult<AckData> observeSas(String flowId, int nativePort) {
    try {
      _observeSasOpt ??= _library.lookupFunction<_NativeObserveSas, _DartObserveSas>(
          'messie_ffi_observe_sas');
    } catch (e) {
      return const RustResult(ok: false, data: null, error: 'observe_sas not available in FFI');
    }
    final flowPtr = flowId.toNativeUtf8();
    try {
      final result = _stringFromPointer(_observeSasOpt!(flowPtr, nativePort));
      return _parse(result, (json) => AckData.fromJson(json as Map<String, dynamic>));
    } finally {
      calloc.free(flowPtr);
    }
  }

  RustResult<Unit> confirmSas(String flowId) {
    try {
      _confirmSasOpt ??= _library.lookupFunction<_NativeConfirmSas, _DartConfirmSas>(
          'messie_ffi_confirm_sas');
    } catch (e) {
      return const RustResult(ok: false, data: null, error: 'confirm_sas not available in FFI');
    }
    final flowPtr = flowId.toNativeUtf8();
    try {
      final result = _stringFromPointer(_confirmSasOpt!(flowPtr));
      return _parse(result, (_) => Unit.instance);
    } finally {
      calloc.free(flowPtr);
    }
  }

  RustResult<Unit> cancelSas(String flowId) {
    try {
      _cancelSasOpt ??= _library.lookupFunction<_NativeCancelSas, _DartCancelSas>(
          'messie_ffi_cancel_sas');
    } catch (e) {
      return const RustResult(ok: false, data: null, error: 'cancel_sas not available in FFI');
    }
    final flowPtr = flowId.toNativeUtf8();
    try {
      final result = _stringFromPointer(_cancelSasOpt!(flowPtr));
      return _parse(result, (_) => Unit.instance);
    } finally {
      calloc.free(flowPtr);
    }
  }

  

  RustResult<TrustStateData> trustState(String userId, {String? deviceId}) {
    try {
      _trustStateOpt ??= _library.lookupFunction<_NativeTrustState, _DartTrustState>(
          'messie_ffi_trust_state');
    } catch (e) {
      return const RustResult(ok: false, data: null, error: 'trust_state not available in FFI');
    }
    final userPtr = userId.toNativeUtf8();
    final devicePtr = (deviceId ?? '').toNativeUtf8();
    try {
      final result = _stringFromPointer(_trustStateOpt!(userPtr, devicePtr));
      return _parse(result, (json) => TrustStateData.fromJson(json as Map<String, dynamic>));
    } finally {
      calloc.free(userPtr);
      calloc.free(devicePtr);
    }
  }

  RustResult<StartSlidingSyncData> startSlidingSync(
    String handle,
    int hpSize,
    int lpBatch,
    int hpTimeline,
    int lpTimeline,
  ) {
    final handlePtr = handle.toNativeUtf8();
    try {
      final result = _stringFromPointer(
        _startSlidingSync(handlePtr, hpSize, lpBatch, hpTimeline, lpTimeline),
      );
      return _parse(
          result,
          (json) =>
              StartSlidingSyncData.fromJson(json as Map<String, dynamic>));
    } finally {
      calloc.free(handlePtr);
    }
  }

  RustResult<AckData> roomListStream(String handle, int nativePort) {
    final handlePtr = handle.toNativeUtf8();
    try {
      final result = _stringFromPointer(_roomListStream(handlePtr, nativePort));
      return _parse(
          result, (json) => AckData.fromJson(json as Map<String, dynamic>));
    } finally {
      calloc.free(handlePtr);
    }
  }

  RustResult<ListRoomsData> listJoinedRooms() {
    final result = _stringFromPointer(_listJoinedRooms());
    return _parse(
        result, (json) => ListRoomsData.fromJson(json as Map<String, dynamic>));
  }

  RustResult<RoomOverviewData> roomOverview(String roomId) {
    final roomPtr = roomId.toNativeUtf8();
    try {
      final result = _stringFromPointer(_roomOverview(roomPtr));
      return _parse(result,
          (json) => RoomOverviewData.fromJson(json as Map<String, dynamic>));
    } finally {
      calloc.free(roomPtr);
    }
  }

  RustResult<OpenRoomData> openRoom(String handle, String roomId) {
    final handlePtr = handle.toNativeUtf8();
    final roomPtr = roomId.toNativeUtf8();
    try {
      final result = _stringFromPointer(_openRoom(handlePtr, roomPtr));
      return _parse(result,
          (json) => OpenRoomData.fromJson(json as Map<String, dynamic>));
    } finally {
      calloc.free(handlePtr);
      calloc.free(roomPtr);
    }
  }

  RustResult<AckData> timelineStream(
    String handle,
    String roomId,
    int nativePort,
  ) {
    final handlePtr = handle.toNativeUtf8();
    final roomPtr = roomId.toNativeUtf8();
    try {
      final result = _stringFromPointer(
        _timelineStream(handlePtr, roomPtr, nativePort),
      );
      return _parse(
          result, (json) => AckData.fromJson(json as Map<String, dynamic>));
    } finally {
      calloc.free(handlePtr);
      calloc.free(roomPtr);
    }
  }

  RustResult<LoadBackwardData> loadBackward(
    String handle,
    String roomId,
    int limit,
  ) {
    final handlePtr = handle.toNativeUtf8();
    final roomPtr = roomId.toNativeUtf8();
    try {
      final result =
          _stringFromPointer(_loadBackward(handlePtr, roomPtr, limit));
      return _parse(result,
          (json) => LoadBackwardData.fromJson(json as Map<String, dynamic>));
    } finally {
      calloc.free(handlePtr);
      calloc.free(roomPtr);
    }
  }

  String _stringFromPointer(_PointerUtf8 pointer) {
    if (pointer == ffi.nullptr) return '';
    final value = pointer.toDartString(); // from package:ffi
    _freeString(pointer); // must match Rust allocator
    return value;
  }

  RustResult<T> _parse<T>(String source, T? Function(Object? json) parser) {
    final decoded = jsonDecode(source) as Map<String, dynamic>;
    final ok = decoded['ok'] == true;
    final error = decoded['error'] as String?;
    final rawData = decoded['data'];
    final data = ok ? parser(rawData) : null;
    return RustResult(ok: ok, data: data, error: error);
  }
}

class _LibraryConfig {
  const _LibraryConfig({required this.useProcess, this.libraryPath});

  final bool useProcess;
  final String? libraryPath;

  static _LibraryConfig detect() {
    final override = Platform.environment['MESSIE_FFI_LIB_PATH'];
    if (override != null && override.isNotEmpty) {
      return _LibraryConfig(useProcess: false, libraryPath: override);
    }

    const base = 'messie_ffi';
    if (Platform.isIOS || Platform.isMacOS) {
      return const _LibraryConfig(useProcess: true);
    }
    if (Platform.isAndroid || Platform.isLinux) {
      return const _LibraryConfig(
          useProcess: false, libraryPath: 'lib$base.so');
    }
    if (Platform.isWindows) {
      return const _LibraryConfig(useProcess: false, libraryPath: '$base.dll');
    }
    return const _LibraryConfig(
        useProcess: false, libraryPath: 'lib$base.dylib');
  }

  ffi.DynamicLibrary open() {
    if (useProcess) {
      return ffi.DynamicLibrary.process();
    }
    final path = libraryPath;
    if (path == null) {
      throw StateError('FFI library path missing');
    }
    return ffi.DynamicLibrary.open(path);
  }
}

class _InitArgs {
  const _InitArgs(this.config, this.homeserverUrl, this.basePath);

  final _LibraryConfig config;
  final String homeserverUrl;
  final String basePath;
}

class _RestoreArgs {
  const _RestoreArgs(this.config, this.homeserverUrl, this.username,
      this.password, this.basePath);

  final _LibraryConfig config;
  final String homeserverUrl;
  final String username;
  final String password;
  final String basePath;
}

class _LogoutArgs {
  const _LogoutArgs(this.config, this.basePath);

  final _LibraryConfig config;
  final String basePath;
}

class _RecoverArgs {
  const _RecoverArgs(this.config, this.recoveryKey);

  final _LibraryConfig config;
  final String recoveryKey;
}

class _DownloadRoomKeysArgs {
  const _DownloadRoomKeysArgs(this.config, this.roomId);

  final _LibraryConfig config;
  final String roomId;
}

class _DumpRoomCryptoArgs {
  const _DumpRoomCryptoArgs(this.config, this.roomId);

  final _LibraryConfig config;
  final String roomId;
}

class _RequestSasArgs {
  const _RequestSasArgs(this.config, this.userId, this.deviceId);

  final _LibraryConfig config;
  final String userId;
  final String deviceId;
}

class _ObserveSasArgs {
  const _ObserveSasArgs(this.config, this.flowId, this.nativePort);

  final _LibraryConfig config;
  final String flowId;
  final int nativePort;
}

class _FlowIdArgs {
  const _FlowIdArgs(this.config, this.flowId);

  final _LibraryConfig config;
  final String flowId;
}

class _TrustStateArgs {
  const _TrustStateArgs(this.config, this.userId, this.deviceId);

  final _LibraryConfig config;
  final String userId;
  final String deviceId;
}

class _StartSyncArgs {
  const _StartSyncArgs(
    this.config,
    this.handle,
    this.hpSize,
    this.lpBatch,
    this.hpTimeline,
    this.lpTimeline,
  );

  final _LibraryConfig config;
  final String handle;
  final int hpSize;
  final int lpBatch;
  final int hpTimeline;
  final int lpTimeline;
}

class _RoomListStreamArgs {
  const _RoomListStreamArgs(this.config, this.handle, this.nativePort);

  final _LibraryConfig config;
  final String handle;
  final int nativePort;
}

class _RoomHandleArgs {
  const _RoomHandleArgs(this.config, this.handle, this.roomId);

  final _LibraryConfig config;
  final String handle;
  final String roomId;
}

class _RoomOverviewArgs {
  const _RoomOverviewArgs(this.config, this.roomId);

  final _LibraryConfig config;
  final String roomId;
}

class _TimelineStreamArgs {
  const _TimelineStreamArgs(
      this.config, this.handle, this.roomId, this.nativePort);

  final _LibraryConfig config;
  final String handle;
  final String roomId;
  final int nativePort;
}

class _LoadBackwardArgs {
  const _LoadBackwardArgs(this.config, this.handle, this.roomId, this.limit);

  final _LibraryConfig config;
  final String handle;
  final String roomId;
  final int limit;
}

class Unit {
  const Unit._();

  static const instance = Unit._();
}
