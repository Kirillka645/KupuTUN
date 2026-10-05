import 'package:flutter_test/flutter_test.dart';
import 'package:kuputun/app/app_state.dart';
import 'package:kuputun/core/models/subscription.dart';
import 'package:kuputun/subscriptions/stock_subscriptions.dart';
import 'package:kuputun/ui/widgets/format.dart';

void main() {
  test('mirrors split by |', () {
    const s = Subscription(id: 'a', url: ' https://a/x.txt | https://b/y.txt|', title: 't');
    expect(s.mirrors, ['https://a/x.txt', 'https://b/y.txt']);
    expect(s.displayHost, 'a');
  });

  test('stock subscriptions are https mirror lists', () {
    expect(StockSubscriptions.all, hasLength(3));
    for (final st in StockSubscriptions.all) {
      final m = Subscription(id: 'x', url: st.url, title: st.title).mirrors;
      expect(m.length, greaterThanOrEqualTo(3));
      expect(m.every((u) => u.startsWith('https://')), isTrue);
      expect(StockSubscriptions.of(st.url), same(st));
    }
  });

  test('leading flag is stripped from display name', () {
    expect(displayServerName('🇳🇱 The Netherlands'), 'The Netherlands');
    expect(displayServerName('🇩🇪|Frankfurt'), 'Frankfurt');
    expect(displayServerName('Moscow 🇷🇺'), 'Moscow 🇷🇺');
    expect(displayServerName('🇷🇺'), '🇷🇺');
  });

  test('tile action persists in UiSettings', () {
    const u = UiSettings(tileAction: TileAction.connectBest);
    expect(UiSettings.fromJson(u.toJson()).tileAction, TileAction.connectBest);
    expect(UiSettings.fromJson(const {}).tileAction, TileAction.toggleLast);
  });
}
