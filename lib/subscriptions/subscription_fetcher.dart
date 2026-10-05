import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/models/subscription.dart';
import 'subscription_parser.dart';

/// Device identity sent to panels that limit devices per subscription
/// (Remnawave / Marzban forks / Happ-compatible panels).
class DeviceIdentity {
  final String hwid; // random, generated once, stored encrypted
  final String os; // Android | Windows | macOS | Linux | iOS
  final String osVersion;
  final String model;
  final String appVersion;
  const DeviceIdentity({required this.hwid, required this.os, required this.osVersion, required this.model, required this.appVersion});

  Map<String, String> headers({bool sendHwid = true}) => {
        'User-Agent': 'KupuTUN/$appVersion ($os $osVersion) Happ-compatible',
        if (sendHwid) 'x-hwid': hwid,
        if (sendHwid) 'x-device-os': os,
        if (sendHwid) 'x-ver-os': osVersion,
        if (sendHwid) 'x-device-model': model,
        'x-app-version': appVersion,
        'Accept': '*/*',
      };
}

/// How to reach the subscription server when it is blocked.
class FetchOptions {
  /// Send the request to this host (CDN front) with `Host:` set to the real host.
  final String? frontingHost;

  /// Local HTTP proxy port (e.g. a temporary core with fragmented freedom
  /// outbound, or the running VPN core). null = direct.
  final int? proxyPort;
  final Duration timeout;
  final bool sendHwid;
  const FetchOptions({this.frontingHost, this.proxyPort, this.timeout = const Duration(seconds: 20), this.sendHwid = true});
}

class SubscriptionFetchException implements Exception {
  final String message;
  final int? statusCode;
  SubscriptionFetchException(this.message, [this.statusCode]);
  @override
  String toString() => statusCode == null ? message : 'HTTP $statusCode: $message';
}

class SubscriptionFetcher {
  final DeviceIdentity identity;
  SubscriptionFetcher(this.identity);

  /// Downloads and parses a subscription; returns parsed servers + metadata.
  ///
  /// `sub.url` may hold several mirrors separated by `|` (same list on
  /// GitHub / GitLab / Codeberg / RU-hosted git). All mirrors are requested
  /// in parallel and the first one that returns a *valid* list wins, so a
  /// blocked, rate-limited (429) or captcha (HTML) mirror never stalls the update.
  Future<ParsedSubscription> fetch(Subscription sub, {FetchOptions options = const FetchOptions()}) {
    final urls = sub.mirrors;
    if (urls.isEmpty) return Future.error(SubscriptionFetchException('empty URL'));
    if (urls.length == 1) return _fetchOne(urls.first, sub, options);
    final done = Completer<ParsedSubscription>();
    final errors = <String>[];
    for (final u in urls) {
      _fetchOne(u, sub, options).then((p) {
        if (!done.isCompleted) done.complete(p);
      }, onError: (Object e) {
        errors.add('${Uri.tryParse(u)?.host ?? u}: $e');
        if (errors.length == urls.length && !done.isCompleted) {
          done.completeError(SubscriptionFetchException('all ${urls.length} mirrors failed — ${errors.join('; ')}'));
        }
      });
    }
    return done.future;
  }

  Future<ParsedSubscription> _fetchOne(String url, Subscription sub, FetchOptions options) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) throw SubscriptionFetchException('bad URL: $url');
    final (body, headers) = await fetchRaw(uri, options: options);
    final head = body.trimLeft();
    final lower = head.length > 300 ? head.substring(0, 300).toLowerCase() : head.toLowerCase();
    if (lower.startsWith('<!doctype html') || lower.startsWith('<html') || lower.contains('<head>')) {
      throw SubscriptionFetchException('got an HTML page instead of a list (captcha / block page)');
    }
    final parsed = SubscriptionParser.parse(body, headers: headers, subscriptionId: sub.id);
    if (parsed.servers.isEmpty) {
      throw SubscriptionFetchException(
          parsed.errors.isEmpty ? 'subscription is empty' : 'no valid servers: ${parsed.errors.first}');
    }
    return parsed;
  }

  Future<(String, Map<String, String>)> fetchRaw(Uri uri, {FetchOptions options = const FetchOptions()}) async {
    final client = HttpClient()
      ..connectionTimeout = options.timeout
      ..idleTimeout = const Duration(seconds: 5)
      ..autoUncompress = true;
    if (options.proxyPort != null) {
      client.findProxy = (_) => 'PROXY 127.0.0.1:${options.proxyPort}';
    }
    try {
      var target = uri;
      if (options.frontingHost != null && options.frontingHost!.isNotEmpty) {
        target = uri.replace(host: options.frontingHost);
      }
      final req = await client.getUrl(target).timeout(options.timeout);
      identity.headers(sendHwid: options.sendHwid).forEach(req.headers.set);
      if (target.host != uri.host) req.headers.host = uri.host;
      req.followRedirects = true;
      req.maxRedirects = 5;
      final resp = await req.close().timeout(options.timeout);
      final body = await resp.transform(utf8.decoder).join().timeout(options.timeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw SubscriptionFetchException(body.length > 200 ? body.substring(0, 200) : body, resp.statusCode);
      }
      final headers = <String, String>{};
      resp.headers.forEach((name, values) => headers[name.toLowerCase()] = values.join(', '));
      return (body, headers);
    } on TimeoutException {
      throw SubscriptionFetchException('timeout after ${options.timeout.inSeconds}s');
    } on SocketException catch (e) {
      throw SubscriptionFetchException('network error: ${e.message}');
    } on HandshakeException catch (e) {
      throw SubscriptionFetchException('TLS error (try fragmentation/fronting): ${e.message}');
    } finally {
      client.close(force: true);
    }
  }
}
