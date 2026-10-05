import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';

/// Thin, platform-neutral facade over the Go bridge (go/bridge).
///
/// Android/iOS: gomobile .aar/.xcframework called from Kotlin/Swift through a
/// MethodChannel. Desktop: c-shared library loaded with dart:ffi; blocking
/// calls run in `Isolate.run` so the UI never stalls (the Go runtime and its
/// global instance map are shared across isolates in the same process).
abstract class CoreBridge {
  Future<void> setAssetDir(String dir);
  Future<void> startInstance(String id, String core, String configJson);
  Future<void> stopInstance(String id);
  Future<void> stopAll();
  Future<bool> isRunning(String id);
  Future<List<int>> freePorts(int n);
  Future<(int, int)> traffic(String id);
  Future<Map<String, String>> version();

  /// Desktop only; Android TUN is owned by the VpnService.
  Future<void> startTun2Socks(String device, int socksPort, int mtu);
  Future<void> stopTun2Socks();

  static CoreBridge create() {
    if (Platform.isAndroid || Platform.isIOS) return MethodChannelCoreBridge();
    return FfiCoreBridge();
  }
}

class CoreException implements Exception {
  final String message;
  CoreException(this.message);
  @override
  String toString() => message;
}

// ---------------------------------------------------------------- mobile

class MethodChannelCoreBridge implements CoreBridge {
  static const _ch = MethodChannel('kuputun/core');

  Future<T?> _call<T>(String m, [Map<String, Object?>? args]) async {
    try {
      return await _ch.invokeMethod<T>(m, args);
    } on PlatformException catch (e) {
      throw CoreException(e.message ?? e.code);
    }
  }

  @override
  Future<void> setAssetDir(String dir) => _call<void>('setAssetDir', {'dir': dir});
  @override
  Future<void> startInstance(String id, String core, String configJson) =>
      _call<void>('startInstance', {'id': id, 'core': core, 'config': configJson});
  @override
  Future<void> stopInstance(String id) => _call<void>('stopInstance', {'id': id});
  @override
  Future<void> stopAll() => _call<void>('stopAll');
  @override
  Future<bool> isRunning(String id) async => await _call<bool>('isRunning', {'id': id}) ?? false;
  @override
  Future<List<int>> freePorts(int n) async {
    final s = await _call<String>('freePorts', {'n': n});
    return (jsonDecode(s!) as List).cast<int>();
  }

  @override
  Future<(int, int)> traffic(String id) async {
    final s = await _call<String>('traffic', {'id': id});
    final m = jsonDecode(s ?? '{}') as Map<String, dynamic>;
    return ((m['up'] as num?)?.toInt() ?? 0, (m['down'] as num?)?.toInt() ?? 0);
  }

  @override
  Future<Map<String, String>> version() async =>
      Map<String, String>.from(jsonDecode(await _call<String>('version') ?? '{}') as Map);
  @override
  Future<void> startTun2Socks(String device, int socksPort, int mtu) =>
      throw UnsupportedError('On mobile the VpnService starts tun2socks');
  @override
  Future<void> stopTun2Socks() async {}
}

// ---------------------------------------------------------------- desktop

typedef _S3 = Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>);
typedef _S1 = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _S0 = Pointer<Utf8> Function();
typedef _V0 = Void Function();
typedef _V0d = void Function();
typedef _PI = Pointer<Utf8> Function(Int32);
typedef _PId = Pointer<Utf8> Function(int);
typedef _I1 = Int32 Function(Pointer<Utf8>);
typedef _I1d = int Function(Pointer<Utf8>);
typedef _T = Pointer<Utf8> Function(Pointer<Utf8>, Int32, Int32, Pointer<Utf8>);
typedef _Td = Pointer<Utf8> Function(Pointer<Utf8>, int, int, Pointer<Utf8>);
typedef _F = Void Function(Pointer<Utf8>);
typedef _Fd = void Function(Pointer<Utf8>);

class _Lib {
  final DynamicLibrary lib;
  late final start = lib.lookupFunction<_S3, _S3>('KtStartInstance');
  late final stop = lib.lookupFunction<_S1, _S1>('KtStopInstance');
  late final stopAll = lib.lookupFunction<_V0, _V0d>('KtStopAll');
  late final isRunning = lib.lookupFunction<_I1, _I1d>('KtIsRunning');
  late final freePorts = lib.lookupFunction<_PI, _PId>('KtFreePorts');
  late final tun = lib.lookupFunction<_T, _Td>('KtStartTun2Socks');
  late final stopTun = lib.lookupFunction<_V0, _V0d>('KtStopTun2Socks');
  late final version = lib.lookupFunction<_S0, _S0>('KtVersion');
  late final traffic = lib.lookupFunction<_S1, _S1>('KtTrafficStats');
  late final assetDir = lib.lookupFunction<_S1, _S1>('KtSetAssetDir');
  late final free = lib.lookupFunction<_F, _Fd>('KtFree');

  _Lib(this.lib);

  static _Lib? _instance;
  static _Lib get i => _instance ??= _Lib(_open());

  static DynamicLibrary _open() {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    if (Platform.isWindows) return DynamicLibrary.open('$exeDir\\libkuputun.dll');
    if (Platform.isMacOS) {
      final fw = '$exeDir/../Frameworks/libkuputun.dylib';
      return DynamicLibrary.open(File(fw).existsSync() ? fw : 'libkuputun.dylib');
    }
    final local = '$exeDir/lib/libkuputun.so';
    return DynamicLibrary.open(File(local).existsSync() ? local : 'libkuputun.so');
  }

  /// Takes ownership of a returned C string.
  String take(Pointer<Utf8> p) {
    final s = p.toDartString();
    free(p);
    return s;
  }

  void check(Pointer<Utf8> p) {
    final s = take(p);
    if (s.isNotEmpty) throw CoreException(s);
  }
}

class FfiCoreBridge implements CoreBridge {
  @override
  Future<void> setAssetDir(String dir) => Isolate.run(() => using((a) => _Lib.i.check(_Lib.i.assetDir(dir.toNativeUtf8(allocator: a)))));

  @override
  Future<void> startInstance(String id, String core, String configJson) => Isolate.run(() => using((a) {
        final l = _Lib.i;
        l.check(l.start(id.toNativeUtf8(allocator: a), core.toNativeUtf8(allocator: a), configJson.toNativeUtf8(allocator: a)));
      }));

  @override
  Future<void> stopInstance(String id) => Isolate.run(() => using((a) => _Lib.i.check(_Lib.i.stop(id.toNativeUtf8(allocator: a)))));

  @override
  Future<void> stopAll() => Isolate.run(() => _Lib.i.stopAll());

  @override
  Future<bool> isRunning(String id) async => using((a) => _Lib.i.isRunning(id.toNativeUtf8(allocator: a)) == 1);

  @override
  Future<List<int>> freePorts(int n) async {
    final s = _Lib.i.take(_Lib.i.freePorts(n));
    if (s.startsWith('ERR:')) throw CoreException(s.substring(4));
    return (jsonDecode(s) as List).cast<int>();
  }

  @override
  Future<(int, int)> traffic(String id) async {
    final s = using((a) => _Lib.i.take(_Lib.i.traffic(id.toNativeUtf8(allocator: a))));
    final m = jsonDecode(s) as Map<String, dynamic>;
    return ((m['up'] as num).toInt(), (m['down'] as num).toInt());
  }

  @override
  Future<Map<String, String>> version() async => Map<String, String>.from(jsonDecode(_Lib.i.take(_Lib.i.version())) as Map);

  @override
  Future<void> startTun2Socks(String device, int socksPort, int mtu) => Isolate.run(() => using((a) {
        final l = _Lib.i;
        l.check(l.tun(device.toNativeUtf8(allocator: a), socksPort, mtu, 'warn'.toNativeUtf8(allocator: a)));
      }));

  @override
  Future<void> stopTun2Socks() => Isolate.run(() => _Lib.i.stopTun());
}
