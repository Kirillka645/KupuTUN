# Схемы данных

Все модели — иммутабельные Dart-классы с `toJson/fromJson` (`lib/core/models`). Серверы, подписки, профили маршрутизации и настройки хранятся в зашифрованном `Vault` (JSON → AES-256-GCM). Результаты тестов — в SQLite.

## Server (`server.dart`)

| Поле | Тип | Описание |
|---|---|---|
| id | String (uuid) | стабильный id; сохраняется при обновлении подписки |
| subscriptionId | String? | null = добавлен вручную |
| name | String | имя из `#fragment`/`ps`/`remarks` |
| protocol | enum | vless, vmess, trojan, shadowsocks, socks, hysteria2, tuic, wireguard |
| address, port | String, int | хост/IP (IPv6 без скобок) |
| credential | String | UUID / пароль / username / private key |
| secret | String? | метод SS, пароль SOCKS/TUIC |
| params | Map<String,String> | все параметры ссылки как есть: type, security, sni, fp, alpn, pbk, sid, spx, flow, path, host, serviceName, mode, extra, obfs, ech, … ; `json`/`jsonCore` для импортированных JSON-конфигов |
| rawLink | String? | исходная ссылка |
| countryCode | String? | ISO-2 (флаг → код → название) |
| sortIndex | int | порядок «как в подписке» |
| core | enum | auto / xray / singbox (auto: hy2/tuic → sing-box) |
| favorite | bool | |

`fingerprint = protocol|address|port|credential|type|path|serviceName` — ключ дедупликации.

## Subscription (`subscription.dart`)

| Поле | Тип | Источник |
|---|---|---|
| id, url, title | String | `profile-title` (поддержка `base64:`) |
| updateInterval | Duration | `profile-update-interval` (часы) |
| lastUpdated | DateTime? | |
| userInfo | {upload, download, total, expire} | `subscription-userinfo` |
| supportUrl / webPageUrl | String? | `support-url` / `profile-web-page-url` (кнопка «Продлить») |
| announce | String? | `announce` |
| routingEnabled / routingDeeplink | bool? / String? | `routing-enable` / `routing` |
| pingType | String? | `ping-type` (tcp, icmp, proxy, proxy-head) |
| sortType | enum | `subscriptions-sort-type` |
| fragment | {enabled, packets, length, interval, maxSplit} | `fragmentation-*` |
| noises | {enabled, type, packet, delay} | `noises-*` |
| autoUpdate, collapsed, order | | UI |
| extra | Map | все неизвестные ключи (вкл. `fronting-host`) |

## TestResult (`test_result.dart`) — таблица `test_results`

```sql
CREATE TABLE test_results(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  server_id TEXT NOT NULL,
  ts INTEGER NOT NULL,          -- epoch ms
  mode TEXT NOT NULL,           -- tcp | icmp | realDelay
  samples TEXT,                 -- "120,-1,118" (-1 = потеря)
  median_ms INTEGER, jitter_ms REAL, loss REAL,
  tls_ms INTEGER,
  down_mbps REAL, up_mbps REAL, bytes INTEGER,
  exit_ip TEXT, exit_country TEXT,
  services TEXT,                -- "YouTube=1,Netflix=0"
  error TEXT
);
CREATE INDEX idx_results_server_ts ON test_results(server_id, ts DESC);
```
Хранится не более 50 записей на сервер. Бейджи: **стабильный** — ≥5 прогонов, средние потери < 5 %, разброс медиан p90−p10 < max(50 мс, 50 % p10); **часто падает** — ≥30 % неудачных прогонов (из ≥3).

## RoutingProfile (`routing_profile.dart`)

```jsonc
{
  "id": "builtin-ru", "name": "Россия direct",
  "mode": "rule",                      // global | rule | direct
  "defaultAction": "proxy",            // proxy | direct | block
  "rules": [
    {"type": "geosite", "values": ["category-ads-all"], "action": "block", "enabled": true},
    {"type": "geoip",   "values": ["ru", "private"],    "action": "direct"}
    // type: domain | domainSuffix | domainKeyword | regex | geosite | ip | geoip | process | package | port | protocol
  ],
  "dns": {
    "remote": {"protocol": "doh", "address": "https://1.1.1.1/dns-query"},
    "direct": {"protocol": "doh", "address": "https://77.88.8.8/dns-query"},
    "fakeIp": false, "blockLeaks": true, "hosts": ["router.lan=192.168.1.1"]
  },
  "geoipUrl": "...geoip.dat", "geositeUrl": "...geosite.dat"
}
```
Импорт/экспорт: `kuputun://routing/add/<base64(json)>`; также принимается Happ-формат (`Name`, `GlobalProxy`, `DirectSites`, `DirectIp`, `ProxySites`, `BlockSites`, `RemoteDNS*`, `DomesticDNS*`, `Geoipurl`, `Geositeurl`).
