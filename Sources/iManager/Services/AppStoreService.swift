import Foundation

// MARK: - Модель приложения App Store

struct AppStoreApp: Identifiable, Codable, Equatable {
    let id: Int
    let bundleID: String
    let name: String
    let sellerName: String
    let version: String
    let iconUrl: String
    let price: Double?
    let currency: String?
    let description: String?
    let minimumOS: String?
    let releaseDate: String?
    let genre: String?
    var purchaseDate: Date? = nil
    var isPurchased: Bool = false
    var isDeletedFromStore: Bool = false

    enum CodingKeys: String, CodingKey {
        case id = "trackId"
        case bundleID = "bundleId"
        case name = "trackName"
        case sellerName = "artistName"
        case version = "version"
        case iconUrl = "artworkUrl512"
        case price = "price"
        case currency = "currency"
        case description = "description"
        case minimumOS = "minimumOsVersion"
        case releaseDate = "currentVersionReleaseDate"
        case genre = "primaryGenreName"
    }
}

struct AppStoreSearchResult: Codable {
    let results: [AppStoreApp]
}

/// Версия приложения в App Store, доступная для повторной загрузки.
struct AppStoreVersion: Identifiable, Equatable {
    let id: String
    var displayVersion: String = ""
    var releaseDate: Date?
    var minimumOS: String?
    var isLoading = false
    var failed = false

    var title: String {
        if !displayVersion.isEmpty {
            return L("Версия %@", displayVersion)
        }
        return L("ID версии %@", id)
    }
}

// MARK: - Сервис

final class AppStoreService: ObservableObject {
    static let shared = AppStoreService()

    @Published private(set) var searchResults: [AppStoreApp] = []
    @Published private(set) var purchasedApps: [AppStoreApp] = []
    @Published private(set) var isSearching = false
    @Published private(set) var isLoadingPurchases = false
    @Published private(set) var isEnrichingPurchases = false
    @Published private(set) var isRestoringSession = false
    @Published private(set) var isLoggingIn = false
    @Published private(set) var isLoggingOut = false
    @Published private(set) var purchasesLoaded = 0
    @Published private(set) var purchasesTotal = 0
    @Published private(set) var purchasesCurrentYear: Int?
    @Published var isAuthenticated = false
    @Published var userAppleID: String?
    @Published var requires2FA = false
    @Published var loginStatus: String?
    @Published var searchError: String?
    @Published var loginError: String?
    @Published var logoutError: String?
    @Published var purchasesError: String?

    private let session = URLSession.shared
    private let savedEmailKey = "iManager.AppStoreAppleID"
    private let signedOutKey = "iManager.AppStoreSignedOut"

    /// Меняется при выходе: результаты уже запущенных запросов, пришедшие
    /// после очистки сессии, не должны возвращать приложение во «вход выполнен».
    private var sessionGeneration = 0

    private init() {}

    var savedEmail: String {
        UserDefaults.standard.string(forKey: savedEmailKey) ?? ""
    }

    // MARK: - Поиск

    @MainActor
    func search(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            return
        }

        isSearching = true
        searchError = nil
        defer { isSearching = false }

        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: trimmed),
            URLQueryItem(name: "entity", value: "software"),
            URLQueryItem(name: "limit", value: "50")
        ]

        guard let url = components.url else { return }

        do {
            let (data, _) = try await session.data(from: url)
            let result = try JSONDecoder().decode(AppStoreSearchResult.self, from: data)
            searchResults = result.results
        } catch {
            searchError = L("Ошибка поиска: %@", error.localizedDescription)
            searchResults = []
        }
    }

    // MARK: - Сессия Apple ID

    /// Пробует восстановить сохранённый вход.
    @MainActor
    func restoreSession() async {
        // После явного выхода сохранённую сессию не подхватываем: даже если
        // удалить файлы не удалось, приложение должно остаться разлогиненным.
        guard !UserDefaults.standard.bool(forKey: signedOutKey) else { return }
        guard !isRestoringSession else { return }
        isRestoringSession = true
        defer { isRestoringSession = false }

        let generation = sessionGeneration

        do {
            if let account = try await IPAToolService.shared.accountInfo() {
                guard generation == sessionGeneration else { return }
                isAuthenticated = true
                userAppleID = account.email
                if purchasedApps.isEmpty {
                    await fetchPurchases()
                }
            }
        } catch {
            // Нет сохранённой сессии — это нормальное состояние при первом запуске.
        }
    }

    @MainActor
    func login(appleID: String, password: String, code: String? = nil) async {
        guard !isLoggingIn else { return }

        let email = appleID.trimmingCharacters(in: .whitespacesAndNewlines)
        let authCode = code?.trimmingCharacters(in: .whitespacesAndNewlines)
        let codeProvided = authCode?.isEmpty == false

        isLoggingIn = true
        loginError = nil
        logoutError = nil
        loginStatus = codeProvided ? L("Проверка кода 2FA…") : L("Проверка Apple ID…")
        let generation = sessionGeneration

        do {
            let account = try await IPAToolService.shared.login(
                email: email,
                password: password,
                authCode: codeProvided ? authCode : nil
            )

            guard generation == sessionGeneration else { return }

            isAuthenticated = true
            userAppleID = account.email.isEmpty ? email : account.email
            requires2FA = false
            loginStatus = nil
            isLoggingIn = false
            UserDefaults.standard.set(email, forKey: savedEmailKey)
            UserDefaults.standard.set(false, forKey: signedOutKey)

            await fetchPurchases()
        } catch IPAToolError.requires2FA {
            requires2FA = true
            loginError = nil
            loginStatus = L("Введите код 2FA, отправленный на ваши устройства Apple.")
            isLoggingIn = false
        } catch {
            loginError = error.localizedDescription
            loginStatus = nil
            isLoggingIn = false
        }
    }

    @MainActor
    func logout() async {
        guard !isLoggingOut else { return }

        isLoggingOut = true
        logoutError = nil
        sessionGeneration += 1
        UserDefaults.standard.set(true, forKey: signedOutKey)

        // Выход должен удалить сессию полностью. Сначала останавливаем всё,
        // что ещё использует её: активные загрузки и запущенные команды
        // ipatool. Иначе процесс может сохранить состояние уже после очистки.
        await DownloadManager.shared.cancelAllAndWait()
        IPAToolService.shared.cancelRunningCommands()

        do {
            try await IPAToolService.shared.revoke()
        } catch {
            logoutError = error.localizedDescription
        }

        isAuthenticated = false
        userAppleID = nil
        requires2FA = false
        loginStatus = nil
        loginError = nil
        purchasesError = nil
        purchasedApps = []
        purchasesLoaded = 0
        purchasesTotal = 0
        purchasesCurrentYear = nil
        isLoadingPurchases = false
        isEnrichingPurchases = false
        isLoggingIn = false
        isLoggingOut = false
    }

    // MARK: - Покупки

    @MainActor
    func fetchPurchases() async {
        guard isAuthenticated, !isLoadingPurchases else { return }

        let generation = sessionGeneration
        isLoadingPurchases = true
        purchasesError = nil
        purchasesLoaded = 0
        purchasesTotal = 0
        purchasesCurrentYear = nil
        purchasedApps = []

        var loaded: [AppStoreApp] = []
        var seenIDs: Set<Int> = []
        let currentYear = Calendar.current.component(.year, from: Date())
        let firstYear = 2008

        do {
            // `ipatool-cpp` умеет отдавать историю за конкретный год. Идём
            // от текущего года назад — UI обновляется после каждого года,
            // а не ждёт всю историю целиком.
            for year in stride(from: currentYear, through: firstYear, by: -1) {
                purchasesCurrentYear = year

                let result = try await IPAToolService.shared.listPurchases(range: "\(year)-all")

                guard generation == sessionGeneration else { return }

                for app in result.apps where Self.isIOSPurchase(app) {
                    let mapped = Self.mapPurchase(app)
                    if mapped.id > 0 {
                        guard seenIDs.insert(mapped.id).inserted else { continue }
                    }
                    loaded.append(mapped)
                }

                loaded.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                purchasedApps = loaded
                purchasesLoaded = loaded.count
            }

            guard generation == sessionGeneration else { return }

            purchasesCurrentYear = nil
            purchasesTotal = loaded.count

            isLoadingPurchases = false
            isEnrichingPurchases = true
            let enriched = await enrichPurchases(loaded)

            guard generation == sessionGeneration else { return }

            purchasedApps = enriched
            isEnrichingPurchases = false
        } catch IPAToolError.notAuthenticated {
            guard generation == sessionGeneration else { return }
            isAuthenticated = false
            userAppleID = nil
            purchasesError = L("Сессия Apple ID истекла. Войдите заново.")
            purchasesCurrentYear = nil
            isLoadingPurchases = false
            isEnrichingPurchases = false
        } catch IPAToolError.requires2FA {
            guard generation == sessionGeneration else { return }
            // Сессия истекла, и ipatool не смог молча войти: Apple требует
            // код 2FA. Показываем форму входа с полем для кода.
            isAuthenticated = false
            requires2FA = true
            loginStatus = L("Сессия истекла. Введите пароль и код 2FA, чтобы продолжить.")
            purchasesCurrentYear = nil
            isLoadingPurchases = false
            isEnrichingPurchases = false
        } catch {
            guard generation == sessionGeneration else { return }
            purchasesError = error.localizedDescription
            purchasesCurrentYear = nil
            isLoadingPurchases = false
            isEnrichingPurchases = false
        }
    }

    // MARK: - Версии приложения

    @MainActor
    func versions(for app: AppStoreApp) async throws -> [String] {
        try await IPAToolService.shared.listVersions(appID: app.id, bundleID: app.bundleID)
    }

    @MainActor
    func versionMetadata(for app: AppStoreApp, versionID: String) async throws -> IPAToolVersionMetadata {
        try await IPAToolService.shared.versionMetadata(
            appID: app.id,
            bundleID: app.bundleID,
            versionID: versionID
        )
    }

    // MARK: - Скачивание

    @MainActor
    func download(app: AppStoreApp) {
        DownloadManager.shared.enqueue(app: app)
    }

    // MARK: - Обогащение данных из каталога

    /// ipatool отдаёт только id/bundleID/название/версию. Иконки, издателя и
    /// признак «приложения больше нет в каталоге» добираем из публичного API.
    private func enrichPurchases(_ apps: [AppStoreApp]) async -> [AppStoreApp] {
        let ids = apps.map(\.id).filter { $0 > 0 }
        guard !ids.isEmpty else { return apps }

        var found: [Int: AppStoreApp] = [:]
        var catalogSucceeded = false

        // Сначала российский каталог (основной для пользователя), затем
        // американский — для приложений, которых нет в RU.
        for chunk in Self.chunks(ids, size: 100) {
            if let results = await lookup(ids: chunk, country: "ru") {
                catalogSucceeded = true
                for result in results {
                    found[result.id] = result
                }
            }
        }

        let missing = ids.filter { found[$0] == nil }
        for chunk in Self.chunks(missing, size: 100) {
            if let results = await lookup(ids: chunk, country: "us") {
                catalogSucceeded = true
                for result in results {
                    found[result.id] = result
                }
            }
        }

        return apps.map { app in
            if let catalogApp = found[app.id] {
                return AppStoreApp(
                    id: app.id,
                    bundleID: app.bundleID.isEmpty ? catalogApp.bundleID : app.bundleID,
                    name: catalogApp.name.isEmpty ? app.name : catalogApp.name,
                    sellerName: catalogApp.sellerName,
                    version: catalogApp.version.isEmpty ? app.version : catalogApp.version,
                    iconUrl: catalogApp.iconUrl,
                    price: app.price ?? catalogApp.price,
                    currency: catalogApp.currency,
                    description: catalogApp.description,
                    minimumOS: catalogApp.minimumOS,
                    releaseDate: catalogApp.releaseDate,
                    genre: catalogApp.genre,
                    purchaseDate: app.purchaseDate,
                    isPurchased: true,
                    isDeletedFromStore: false
                )
            }

            var updated = app
            updated.isDeletedFromStore = catalogSucceeded && app.id > 0
            return updated
        }
    }

    private func lookup(ids: [Int], country: String) async -> [AppStoreApp]? {
        guard !ids.isEmpty else { return [] }

        var components = URLComponents(string: "https://itunes.apple.com/lookup")!
        components.queryItems = [
            URLQueryItem(name: "id", value: ids.map(String.init).joined(separator: ",")),
            URLQueryItem(name: "entity", value: "software"),
            URLQueryItem(name: "country", value: country),
            URLQueryItem(name: "limit", value: "200")
        ]

        guard let url = components.url else { return nil }

        do {
            let (data, _) = try await session.data(from: url)
            return try JSONDecoder().decode(AppStoreSearchResult.self, from: data).results
        } catch {
            return nil
        }
    }

    // MARK: - Вспомогательное

    /// В истории покупок есть не только iOS-приложения. `ipatool-cpp` отдаёт
    /// тип покупки в поле `kind` ("iOS App", "Book", "Mac App", …). Оставляем
    /// iOS/iPadOS-приложения и записи без типа — у удалённых из каталога
    /// приложений метаданные часто неполные.
    private static func isIOSPurchase(_ app: IPAToolApp) -> Bool {
        let name = app.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            return false
        }

        if let platforms = app.platforms, !platforms.isEmpty {
            let lowercased = platforms.map { $0.lowercased() }
            if lowercased.contains("iphone") || lowercased.contains("ipad") {
                return true
            }
            if lowercased.contains("macos")
                || lowercased.contains("appletv")
                || lowercased.contains("visionos")
                || lowercased.contains("watchos") {
                return false
            }
        }

        if let kind = app.kind?.trimmingCharacters(in: .whitespacesAndNewlines), !kind.isEmpty {
            let lowercased = kind.lowercased()
            // Только настоящие iOS-приложения. Подписки, встроенные покупки,
            // пополнения, Mac-приложения, книги и прочее отбрасываем.
            return lowercased == "ios app" || lowercased.contains("ios app")
        }

        return true
    }

    private static func mapPurchase(_ app: IPAToolApp) -> AppStoreApp {
        let fallbackName = app.bundleID.isEmpty ? L("Приложение %d", app.id) : app.bundleID
        return AppStoreApp(
            id: app.id,
            bundleID: app.bundleID,
            name: app.name.isEmpty ? fallbackName : app.name,
            sellerName: "",
            version: app.version,
            iconUrl: "",
            price: app.price,
            currency: nil,
            description: nil,
            minimumOS: nil,
            releaseDate: nil,
            genre: nil,
            purchaseDate: parseDate(app.purchaseDate),
            isPurchased: true,
            isDeletedFromStore: false
        )
    }

    static func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }

        // ipatool-cpp отдаёт даты вида "31 Dec 2025" с неразрывным пробелом.
        let normalized = raw
            .replacingOccurrences(of: "\\u{00A0}", with: " ")
            .replacingOccurrences(of: "\\u{202F}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: normalized) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: normalized) {
            return date
        }

        // Apple commerce API иногда отдаёт даты без часового пояса или
        // в формате "yyyy-MM-dd HH:mm:ss".
        let fallbacks = [
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd",
            "d MMM yyyy",
            "dd MMM yyyy",
            "d MMMM yyyy",
            "dd MMMM yyyy"
        ]
        for format in fallbacks {
            let dateFormatter = DateFormatter()
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            dateFormatter.timeZone = TimeZone(identifier: "UTC")
            dateFormatter.dateFormat = format
            if let date = dateFormatter.date(from: normalized) {
                return date
            }
        }

        return nil
    }

    private static func chunks<T>(_ values: [T], size: Int) -> [[T]] {
        guard size > 0 else { return [values] }
        return stride(from: 0, to: values.count, by: size).map {
            Array(values[$0..<min($0 + size, values.count)])
        }
    }
}
