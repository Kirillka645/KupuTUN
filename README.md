# KupuTUN

Быстрый, «умный» и открытый прокси/VPN-клиент на **Xray-core** и **sing-box** для Android (+TV), Windows, macOS и Linux. Позже — iOS/tvOS.
Совместим с форматом подписок Happ. Главная фишка — умное тестирование серверов: пакетный real-delay тест, TLS-handshake, джиттер и потери, скорость ↓/↑ с живым графиком, Smart Score и автопереключение.

**Лицензия:** GPL-3.0 · **Телеметрия:** отсутствует · **Данные:** только локально и в зашифрованном виде.

## Возможности

| Область | Что есть |
|---|---|
| Протоколы | VLESS (Reality, Vision, XHTTP, gRPC, WS, HTTPUpgrade), VMess, Trojan, Shadowsocks (вкл. 2022), SOCKS5, Hysteria2, TUIC, WireGuard |
| Импорт | буфер, QR (камера и картинка), файл, deeplink `kuputun://`/`happ://`, ручной редактор, JSON-конфиги Xray/sing-box |
| Подписки | base64/plain/JSON, заголовки Happ (`subscription-userinfo`, `profile-title`, `profile-update-interval`, `support-url`, `announce`, `routing-enable`, `routing`, `ping-type`, `subscriptions-sort-type`, fragmentation/noises), комментарии `#key: value`, HWID-заголовки, фоллбэки загрузки: напрямую → через VPN → фрагментация → fronting |
| Тестер | TCP / ICMP / real delay (+TLS-handshake), 16 потоков, 3 замера, медиана/джиттер/потери; один экземпляр ядра на 64 сервера; бисекция при битом конфиге |
| Скорость | download/upload, режимы «быстрый» (5 с) и «точный» (15 с), живой график, расход трафика показывается заранее |
| Сортировка/фильтры | пинг, скорость, джиттер, страна, алфавит, «как в подписке», Smart Score; недоступные — вниз и серым; фильтры страна/протокол/рабочие/пинг/скорость/поиск |
| Автовыбор | «Лучший сервер», auto-switch через Xray observatory + leastPing balancer (без разрыва) или Dart-failover с горячей заменой ядра |
| История | SQLite, мини-графики, бейджи «стабильный» / «часто падает» |
| Сервисы | YouTube, Telegram, Instagram, ChatGPT, Netflix + выходной IP и страна |
| Маршрутизация | Global/Rule/Direct, пресет «Россия direct», GeoIP/GeoSite, домены, IP, процессы, приложения (Android split-tunnel), DoH/DoT/DoQ, FakeIP, раздельные DNS, защита от утечек |
| Обход | фрагментация ClientHello, noises, mux, uTLS, ECH, «Автоподбор обхода», выбор самого быстрого IP сервера |
| UX | M3, тёмная/светлая, акцент, RU/EN/FA/ZH, QS-плитка и виджет Android, трей на десктопе, Always-on, автоподключение (запуск / недоверенный Wi-Fi) |
| Безопасность | Keystore/Keychain/DPAPI + AES-256-GCM, kill switch, блок IPv6, зашифрованный бэкап (PBKDF2 310k + AES-GCM) |

## Документация

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — архитектура, структура репозитория, ключевые решения
- [docs/DATA_MODELS.md](docs/DATA_MODELS.md) — схемы Server, Subscription, TestResult, RoutingProfile
- [docs/SUBSCRIPTIONS.md](docs/SUBSCRIPTIONS.md) — формат подписок и deeplink-ов (совместимость с Happ)
- [docs/ROADMAP.md](docs/ROADMAP.md) — план MVP → v1.0
- [docs/BUILD.md](docs/BUILD.md) — сборка под все платформы

## Быстрый старт (разработка)

```bash
flutter create --org dev.kuputun --project-name kuputun --platforms android,linux,windows,macos .
scripts/build_go.sh linux        # или android / windows / macos
flutter test
flutter run -d linux
scripts/bundle_native.sh linux   # для release-бандла
```
