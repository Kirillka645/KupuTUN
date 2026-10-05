# Сборка KupuTUN

## Требования
| Компонент | Версия |
|---|---|
| Flutter | 3.47.6 (Dart 3.13+) — минимум 3.44 (см. `pubspec.lock`) |
| Go | 1.26+ (см. `go/go.mod`) |
| Android | JDK 17–21, Android SDK 36, NDK 27, `gomobile` (ставится скриптом) |
| Linux | clang, cmake, ninja, pkg-config, libgtk-3-dev, libsecret-1-dev, libayatana-appindicator3-dev, libnotify-dev |
| Windows | Visual Studio 2022 (Desktop C++), MSYS2/mingw-w64 gcc для cgo |
| macOS | Xcode 15+, CLT |

## 1. Платформенные файлы
В репозитории уже лежат `android/` (вместе с Gradle wrapper) и `windows/`, поэтому
`flutter create` для них не нужен — сразу:
```bash
flutter pub get
```
`flutter create` остаётся нужным только для отсутствующих платформ (`linux`, `macos`)
и безопасен: существующие файлы он не перезаписывает.
```bash
flutter create --org dev.kuputun --project-name kuputun --platforms linux,macos .
```

## 2. Нативное ядро (Go)
```bash
scripts/build_go.sh android   # -> android/app/libs/kuputun.aar   (arm64, armv7, x86_64)
scripts/build_go.sh linux     # -> build/native/linux/libkuputun.so
scripts/build_go.sh windows   # -> build/native/windows/libkuputun.dll + wintun.dll
scripts/build_go.sh macos     # -> build/native/macos/libkuputun.dylib (universal)
```
Первый запуск выполнит `go mod tidy` и создаст `go/go.sum` — закоммитьте его, это фиксирует зависимости для воспроизводимых сборок.
Теги: `with_quic,with_utls,with_wireguard,with_gvisor` (Hysteria2/TUIC, uTLS, WireGuard, userspace-стек). Ядро без sing-box: `KUPUTUN_TAGS=... go build -tags nosingbox`, без Xray — `-tags noxray`.

## 3. Приложение
```bash
# Android
flutter build apk --release --split-per-abi
# Linux
flutter build linux --release && scripts/bundle_native.sh linux
sudo setcap cap_net_admin,cap_net_bind_service=+ep build/linux/x64/release/bundle/kuputun   # TUN без root
# Windows (TUN требует запуска от администратора)
flutter build windows --release && scripts/bundle_native.sh windows
# macOS (App Sandbox выключен в entitlements)
flutter build macos --release && MACOS_SIGN_IDENTITY="Developer ID Application: ..." scripts/bundle_native.sh macos
```

## 4. Тесты
```bash
flutter test                 # парсеры, подписки, deeplink, билдеры конфигов, статистика, Smart Score, сортировка
cd go && go vet ./...
```

## 5. Подпись Android в CI
Секреты репозитория: `ANDROID_KEYSTORE_B64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`. Без них релиз подписывается debug-ключом.

## 6. Релиз
`git tag v1.0.0 && git push --tags` → GitHub Actions собирает APK (по ABI + universal), Linux tar.gz, Windows zip, macOS zip и публикует релиз с `SHA256SUMS.txt`.

## Воспроизводимость
`-trimpath`, `-buildid=`, `-buildvcs=false`, `-mod=readonly`, закреплённые версии Flutter/Go в CI, `go.sum` и `pubspec.lock` в репозитории, `SOURCE_DATE_EPOCH` = время последнего коммита.

## Известные моменты
- API Xray-core и sing-box меняются между версиями: мост написан под Xray `v25.9.x` и sing-box `1.12.x`. При обновлении ядер проверяйте `go/bridge/*.go` (`go vet`).
- Xray TUN-inbound экспериментален и зависит от версии Xray; по умолчанию на десктопе используется sing-box TUN.
- SHA-256 архива wintun в `build_go.sh` проверяется — при обновлении версии wintun обновите хэш.
  `wintun.net` часто рвёт TLS-соединение по curl (ошибка 35); скрипт делает 4 попытки и
  автоматически переключается на `Invoke-WebRequest`. Можно задать другой зеркал через
  `KUPUTUN_WINTUN_URL`.
- Android: список приложений для split-tunnel строится по `<queries>` с `MAIN`/`LAUNCHER`
  (только запускаемые приложения), поэтому `QUERY_ALL_PACKAGES` не нужен и декларация для Google Play не требуется.
