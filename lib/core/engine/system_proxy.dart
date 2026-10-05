import 'dart:io';

/// Sets / clears the OS-wide HTTP(S)+SOCKS proxy on desktop.
/// Decision: shell out to the platform's own tools (reg / networksetup /
/// gsettings + kwriteconfig) – no extra native code, easy to audit.
class SystemProxy {
  static Future<void> enable(int httpPort, int socksPort, {List<String> bypass = const ['localhost', '127.*', '10.*', '172.16.*', '192.168.*', '<local>']}) async {
    if (Platform.isWindows) {
      const key = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';
      await _run('reg', ['add', key, '/v', 'ProxyEnable', '/t', 'REG_DWORD', '/d', '1', '/f']);
      await _run('reg', ['add', key, '/v', 'ProxyServer', '/t', 'REG_SZ', '/d', '127.0.0.1:$httpPort', '/f']);
      await _run('reg', ['add', key, '/v', 'ProxyOverride', '/t', 'REG_SZ', '/d', bypass.join(';'), '/f']);
    } else if (Platform.isMacOS) {
      for (final svc in await _macServices()) {
        await _run('networksetup', ['-setwebproxy', svc, '127.0.0.1', '$httpPort']);
        await _run('networksetup', ['-setsecurewebproxy', svc, '127.0.0.1', '$httpPort']);
        await _run('networksetup', ['-setsocksfirewallproxy', svc, '127.0.0.1', '$socksPort']);
        await _run('networksetup', ['-setproxybypassdomains', svc, ...bypass.where((b) => b != '<local>')]);
      }
    } else if (Platform.isLinux) {
      await _run('gsettings', ['set', 'org.gnome.system.proxy', 'mode', 'manual']);
      for (final p in ['http', 'https']) {
        await _run('gsettings', ['set', 'org.gnome.system.proxy.$p', 'host', '127.0.0.1']);
        await _run('gsettings', ['set', 'org.gnome.system.proxy.$p', 'port', '$httpPort']);
      }
      await _run('gsettings', ['set', 'org.gnome.system.proxy.socks', 'host', '127.0.0.1']);
      await _run('gsettings', ['set', 'org.gnome.system.proxy.socks', 'port', '$socksPort']);
      await _run('kwriteconfig5', ['--file', 'kioslaverc', '--group', 'Proxy Settings', '--key', 'ProxyType', '1']);
      await _run('kwriteconfig5', ['--file', 'kioslaverc', '--group', 'Proxy Settings', '--key', 'httpProxy', 'http://127.0.0.1 $httpPort']);
      await _run('kwriteconfig5', ['--file', 'kioslaverc', '--group', 'Proxy Settings', '--key', 'httpsProxy', 'http://127.0.0.1 $httpPort']);
      await _run('kwriteconfig5', ['--file', 'kioslaverc', '--group', 'Proxy Settings', '--key', 'socksProxy', 'socks://127.0.0.1 $socksPort']);
    }
  }

  static Future<void> disable() async {
    if (Platform.isWindows) {
      await _run('reg', ['add', r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings', '/v', 'ProxyEnable', '/t', 'REG_DWORD', '/d', '0', '/f']);
    } else if (Platform.isMacOS) {
      for (final svc in await _macServices()) {
        await _run('networksetup', ['-setwebproxystate', svc, 'off']);
        await _run('networksetup', ['-setsecurewebproxystate', svc, 'off']);
        await _run('networksetup', ['-setsocksfirewallproxystate', svc, 'off']);
      }
    } else if (Platform.isLinux) {
      await _run('gsettings', ['set', 'org.gnome.system.proxy', 'mode', 'none']);
      await _run('kwriteconfig5', ['--file', 'kioslaverc', '--group', 'Proxy Settings', '--key', 'ProxyType', '0']);
    }
  }

  static Future<List<String>> _macServices() async {
    final r = await Process.run('networksetup', ['-listallnetworkservices']);
    return r.stdout
        .toString()
        .split('\n')
        .skip(1)
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && !e.startsWith('*'))
        .toList();
  }

  /// Missing tools (e.g. no KDE) are ignored on purpose.
  static Future<void> _run(String exe, List<String> args) async {
    try {
      await Process.run(exe, args);
    } on ProcessException {
      return;
    }
  }
}
