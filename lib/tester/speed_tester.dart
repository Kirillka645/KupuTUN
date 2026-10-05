import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'stats.dart';

enum SpeedMode { quick, accurate }

class SpeedConfig {
  final Uri downloadUrl; // must accept ?bytes=N or serve a fixed file
  final Uri uploadUrl;
  final int downloadBytes;
  final int uploadBytes;
  final Duration timeLimit;
  final bool upload;

  const SpeedConfig({
    required this.downloadUrl,
    required this.uploadUrl,
    required this.downloadBytes,
    required this.uploadBytes,
    required this.timeLimit,
    this.upload = true,
  });

  /// Cloudflare speed endpoints; "quick" = 5 s / 10 MB, "accurate" = 15 s / 25 MB.
  factory SpeedConfig.forMode(SpeedMode m, {String? customDownloadUrl, bool upload = true}) {
    final quick = m == SpeedMode.quick;
    final down = quick ? 10 * 1000 * 1000 : 25 * 1000 * 1000;
    final up = quick ? 3 * 1000 * 1000 : 10 * 1000 * 1000;
    return SpeedConfig(
      downloadUrl: Uri.parse(customDownloadUrl ?? 'https://speed.cloudflare.com/__down?bytes=$down'),
      uploadUrl: Uri.parse('https://speed.cloudflare.com/__up'),
      downloadBytes: down,
      uploadBytes: up,
      timeLimit: Duration(seconds: quick ? 5 : 15),
      upload: upload,
    );
  }

  /// Worst-case traffic per server, shown to the user before starting.
  int get maxTrafficBytes => downloadBytes + (upload ? uploadBytes : 0);
}

/// Live sample for the chart.
class SpeedSample {
  final bool upload;
  final Duration t;
  final double mbps; // instantaneous (last 250 ms window)
  final int totalBytes;
  const SpeedSample(this.upload, this.t, this.mbps, this.totalBytes);
}

class SpeedResult {
  final double? downloadMbps;
  final double? uploadMbps;
  final int bytesUsed;
  final String? error;
  const SpeedResult({this.downloadMbps, this.uploadMbps, this.bytesUsed = 0, this.error});
}

/// Measures throughput through a local HTTP proxy port.
///
/// Decision: the reported value is total bytes / total time *after the first
/// byte* (excludes connection setup, which is what "ping" measures), using a
/// time cap so slow servers never burn the whole budget.
class SpeedTester {
  static const _window = Duration(milliseconds: 250);

  Future<SpeedResult> run(int proxyPort, SpeedConfig cfg, {void Function(SpeedSample)? onSample}) async {
    var used = 0;
    double? down, up;
    String? err;
    try {
      final d = await _download(proxyPort, cfg, onSample);
      down = d.$1;
      used += d.$2;
    } on Object catch (e) {
      err = 'download: $e';
    }
    if (cfg.upload) {
      try {
        final u = await _upload(proxyPort, cfg, onSample);
        up = u.$1;
        used += u.$2;
      } on Object catch (e) {
        err = '${err == null ? '' : '$err; '}upload: $e';
      }
    }
    return SpeedResult(downloadMbps: down, uploadMbps: up, bytesUsed: used, error: down == null ? err : null);
  }

  HttpClient _client(int port, Duration t) => HttpClient()
    ..findProxy = ((_) => 'PROXY 127.0.0.1:$port')
    ..connectionTimeout = t
    ..autoUncompress = false;

  Future<(double, int)> _download(int port, SpeedConfig cfg, void Function(SpeedSample)? onSample) async {
    final client = _client(port, cfg.timeLimit);
    try {
      final req = await client.getUrl(cfg.downloadUrl).timeout(cfg.timeLimit);
      final resp = await req.close().timeout(cfg.timeLimit);
      if (resp.statusCode != 200) throw HttpException('status ${resp.statusCode}');
      final sw = Stopwatch();
      var total = 0, windowBytes = 0;
      var lastTick = Duration.zero;
      final done = Completer<void>();
      late StreamSubscription<List<int>> sub;
      sub = resp.listen((chunk) {
        if (!sw.isRunning) sw.start();
        total += chunk.length;
        windowBytes += chunk.length;
        final now = sw.elapsed;
        if (now - lastTick >= _window) {
          onSample?.call(SpeedSample(false, now, mbps(windowBytes, now - lastTick), total));
          windowBytes = 0;
          lastTick = now;
        }
        if (now >= cfg.timeLimit || total >= cfg.downloadBytes) {
          sub.cancel();
          if (!done.isCompleted) done.complete();
        }
      }, onError: (Object e) {
        if (!done.isCompleted) done.completeError(e);
      }, onDone: () {
        if (!done.isCompleted) done.complete();
      }, cancelOnError: true);
      await done.future.timeout(cfg.timeLimit + const Duration(seconds: 5), onTimeout: () => sub.cancel());
      sw.stop();
      if (total == 0) throw const HttpException('no data');
      return (mbps(total, sw.elapsed), total);
    } finally {
      client.close(force: true);
    }
  }

  Future<(double, int)> _upload(int port, SpeedConfig cfg, void Function(SpeedSample)? onSample) async {
    final client = _client(port, cfg.timeLimit);
    try {
      final req = await client.postUrl(cfg.uploadUrl).timeout(cfg.timeLimit);
      req.headers.contentType = ContentType.binary;
      req.contentLength = cfg.uploadBytes;
      final chunk = Uint8List(64 * 1024);
      final rnd = Random();
      for (var i = 0; i < chunk.length; i++) {
        chunk[i] = rnd.nextInt(256);
      }
      final sw = Stopwatch()..start();
      var sent = 0, windowBytes = 0;
      var lastTick = Duration.zero;
      var aborted = false;
      while (sent < cfg.uploadBytes) {
        final n = min(chunk.length, cfg.uploadBytes - sent);
        req.add(n == chunk.length ? chunk : Uint8List.sublistView(chunk, 0, n));
        await req.flush().timeout(cfg.timeLimit);
        sent += n;
        windowBytes += n;
        final now = sw.elapsed;
        if (now - lastTick >= _window) {
          onSample?.call(SpeedSample(true, now, mbps(windowBytes, now - lastTick), sent));
          windowBytes = 0;
          lastTick = now;
        }
        if (now >= cfg.timeLimit) {
          aborted = true;
          break;
        }
      }
      final elapsed = sw.elapsed;
      if (aborted) {
        req.abort();
      } else {
        final resp = await req.close().timeout(const Duration(seconds: 10));
        await resp.drain<void>();
      }
      return (mbps(sent, elapsed), sent);
    } finally {
      client.close(force: true);
    }
  }
}
