import 'dart:async';
import 'dart:convert';

import '../core/config/core_settings.dart';
import '../core/config/singbox_config_builder.dart';
import '../core/config/xray_config_builder.dart';
import '../core/engine/core_bridge.dart';
import '../core/models/server.dart';
import '../core/models/test_result.dart';
import '../routing/routing_presets.dart';
import 'ping_tester.dart';
import 'pool.dart';
import 'service_checker.dart';
import 'speed_tester.dart';
import 'stats.dart';
import 'tester_settings.dart';

class TestProgress {
  final int done;
  final int total;
  final TestResult? result; // result for one server, when available
  const TestProgress(this.done, this.total, [this.result]);
  double get fraction => total == 0 ? 1 : done / total;
}

/// Orchestrates mass testing.
///
/// Why it is faster than per-server testing:
///  * one core instance per batch of up to [batchSize] servers (N inbounds -> N outbounds),
///    so startup cost is paid once instead of N times;
///  * probes run through a [TaskPool] with a user-defined concurrency limit;
///  * a broken server cannot kill the batch: on start failure the batch is
///    bisected until the bad configs are isolated.
class TesterService {
  final CoreBridge bridge;
  CoreSettings coreSettings;
  static const batchSize = 64;
  TaskPool? _pool;
  int _seq = 0;

  TesterService(this.bridge, this.coreSettings);

  void cancel() => _pool?.cancel();

  Stream<TestProgress> pingAll(List<Server> servers, TesterSettings ts) {
    final ctrl = StreamController<TestProgress>();
    () async {
      final pool = _pool = TaskPool(ts.concurrency);
      var done = 0;
      void emit(TestResult r) {
        done++;
        if (!ctrl.isClosed) ctrl.add(TestProgress(done, servers.length, r));
      }

      try {
        if (ts.pingMode == PingMode.realDelay) {
          await _realDelayAll(servers, ts, pool, emit);
        } else {
          await Future.wait(servers.map((s) => pool.run(() async => emit(await _directPing(s, ts)))));
        }
      } finally {
        _pool = null;
        await ctrl.close();
      }
    }();
    return ctrl.stream;
  }

  Future<TestResult> _directPing(Server s, TesterSettings ts) async {
    final List<int?> samples;
    if (ts.pingMode == PingMode.icmp) {
      samples = await PingProbes.icmp(s.address, count: ts.samples, timeout: ts.timeout);
    } else {
      samples = [for (var i = 0; i < ts.samples; i++) await PingProbes.tcpConnect(s.address, s.port, ts.timeout)];
    }
    final st = LatencyStats.from(samples);
    return TestResult(
      serverId: s.id,
      timestamp: DateTime.now(),
      mode: ts.pingMode,
      samples: samples,
      medianMs: st.median,
      jitterMs: st.jitter,
      lossPercent: st.lossPercent,
      error: st.median == null ? 'unreachable' : null,
    );
  }

  Future<void> _realDelayAll(List<Server> servers, TesterSettings ts, TaskPool pool, void Function(TestResult) emit) async {
    final xray = <Server>[], singbox = <Server>[], raw = <Server>[];
    for (final s in servers) {
      if (s.params.containsKey('json')) {
        raw.add(s);
      } else if (s.effectiveCore == CoreType.singbox) {
        singbox.add(s);
      } else {
        xray.add(s);
      }
    }
    final batches = <Future<void>>[];
    for (var i = 0; i < xray.length; i += batchSize) {
      batches.add(_runBatch(xray.sublist(i, (i + batchSize).clamp(0, xray.length)), 'xray', ts, pool, emit));
    }
    for (var i = 0; i < singbox.length; i += batchSize) {
      batches.add(_runBatch(singbox.sublist(i, (i + batchSize).clamp(0, singbox.length)), 'singbox', ts, pool, emit));
    }
    for (final s in raw) {
      batches.add(_runBatch([s], s.param('jsonCore', 'xray'), ts, pool, emit));
    }
    await Future.wait(batches);
  }

  Future<void> _runBatch(List<Server> batch, String core, TesterSettings ts, TaskPool pool, void Function(TestResult) emit) async {
    if (batch.isEmpty || pool.cancelled) return;
    final id = 'test-${_seq++}';
    // Configs that cannot even be built are reported immediately.
    final buildable = <Server>[];
    for (final s in batch) {
      try {
        if (core == 'xray' && !s.params.containsKey('json')) XrayConfigBuilder(coreSettings).outbound(s, 'probe');
        if (core == 'singbox' && !s.params.containsKey('json')) SingboxConfigBuilder(coreSettings).outbound(s, 'probe');
        buildable.add(s);
      } on Object catch (e) {
        emit(_fail(s, ts, '$e'));
      }
    }
    if (buildable.isEmpty) return;
    final ports = await bridge.freePorts(buildable.length);
    final cfg = _batchConfig(buildable, ports, core);
    try {
      await bridge.startInstance(id, core, cfg);
    } on CoreException catch (e) {
      if (buildable.length == 1) {
        emit(_fail(buildable.first, ts, e.message));
        return;
      }
      final mid = buildable.length ~/ 2;
      await Future.wait([
        _runBatch(buildable.sublist(0, mid), core, ts, pool, emit),
        _runBatch(buildable.sublist(mid), core, ts, pool, emit),
      ]);
      return;
    }
    try {
      await Future.wait([
        for (var i = 0; i < buildable.length; i++)
          pool.run(() async => emit(await _probeThroughProxy(buildable[i], ports[i], ts))),
      ]);
    } finally {
      await bridge.stopInstance(id);
    }
  }

  String _batchConfig(List<Server> servers, List<int> ports, String core) {
    final Map<String, dynamic> m;
    if (servers.length == 1 && servers.first.params.containsKey('json')) {
      m = core == 'singbox'
          ? (SingboxConfigBuilder(coreSettings).buildMain(servers.first, _testRouting)..['inbounds'] = [
              {'type': 'http', 'tag': 'in-0', 'listen': '127.0.0.1', 'listen_port': ports.first}
            ])
          : XrayConfigBuilder(coreSettings).buildRawJsonTest(servers.first, ports.first);
    } else if (core == 'singbox') {
      m = SingboxConfigBuilder(coreSettings).buildBatchTest(servers, ports);
    } else {
      m = XrayConfigBuilder(coreSettings).buildBatchTest(servers, ports);
    }
    return _encode(m);
  }

  Future<TestResult> _probeThroughProxy(Server s, int port, TesterSettings ts) async {
    final url = Uri.parse(ts.url);
    final samples = <int?>[];
    for (var i = 0; i < ts.samples; i++) {
      samples.add(await PingProbes.realDelay(port, url, ts.timeout, head: ts.useHead));
    }
    final st = LatencyStats.from(samples);
    int? tls;
    if (ts.measureTls && st.median != null) {
      tls = await PingProbes.tlsHandshake(port, url.host, ts.timeout);
    }
    return TestResult(
      serverId: s.id,
      timestamp: DateTime.now(),
      mode: PingMode.realDelay,
      samples: samples,
      medianMs: st.median,
      jitterMs: st.jitter,
      lossPercent: st.lossPercent,
      tlsHandshakeMs: tls,
      error: st.median == null ? 'no response through proxy' : null,
    );
  }

  TestResult _fail(Server s, TesterSettings ts, String err) => TestResult(
        serverId: s.id,
        timestamp: DateTime.now(),
        mode: ts.pingMode,
        samples: List<int?>.filled(ts.samples, null),
        lossPercent: 100,
        error: err,
      );

  /// Speed test (sequential on purpose: parallel tests would share bandwidth
  /// and produce meaningless numbers).
  Future<TestResult> speedTest(Server s, TesterSettings ts, {void Function(SpeedSample)? onSample}) =>
      _withSingle(s, (port) async {
        final cfg = SpeedConfig.forMode(ts.speedMode, customDownloadUrl: ts.customSpeedUrl, upload: ts.speedUpload);
        final r = await SpeedTester().run(port, cfg, onSample: onSample);
        return TestResult(
          serverId: s.id,
          timestamp: DateTime.now(),
          mode: PingMode.realDelay,
          downloadMbps: r.downloadMbps,
          uploadMbps: r.uploadMbps,
          bytesUsed: r.bytesUsed,
          error: r.error,
        );
      });

  /// Service availability + exit IP / country.
  Future<TestResult> serviceCheck(Server s) => _withSingle(s, (port) async {
        final results = await Future.wait([ServiceChecker.check(port), ServiceChecker.exitIp(port)]);
        final services = results[0] as Map<String, bool>;
        final exit = results[1] as (String?, String?);
        return TestResult(
          serverId: s.id,
          timestamp: DateTime.now(),
          mode: PingMode.realDelay,
          services: services,
          exitIp: exit.$1,
          exitCountry: exit.$2,
        );
      });

  /// Runs [body] with a single-server test instance and returns its result.
  Future<TestResult> _withSingle(Server s, Future<TestResult> Function(int port) body) async {
    final core = s.params.containsKey('json') ? s.param('jsonCore', 'xray') : (s.effectiveCore == CoreType.singbox ? 'singbox' : 'xray');
    final port = (await bridge.freePorts(1)).first;
    final id = 'test-${_seq++}';
    try {
      await bridge.startInstance(id, core, _batchConfig([s], [port], core));
    } on Object catch (e) {
      return TestResult(serverId: s.id, timestamp: DateTime.now(), mode: PingMode.realDelay, error: '$e');
    }
    try {
      return await body(port);
    } finally {
      await bridge.stopInstance(id);
    }
  }

  static String _encode(Map<String, dynamic> m) => jsonEncode(m);
}

final _testRouting = RoutingPresets.global();
