import 'dart:async';
import 'dart:io';

/// Checks which popular services are reachable through a proxy port and
/// detects the exit IP/country via Cloudflare's trace endpoint (no API key).
class ServiceChecker {
  /// Each probe hits an endpoint that is blocked/geo-fenced in the same way as
  /// the real service. Success = HTTP status not 403/451 and no network error.
  static final Map<String, Uri> services = {
    'YouTube': Uri.parse('https://www.youtube.com/generate_204'),
    'Telegram': Uri.parse('https://web.telegram.org/'),
    'Instagram': Uri.parse('https://www.instagram.com/'),
    'ChatGPT': Uri.parse('https://chatgpt.com/cdn-cgi/trace'),
    'Netflix': Uri.parse('https://www.netflix.com/title/81280792'),
  };

  static Future<Map<String, bool>> check(int proxyPort, {Duration timeout = const Duration(seconds: 8)}) async {
    final entries = await Future.wait(services.entries.map((e) async => MapEntry(e.key, await _ok(proxyPort, e.key, e.value, timeout))));
    return Map.fromEntries(entries);
  }

  static Future<bool> _ok(int port, String name, Uri url, Duration timeout) async {
    final c = HttpClient()
      ..findProxy = ((_) => 'PROXY 127.0.0.1:$port')
      ..connectionTimeout = timeout;
    try {
      final req = await c.getUrl(url).timeout(timeout);
      req.followRedirects = false;
      req.headers.set(HttpHeaders.userAgentHeader,
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36');
      final resp = await req.close().timeout(timeout);
      final body = name == 'ChatGPT' || name == 'Netflix' ? await resp.transform(const SystemEncoding().decoder).join() : '';
      if (resp.statusCode != 200 && name != 'ChatGPT' && name != 'Netflix') await resp.drain<void>();
      if (resp.statusCode == 403 || resp.statusCode == 451) return false;
      if (name == 'ChatGPT') {
        // OpenAI blocks some countries: trace gives loc=XX
        final loc = RegExp(r'loc=([A-Z]{2})').firstMatch(body)?.group(1);
        return loc != null && !_chatGptBlocked.contains(loc);
      }
      if (name == 'Netflix') {
        // A title that only exists in some regions; "Not Available"/redirect = no catalogue
        return resp.statusCode == 200 && !body.contains('NSEZ-403');
      }
      return resp.statusCode < 500;
    } on Object {
      return false;
    } finally {
      c.close(force: true);
    }
  }

  static const _chatGptBlocked = {'RU', 'BY', 'CN', 'HK', 'IR', 'KP', 'SY', 'CU', 'VE', 'AF', 'MO'};

  /// Returns (ip, countryCode) of the exit node.
  static Future<(String?, String?)> exitIp(int proxyPort, {Duration timeout = const Duration(seconds: 8)}) async {
    final c = HttpClient()
      ..findProxy = ((_) => 'PROXY 127.0.0.1:$proxyPort')
      ..connectionTimeout = timeout;
    try {
      final req = await c.getUrl(Uri.parse('https://one.one.one.one/cdn-cgi/trace')).timeout(timeout);
      final resp = await req.close().timeout(timeout);
      final body = await resp.transform(const SystemEncoding().decoder).join().timeout(timeout);
      final ip = RegExp(r'^ip=(.+)$', multiLine: true).firstMatch(body)?.group(1)?.trim();
      final loc = RegExp(r'^loc=([A-Z]{2})$', multiLine: true).firstMatch(body)?.group(1);
      return (ip, loc);
    } on Object {
      return (null, null);
    } finally {
      c.close(force: true);
    }
  }
}
