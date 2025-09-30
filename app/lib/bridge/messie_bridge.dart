import 'dart:io';

import 'bridge_generated.dart';

MessieFfi? _messieFfi;

MessieFfi get messieFfi => _messieFfi ??= createMessieFfi();

MessieFfi createMessieFfi() {
  const base = 'messie_ffi';
  if (Platform.isIOS || Platform.isMacOS) {
    return MessieFfiImpl.dynamic();
  }
  if (Platform.isAndroid) {
    return MessieFfiImpl.fromDynamicLibraryPath('lib${base}.so');
  }
  if (Platform.isLinux) {
    return MessieFfiImpl.fromDynamicLibraryPath('lib${base}.so');
  }
  if (Platform.isWindows) {
    return MessieFfiImpl.fromDynamicLibraryPath('${base}.dll');
  }
  final library = 'lib${base}.dylib';
  return MessieFfiImpl.fromDynamicLibraryPath(library);
}

Future<String> rustPing() => messieFfi.ping();
