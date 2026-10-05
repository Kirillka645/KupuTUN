import 'dart:async';
import 'dart:convert';
import 'dart:io' hide BytesBuilder;
import 'dart:typed_data' show BytesBuilder;

/// Low-level latency probes. All return milliseconds or null on failure.
class PingProbes {
  /// TCP connect to the server itself (no proxy). Cheap, but says nothing
  /// about whether the proxy protocol works.
  static Future<int?> tcpConnect(String host, int port, Duration timeout) async {
    final sw = Stopwatch()..start();
    Socket? s;
    try {
      s = await Socket.connect(host, port, timeout: timeout);
      return sw.elapsedMilliseconds;
    } on Object {
      return null;
    } finally {
      s?.destroy();
    }
  }

  /// ICMP via the system `ping` binary (no raw-socket permission needed).
  static Future<List<int?>> icmp(String host, {int count = 3, Duration timeout = const Duration(seconds: 3)}) async {
    final List<String> args;
    if (Platform.isWindows) {
      args = ['-n', '$count', '-w', '${timeout.inMilliseconds}', host];
    } else if (Platform.isMacOS) {
      args = ['-c', '$count', '-W', '${timeout.inMilliseconds}', host];
    } else {
      args = ['-c', '$count', '-W', '${timeout.inSeconds.clamp(1, 30)}', host];
    }
    try {
      final r = await Process.run('ping', args, stdoutEncoding: const SystemEncoding())
          .timeout(timeout * (count + 1));
      final out = r.stdout.toString();
      final re = RegExp(r'(?:time|время|زمان|时间)[=<]\s*([\d.,]+)', caseSensitive: false);
      final got = re.allMatches(out).map((m) => double.tryParse(m.group(1)!.replaceAll(',', '.'))?.round()).toList();
      return [...got, ...List<int?>.filled((count - got.length).clamp(0, count), null)];
    } on Object {
      return List<int?>.filled(count, null);
    }
  }

  /// Real delay: full HTTP request through the proxy (fresh connection each
  /// call, so proxy handshake is included — matches what users feel).
  static Future<int?> realDelay(int proxyPort, Uri url, Duration timeout, {bool head = false}) async {
    final client = HttpClient()
      ..findProxy = ((_) => 'PROXY 127.0.0.1:$proxyPort')
      ..connectionTimeout = timeout
      ..idleTimeout = Duration.zero;
    final sw = Stopwatch()..start();
    try {
      final req = await (head ? client.headUrl(url) : client.getUrl(url)).timeout(timeout);
      req.followRedirects = false;
      req.headers.set(HttpHeaders.userAgentHeader, 'KupuTUN-tester');
      final resp = await req.close().timeout(timeout - sw.elapsed);
      await resp.drain<void>().timeout(timeout - sw.elapsed);
      if (resp.statusCode >= 500) return null;
      return sw.elapsedMilliseconds;
    } on Object {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// TLS handshake time to [host]:443 measured *through* the proxy:
  /// CONNECT via the local HTTP inbound, then time only the TLS handshake.
  /// RawSocket is used so the CONNECT reply can be consumed byte-exactly
  /// before handing the same subscription to RawSecureSocket.
  static Future<int?> tlsHandshake(int proxyPort, String host, Duration timeout) async {
    RawSocket? raw;
    RawSecureSocket? tls;
    StreamSubscription<RawSocketEvent>? sub;
    try {
      raw = await RawSocket.connect('127.0.0.1', proxyPort, timeout: timeout);
      final sock = raw;
      final req = latin1.encode('CONNECT $host:443 HTTP/1.1\r\nHost: $host:443\r\n\r\n');
      var written = 0;
      final header = BytesBuilder();
      final done = Completer<bool>();
      sub = sock.listen((ev) {
        if (ev == RawSocketEvent.write && written < req.length) {
          written += sock.write(req, written);
          if (written < req.length) sock.writeEventsEnabled = true;
        } else if (ev == RawSocketEvent.read) {
          // read one byte at a time until end of header: never over-reads TLS data
          while (!done.isCompleted) {
            final b = sock.read(1);
            if (b == null || b.isEmpty) break;
            header.add(b);
            final t = latin1.decode(header.toBytes());
            if (t.endsWith('\r\n\r\n')) {
              done.complete(t.startsWith('HTTP/1.1 200') || t.startsWith('HTTP/1.0 200'));
            }
          }
        } else if (ev == RawSocketEvent.readClosed || ev == RawSocketEvent.closed) {
          if (!done.isCompleted) done.complete(false);
        }
      });
      final ok = await done.future.timeout(timeout);
      if (!ok) return null;
      sub.pause();
      final sw = Stopwatch()..start();
      tls = await RawSecureSocket.secure(sock, subscription: sub, host: host).timeout(timeout);
      return sw.elapsedMilliseconds;
    } on Object {
      return null;
    } finally {
      if (tls != null) {
        await tls.close();
      } else {
        await sub?.cancel();
        await raw?.close();
      }
    }
  }
}
