import 'dart:io';

import '../core/models/routing_profile.dart';

/// Downloads geoip.dat / geosite.dat for Xray (sing-box fetches rule-sets itself).
/// Atomic replace: download to *.tmp, verify size, then rename.
class GeoUpdater {
  final String assetDir;
  GeoUpdater(this.assetDir);

  static const maxAge = Duration(days: 3);

  Future<bool> needsUpdate() async {
    for (final f in ['geoip.dat', 'geosite.dat']) {
      final file = File('$assetDir/$f');
      if (!await file.exists()) return true;
      if (DateTime.now().difference(await file.lastModified()) > maxAge) return true;
    }
    return false;
  }

  /// [proxyPort]: download through the running core when direct access is blocked.
  Future<void> update(RoutingProfile p, {int? proxyPort}) async {
    await Directory(assetDir).create(recursive: true);
    await _download(Uri.parse(p.geoipUrl), 'geoip.dat', proxyPort);
    await _download(Uri.parse(p.geositeUrl), 'geosite.dat', proxyPort);
  }

  Future<void> _download(Uri url, String name, int? proxyPort) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    if (proxyPort != null) client.findProxy = (_) => 'PROXY 127.0.0.1:$proxyPort';
    final tmp = File('$assetDir/$name.tmp');
    try {
      final req = await client.getUrl(url);
      final resp = await req.close();
      if (resp.statusCode != 200) throw HttpException('HTTP ${resp.statusCode} for $url');
      final sink = tmp.openWrite();
      await resp.pipe(sink);
      if (await tmp.length() < 1024) throw const FileSystemException('downloaded geo file is too small');
      await tmp.rename('$assetDir/$name');
    } finally {
      client.close(force: true);
      if (await tmp.exists()) await tmp.delete();
    }
  }
}
