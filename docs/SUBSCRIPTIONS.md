# Подписки и deeplink-и

## Тело подписки
- base64 списка ссылок (std/url-safe, с/без паддинга) или plain-текст;
- JSON: объект или массив полных конфигов Xray (`outbounds[].protocol`) или sing-box (`outbounds[].type`); сохраняется целиком;
- комментарии метаданных в теле: `#profile-title: base64:0JzQvtC5`, `#profile-update-interval: 6`, `#announce: ...` (заголовки HTTP имеют приоритет).

## Заголовки
| Заголовок | Значение |
|---|---|
| `subscription-userinfo` | `upload=..; download=..; total=..; expire=<unix>` |
| `profile-title` | строка или `base64:...` |
| `profile-update-interval` | часы |
| `support-url`, `profile-web-page-url` | ссылки поддержки/продления |
| `announce` | объявление (поддержка `base64:`) |
| `routing-enable`, `routing` | включить и передать профиль `happ://routing/...` / `kuputun://routing/...` |
| `ping-type` | `tcp` / `icmp` / `proxy` / `proxy-head` |
| `subscriptions-sort-type` | `ping` / `name` / `none` |
| `fragmentation-enable/-packets/-length/-interval/-maxsplit` | фрагментация ClientHello |
| `noises-enable/-type/-packet/-delay` | UDP noises |

## Что отправляет клиент
`User-Agent: KupuTUN/<ver> (<os> <ver>) Happ-compatible`, `x-hwid` (случайный id устройства, хранится зашифрованно), `x-device-os`, `x-ver-os`, `x-device-model`, `x-app-version`. HWID можно отключить (`FetchOptions.sendHwid`).

## Deeplink-и
- `kuputun://add/<urlencoded url>[#name]` — добавить подписку (принимается и base64 URL)
- `kuputun://import/<ссылка | base64-список>` — импорт серверов
- `kuputun://routing/add/<base64 json>` — добавить профиль; `.../onadd/...` — добавить и включить
- `happ://add/...`, `happ://routing/add|onadd/...` — совместимость с Happ
- Прямые `vless://`, `vmess://`, `trojan://`, `ss://`, `hy2://`, `tuic://` — тоже открываются приложением.
