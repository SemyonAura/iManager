# iManager

Нативный менеджер iOS-устройств для macOS на SwiftUI.  
A native SwiftUI iOS device manager for macOS.

iManager — графическая оболочка для [Sorvigolova/ipatool](https://github.com/Sorvigolova/ipatool).  
iManager is a GUI frontend for [Sorvigolova/ipatool](https://github.com/Sorvigolova/ipatool).

![macOS](https://img.shields.io/badge/macOS-12.0%2B-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-5.8-orange?logo=swift)
![UI](https://img.shields.io/badge/UI-SwiftUI-blue)
![Version](https://img.shields.io/badge/version-0.1.0-green)

---

## Русский

### Возможности

- **Устройства** — обнаружение iPhone/iPad через usbmuxd, USB/Wi-Fi подключение, статус сопряжения.
- **Обзор** — модель, iOS/сборка, UDID, серийный номер, активация, аппаратные данные, батарея, сеть, MAC-адреса, сопряжение, копирование сводки.
- **Приложения** — список установленных приложений, установка `.ipa`, пакетная установка нескольких `.ipa`, удаление приложений.
- **App Store** — поиск, покупки, выбор версии, загрузка `.ipa` через `ipatool`.
- **Загрузки** — очередь загрузок, прогресс, повтор, отмена, открытие в Finder.
- **Локализация** — русский и английский интерфейс, переключение в настройках/меню.
- **Нативный вид** — SwiftUI, без Electron и веб-обёрток.

### Требования

- macOS **12.0 Monterey** или новее.
- Command Line Tools for Xcode (`xcode-select --install`).
- Для работы с устройством: iPhone/iPad, кабель USB или синхронизация по Wi-Fi, доверие компьютеру на устройстве.

### Сборка

```bash
git clone https://github.com/SemyonAura/iManager.git
cd iManager
./build.sh
open build/iManager.app
```

`build.sh` компилирует проект напрямую через `swiftc`, собирает universal binary (`x86_64` + `arm64`), копирует ресурсы, подписывает ad-hoc и создаёт `build/iManager.app`.

### DMG

```bash
APP=build/iManager.app
OUT=build/iManager.dmg
STAGE=build/dmg-stage
rm -rf "$STAGE" "$OUT"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "iManager" -srcfolder "$STAGE" -ov -format UDZO "$OUT"
```

### Структура проекта

```text
Sources/iManager/
  App/        Точка входа, команды меню
  Models/     Модели устройств и данных
  Services/   usbmuxd, MobileDevice, AFC, App Store, загрузки, локализация
  Views/      SwiftUI-интерфейс
Resources/    Info.plist, иконка, ipatool, shim
Tools/        Вспомогательные утилиты
build.sh      Сборка .app без Xcode project
```

### App Store / ipatool

iManager — графическая оболочка для [ipatool (Sorvigolova fork)](https://github.com/Sorvigolova/ipatool). Бинарник поставляется в `Resources/bin/ipatool`.  
Перед входом и загрузкой iManager передаёт ipatool окружение устройства; при выходе из Apple ID локальная сессия ipatool очищается, чтобы следующий вход мог запросить 2FA.

> Используйте функцию загрузки только для приложений и аккаунтов, к которым у вас есть законный доступ. Соблюдайте условия Apple и применимое законодательство.

### Ограничения

- Некоторые данные недоступны без разблокировки устройства и доверия компьютеру.
- Установка/загрузка приложений зависит от состояния устройства, подписи IPA и правил Apple.
- Проект использует приватные фреймворки Apple (`MobileDevice.framework`) и может потребовать адаптации на будущих версиях macOS/iOS.

### Разработка

Локальные артефакты не коммитятся: `build/`, `.build/`, `.DS_Store`, `*.xcodeproj`, `xcuserdata/`.  
`BUILD.md` и локальные заметки также игнорируются `.gitignore`.

---

## English

### Features

- **Devices** — discovers iPhone/iPad over usbmuxd, shows USB/Wi-Fi connection and pairing state.
- **Overview** — model, iOS/build, UDID, serial number, activation, hardware details, battery, network, MAC addresses, pairing, and summary copy.
- **Apps** — installed app list, single `.ipa` install, batch `.ipa` install, app removal.
- **App Store** — search, purchases, version picker, `.ipa` download via `ipatool`.
- **Downloads** — download queue with progress, retry, cancel, and Reveal in Finder.
- **Localization** — Russian and English UI, switchable from settings/menu.
- **Native UI** — built with SwiftUI, no Electron/web wrapper.

### Requirements

- macOS **12.0 Monterey** or newer.
- Xcode Command Line Tools (`xcode-select --install`).
- For device features: iPhone/iPad, USB cable or Wi-Fi sync, and Trust This Computer on the device.

### Build

```bash
git clone https://github.com/SemyonAura/iManager.git
cd iManager
./build.sh
open build/iManager.app
```

`build.sh` compiles the app directly with `swiftc`, produces a universal binary (`x86_64` + `arm64`), copies resources, ad-hoc signs the bundle, and creates `build/iManager.app`.

### DMG

```bash
APP=build/iManager.app
OUT=build/iManager.dmg
STAGE=build/dmg-stage
rm -rf "$STAGE" "$OUT"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "iManager" -srcfolder "$STAGE" -ov -format UDZO "$OUT"
```

### Project Structure

```text
Sources/iManager/
  App/        App entry point and menu commands
  Models/     Device/data models
  Services/   usbmuxd, MobileDevice, AFC, App Store, downloads, localization
  Views/      SwiftUI interface
Resources/    Info.plist, icon, ipatool, shim
Tools/        Helper utilities
build.sh      Builds the .app without an Xcode project
```

### App Store / ipatool

iManager is a GUI frontend for [ipatool (Sorvigolova fork)](https://github.com/Sorvigolova/ipatool). The bundled binary is located at `Resources/bin/ipatool`.  
iManager provides the required device environment for ipatool and clears the local ipatool session on Apple ID sign-out so the next sign-in can request 2FA.

> Use download features only for apps/accounts you are legally authorized to access. Follow Apple terms and applicable laws.

### Limitations

- Some information requires the device to be unlocked and trusted.
- App install/download behavior depends on device state, IPA signing, and Apple rules.
- The project uses Apple private frameworks (`MobileDevice.framework`) and may need updates for future macOS/iOS releases.

### License

Add a `LICENSE` file if you want to publish this project under a specific license.
