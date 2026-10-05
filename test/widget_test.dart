// Replaces the default `flutter create` widget test (which references MyApp).
import 'package:flutter_test/flutter_test.dart';
import 'package:kuputun/ui/l10n.dart';

void main() {
  test('l10n falls back to English, then to key', () {
    expect(const L10n('ru').t('connect'), 'Подключить');
    expect(const L10n('fa').t('sortSmart'), 'Smart Score');
    expect(const L10n('zh').t('unknown-key'), 'unknown-key');
    expect(const L10n('fa').rtl, isTrue);
  });
}
