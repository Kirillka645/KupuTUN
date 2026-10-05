import '../core/models/server.dart';
import '../core/models/test_result.dart';
import 'smart_score.dart';

enum SortBy { subscription, ping, speed, jitter, country, name, smart }

class ServerFilter {
  final Set<String> countries; // empty = all
  final Set<ProxyProtocol> protocols; // empty = all
  final bool onlyAlive;
  final int? maxPingMs;
  final double? minSpeedMbps;
  final String query;
  const ServerFilter({
    this.countries = const {},
    this.protocols = const {},
    this.onlyAlive = false,
    this.maxPingMs,
    this.minSpeedMbps,
    this.query = '',
  });

  bool get isActive =>
      countries.isNotEmpty || protocols.isNotEmpty || onlyAlive || maxPingMs != null || minSpeedMbps != null || query.isNotEmpty;

  ServerFilter copyWith({
    Set<String>? countries,
    Set<ProxyProtocol>? protocols,
    bool? onlyAlive,
    int? maxPingMs,
    bool clearMaxPing = false,
    double? minSpeedMbps,
    bool clearMinSpeed = false,
    String? query,
  }) =>
      ServerFilter(
        countries: countries ?? this.countries,
        protocols: protocols ?? this.protocols,
        onlyAlive: onlyAlive ?? this.onlyAlive,
        maxPingMs: clearMaxPing ? null : (maxPingMs ?? this.maxPingMs),
        minSpeedMbps: clearMinSpeed ? null : (minSpeedMbps ?? this.minSpeedMbps),
        query: query ?? this.query,
      );
}

/// Pure sort/filter logic (unit-tested). Unavailable servers always go last,
/// whatever the sort key, and keep their relative subscription order.
class ServerSorter {
  static List<Server> apply(
    List<Server> servers,
    Map<String, TestResult> results, {
    SortBy sortBy = SortBy.subscription,
    ServerFilter filter = const ServerFilter(),
    ScoreWeights weights = const ScoreWeights(),
  }) {
    final q = filter.query.trim().toLowerCase();
    final list = servers.where((s) {
      final r = results[s.id];
      if (filter.countries.isNotEmpty && !filter.countries.contains(r?.exitCountry ?? s.countryCode)) return false;
      if (filter.protocols.isNotEmpty && !filter.protocols.contains(s.protocol)) return false;
      if (filter.onlyAlive && !(r?.isAlive ?? false)) return false;
      if (filter.maxPingMs != null && (r?.medianMs == null || r!.medianMs! >= filter.maxPingMs!)) return false;
      if (filter.minSpeedMbps != null && (r?.downloadMbps == null || r!.downloadMbps! <= filter.minSpeedMbps!)) return false;
      if (q.isNotEmpty && !s.name.toLowerCase().contains(q) && !s.address.toLowerCase().contains(q)) return false;
      return true;
    }).toList();

    int deadRank(Server s) {
      final r = results[s.id];
      if (r == null) return 1; // untested: between alive and dead
      return r.isAlive ? 0 : 2;
    }

    int byNullableNum(num? a, num? b, {bool desc = false}) {
      if (a == null && b == null) return 0;
      if (a == null) return 1;
      if (b == null) return -1;
      return desc ? b.compareTo(a) : a.compareTo(b);
    }

    int cmp(Server a, Server b) {
      final d = deadRank(a).compareTo(deadRank(b));
      if (d != 0 && sortBy != SortBy.subscription && sortBy != SortBy.name) return d;
      if (sortBy == SortBy.subscription || sortBy == SortBy.name) {
        // dead still last, but untested are treated as alive here
        final da = deadRank(a) == 2 ? 1 : 0, db = deadRank(b) == 2 ? 1 : 0;
        if (da != db) return da.compareTo(db);
      }
      final ra = results[a.id], rb = results[b.id];
      final c = switch (sortBy) {
        SortBy.subscription => 0,
        SortBy.ping => byNullableNum(ra?.medianMs, rb?.medianMs),
        SortBy.speed => byNullableNum(ra?.downloadMbps, rb?.downloadMbps, desc: true),
        SortBy.jitter => byNullableNum(ra?.jitterMs, rb?.jitterMs),
        SortBy.country => (ra?.exitCountry ?? a.countryCode ?? 'ZZ').compareTo(rb?.exitCountry ?? b.countryCode ?? 'ZZ'),
        SortBy.name => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        SortBy.smart => SmartScore.compute(rb, weights).compareTo(SmartScore.compute(ra, weights)),
      };
      if (c != 0) return c;
      final sa = (a.subscriptionId ?? '').compareTo(b.subscriptionId ?? '');
      return sa != 0 ? sa : a.sortIndex.compareTo(b.sortIndex);
    }

    // stable sort: Dart's List.sort is not guaranteed stable → decorate with index
    final indexed = list.asMap().entries.toList()
      ..sort((x, y) {
        final c = cmp(x.value, y.value);
        return c != 0 ? c : x.key.compareTo(y.key);
      });
    return indexed.map((e) => e.value).toList();
  }

  /// Best server for "Лучший сервер": highest Smart Score among alive.
  static Server? best(List<Server> servers, Map<String, TestResult> results, ScoreWeights w) {
    Server? best;
    var bestScore = -1.0;
    for (final s in servers) {
      final sc = SmartScore.compute(results[s.id], w);
      if (sc > bestScore) {
        bestScore = sc;
        best = s;
      }
    }
    return bestScore < 0 ? null : best;
  }
}
