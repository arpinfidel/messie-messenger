import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:isolate';
import 'dart:io';

import 'package:ffi/ffi.dart'; // Utf8, toNativeUtf8, toDartString, calloc

typedef _PointerUtf8 = ffi.Pointer<Utf8>;

// ---- FFI signature typedefs (avoid parser confusion with inline function types) ----
typedef _NativePing = _PointerUtf8 Function();
typedef _DartPing   = _PointerUtf8 Function();

typedef _NativeInitClient = _PointerUtf8 Function(_PointerUtf8, _PointerUtf8);
typedef _DartInitClient   = _PointerUtf8 Function(_PointerUtf8, _PointerUtf8);

typedef _NativeRestoreOrLogin = _PointerUtf8 Function(
  _PointerUtf8, _PointerUtf8, _PointerUtf8, _PointerUtf8
);
typedef _DartRestoreOrLogin = _PointerUtf8 Function(
  _PointerUtf8, _PointerUtf8, _PointerUtf8, _PointerUtf8
);

typedef _NativeLogout = _PointerUtf8 Function(_PointerUtf8);
typedef _DartLogout   = _PointerUtf8 Function(_PointerUtf8);

typedef _NativeFreeString = ffi.Void Function(_PointerUtf8);
typedef _DartFreeString   = void Function(_PointerUtf8);

// -----------------------------------------------------------------------------

Future<String> rustPing() => Isolate.run(() => _pingIsolate(_LibraryConfig.detect()));

Future<RustResult<InitClientData>> rustInitClient({
  required String homeserverUrl,
  required String basePath,
}) {
  final args = _InitArgs(_LibraryConfig.detect(), homeserverUrl, basePath);
  return Isolate.run(() => _initClientIsolate(args));
}

Future<RustResult<LoginData>> rustRestoreOrLogin({
  required String homeserverUrl,
  required String username,
  required String password,
  required String basePath,
}) {
  final args = _RestoreArgs(
    _LibraryConfig.detect(),
    homeserverUrl,
    username,
    password,
    basePath,
  );
  return Isolate.run(() => _restoreOrLoginIsolate(args));
}

Future<RustResult<Unit>> rustLogout({required String basePath}) {
  final args = _LogoutArgs(_LibraryConfig.detect(), basePath);
  return Isolate.run(() => _logoutIsolate(args));
}

String _pingIsolate(_LibraryConfig config) {
  final bindings = _RustBindings(config.open());
  return bindings.ping();
}

RustResult<InitClientData> _initClientIsolate(_InitArgs args) {
  final bindings = _RustBindings(args.config.open());
  return bindings.initClient(args.homeserverUrl, args.basePath);
}

RustResult<LoginData> _restoreOrLoginIsolate(_RestoreArgs args) {
  final bindings = _RustBindings(args.config.open());
  return bindings.restoreOrLogin(
    args.homeserverUrl,
    args.username,
    args.password,
    args.basePath,
  );
}

RustResult<Unit> _logoutIsolate(_LogoutArgs args) {
  final bindings = _RustBindings(args.config.open());
  return bindings.logout(args.basePath);
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

class _RustBindings {
  _RustBindings(ffi.DynamicLibrary library)
      : _ping = library.lookupFunction<_NativePing, _DartPing>('messie_ffi_ping'),
        _initClient = library.lookupFunction<_NativeInitClient, _DartInitClient>('messie_ffi_init_client'),
        _restoreOrLogin = library.lookupFunction<_NativeRestoreOrLogin, _DartRestoreOrLogin>('messie_ffi_restore_or_login'),
        _logout = library.lookupFunction<_NativeLogout, _DartLogout>('messie_ffi_logout'),
        _freeString = library.lookupFunction<_NativeFreeString, _DartFreeString>('messie_ffi_free_string');

  final _DartPing _ping;
  final _DartInitClient _initClient;
  final _DartRestoreOrLogin _restoreOrLogin;
  final _DartLogout _logout;
  final _DartFreeString _freeString;

  String ping() => _stringFromPointer(_ping());

  RustResult<InitClientData> initClient(String homeserverUrl, String basePath) {
    final hsPtr = homeserverUrl.toNativeUtf8();
    final basePtr = basePath.toNativeUtf8();
    try {
      final result = _stringFromPointer(_initClient(hsPtr, basePtr));
      return _parse(result, (json) => InitClientData.fromJson(json as Map<String, dynamic>));
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
      final result = _stringFromPointer(_restoreOrLogin(hsPtr, userPtr, passPtr, basePtr));
      return _parse(result, (json) => LoginData.fromJson(json as Map<String, dynamic>));
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
    const base = 'messie_ffi';
    if (Platform.isIOS || Platform.isMacOS) {
      return const _LibraryConfig(useProcess: true);
    }
    if (Platform.isAndroid || Platform.isLinux) {
      return const _LibraryConfig(useProcess: false, libraryPath: 'lib$base.so');
    }
    if (Platform.isWindows) {
      return const _LibraryConfig(useProcess: false, libraryPath: '$base.dll');
    }
    return const _LibraryConfig(useProcess: false, libraryPath: 'lib$base.dylib');
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
  const _RestoreArgs(this.config, this.homeserverUrl, this.username, this.password, this.basePath);

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
class Unit {
  const Unit._();

  static const instance = Unit._();
}
