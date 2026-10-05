/// Built-in public subscriptions added on first launch (can be deleted and
/// restored from Settings). Each entry lists mirrors separated by `|`; the
/// fetcher races them, so whichever mirror is reachable on the current
/// network (incl. RU-hosted gitverse/hub.mos.ru under whitelists) wins.
class StockSubscription {
  final String title;
  final String url;
  const StockSubscription(this.title, this.url);
}

class StockSubscriptions {
  static const all = <StockSubscription>[
    StockSubscription(
      'Белые списки · Mobile',
      'https://gitlab.com/igareck/vpn-configs-for-russia/raw/main/Vless-Reality-White-Lists-Rus-Mobile.txt'
          '|https://codeberg.org/igareck/vpn-configs-for-russia/raw/branch/main/Vless-Reality-White-Lists-Rus-Mobile.txt'
          '|https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/main/Vless-Reality-White-Lists-Rus-Mobile.txt'
          '|https://raw.githack.com/igareck/vpn-configs-for-russia/main/Vless-Reality-White-Lists-Rus-Mobile.txt',
    ),
    StockSubscription(
      'Белые списки · Universal',
      'https://hub.mos.ru/zieng2/wl/raw/main/list_universal.txt'
          '|https://gitverse.ru/api/repos/zieng2/wl/raw/branch/master/list_universal.txt'
          '|https://raw.githubusercontent.com/zieng2/wl/main/vless_universal.txt'
          '|https://codeberg.org/zieng2/wl/raw/branch/main/vless_universal.txt'
          '|https://gitlab.com/zieng2/wl/raw/main/vless_universal.txt',
    ),
    StockSubscription(
      'Чёрные списки · Mobile',
      'https://gitlab.com/igareck/vpn-configs-for-russia/raw/main/BLACK_VLESS_RUS_mobile.txt'
          '|https://codeberg.org/igareck/vpn-configs-for-russia/raw/branch/main/BLACK_VLESS_RUS_mobile.txt'
          '|https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/main/BLACK_VLESS_RUS_mobile.txt'
          '|https://raw.githack.com/igareck/vpn-configs-for-russia/main/BLACK_VLESS_RUS_mobile.txt',
    ),
  ];

  /// Built-in entry for this URL (stock lists keep their short titles —
  /// the upstream `profile-title` is long and noisy).
  static StockSubscription? of(String url) {
    for (final s in all) {
      if (s.url == url) return s;
    }
    return null;
  }
}
