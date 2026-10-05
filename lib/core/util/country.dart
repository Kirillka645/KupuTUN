/// Country detection for server names.
///
/// Decision: flag emoji is the most reliable signal in real subscriptions,
/// then ISO codes in brackets / as separate tokens, then country names.
/// GeoIP of the exit IP (from the tester) overrides this later.
class CountryDetector {
  static const _names = <String, String>{
    'russia': 'RU', 'россия': 'RU', 'рф': 'RU', 'moscow': 'RU', 'москва': 'RU',
    'germany': 'DE', 'германия': 'DE', 'frankfurt': 'DE', 'франкфурт': 'DE',
    'netherlands': 'NL', 'нидерланды': 'NL', 'amsterdam': 'NL', 'амстердам': 'NL', 'holland': 'NL',
    'finland': 'FI', 'финляндия': 'FI', 'helsinki': 'FI',
    'sweden': 'SE', 'швеция': 'SE', 'stockholm': 'SE',
    'poland': 'PL', 'польша': 'PL', 'warsaw': 'PL',
    'france': 'FR', 'франция': 'FR', 'paris': 'FR',
    'united kingdom': 'GB', 'great britain': 'GB', 'england': 'GB', 'london': 'GB', 'великобритания': 'GB', 'англия': 'GB',
    'usa': 'US', 'united states': 'US', 'america': 'US', 'сша': 'US', 'new york': 'US',
    'canada': 'CA', 'канада': 'CA',
    'turkey': 'TR', 'türkiye': 'TR', 'турция': 'TR', 'istanbul': 'TR',
    'kazakhstan': 'KZ', 'казахстан': 'KZ', 'almaty': 'KZ',
    'latvia': 'LV', 'латвия': 'LV', 'riga': 'LV',
    'lithuania': 'LT', 'литва': 'LT',
    'estonia': 'EE', 'эстония': 'EE', 'tallinn': 'EE',
    'japan': 'JP', 'япония': 'JP', 'tokyo': 'JP',
    'singapore': 'SG', 'сингапур': 'SG',
    'hong kong': 'HK', 'гонконг': 'HK',
    'korea': 'KR', 'корея': 'KR', 'seoul': 'KR',
    'india': 'IN', 'индия': 'IN',
    'uae': 'AE', 'emirates': 'AE', 'оаэ': 'AE', 'dubai': 'AE',
    'switzerland': 'CH', 'швейцария': 'CH',
    'austria': 'AT', 'австрия': 'AT', 'vienna': 'AT',
    'italy': 'IT', 'италия': 'IT', 'milan': 'IT',
    'spain': 'ES', 'испания': 'ES', 'madrid': 'ES',
    'czech': 'CZ', 'чехия': 'CZ', 'prague': 'CZ',
    'ukraine': 'UA', 'украина': 'UA',
    'georgia': 'GE', 'грузия': 'GE',
    'armenia': 'AM', 'армения': 'AM',
    'serbia': 'RS', 'сербия': 'RS',
    'moldova': 'MD', 'молдова': 'MD',
    'romania': 'RO', 'румыния': 'RO',
    'bulgaria': 'BG', 'болгария': 'BG',
    'israel': 'IL', 'израиль': 'IL',
    'iran': 'IR', 'иран': 'IR',
    'china': 'CN', 'китай': 'CN',
    'brazil': 'BR', 'бразилия': 'BR',
    'australia': 'AU', 'австралия': 'AU',
  };

  static const _codes = {
    'RU', 'DE', 'NL', 'FI', 'SE', 'PL', 'FR', 'GB', 'UK', 'US', 'CA', 'TR', 'KZ', 'LV', 'LT', 'EE', 'JP', 'SG',
    'HK', 'KR', 'IN', 'AE', 'CH', 'AT', 'IT', 'ES', 'CZ', 'UA', 'GE', 'AM', 'RS', 'MD', 'RO', 'BG', 'IL', 'IR',
    'CN', 'BR', 'AU', 'NO', 'DK', 'BE', 'PT', 'IE', 'HU', 'GR', 'BY', 'UZ', 'KG', 'AZ', 'TW', 'VN', 'TH', 'MY',
    'ID', 'PH', 'MX', 'AR', 'CL', 'ZA', 'EG', 'SA', 'CY', 'LU', 'IS', 'SK', 'SI', 'HR', 'MT', 'AL', 'MK',
  };

  /// Returns ISO 3166-1 alpha-2 code or null.
  static String? detect(String name) {
    final flag = fromFlag(name);
    if (flag != null) return flag;
    for (final m in RegExp(r'(?:^|[^A-Za-z])([A-Z]{2})(?=$|[^A-Za-z])').allMatches(name)) {
      final c = m.group(1)!;
      if (_codes.contains(c)) return c == 'UK' ? 'GB' : c;
    }
    final lower = name.toLowerCase();
    for (final e in _names.entries) {
      if (lower.contains(e.key)) return e.value;
    }
    return null;
  }

  /// Extracts the first regional-indicator pair (🇩🇪 -> DE).
  static String? fromFlag(String s) {
    final runes = s.runes.toList();
    for (var i = 0; i + 1 < runes.length; i++) {
      final a = runes[i], b = runes[i + 1];
      if (_isRi(a) && _isRi(b)) {
        return String.fromCharCodes([a - 0x1F1E6 + 65, b - 0x1F1E6 + 65]);
      }
    }
    return null;
  }

  static bool _isRi(int r) => r >= 0x1F1E6 && r <= 0x1F1FF;

  /// DE -> 🇩🇪
  static String flagOf(String? code) {
    if (code == null || code.length != 2) return '🌐';
    final up = code.toUpperCase();
    return String.fromCharCodes([up.codeUnitAt(0) - 65 + 0x1F1E6, up.codeUnitAt(1) - 65 + 0x1F1E6]);
  }
}
