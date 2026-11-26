import Foundation
import Combine

// MARK: - Язык интерфейса

enum AppLanguage: String, CaseIterable, Identifiable {
    case ru
    case en

    var id: String { rawValue }

    /// Название языка всегда показывается на самом языке.
    var title: String {
        switch self {
        case .ru: return "Русский"
        case .en: return "English"
        }
    }

    var subtitle: String {
        switch self {
        case .ru: return "Русский язык"
        case .en: return "English language"
        }
    }

    var locale: Locale {
        Locale(identifier: self == .ru ? "ru_RU" : "en_US")
    }
}

// MARK: - Менеджер локализации

/// Переводит строки во время выполнения. Ключом служит русская строка,
/// поэтому словарь легко дополнять: при отсутствии перевода показывается
/// исходный текст.
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    static let storageKey = "appLanguage"

    @Published var language: AppLanguage {
        didSet {
            guard oldValue != language else { return }
            UserDefaults.standard.set(language.rawValue, forKey: Self.storageKey)
        }
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: Self.storageKey) ?? AppLanguage.ru.rawValue
        language = AppLanguage(rawValue: saved) ?? .ru
    }

    var isEnglish: Bool { language == .en }

    var locale: Locale { language.locale }

    func text(_ key: String) -> String {
        guard language == .en else { return key }
        return Self.english[key] ?? key
    }

    // MARK: Словарь

    private static let english: [String: String] = [
        // Общие
        "Настройки": "Settings",
        "Настройки…": "Settings…",
        "Настройки приложения": "App Settings",
        "Язык": "Language",
        "Язык интерфейса": "Interface Language",
        "Выберите язык интерфейса. Изменения применяются сразу.": "Choose the interface language. Changes apply immediately.",
        "Изменения применяются сразу.": "Changes apply immediately.",
        "Интерфейс": "Interface",
        "Внешний вид": "Appearance",
        "О приложении": "About",
        "Версия": "Version",
        "Закрыть": "Close",
        "Отмена": "Cancel",
        "Готово": "Done",
        "Да": "Yes",
        "Нет": "No",
        "Нет данных": "No data",
        "Неизвестно": "Unknown",
        "Обновить": "Refresh",
        "Повторить": "Retry",
        "Удалить": "Delete",
        "Создать": "Create",
        "Переименовать": "Rename",
        "Открыть": "Open",
        "В очереди": "Queued",

        // Приложение и меню
        "Устройство": "Device",
        "Обновить список": "Refresh Device List",
        "Настройки и язык": "Settings & Language",
        "iManager — менеджер iOS-устройств": "iManager — iOS device manager",
        "Русский": "Русский",
        "English": "English",

        // Боковая панель
        "Устройства": "Devices",
        "Инструменты": "Tools",
        "Загрузки": "Downloads",
        "Загрузки (%d)": "Downloads (%d)",
        "Состояние": "Status",
        "Поиск устройств…": "Searching for devices…",
        "Ожидание подключения": "Waiting for connection",
        "Обнаружено: %d": "Found: %d",
        "Обновлено: %@": "Updated: %@",
        "Нет подключённых устройств": "No devices connected",
        "Подключите iPhone или iPad по USB либо включите синхронизацию по Wi-Fi.": "Connect an iPhone or iPad via USB, or enable Wi-Fi syncing.",
        "Устройства не найдены": "No devices found",

        // Разделы устройства
        "Обзор": "Overview",
        "Файлы": "Files",
        "Приложения": "Apps",
        "Диагностика": "Diagnostics",
        "Раздел": "Section",
        "Перечитать сведения об устройстве": "Reload device information",

        // Сведения об устройстве
        "Сведения об устройстве": "Device Information",
        "Данные получены от устройства": "Data received from the device",
        "Доступны только базовые данные usbmuxd": "Only basic usbmuxd data is available",
        "Модель": "Model",
        "Версия iOS": "iOS Version",
        "Сборка": "Build",
        "Подключение": "Connection",
        "Серийный номер": "Serial Number",
        "Аккумулятор": "Battery",
        "Оперативная память": "Memory",
        "Доступ и сопряжение": "Access & Pairing",
        "Pairing открывает доступ к сервисам устройства": "Pairing grants access to device services",
        "Ограниченный доступ": "Limited Access",
        "Не удалось получить сведения об устройстве. Разблокируйте iPhone или iPad, подтвердите доверие этому компьютеру и нажмите «Обновить».": "Could not retrieve device information. Unlock the iPhone or iPad, trust this computer, and tap Refresh.",
        "iOS-устройство": "iOS Device",
        "Неизвестная модель": "Unknown Model",

        // Сопряжение
        "Устройство сопряжено": "Device Paired",
        "Доверенная связь установлена. Доступны сервисы устройства, включая installation_proxy.": "A trusted connection is established. Device services, including installation_proxy, are available.",
        "Проверка сопряжения…": "Checking pairing…",
        "Ожидание подтверждения": "Waiting for Confirmation",
        "Разблокируйте устройство и нажмите «Доверять» на его экране.": "Unlock the device and tap Trust on its screen.",
        "Требуется сопряжение": "Pairing Required",
        "Чтобы открыть доступ к сервисам устройства и списку приложений, подтвердите доверие этому компьютеру.": "To access device services and the app list, trust this computer.",
        "Сопрячь устройство": "Pair Device",
        "Сопряжение не удалось": "Pairing Failed",
        "Повторить сопряжение": "Retry Pairing",
        "Сопряжено": "Paired",
        "Не сопряжено": "Not Paired",
        "Сопряжение…": "Pairing…",
        "Ошибка pairing": "Pairing Error",
        "Проверка pairing": "Checking Pairing",

        // Хранилище
        "Хранилище": "Storage",
        "%@ из %@": "%@ of %@",
        "Занято: %@": "Used: %@",
        "Доступно: %@": "Available: %@",
        "В т.ч. вытесняемые данные: %@": "Including purgeable: %@",
        "Доступно — как в iOS: свободное место плюс вытесняемые данные.": "Available — same as iOS: free space plus purgeable data.",
        "Как в iOS: доступно = свободное + вытесняемые данные": "Same as iOS: available = free + purgeable data",
        "Всего": "Total",
        "Занято": "Used",
        "Доступно": "Available",
        "Свободно (без вытесняемых)": "Free (excluding purgeable)",
        "Вытесняемые данные": "Purgeable Data",
        "Системный раздел": "System Partition",
        "Нет данных о хранилище": "No Storage Data",
        "Разблокируйте устройство и нажмите «Обновить».": "Unlock the device and tap Refresh.",

        // Приложения
        "Список ещё не загружен": "The list hasn't loaded yet",
        "Чтение метаданных .ipa": "Reading .ipa metadata",
        "Установить .ipa…": "Install .ipa…",
        "Установить приложения из одного или нескольких файлов .ipa": "Install apps from one or more .ipa files",
        "Системные": "System",
        "Чтение списка приложений через installation_proxy…": "Reading the app list via installation_proxy…",
        "Не удалось получить список": "Could Not Load the List",
        "На устройстве не найдено приложений.": "No apps found on the device.",
        "Поиск по названию или bundle ID": "Search by name or bundle ID",
        "Удалить приложение": "Uninstall App",
        "Удалить приложение?": "Uninstall app?",
        "Приложение %@ будет полностью удалено с устройства вместе со всеми данными.": "The app %@ will be completely removed from the device along with all its data.",
        "Не удалось прочитать .ipa": "Could Not Read .ipa",
        "Не удалось прочитать выбранные файлы или они не являются корректными .ipa.": "The selected files couldn't be read or aren't valid .ipa files.",

        // Установка
        "Сведения о подписи": "Signature Details",
        "Установка заблокирована": "Installation Blocked",
        "Перед установкой разблокируйте устройство и не блокируйте экран до завершения.": "Before installing, unlock the device and keep the screen awake until it finishes.",
        "Файл": "File",
        "Размер": "Size",
        "Подпись": "Signature",
        "Профиль": "Profile",
        "Команда": "Team",
        "Действует до": "Valid Until",
        "Устройство в профиле": "Device in Profile",
        "Минимальная iOS": "Minimum iOS",
        "Приложение установлено на устройство": "The app has been installed on the device",
        "Установка не удалась": "Installation Failed",
        "Установка…": "Installing…",
        "Установить": "Install",
        "Установка приложений": "Installing Apps",
        "Выбрано: %d файлов .ipa": "%d .ipa files selected",
        "Установка в очереди…": "Installation queued…",
        "Установить все": "Install All",
        "Сертификат разработчика": "Developer Certificate",
        "Enterprise-подпись": "Enterprise Signature",
        "Перепакован без FairPlay": "Repackaged without FairPlay",
        "Без подписи": "Unsigned",
        "В IPA нет подписи кода. iOS не установит такое приложение. Подпишите его сертификатом разработчика или через сервис подписи.": "The IPA has no code signature. iOS won't install this app. Sign it with a developer certificate or a signing service.",
        "IPA выглядит перепакованным: в нём нет FairPlay-подписи App Store. iOS отклонит его при проверке подписи. Переподпишите приложение.": "The IPA looks repackaged: it has no App Store FairPlay signature. iOS will reject it during signature validation. Re-sign the app.",
        "Срок действия профиля подписи истёк %@. Переподпишите IPA.": "The signing profile expired on %@. Re-sign the IPA.",
        "Профиль подписи не содержит UDID этого устройства. Добавьте устройство в профиль и переподпишите IPA.": "The signing profile doesn't include this device's UDID. Add the device to the profile and re-sign the IPA.",
        "App Store-подпись проверяется устройством. Установка пройдёт, если устройство авторизовано для этой покупки. Изменённые после скачивания приложения не установятся.": "The App Store signature is verified by the device. Installation succeeds if the device is authorized for this purchase. Apps modified after download won't install.",
        "Копирование на устройство": "Copying to Device",
        "Подготовка": "Preparing",
        "Распаковка пакета": "Extracting Package",
        "Проверка пакета": "Inspecting Package",
        "Предварительная проверка": "Preflight Check",
        "Проверка подписи": "Verifying Signature",
        "Создание контейнера": "Creating Container",
        "Установка приложения": "Installing Application",
        "Завершение установки": "Finishing Installation",
        "Настройка песочницы": "Sandboxing Application",
        "Генерация карты приложения": "Generating Application Map",
        "Установлено": "Installed",
        "Установка": "Installation",

        // Ошибки .ipa
        "Выбранный файл не является .ipa.": "The selected file isn't an .ipa.",
        "Файл не найден: %@": "File not found: %@",
        "Не удалось прочитать архив: %@": "Could not read the archive: %@",
        "В архиве нет каталога Payload с приложением.": "The archive has no Payload folder with an app.",
        "В архиве не найден Info.plist приложения.": "The app's Info.plist wasn't found in the archive.",
        "Не удалось разобрать Info.plist: %@": "Could not parse Info.plist: %@",
        "В Info.plist отсутствует CFBundleIdentifier.": "CFBundleIdentifier is missing from Info.plist.",

        // Диагностика
        "Диагностика устройства": "Device Diagnostics",
        "Данные получены от устройства через lockdownd": "Data received from the device via lockdownd",
        "Тип продукта": "Product Type",
        "Архитектура CPU": "CPU Architecture",
        "Номер модели": "Model Number",
        "Регион": "Region",
        "Активация": "Activation",
        "Аппаратная платформа": "Hardware Platform",
        "Аппаратная модель": "Hardware Model",
        "Цвет корпуса": "Enclosure Color",
        "Уровень заряда": "Battery Level",
        "Зарядка": "Charging",
        "Циклы зарядки": "Charge Cycles",
        "Сеть": "Network",
        "Wi-Fi (MAC)": "Wi-Fi (MAC)",
        "Bluetooth (MAC)": "Bluetooth (MAC)",
        "Обновление…": "Refreshing…",
        "Обновить данные": "Refresh Data",
        "Скопировать сводку": "Copy Summary",
        "Активировано": "Activated",
        "Заводская активация": "Factory Activated",
        "Идёт зарядка": "Charging",
        "Не заряжается": "Not Charging",
        "Устройство: %@ (%@)": "Device: %@ (%@)",
        "Тип: %@": "Type: %@",
        "iOS: %@ (%@)": "iOS: %@ (%@)",
        "UDID: %@": "UDID: %@",
        "Серийный: %@": "Serial: %@",
        "Аккумулятор: %d%%": "Battery: %d%%",
        "Хранилище: %@ из %@, доступно %@": "Storage: %@ of %@, available %@",
        "Оперативная память: %@": "Memory: %@",
        "Wi-Fi MAC: %@": "Wi-Fi MAC: %@",
        "Bluetooth MAC: %@": "Bluetooth MAC: %@",

        // App Store
        "App Store": "App Store",
        "По алфавиту": "Alphabetically",
        "По дате покупки": "By Purchase Date",
        "Вкладка": "Tab",
        "Поиск": "Search",
        "Мои покупки": "My Purchases",
        "Поиск приложений, история покупок и скачивание файлов .ipa": "Search apps, purchase history, and .ipa downloads",
        "Вход выполнен. Доступны покупки и загрузка из App Store.": "Signed in. Purchases and App Store downloads are available.",
        "Обновить покупки": "Refresh Purchases",
        "Выйти": "Sign Out",
        "Выход…": "Signing Out…",
        "Выйти из Apple ID?": "Sign out of Apple ID?",
        "Выйти и остановить загрузки": "Sign Out and Stop Downloads",
        "Активные загрузки будут остановлены, сохранённая сессия удалена. При следующем входе Apple запросит код 2FA.": "Active downloads will be stopped and the saved session deleted. Apple will request a 2FA code the next time you sign in.",
        "Удалить сохранённую сессию. При следующем входе Apple запросит код 2FA.": "Delete the saved session. Apple will request a 2FA code the next time you sign in.",
        "Вход в Apple ID": "Apple ID Sign In",
        "Нужен для истории покупок и скачивания .ipa с серверов Apple.": "Required for purchase history and downloading .ipa files from Apple.",
        "Проверка сохранённой сессии…": "Checking saved session…",
        "Apple ID (email)": "Apple ID (email)",
        "Пароль": "Password",
        "Код 2FA": "2FA Code",
        "Проверка…": "Checking…",
        "Подтвердить код": "Confirm Code",
        "Войти": "Sign In",
        "Введите 6-значный код, который Apple отправил на доверенные устройства. Код действует несколько минут.": "Enter the 6-digit code Apple sent to your trusted devices. The code expires after a few minutes.",
        "Первый вход может занять до минуты: Apple проверяет устройство и аккаунт.": "The first sign-in can take up to a minute while Apple verifies the device and account.",
        "Название приложения…": "App name…",
        "Найти": "Search",
        "Поиск в App Store…": "Searching the App Store…",
        "Ошибка поиска": "Search Error",
        "Введите название приложения и нажмите «Найти».": "Enter an app name and click Search.",
        "Ничего не найдено. Попробуйте другое название.": "Nothing found. Try a different name.",
        "Для скачивания нужен вход": "Sign In Required to Download",
        "Войдите в Apple ID выше. Бесплатные приложения тоже требуют лицензию, привязанную к аккаунту.": "Sign in to your Apple ID above. Even free apps require a license tied to your account.",
        "Войдите в Apple ID": "Sign In to Apple ID",
        "После входа здесь появится полная история покупок: бесплатные и платные приложения, а также приложения, удалённые из App Store.": "After signing in, your full purchase history will appear here: free and paid apps, including apps removed from the App Store.",
        "Не удалось загрузить покупки": "Could Not Load Purchases",
        "Покупки не найдены. Возможно, на этом Apple ID ещё нет загруженных приложений.": "No purchases found. This Apple ID may not have any downloaded apps yet.",
        "Фильтр по названию или bundle ID…": "Filter by name or bundle ID…",
        "Сортировка": "Sort",
        "Сортировка покупок": "Purchase Sorting",
        "Догружаем иконки…": "Loading icons…",
        "Удалено из App Store": "Removed from App Store",
        "Бесплатно": "Free",
        "Скачивается…": "Downloading…",
        "Скачать": "Download",
        "Скачать .ipa в папку iManager": "Download .ipa to the iManager folder",
        "Сначала войдите в Apple ID": "Sign in to Apple ID first",
        "Выбрать версию для скачивания": "Choose a version to download",
        "Найдено: %d": "Found: %d",
        "Загрузка покупок: %d · уже %d": "Loading purchases: %d · %d loaded",
        "Загрузка покупок: %d…": "Loading purchases: %d…",
        "Загрузка покупок: %d из %d": "Loading purchases: %d of %d",
        "Загрузка истории покупок…": "Loading purchase history…",

        // Версии
        "Получаем список версий…": "Loading versions…",
        "Не удалось получить версии": "Could Not Load Versions",
        "Для этого приложения нет доступных версий.": "No versions are available for this app.",
        "Старые версии могут больше не устанавливаться на iOS.": "Older versions may no longer install on iOS.",
        "Скачать последнюю": "Download Latest",
        "Загружаем сведения…": "Loading details…",
        "Не удалось получить сведения": "Could not load details",

        // Файлы
        "Корень": "Root",
        "Корень проводника — общий каталог Media на устройстве. Файлы приложений доступны через их контейнеры.": "The browser root is the device's shared Media directory. App files are available through their containers.",
        "Чтение папки": "Reading folder",
        "Загрузить файлы…": "Upload Files…",
        "Скопировать файлы с Mac в текущую папку на устройстве": "Copy files from the Mac to the current folder on the device",
        "Новая папка": "New Folder",
        "Обновить содержимое папки": "Refresh folder contents",
        "Имя папки": "Folder Name",
        "Папка будет создана в %@": "The folder will be created in %@",
        "На уровень выше": "Go Up",
        "Корень Media": "Media Root",
        "Переименовать «%@»": "Rename “%@”",
        "Новое имя": "New Name",
        "Чтение папки…": "Reading folder…",
        "Папка пуста": "Folder is empty",
        "Отпустите файлы, чтобы загрузить их в %@": "Drop files to upload them to %@",
        "Удалить «%@»?": "Delete “%@”?",
        "Папка будет удалена со всем содержимым. Действие необратимо.": "The folder will be deleted with all its contents. This cannot be undone.",
        "Файл будет удалён с устройства. Действие необратимо.": "The file will be deleted from the device. This cannot be undone.",
        "Передача файла…": "Transferring file…",
        "Не удалось выполнить операцию": "Operation Failed",
        "Скрыть сообщение": "Dismiss message",
        "Скачать файл с устройства": "Download File from Device",
        "Загрузить файлы на устройство": "Upload Files to Device",
        "Файлы будут скопированы в %@": "Files will be copied to %@",
        "Скачать папку «%@»": "Download Folder “%@”",
        "Выберите папку на Mac, куда сохранить содержимое.": "Choose a folder on the Mac to save the contents.",
        "Скачать сюда": "Download Here",
        "Скачать на Mac": "Download to Mac",
        "Скачать папку…": "Download Folder…",
        "Скачать…": "Download…",
        "Переименовать…": "Rename…",
        "Удалить…": "Delete…",
        "Папка": "Folder",
        "Символическая ссылка": "Symbolic Link",
        "0 байт": "0 bytes",
        "Папок: %d, файлов: %d": "Folders: %d, files: %d",
        "Скачивание «%@»": "Downloading “%@”",
        "Скачивание «%@»: %@": "Downloading “%@”: %@",
        "Скачано: %@ (%@)": "Downloaded: %@ (%@)",
        "Скачивание папки «%@»": "Downloading folder “%@”",
        "Скачано файлов: %d (%@)": "Files downloaded: %d (%@)",
        "Загрузка «%@»": "Uploading “%@”",
        "Загрузка файлов: %d": "Uploading files: %d",
        "Загрузка «%@»: %@": "Uploading “%@”: %@",
        "Загружено: %@": "Uploaded: %@",
        "Загружено файлов: %d": "Files uploaded: %d",
        "Недопустимое имя папки.": "Invalid folder name.",
        "Создана папка: %@": "Folder created: %@",
        "Удалено: %@": "Deleted: %@",
        "Недопустимое имя файла.": "Invalid file name.",
        "Переименовано: %@ → %@": "Renamed: %@ → %@",

        // Загрузки
        "Не удалось открыть пакет": "Could Not Open Package",
        "Файлы .ipa сохраняются в %@": ".ipa files are saved to %@",
        "Перечитать папку загрузок": "Rescan the downloads folder",
        "Открыть папку": "Open Folder",
        "В процессе": "In Progress",
        "Загрузки выполняются последовательно": "Downloads run sequentially",
        "%@/с": "%@/s",
        "Отменить": "Cancel",
        "Не удалось скачать": "Download Failed",
        "Загрузка отменена.": "Download cancelled.",
        "Неизвестная ошибка.": "Unknown error.",
        "Убрать из списка": "Remove from list",
        "Скачанные файлы": "Downloaded Files",
        "Готовые .ipa появятся здесь": "Downloaded .ipa files will appear here",
        "Устройство не подключено": "No device connected",
        "После завершения загрузки файл появится в этой папке.": "The file will appear in this folder when the download completes.",
        "Подключите iPhone или iPad по USB": "Connect an iPhone or iPad via USB",
        "Установить на устройство": "Install on device",
        "Показать в Finder": "Show in Finder",
        "Удалить файл": "Delete File",
        "Действия с файлом": "File Actions",
        "Пока нет загрузок": "No Downloads Yet",
        "Откройте App Store, найдите приложение или выберите его из своих покупок и нажмите «Скачать». Файл .ipa сохранится в папку iManager.": "Open the App Store, search for an app or choose one from your purchases, and click Download. The .ipa file will be saved to the iManager folder.",
        "Открыть App Store": "Open App Store",
        "Загрузка": "Downloading",
        "Ожидает начала": "Waiting to start",
        "Получение данных…": "Receiving data…",
        "Подготовка загрузки…": "Preparing download…",
        "Остановка…": "Stopping…",
        "Файл не появился в папке загрузок. Проверьте вход в Apple ID и повторите попытку.": "The file didn't appear in the downloads folder. Check your Apple ID sign-in and try again.",

        // Ошибки сервисов
        "Утилита ipatool не найдена внутри приложения. Пересоберите iManager.": "The ipatool utility wasn't found inside the app. Rebuild iManager.",
        "Вы не вошли в Apple ID. Войдите в раздел «Мои покупки».": "You're not signed in to Apple ID. Sign in under My Purchases.",
        "Apple запросил код двухфакторной аутентификации (2FA).": "Apple requested a two-factor authentication (2FA) code.",
        "Не удалось разобрать ответ ipatool: %@": "Could not parse the ipatool response: %@",
        "Apple не подтвердил вход. Проверьте Apple ID и пароль.": "Apple didn't confirm the sign-in. Check your Apple ID and password.",
        "Не удалось войти в Apple ID (код %d).": "Could not sign in to Apple ID (code %d).",
        "ipatool завершился с кодом %d.": "ipatool exited with code %d.",
        "Неизвестен идентификатор приложения.": "Unknown app identifier.",
        "Не удалось получить список версий (код %d).": "Could not load the version list (code %d).",
        "Не удалось получить сведения о версии (код %d).": "Could not load version details (code %d).",
        "нет данных о версии": "no version data",
        "Не удалось запустить ipatool: %@": "Could not launch ipatool: %@",
        "Не удалось удалить данные сессии Apple ID: %@": "Could not delete the Apple ID session data: %@",
        "Сессия Apple ID не найдена. Войдите в «Мои покупки» заново.": "Apple ID session not found. Sign in again under My Purchases.",
        "Сессия Apple ID истекла. Войдите в «Мои покупки» заново.": "Apple ID session expired. Sign in again under My Purchases.",
        "Сессия Apple ID истекла. Войдите заново.": "Apple ID session expired. Sign in again.",
        "Apple запросил код 2FA. Введите его и повторите вход.": "Apple requested a 2FA code. Enter it and sign in again.",
        "Apple временно заблокировал аккаунт. Разблокируйте его через устройство или iCloud и повторите вход.": "Apple temporarily locked the account. Unlock it on a device or via iCloud and sign in again.",
        "Пароль Apple ID изменился. Войдите заново.": "The Apple ID password changed. Sign in again.",
        "Неверный Apple ID или пароль.": "Incorrect Apple ID or password.",
        "Неверный код двухфакторной аутентификации.": "Incorrect two-factor authentication code.",
        "Нет связи с серверами Apple. Проверьте подключение к интернету.": "No connection to Apple servers. Check your internet connection.",
        "Для этого приложения не получена лицензия. Повторите загрузку с включённым получением лицензии.": "No license was obtained for this app. Retry the download with license acquisition enabled.",
        "Приложение не найдено в App Store. Возможно, оно удалено из магазина.": "The app wasn't found in the App Store. It may have been removed from the store.",
        "Приложение временно недоступно в App Store. Попробуйте другую версию или повторите позже.": "The app is temporarily unavailable in the App Store. Try another version or retry later.",
        "Apple вернул пустой список загрузки. Войдите в Apple ID заново.": "Apple returned an empty download list. Sign in to Apple ID again.",
        "Файл скачался повреждённым. Повторите загрузку.": "The file downloaded corrupted. Retry the download.",
        "Проверка кода 2FA…": "Verifying 2FA code…",
        "Проверка Apple ID…": "Verifying Apple ID…",
        "Введите код 2FA, отправленный на ваши устройства Apple.": "Enter the 2FA code sent to your Apple devices.",
        "Сессия истекла. Введите пароль и код 2FA, чтобы продолжить.": "The session expired. Enter your password and 2FA code to continue.",
        "Ошибка поиска: %@": "Search error: %@",
        "Ошибка удаления %@: %@": "Could not uninstall %@: %@",
        "Установка этого пакета невозможна.": "This package can't be installed.",

        // AFC
        "AFC недоступен: %@": "AFC unavailable: %@",
        "%@: %@ (код %d)": "%@: %@ (code %d)",
        "Некорректный ответ AFC: %@": "Invalid AFC response: %@",
        "успешно": "success",
        "неизвестная ошибка": "unknown error",
        "некорректный заголовок пакета": "invalid packet header",
        "недостаточно ресурсов": "insufficient resources",
        "ошибка чтения": "read error",
        "ошибка записи": "write error",
        "неизвестный тип пакета": "unknown packet type",
        "некорректный аргумент": "invalid argument",
        "файл или папка не найдены": "file or folder not found",
        "это папка": "is a directory",
        "доступ запрещён": "permission denied",
        "сервис не подключён": "service not connected",
        "тайм-аут операции": "operation timed out",
        "слишком много данных": "too much data",
        "конец данных": "end of data",
        "операция не поддерживается": "operation not supported",
        "объект уже существует": "object already exists",
        "объект занят": "object busy",
        "недостаточно свободного места": "not enough free space",
        "операция заблокирована": "operation locked",
        "ошибка ввода-вывода": "I/O error",
        "операция прервана": "operation interrupted",
        "операция выполняется": "operation in progress",
        "неизвестный код ошибки": "unknown error code",
        "соединение не открыто": "connection is not open",

        // MobileDevice
        "MobileDevice.framework недоступен: %@": "MobileDevice.framework unavailable: %@",
        "Устройство %@ не найдено через MobileDevice.framework": "Device %@ wasn't found via MobileDevice.framework",
        "Устройство не сопряжено. Подтвердите доверие этому компьютеру на экране устройства.": "The device isn't paired. Trust this computer on the device screen.",
        "%@: устройство заблокировано или защищено паролем. Разблокируйте iPhone и не блокируйте экран во время установки.": "%@: the device is locked or passcode-protected. Unlock the iPhone and keep the screen awake during installation.",
        "%@ завершилась с ошибкой 0x%@. Разблокируйте устройство и подтвердите запрос «Доверять».": "%@ failed with error 0x%@. Unlock the device and confirm the Trust prompt.",
        "Некорректный ответ MobileDevice.framework: %@": "Invalid MobileDevice.framework response: %@",
        "Некорректный .ipa: %@": "Invalid .ipa: %@",
        "Устройство заблокировано. Разблокируйте его и повторите установку.": "The device is locked. Unlock it and retry the installation.",
        "Устройство отклонило приложение при проверке (ApplicationVerificationFailed).": "The device rejected the app during verification (ApplicationVerificationFailed).",
        "Не удалось проверить подпись приложения. Скорее всего, IPA перепакован или повреждён.": "Could not verify the app signature. The IPA is likely repackaged or damaged.",
        "Не найдена действительная подпись кода. Подпишите IPA сертификатом разработчика.": "No valid code signature found. Sign the IPA with a developer certificate.",
        "Приложение подписано с недействительными entitlements.": "The app is signed with invalid entitlements.",
        "Не найден provisioning profile для этого приложения.": "No provisioning profile was found for this app.",
        "Срок действия сертификата или профиля подписи истёк.": "The certificate or signing profile has expired.",
        "Устройство не поддерживает минимальную версию iOS приложения.": "The device doesn't support the app's minimum iOS version.",
        "Недействительный сертификат подписи.": "Invalid signing certificate.",
        "Профиль подписи не содержит это устройство.": "The signing profile doesn't include this device.",
        "Разблокируйте устройство, подтвердите доверие компьютеру и проверьте подпись IPA.": "Unlock the device, trust the computer, and check the IPA signature.",
        "Установка завершилась с ошибкой 0x%@. %@": "Installation failed with error 0x%@. %@",
        "Детали: %@": "Details: %@",
        "AMDCreateDeviceList вернул nil": "AMDCreateDeviceList returned nil",
        "AMDeviceLookupApplications вернул пустой указатель": "AMDeviceLookupApplications returned a null pointer",
        "ID версии %@": "Version ID %@",
        "iManager автоматически обнаружит устройство по USB или Wi-Fi, если на устройстве включена синхронизация по Wi-Fi.": "iManager automatically detects a device over USB or Wi-Fi when Wi-Fi syncing is enabled on the device.",
        "lockdownd вернул ошибку: %@": "lockdownd returned an error: %@",
        "plist не является словарём": "plist is not a dictionary",
        "unzip завершился с кодом %d": "unzip exited with code %d",
        "usbmuxd отклонил подключение к устройству (код %d)": "usbmuxd refused the device connection (code %d)",
        "В разработке": "In Development",
        "Версия %@": "Version %@",
        "Запланировано": "Planned",
        "Истекло время ожидания ответа": "Response timed out",
        "Куплено %@": "Purchased %@",
        "Не удалось подключиться к usbmuxd: %@": "Could not connect to usbmuxd: %@",
        "Не удалось создать сокет: %@": "Could not create a socket: %@",
        "Некорректный ответ lockdownd: %@": "Invalid lockdownd response: %@",
        "Некорректный ответ usbmuxd: %@": "Invalid usbmuxd response: %@",
        "Ошибка ввода-вывода: %@": "I/O error: %@",
        "Подключите iPhone или iPad": "Connect an iPhone or iPad",
        "Показано: %d из %d": "Showing %d of %d",
        "Пользовательских: %d, всего: %d": "User apps: %d, total: %d",
        "Приложение %d": "App %d",
        "Работает напрямую через usbmuxd — без сторонних утилит": "Works directly through usbmuxd — no third-party tools",
        "Соединение закрыто удалённой стороной": "Connection closed by the remote side",
        "Удалить %@": "Uninstall %@",
        "внутренняя ошибка": "internal error",
        "корневой объект не является словарём": "root object is not a dictionary",
        "не удалось декодировать список файлов": "could not decode the file list",
        "не удалось загрузить MobileDevice.framework": "could not load MobileDevice.framework",
        "не удалось загрузить функции": "could not load functions",
        "не удалось создать файл %@": "could not create file %@",
        "недостаточно данных": "not enough data",
        "недостаточно памяти": "not enough memory",
        "некорректная длина пакета: %d": "invalid packet length: %d",
        "ожидался Result, получен %@": "expected Result, got %@",
        "отсутствует поле DeviceList": "DeviceList field is missing",
        "ошибка AFC": "AFC error",
        "ошибка SSL": "SSL error",
        "ошибка мультиплексирования": "multiplexing error",
        "папка не пуста": "folder is not empty",
        "слишком длинный путь сокета": "socket path is too long",
        "соединение AFC закрыто": "AFC connection is closed",
        "список приложений не является словарём": "the app list is not a dictionary",
        "файл не найден: %@": "file not found: %@",
    ]
}

// MARK: - Хелперы

/// Возвращает строку на текущем языке интерфейса.
func L(_ key: String, _ args: CVarArg...) -> String {
    let manager = LocalizationManager.shared
    let format = manager.text(key)
    guard !args.isEmpty else { return format }
    return String(format: format, locale: manager.locale, arguments: args)
}

/// Склонение с учётом текущего языка. Для русского используются три формы,
/// для английского — одна/множественная.
func LCount(
    _ count: Int,
    ruOne: String,
    ruFew: String,
    ruMany: String,
    enOne: String,
    enMany: String
) -> String {
    if LocalizationManager.shared.isEnglish {
        return "\(count) \(count == 1 ? enOne : enMany)"
    }
    let mod10 = count % 10
    let mod100 = count % 100
    let word: String
    if mod10 == 1 && mod100 != 11 {
        word = ruOne
    } else if (2...4).contains(mod10) && !(12...14).contains(mod100) {
        word = ruFew
    } else {
        word = ruMany
    }
    return "\(count) \(word)"
}


/// Форматирует дату с локалью текущего языка интерфейса.
func LDate(
    _ date: Date,
    dateStyle: DateFormatter.Style = .medium,
    timeStyle: DateFormatter.Style = .none
) -> String {
    let formatter = DateFormatter()
    formatter.locale = LocalizationManager.shared.locale
    formatter.dateStyle = dateStyle
    formatter.timeStyle = timeStyle
    return formatter.string(from: date)
}
