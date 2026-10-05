import 'package:flutter_test/flutter_test.dart';
import 'package:kuputun/core/models/server.dart';
import 'package:kuputun/core/models/test_result.dart';
import 'package:kuputun/tester/server_sorter.dart';
import 'package:kuputun/tester/smart_score.dart';
import 'package:kuputun/tester/stats.dart';

TestResult r(String id, int? ping, {double? down, double jitter = 5, double loss = 0}) => TestResult(
      serverId: id,
      timestamp: DateTime(2026),
      mode: PingMode.realDelay,
      samples: [ping],
      medianMs: ping,
      jitterMs: ping == null ? null : jitter,
      lossPercent: ping == null ? 100 : loss,
      downloadMbps: down,
    );

Server s(String id, {int idx = 0, String name = 'x'}) =>
    Server(id: id, name: name, protocol: ProxyProtocol.vless, address: 'a', port: 1, credential: 'c', sortIndex: idx);

void main() {
  test('median / jitter / loss', () {
    final st = LatencyStats.from([100, null, 120]);
    expect(st.median, 110);
    expect(st.jitter, 20);
    expect(st.lossPercent, closeTo(33.3, 0.1));
    expect(LatencyStats.from([null, null]).median, isNull);
    expect(LatencyStats.from([50, 70, 60]).median, 60);
  });

  test('mbps', () {
    expect(mbps(1250000, const Duration(seconds: 1)), closeTo(10, 0.001));
  });

  test('smart score prefers fast & stable, dead = -1', () {
    const w = ScoreWeights();
    final good = SmartScore.compute(r('a', 40, down: 80, jitter: 2), w);
    final bad = SmartScore.compute(r('b', 400, down: 5, jitter: 60, loss: 33), w);
    expect(good, greaterThan(bad));
    expect(SmartScore.compute(r('c', null), w), -1);
    expect(good, inInclusiveRange(0, 100));
  });

  test('sorting puts dead servers last for every key', () {
    final servers = [s('dead', idx: 0), s('slow', idx: 1), s('fast', idx: 2), s('untested', idx: 3)];
    final res = {'dead': r('dead', null), 'slow': r('slow', 300), 'fast': r('fast', 50)};
    for (final key in SortBy.values) {
      final out = ServerSorter.apply(servers, res, sortBy: key);
      expect(out.last.id, 'dead', reason: key.name);
    }
    expect(ServerSorter.apply(servers, res, sortBy: SortBy.ping).first.id, 'fast');
    expect(ServerSorter.apply(servers, res, sortBy: SortBy.subscription).map((e) => e.id).take(3), ['slow', 'fast', 'untested']);
  });

  test('filters', () {
    final servers = [s('a', name: 'Germany'), s('b', name: 'Finland')];
    final res = {'a': r('a', 50, down: 100), 'b': r('b', 250, down: 5)};
    expect(ServerSorter.apply(servers, res, filter: const ServerFilter(maxPingMs: 100)).single.id, 'a');
    expect(ServerSorter.apply(servers, res, filter: const ServerFilter(minSpeedMbps: 10)).single.id, 'a');
    expect(ServerSorter.apply(servers, res, filter: const ServerFilter(query: 'fin')).single.id, 'b');
  });

  test('badges', () {
    final stable = List.generate(6, (i) => r('a', 60 + i));
    expect(SmartScore.badge(stable), StabilityBadge.stable);
    final flaky = [r('a', 50), r('a', null), r('a', null), r('a', 60)];
    expect(SmartScore.badge(flaky), StabilityBadge.flaky);
  });
}
