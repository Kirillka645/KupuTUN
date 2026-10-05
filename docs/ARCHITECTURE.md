# Архитектура KupuTUN

## Слои (Clean Architecture)

```
┌────────────────────────── UI (Flutter) ───────────────────────────┐
│ ui/home  ui/servers  ui/settings  ui/import  ui/desktop(tray)       │
└───────────────▲──────────────────────────────────────────────────────┘
                │ Provider (ChangeNotifier)
┌───────────────┴──────────── app/AppState (use-cases) ──────────────┐
│ импорт, подписки, тесты, подключение, бэкап, уведомления, deeplink  │
└──▲──────────────▲────────────────▲───────────────▲──────────────────┘
   │              │                │               │
subscriptions/  tester/          routing/        data/
 link_parser     tester_service   presets         vault (AES-GCM + keystore)
 sub_parser      ping/speed       validator       history_db (SQLite)
 fetcher(HWID)   smart_score      geo_updater
 deeplink        sorter, bypass
   │              │                │
   └──────────────┴────────┬───────┘
                    core/ (домен + инфраструктура)
         models · config builders (Xray / sing-box) · engine
                           │
          CoreBridge ── MethodChannel (Android/iOS) ── Kotlin VpnService
                     └─ dart:ffi (desktop) ─────────── libkuputun (Go)
                                                         ├ Xray-core
                                                         ├ sing-box
                                                         └ tun2socks
```

Правило зависимостей: `ui → app → (subscriptions | tester | routing | data) → core`. `core` не знает о Flutter-виджетах; парсеры, билдеры конфигов, тестовая статистика и сортировка — чистый Dart и покрыты unit-тестами.

## Структура репозитория

```
kuputun/
├─ lib/
│  ├─ main.dart                       точка входа, deeplink-и, трей
│  ├─ app/app_state.dart              use-case слой, состояние приложения
│  ├─ core/
│  │  ├─ models/                      Server, Subscription, TestResult, RoutingProfile
│  │  ├─ config/                      CoreSettings, XrayConfigBuilder, SingboxConfigBuilder
│  │  ├─ engine/                      CoreBridge (FFI/MethodChannel), CoreManager, VpnPlatform, SystemProxy
│  │  └─ util/                        base64, страны/флаги, uuid
│  ├─ subscriptions/                  link_parser (+export/QR-маска), subscription_parser, fetcher, deeplink
│  ├─ tester/                         ping/TLS, speed, services, Smart Score, сортировка/фильтры, пул, bypass
│  ├─ routing/                        пресеты, валидатор правил, обновление geo-файлов
│  ├─ data/                           Vault (шифрование), BackupService, HistoryDb
│  └─ ui/                             экраны и виджеты, l10n
├─ go/                                нативный мост
│  ├─ bridge/                         StartInstance/StopInstance/FreePorts/Traffic/Tun2Socks (gomobile API)
│  └─ cmd/libkuputun/                 c-shared обёртка для desktop (Dart FFI)
├─ android/app/                       Gradle, Manifest, Kotlin: VpnService, QS tile, виджет, Keystore
├─ macos/Runner/*.entitlements        без App Sandbox (нужно для utun/системного прокси)
├─ test/                              unit-тесты парсеров, билдеров, тестера, сортировки
├─ scripts/                           build_go.sh, bundle_native.sh
├─ .github/workflows/ci.yml           тесты + сборки под все платформы + релиз по тегу
└─ docs/
```

## Ключевые решения (коротко)

1. **Конфиги генерирует Dart, Go только исполняет JSON.** Одна логика для всех платформ, всё тестируется без нативной сборки. Go-мост тонкий: запуск/остановка экземпляров по id, порты, счётчики, tun2socks.
2. **Несколько экземпляров ядра в одном процессе.** `main` — подключение пользователя, `test-*` — тестер, `tun` — TUN-обёртка sing-box, `subfetch` — фрагментированная загрузка подписки. Тесты не трогают активное подключение.
3. **Пакетный тест — почему быстрее Happ.** На 64 сервера поднимается один экземпляр Xray/sing-box с 64 HTTP-inbound → 64 outbound (routing по inboundTag). Стоимость старта ядра платится один раз; пробы идут через пул с лимитом потоков. Если один конфиг ломает старт, батч рекурсивно делится пополам — остальные серверы всё равно тестируются.
4. **Real delay = полный HTTP-запрос через прокси на свежем соединении** (как ощущает пользователь), TLS-handshake измеряется отдельно через CONNECT + RawSecureSocket.
5. **Smart Score по фиксированным кривым** (а не min-max по списку): оценки сравнимы между прогонами, выбросы не ломают рейтинг. Нет скорости — её вес перераспределяется.
6. **Автопереключение без разрыва:** при auto-switch и пуле Xray-серверов используется observatory + `leastPing` balancer прямо в ядре. Иначе — health-check и горячая замена только proxy-ядра (TUN/VpnService остаются).
7. **TUN:**
   - Android: VpnService → fd → tun2socks → SOCKS ядра. Своё приложение исключено из туннеля (нет петель), `::/0` заведён в туннель и блокируется (нет IPv6-утечек), DNS перехватывается ядром.
   - Desktop: sing-box TUN (auto_route + strict_route = kill switch). Для Xray-серверов — гибрид: Xray как proxy-ядро, sing-box держит TUN и split-routing, IP серверов исключены из маршрутов. Xray TUN — экспериментально.
8. **geosite/geoip:** Xray — `.dat` (runetfreedom, автообновление раз в 3 дня), sing-box — `.srs` rule-set из того же источника, поэтому оба ядра маршрутизируют одинаково.
9. **Хранение:** серверы/подписки/настройки — AES-256-GCM-блобы, ключ в OS keystore. История тестов — SQLite без секретов. Последний конфиг для QS-плитки/Always-on — отдельно зашифрован ключом Android Keystore.
10. **Подписки устойчивы к блокировкам:** напрямую → через активный VPN → через временное ядро с фрагментацией ClientHello → domain fronting.
11. **ID серверов переживают обновление подписки** (сопоставление по fingerprint), поэтому история и бейджи не теряются.
12. **Локализация без кодогенерации** — меньше шагов сборки, fallback EN → ключ.
