import 'dart:ffi' as ffi;
import 'dart:isolate';
import 'dart:io';
import 'package:ffi/ffi.dart';

typedef _PointerUtf8 = ffi.Pointer<Utf8>;

typedef _NativePostCObjectFn = ffi.NativeFunction<ffi.Int8 Function(ffi.Int64, ffi.Pointer<ffi.Void>)>;
typedef _NativeStoreDartPostCObject = ffi.Void Function(ffi.Pointer<_NativePostCObjectFn>);
typedef _DartStoreDartPostCObject = void Function(ffi.Pointer<_NativePostCObjectFn>);

typedef _NativeFreeString = ffi.Void Function(_PointerUtf8);
typedef _DartFreeString = void Function(_PointerUtf8);

typedef _NativeClientSyncOnce = ffi.Uint8 Function(ffi.Uint64);
typedef _DartClientSyncOnce = int Function(int);

ffi.DynamicLibrary? _lib;
bool _postCObjectRegistered = false;

ffi.DynamicLibrary _open() {
  if (_lib != null) return _lib!;
  final override = Platform.environment['MESSIE_FFI_LIB_V2_PATH'];
  if (override != null && override.isNotEmpty) {
    return _lib = ffi.DynamicLibrary.open(override);
  }
  const base = 'messie_ffi_v2';
  if (Platform.isIOS || Platform.isMacOS) {
    return _lib = ffi.DynamicLibrary.process();
  } else if (Platform.isAndroid || Platform.isLinux) {
    return _lib = ffi.DynamicLibrary.open('lib$base.so');
  } else if (Platform.isWindows) {
    return _lib = ffi.DynamicLibrary.open('$base.dll');
  } else {
    return _lib = ffi.DynamicLibrary.open('lib$base.dylib');
  }
}

void _ensurePostCObjectRegistered() {
  if (_postCObjectRegistered) return;
  final lib = _open();
  final store = lib.lookupFunction<_NativeStoreDartPostCObject, _DartStoreDartPostCObject>('messie_v2_store_dart_post_cobject');
  store(ffi.NativeApi.postCObject.cast<_NativePostCObjectFn>());
  _postCObjectRegistered = true;
}

String _fromPtr(ffi.Pointer<Utf8> ptr) {
  try {
    final str = ptr.toDartString();
    return str;
  } finally {
    final free = _open().lookupFunction<_NativeFreeString, _DartFreeString>('messie_v2_free_string');
    free(ptr);
  }
}

bool clientSyncOnce({required int handle}) {
  _ensurePostCObjectRegistered();
  final lib = _open();
  final fn = lib.lookupFunction<_NativeClientSyncOnce, _DartClientSyncOnce>('messie_v2_client_sync_once');
  final ok = fn(handle);
  return ok != 0;
}

// ---- Sliding Sync (v2 thin) ----

final class MessieV2SlidingSyncConfig extends ffi.Struct {
  @ffi.Uint32()
  external int pollTimeoutMs;

  @ffi.Uint32()
  external int networkTimeoutMs;

  @ffi.Bool()
  external bool enableE2ee;

  @ffi.Bool()
  external bool enableToDevice;
}

final class MessieV2SlidingSyncHandle extends ffi.Struct {
  @ffi.Uint64()
  external int value;
}

final class MessieV2SlidingSyncResult extends ffi.Struct {
  @ffi.Int32()
  external int error;

  external MessieV2SlidingSyncHandle handle;
}


typedef _NativeSsCreate = MessieV2SlidingSyncResult Function(
    ffi.Uint64, MessieV2SlidingSyncConfig);
typedef _DartSsCreate = MessieV2SlidingSyncResult Function(
    int, MessieV2SlidingSyncConfig);

typedef _NativeSsStart = ffi.Uint8 Function(
    MessieV2SlidingSyncHandle, ffi.Int64);
typedef _DartSsStart = int Function(
    MessieV2SlidingSyncHandle, int);

typedef _NativeSsStop = ffi.Uint8 Function(MessieV2SlidingSyncHandle);
typedef _DartSsStop = int Function(MessieV2SlidingSyncHandle);

//

int ssCreate({
  required int clientHandle,
  int pollTimeoutMs = 0,
  int networkTimeoutMs = 0,
  bool enableE2ee = true,
  bool enableToDevice = true,
}) {
  _ensurePostCObjectRegistered();
  final lib = _open();
  final create = lib.lookupFunction<_NativeSsCreate, _DartSsCreate>(
      'messie_v2_sliding_sync_create');
  final cfg = calloc<MessieV2SlidingSyncConfig>();
  try {
    cfg.ref
      ..pollTimeoutMs = pollTimeoutMs
      ..networkTimeoutMs = networkTimeoutMs
      ..enableE2ee = enableE2ee
      ..enableToDevice = enableToDevice;
    final result = create(clientHandle, cfg.ref);
    if (result.error != 0) {
      throw Exception('sliding_sync_create failed (code=${result.error})');
    }
    return result.handle.value;
  } finally {
    calloc.free(cfg);
  }
}

bool ssStart({required int ssHandle, required int port}) {
  _ensurePostCObjectRegistered();
  final lib = _open();
  final start = lib.lookupFunction<_NativeSsStart, _DartSsStart>(
      'messie_v2_sliding_sync_start_streaming');
  final h = calloc<MessieV2SlidingSyncHandle>();
  try {
    h.ref.value = ssHandle;
    final ok = start(h.ref, port);
    return ok != 0;
  } finally {
    calloc.free(h);
  }
}

bool ssStop({required int ssHandle}) {
  _ensurePostCObjectRegistered();
  final lib = _open();
  final stop = lib.lookupFunction<_NativeSsStop, _DartSsStop>(
      'messie_v2_sliding_sync_stop');
  final h = calloc<MessieV2SlidingSyncHandle>();
  try {
    h.ref.value = ssHandle;
    final ok = stop(h.ref);
    return ok != 0;
  } finally {
    calloc.free(h);
  }
}

//

// Removed JSON subscribe/expire in favor of thin API

// Thin subscribe/expire (no JSON)

final class MessieV2StrPair extends ffi.Struct {
  external ffi.Pointer<Utf8> key1;
  external ffi.Pointer<Utf8> key2;
}

typedef _NativeSsSubscribe = ffi.Uint8 Function(
  ffi.Uint64,
  ffi.Pointer<ffi.Pointer<Utf8>>, // room_ids
  ffi.IntPtr,
  ffi.Uint8, // has_timeline
  ffi.Uint32, // timeline_limit
  ffi.Pointer<MessieV2StrPair>, // pairs
  ffi.IntPtr,
  ffi.Uint8,
);
typedef _DartSsSubscribe = int Function(
  int,
  ffi.Pointer<ffi.Pointer<Utf8>>,
  int,
  int,
  int,
  ffi.Pointer<MessieV2StrPair>,
  int,
  int,
);

typedef _NativeSsExpire = ffi.Uint8 Function(ffi.Uint64);
typedef _DartSsExpire = int Function(int);

bool ssSubscribeToRooms({
  required int ssHandle,
  required List<String> roomIds,
  int? timelineLimit,
  List<(String, String)>? requiredState,
  required bool cancelInFlight,
}) {
  _ensurePostCObjectRegistered();
  final lib = _open();
  final fn = lib.lookupFunction<_NativeSsSubscribe, _DartSsSubscribe>(
      'messie_v2_sliding_sync_subscribe_to_rooms');

  // Prepare room ids array
  final idsPtrs = calloc<ffi.Pointer<Utf8>>(roomIds.length);
  for (var i = 0; i < roomIds.length; i++) {
    idsPtrs[i] = roomIds[i].toNativeUtf8();
  }

  // Prepare pairs array if provided
  ffi.Pointer<MessieV2StrPair> pairsPtr = ffi.nullptr;
  var pairsLen = 0;
  final pairs = requiredState;
  if (pairs != null && pairs.isNotEmpty) {
    pairsLen = pairs.length;
    pairsPtr = calloc<MessieV2StrPair>(pairsLen);
    for (var i = 0; i < pairsLen; i++) {
      final (et, sk) = pairs[i];
      pairsPtr[i].key1 = et.toNativeUtf8();
      pairsPtr[i].key2 = sk.toNativeUtf8();
    }
  }

  try {
    final ok = fn(
      ssHandle,
      idsPtrs,
      roomIds.length,
      timelineLimit != null ? 1 : 0,
      timelineLimit ?? 0,
      pairsPtr,
      pairsLen,
      cancelInFlight ? 1 : 0,
    );
    return ok != 0;
  } finally {
    // Free allocated strings
    for (var i = 0; i < roomIds.length; i++) {
      calloc.free(idsPtrs[i]);
    }
    calloc.free(idsPtrs);
    if (pairs != null && pairs.isNotEmpty) {
      for (var i = 0; i < pairsLen; i++) {
        calloc.free(pairsPtr[i].key1);
        calloc.free(pairsPtr[i].key2);
      }
      calloc.free(pairsPtr);
    }
  }
}

bool ssExpireSession({required int ssHandle}) {
  _ensurePostCObjectRegistered();
  final lib = _open();
  final fn = lib.lookupFunction<_NativeSsExpire, _DartSsExpire>(
      'messie_v2_sliding_sync_expire_session');
  final ok = fn(ssHandle);
  return ok != 0;
}

// ---- Rooms / Summaries (v2 thin) ----

final class MessieV2StrList extends ffi.Struct {
  external ffi.Pointer<ffi.Pointer<Utf8>> ptr;
  @ffi.IntPtr()
  external int len;
}

typedef _NativeClientListJoinedRooms = MessieV2StrList Function(ffi.Uint64);
typedef _DartClientListJoinedRooms = MessieV2StrList Function(int);
typedef _NativeFreeStrList = ffi.Void Function(MessieV2StrList);
typedef _DartFreeStrList = void Function(MessieV2StrList);

List<String> clientListJoinedRooms({required int clientHandle}) {
  _ensurePostCObjectRegistered();
  final lib = _open();
  final fn = lib.lookupFunction<_NativeClientListJoinedRooms, _DartClientListJoinedRooms>('messie_v2_client_list_joined_rooms');
  final freeList = lib.lookupFunction<_NativeFreeStrList, _DartFreeStrList>('messie_v2_free_str_list');
  final list = fn(clientHandle);
  try {
    final out = <String>[];
    final ptrs = list.ptr;
    for (var i = 0; i < list.len; i++) {
      final s = ptrs.elementAt(i).value;
      out.add(s.toDartString());
    }
    return out;
  } finally {
    freeList(list);
  }
}

// ---- Thin Client + Room Summary ----

final class MessieV2ClientCreateResult extends ffi.Struct {
  @ffi.Int32()
  external int error;
  @ffi.Uint64()
  external int handle;
}

final class MessieV2LoginResult extends ffi.Struct {
  @ffi.Int32()
  external int error;
  external ffi.Pointer<Utf8> user_id; // nullable when error!=0
}

typedef _NativeClientCreate = MessieV2ClientCreateResult Function(_PointerUtf8, _PointerUtf8);
typedef _DartClientCreate = MessieV2ClientCreateResult Function(_PointerUtf8, _PointerUtf8);

typedef _NativeClientLogin = MessieV2LoginResult Function(ffi.Uint64, _PointerUtf8, _PointerUtf8);
typedef _DartClientLogin = MessieV2LoginResult Function(int, _PointerUtf8, _PointerUtf8);

({bool success, int handle}) clientCreate({required String homeserverUrl, required String basePath}) {
  _ensurePostCObjectRegistered();
  final lib = _open();
  final fn = lib.lookupFunction<_NativeClientCreate, _DartClientCreate>('messie_v2_client_create');
  final hs = homeserverUrl.toNativeUtf8();
  final bp = basePath.toNativeUtf8();
  try {
    final res = fn(hs, bp);
    return (success: res.error == 0, handle: res.handle);
  } finally {
    calloc.free(hs);
    calloc.free(bp);
  }
}

({bool success, String? userId}) clientLogin({required int handle, String? username, String? password}) {
  _ensurePostCObjectRegistered();
  final lib = _open();
  final fn = lib.lookupFunction<_NativeClientLogin, _DartClientLogin>('messie_v2_client_login');
  final un = (username ?? '').toNativeUtf8();
  final pw = (password ?? '').toNativeUtf8();
  try {
    final res = fn(handle, username == null ? ffi.nullptr : un, password == null ? ffi.nullptr : pw);
    String? uid;
    if (res.error == 0 && res.user_id != ffi.nullptr) {
      uid = res.user_id.toDartString();
      // Free the string we consumed
      final free = _open().lookupFunction<_NativeFreeString, _DartFreeString>('messie_v2_free_string');
      free(res.user_id);
    }
    return (success: res.error == 0, userId: uid);
  } finally {
    calloc.free(un);
    calloc.free(pw);
  }
}

// Error codes are part of base structs; no separate *_ex APIs

final class MessieV2RoomSummary extends ffi.Struct {
  @ffi.Bool()
  external bool success;
  external ffi.Pointer<Utf8> room_id;
  external ffi.Pointer<Utf8> name;
  external ffi.Pointer<Utf8> avatar_url; // nullable
  @ffi.Uint64()
  external int notification_count;
  @ffi.Uint64()
  external int highlight_count;
  @ffi.Bool()
  external bool is_marked_unread;
}

typedef _NativeRoomGetSummary = MessieV2RoomSummary Function(ffi.Uint64, _PointerUtf8);
typedef _DartRoomGetSummary = MessieV2RoomSummary Function(int, _PointerUtf8);

({bool success, String? roomId, String? name, String? avatarUrl, int notificationCount, int highlightCount, bool isMarkedUnread}) roomGetSummary({required int clientHandle, required String roomId}) {
  _ensurePostCObjectRegistered();
  final lib = _open();
  final fn = lib.lookupFunction<_NativeRoomGetSummary, _DartRoomGetSummary>('messie_v2_room_get_summary');
  final rid = roomId.toNativeUtf8();
  try {
    final res = fn(clientHandle, rid);
    if (!res.success) {
      return (success: false, roomId: null, name: null, avatarUrl: null, notificationCount: 0, highlightCount: 0, isMarkedUnread: false);
    }
    final free = _open().lookupFunction<_NativeFreeString, _DartFreeString>('messie_v2_free_string');
    String? gotRoomId;
    String? gotName;
    String? gotAvatar;
    if (res.room_id != ffi.nullptr) { gotRoomId = res.room_id.toDartString(); free(res.room_id); }
    if (res.name != ffi.nullptr) { gotName = res.name.toDartString(); free(res.name); }
    if (res.avatar_url != ffi.nullptr) { gotAvatar = res.avatar_url.toDartString(); free(res.avatar_url); }
    return (
      success: true,
      roomId: gotRoomId,
      name: gotName,
      avatarUrl: gotAvatar,
      notificationCount: res.notification_count,
      highlightCount: res.highlight_count,
      isMarkedUnread: res.is_marked_unread,
    );
  } finally {
    calloc.free(rid);
  }
}

// Removed JSON room summaries + overview in favor of roomGetSummary()

// ---- Timeline / Messaging (v2) ----

// (removed JSON timeline typedefs in favor of typed)

// (removed JSON room ops typedefs in favor of typed)

// Thin Timeline FFI
final class MessieV2TimelineHandle extends ffi.Struct {
  @ffi.Uint64()
  external int value;
}

final class MessieV2TimelineResult extends ffi.Struct {
  @ffi.Int32()
  external int error;
  external MessieV2TimelineHandle handle;
}

typedef _NativeTimelineOpen = MessieV2TimelineResult Function(ffi.Uint64, _PointerUtf8);
typedef _DartTimelineOpen = MessieV2TimelineResult Function(int, _PointerUtf8);

typedef _NativeTimelineStartStreaming = ffi.Uint8 Function(MessieV2TimelineHandle, ffi.Int64);
typedef _DartTimelineStartStreaming = int Function(MessieV2TimelineHandle, int);

typedef _NativeTimelineLoadBackward = ffi.Uint8 Function(MessieV2TimelineHandle, ffi.Uint32);
typedef _DartTimelineLoadBackward = int Function(MessieV2TimelineHandle, int);
// no *_ex timeline variants

// Thin Room Ops FFI
typedef _NativeRoomSendText = ffi.Uint8 Function(ffi.Uint64, _PointerUtf8, _PointerUtf8, _PointerUtf8);
typedef _DartRoomSendText = int Function(int, _PointerUtf8, _PointerUtf8, _PointerUtf8);

typedef _NativeRoomMarkReadUpTo = ffi.Uint8 Function(ffi.Uint64, _PointerUtf8, _PointerUtf8);
typedef _DartRoomMarkReadUpTo = int Function(int, _PointerUtf8, _PointerUtf8);
// no *_ex room ops

// Unread count FFI removed: Synapse sliding sync does not provide counts reliably.

// (removed JSON timeline helpers)

// Thin timeline convenience
({bool success, int handle}) timelineOpen({required int clientHandle, required String roomId}) {
  _ensurePostCObjectRegistered();
  final lib = _open();
  final fn = lib.lookupFunction<_NativeTimelineOpen, _DartTimelineOpen>('messie_v2_timeline_open');
  final rid = roomId.toNativeUtf8();
  try {
    final res = fn(clientHandle, rid);
    return (success: res.error == 0, handle: res.handle.value);
  } finally {
    calloc.free(rid);
  }
}

bool timelineStartStreaming({required int timelineHandle, required int port}) {
  _ensurePostCObjectRegistered();
  final lib = _open();
  final start = lib.lookupFunction<_NativeTimelineStartStreaming, _DartTimelineStartStreaming>('messie_v2_timeline_start_streaming');
  final h = calloc<MessieV2TimelineHandle>();
  try {
    h.ref.value = timelineHandle;
    final ok = start(h.ref, port);
    return ok != 0;
  } finally {
    calloc.free(h);
  }
}

bool timelineLoadBackward({required int timelineHandle, required int limit}) {
  _ensurePostCObjectRegistered();
  final lib = _open();
  final load = lib.lookupFunction<_NativeTimelineLoadBackward, _DartTimelineLoadBackward>('messie_v2_timeline_load_backward');
  final h = calloc<MessieV2TimelineHandle>();
  try {
    h.ref.value = timelineHandle;
    final ok = load(h.ref, limit);
    return ok != 0;
  } finally {
    calloc.free(h);
  }
}

//

// (removed JSON room send helper)

bool roomSendText({required int clientHandle, required String roomId, required String body, String? replyTo}) {
  _ensurePostCObjectRegistered();
  final lib = _open();
  final fn = lib.lookupFunction<_NativeRoomSendText, _DartRoomSendText>('messie_v2_room_send_text');
  final rid = roomId.toNativeUtf8();
  final b = body.toNativeUtf8();
  final r = (replyTo ?? '').toNativeUtf8();
  try {
    final ok = fn(clientHandle, rid, b, replyTo == null ? ffi.nullptr : r);
    return ok != 0;
  } finally {
    calloc.free(rid);
    calloc.free(b);
    calloc.free(r);
  }
}

// (removed JSON mark read helper)

bool roomMarkReadUpTo({required int clientHandle, required String roomId, required String eventId}) {
  _ensurePostCObjectRegistered();
  final lib = _open();
  final fn = lib.lookupFunction<_NativeRoomMarkReadUpTo, _DartRoomMarkReadUpTo>('messie_v2_room_mark_read_up_to');
  final rid = roomId.toNativeUtf8();
  final eid = eventId.toNativeUtf8();
  try {
    final ok = fn(clientHandle, rid, eid);
    return ok != 0;
  } finally {
    calloc.free(rid);
    calloc.free(eid);
  }
}

//

// Count getters/subscriptions intentionally removed.

// Test helpers
typedef _NativeRoomJoin = _PointerUtf8 Function(ffi.Uint64, _PointerUtf8);
typedef _DartRoomJoin = _PointerUtf8 Function(int, _PointerUtf8);

String roomJoin({required int handle, required String roomId}) {
  _ensurePostCObjectRegistered();
  final lib = _open();
  final fn = lib.lookupFunction<_NativeRoomJoin, _DartRoomJoin>('messie_v2_room_join');
  final rid = roomId.toNativeUtf8();
  try {
    final res = fn(handle, rid);
    return _fromPtr(res);
  } finally {
    calloc.free(rid);
  }
}

// Removed test-only helpers for unread count waiting

// (removed JSON room updates/counts helpers)

// ---- Backup / SSSS (v2) ----

final class MessieV2BackupStatus extends ffi.Struct {
  @ffi.Bool()
  external bool success;
  @ffi.Bool()
  external bool enabled;
  @ffi.Bool()
  external bool exists_on_server;
  @ffi.Bool()
  external bool needs_recovery;
  external ffi.Pointer<Utf8> recovery_state; // nullable when !success
}

typedef _NativeBackupStatus = MessieV2BackupStatus Function(ffi.Uint64);
typedef _DartBackupStatus = MessieV2BackupStatus Function(int);

typedef _NativeBackupStatusStream = ffi.Uint8 Function(ffi.Uint64, ffi.Int64);
typedef _DartBackupStatusStream = int Function(int, int);

typedef _NativeEnableOnlineBackup = _PointerUtf8 Function(ffi.Uint64, ffi.Uint8);
typedef _DartEnableOnlineBackup = _PointerUtf8 Function(int, int);

typedef _NativeSsssImportRecoveryKey = _PointerUtf8 Function(ffi.Uint64, _PointerUtf8);
typedef _DartSsssImportRecoveryKey = _PointerUtf8 Function(int, _PointerUtf8);

typedef _NativeSsssBootstrap = _PointerUtf8 Function(ffi.Uint64, ffi.Uint8, _PointerUtf8);
typedef _DartSsssBootstrap = _PointerUtf8 Function(int, int, _PointerUtf8);

typedef _NativeSsssExportRecoveryKey = _PointerUtf8 Function(ffi.Uint64);
typedef _DartSsssExportRecoveryKey = _PointerUtf8 Function(int);

({bool success, bool enabled, bool existsOnServer, bool needsRecovery, String? recoveryState}) backupStatus({required int handle}) {
  _ensurePostCObjectRegistered();
  final lib = _open();
  final fn = lib.lookupFunction<_NativeBackupStatus, _DartBackupStatus>('messie_v2_backup_status');
  final res = fn(handle);
  String? rs;
  if (res.success && res.recovery_state != ffi.nullptr) {
    rs = res.recovery_state.toDartString();
    final free = _open().lookupFunction<_NativeFreeString, _DartFreeString>('messie_v2_free_string');
    free(res.recovery_state);
  }
  return (success: res.success, enabled: res.enabled, existsOnServer: res.exists_on_server, needsRecovery: res.needs_recovery, recoveryState: rs);
}

bool backupStatusStream({required int handle, required int port}) {
  _ensurePostCObjectRegistered();
  final lib = _open();
  final fn = lib.lookupFunction<_NativeBackupStatusStream, _DartBackupStatusStream>('messie_v2_backup_status_stream');
  final ok = fn(handle, port);
  return ok != 0;
}

String enableOnlineBackup({required int handle, required bool generateNew}) {
  _ensurePostCObjectRegistered();
  final lib = _open();
  final fn = lib.lookupFunction<_NativeEnableOnlineBackup, _DartEnableOnlineBackup>('messie_v2_enable_online_backup');
  final res = fn(handle, generateNew ? 1 : 0);
  return _fromPtr(res);
}

String ssssImportRecoveryKey({required int handle, required String recoveryKey}) {
  _ensurePostCObjectRegistered();
  final lib = _open();
  final fn = lib.lookupFunction<_NativeSsssImportRecoveryKey, _DartSsssImportRecoveryKey>('messie_v2_ssss_import_recovery_key');
  final key = recoveryKey.toNativeUtf8();
  try {
    final res = fn(handle, key);
    return _fromPtr(res);
  } finally {
    calloc.free(key);
  }
}

String ssssBootstrap({required int handle, required bool generateNewKey, String? passphrase}) {
  _ensurePostCObjectRegistered();
  final lib = _open();
  final fn = lib.lookupFunction<_NativeSsssBootstrap, _DartSsssBootstrap>('messie_v2_ssss_bootstrap');
  final pp = (passphrase ?? '').toNativeUtf8();
  try {
    final res = fn(handle, generateNewKey ? 1 : 0, passphrase == null ? ffi.nullptr : pp);
    return _fromPtr(res);
  } finally {
    calloc.free(pp);
  }
}

String ssssExportRecoveryKey({required int handle}) {
  _ensurePostCObjectRegistered();
  final lib = _open();
  final fn = lib.lookupFunction<_NativeSsssExportRecoveryKey, _DartSsssExportRecoveryKey>('messie_v2_ssss_export_recovery_key');
  final res = fn(handle);
  return _fromPtr(res);
}

// ---- SAS Verification (v2) ----

typedef _NativeRequestSasVerification = _PointerUtf8 Function(ffi.Uint64, _PointerUtf8, _PointerUtf8);
typedef _DartRequestSasVerification = _PointerUtf8 Function(int, _PointerUtf8, _PointerUtf8);

typedef _NativeObserveSas = _PointerUtf8 Function(_PointerUtf8, ffi.Int64);
typedef _DartObserveSas = _PointerUtf8 Function(_PointerUtf8, int);

typedef _NativeConfirmSas = _PointerUtf8 Function(_PointerUtf8);
typedef _DartConfirmSas = _PointerUtf8 Function(_PointerUtf8);

typedef _NativeCancelSas = _PointerUtf8 Function(_PointerUtf8);
typedef _DartCancelSas = _PointerUtf8 Function(_PointerUtf8);
// Thin SAS
final class MessieV2SasHandle extends ffi.Struct {
  @ffi.Uint64()
  external int value;
}
final class MessieV2SasResult extends ffi.Struct {
  @ffi.Uint8()
  external int success;
  external MessieV2SasHandle handle;
}
typedef _NativeSasRequest = MessieV2SasResult Function(ffi.Uint64, _PointerUtf8, _PointerUtf8);
typedef _DartSasRequest = MessieV2SasResult Function(int, _PointerUtf8, _PointerUtf8);
typedef _NativeSasStartStreaming = ffi.Uint8 Function(MessieV2SasHandle, ffi.Int64);
typedef _DartSasStartStreaming = int Function(MessieV2SasHandle, int);
typedef _NativeSasConfirm = ffi.Uint8 Function(MessieV2SasHandle);
typedef _DartSasConfirm = int Function(MessieV2SasHandle);
typedef _NativeSasCancel = ffi.Uint8 Function(MessieV2SasHandle);
typedef _DartSasCancel = int Function(MessieV2SasHandle);
// Thin emoji/decimals
final class MessieV2SasEmoji extends ffi.Struct {
  @ffi.Uint8()
  external int count;
  external _PointerUtf8 item0;
  external _PointerUtf8 item1;
  external _PointerUtf8 item2;
  external _PointerUtf8 item3;
  external _PointerUtf8 item4;
  external _PointerUtf8 item5;
  external _PointerUtf8 item6;
}
final class MessieV2SasDecimals extends ffi.Struct {
  @ffi.Uint8()
  external int success;
  @ffi.Uint16()
  external int a;
  @ffi.Uint16()
  external int b;
  @ffi.Uint16()
  external int c;
}
typedef _NativeSasGetEmoji = MessieV2SasEmoji Function(MessieV2SasHandle);
typedef _DartSasGetEmoji = MessieV2SasEmoji Function(MessieV2SasHandle);
typedef _NativeSasGetDecimals = MessieV2SasDecimals Function(MessieV2SasHandle);
typedef _DartSasGetDecimals = MessieV2SasDecimals Function(MessieV2SasHandle);
typedef _NativeSasFreeHandle = ffi.Uint8 Function(MessieV2SasHandle);
typedef _DartSasFreeHandle = int Function(MessieV2SasHandle);

String requestSasVerification({required int handle, required String userId, String? deviceId}) {
  _ensurePostCObjectRegistered();
  final lib = _open();
  final fn = lib.lookupFunction<_NativeRequestSasVerification, _DartRequestSasVerification>('messie_v2_request_sas_verification');
  final uid = userId.toNativeUtf8();
  final did = (deviceId ?? '').toNativeUtf8();
  try {
    final res = fn(handle, uid, deviceId == null ? ffi.nullptr : did);
    return _fromPtr(res);
  } finally {
    calloc.free(uid);
    calloc.free(did);
  }
}

String observeSas({required String flowId, required int port}) {
  _ensurePostCObjectRegistered();
  final lib = _open();
  final fn = lib.lookupFunction<_NativeObserveSas, _DartObserveSas>('messie_v2_observe_sas');
  final fid = flowId.toNativeUtf8();
  try {
    final res = fn(fid, port);
    return _fromPtr(res);
  } finally {
    calloc.free(fid);
  }
}

String confirmSas({required String flowId}) {
  _ensurePostCObjectRegistered();
  final lib = _open();
  final fn = lib.lookupFunction<_NativeConfirmSas, _DartConfirmSas>('messie_v2_confirm_sas');
  final fid = flowId.toNativeUtf8();
  try {
    final res = fn(fid);
    return _fromPtr(res);
  } finally {
    calloc.free(fid);
  }
}

String cancelSas({required String flowId}) {
  _ensurePostCObjectRegistered();
  final lib = _open();
  final fn = lib.lookupFunction<_NativeCancelSas, _DartCancelSas>('messie_v2_cancel_sas');
  final fid = flowId.toNativeUtf8();
  try {
    final res = fn(fid);
    return _fromPtr(res);
  } finally {
    calloc.free(fid);
  }
}

// Thin SAS convenience
({bool success, int handle}) sasRequest({required int clientHandle, required String userId, String? deviceId}) {
  _ensurePostCObjectRegistered();
  final lib = _open();
  final fn = lib.lookupFunction<_NativeSasRequest, _DartSasRequest>('messie_v2_sas_request');
  final uid = userId.toNativeUtf8();
  final did = (deviceId ?? '').toNativeUtf8();
  try {
    final res = fn(clientHandle, uid, deviceId == null ? ffi.nullptr : did);
    return (success: res.success != 0, handle: res.handle.value);
  } finally {
    calloc.free(uid);
    calloc.free(did);
  }
}

bool sasStartStreaming({required int sasHandle, required int port}) {
  _ensurePostCObjectRegistered();
  final lib = _open();
  final start = lib.lookupFunction<_NativeSasStartStreaming, _DartSasStartStreaming>('messie_v2_sas_start_streaming');
  final h = calloc<MessieV2SasHandle>();
  try {
    h.ref.value = sasHandle;
    final ok = start(h.ref, port);
    return ok != 0;
  } finally {
    calloc.free(h);
  }
}

bool sasConfirm({required int sasHandle}) {
  _ensurePostCObjectRegistered();
  final lib = _open();
  final confirm = lib.lookupFunction<_NativeSasConfirm, _DartSasConfirm>('messie_v2_sas_confirm');
  final h = calloc<MessieV2SasHandle>();
  try {
    h.ref.value = sasHandle;
    final ok = confirm(h.ref);
    return ok != 0;
  } finally {
    calloc.free(h);
  }
}

bool sasCancel({required int sasHandle}) {
  _ensurePostCObjectRegistered();
  final lib = _open();
  final cancel = lib.lookupFunction<_NativeSasCancel, _DartSasCancel>('messie_v2_sas_cancel');
  final h = calloc<MessieV2SasHandle>();
  try {
    h.ref.value = sasHandle;
    final ok = cancel(h.ref);
    return ok != 0;
  } finally {
    calloc.free(h);
  }
}

List<String> sasGetEmoji({required int sasHandle}) {
  _ensurePostCObjectRegistered();
  final lib = _open();
  final getEmoji = lib.lookupFunction<_NativeSasGetEmoji, _DartSasGetEmoji>('messie_v2_sas_get_emoji');
  final h = calloc<MessieV2SasHandle>();
  try {
    h.ref.value = sasHandle;
    final res = getEmoji(h.ref);
    final out = <String>[];
    final items = [res.item0, res.item1, res.item2, res.item3, res.item4, res.item5, res.item6];
    for (var i = 0; i < res.count && i < items.length; i++) {
      final ptr = items[i];
      if (ptr.address != 0) {
        out.add(_fromPtr(ptr));
      }
    }
    return out;
  } finally {
    calloc.free(h);
  }
}

({bool success, int a, int b, int c}) sasGetDecimals({required int sasHandle}) {
  _ensurePostCObjectRegistered();
  final lib = _open();
  final getDec = lib.lookupFunction<_NativeSasGetDecimals, _DartSasGetDecimals>('messie_v2_sas_get_decimals');
  final h = calloc<MessieV2SasHandle>();
  try {
    h.ref.value = sasHandle;
    final res = getDec(h.ref);
    return (success: res.success != 0, a: res.a, b: res.b, c: res.c);
  } finally {
    calloc.free(h);
  }
}

bool sasFree({required int sasHandle}) {
  _ensurePostCObjectRegistered();
  final lib = _open();
  final freeFn = lib.lookupFunction<_NativeSasFreeHandle, _DartSasFreeHandle>('messie_v2_sas_free');
  final h = calloc<MessieV2SasHandle>();
  try {
    h.ref.value = sasHandle;
    final ok = freeFn(h.ref);
    return ok != 0;
  } finally {
    calloc.free(h);
  }
}
