import SwiftUI

private enum PurchaseSort: String, CaseIterable, Identifiable {
    case name
    case date

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: return L("По алфавиту")
        case .date: return L("По дате покупки")
        }
    }

    var icon: String {
        switch self {
        case .name: return "textformat.abc"
        case .date: return "calendar"
        }
    }
}

struct StoreView: View {
    @ObservedObject private var l10n = LocalizationManager.shared
    @StateObject private var store = AppStoreService.shared
    @ObservedObject private var downloads = DownloadManager.shared
    @EnvironmentObject private var manager: DeviceManager

    @State private var selectedTab = 0 // 0: Поиск, 1: Мои покупки
    @State private var searchText = ""
    @State private var purchasesFilter = ""
    @State private var purchaseSort: PurchaseSort = .date
    @State private var versionApp: AppStoreApp?

    @State private var appleID = ""
    @State private var password = ""
    @State private var code = ""
    @State private var didRestoreSession = false
    @State private var showLogoutConfirmation = false

    @FocusState private var codeFocused: Bool

    private var isAuthenticated: Bool { store.isAuthenticated }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                accountCard

                Picker(L("Вкладка"), selection: $selectedTab) {
                    Text(L("Поиск")).tag(0)
                    Text(L("Мои покупки")).tag(1)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 280)

                if selectedTab == 0 {
                    searchTabContent
                } else {
                    purchasesTabContent
                }
            }
            .padding(26)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("App Store")
        .onAppear {
            if appleID.isEmpty {
                appleID = store.savedEmail
            }
            guard !didRestoreSession else { return }
            didRestoreSession = true
            Task { await store.restoreSession() }
        }
        .onChange(of: store.requires2FA) { required in
            if required {
                codeFocused = true
            }
        }
        .sheet(item: $versionApp) { app in
            VersionPickerView(app: app)
        }
        .confirmationDialog(
            L("Выйти из Apple ID?"),
            isPresented: $showLogoutConfirmation
        ) {
            Button(L("Выйти и остановить загрузки"), role: .destructive) {
                performLogout()
            }
            Button(L("Отмена"), role: .cancel) {}
        } message: {
            Text(L("Активные загрузки будут остановлены, сохранённая сессия удалена. При следующем входе Apple запросит код 2FA."))
        }
    }

    // MARK: - Заголовок

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("App Store")
                    .font(.system(size: 30, weight: .bold))

                Text(L("Поиск приложений, история покупок и скачивание файлов .ipa"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if !downloads.activeDownloads.isEmpty || !downloads.library.isEmpty {
                Button {
                    manager.selectedDeviceID = "downloads"
                } label: {
                    Label(
                        downloads.activeDownloads.isEmpty
                            ? L("Загрузки")
                            : L("Загрузки (%d)", downloads.activeDownloads.count),
                        systemImage: "arrow.down.circle"
                    )
                }
            }
        }
    }

    // MARK: - Аккаунт

    @ViewBuilder
    private var accountCard: some View {
        if isAuthenticated {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(store.userAppleID ?? "Apple ID")
                        .font(.callout.weight(.semibold))

                    Text(L("Вход выполнен. Доступны покупки и загрузка из App Store."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if store.isLoadingPurchases || store.isEnrichingPurchases {
                    ProgressView()
                        .controlSize(.small)
                }

                Button(L("Обновить покупки")) {
                    Task { await store.fetchPurchases() }
                }
                .controlSize(.small)
                .disabled(store.isLoadingPurchases)

                Button {
                    if downloads.activeDownloads.isEmpty {
                        performLogout()
                    } else {
                        showLogoutConfirmation = true
                    }
                } label: {
                    if store.isLoggingOut {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text(L("Выход…"))
                        }
                    } else {
                        Text(L("Выйти"))
                    }
                }
                .controlSize(.small)
                .disabled(store.isLoggingOut)
                .help(L("Удалить сохранённую сессию. При следующем входе Apple запросит код 2FA."))
            }
            .padding(14)
            .background(cardBackground)
        } else {
            loginCard
        }
    }

    private var loginCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "lock.shield")
                    .font(.title3)
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Вход в Apple ID"))
                        .font(.callout.weight(.semibold))

                    Text(L("Нужен для истории покупок и скачивания .ipa с серверов Apple."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if store.isRestoringSession {
                    ProgressView()
                        .controlSize(.small)
                    Text(L("Проверка сохранённой сессии…"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                TextField("Apple ID (email)", text: $appleID)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)

                SecureField(L("Пароль"), text: $password)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)

                if store.requires2FA {
                    TextField(L("Код 2FA"), text: $code)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 110)
                        .focused($codeFocused)
                }

                Button {
                    submitLogin()
                } label: {
                    if store.isLoggingIn {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text(L("Проверка…"))
                        }
                    } else {
                        Text(store.requires2FA ? L("Подтвердить код") : L("Войти"))
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    appleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || password.isEmpty
                        || store.isLoggingIn
                        || (store.requires2FA && code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                )
            }

            if let status = store.loginStatus {
                HStack(spacing: 7) {
                    ProgressView()
                        .controlSize(.small)
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let error = store.loginError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let error = store.logoutError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if store.requires2FA {
                Text(L("Введите 6-значный код, который Apple отправил на доверенные устройства. Код действует несколько минут."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(L("Первый вход может занять до минуты: Apple проверяет устройство и аккаунт."))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    private func performLogout() {
        password = ""
        code = ""
        Task { await store.logout() }
    }

    private func submitLogin() {
        let email = appleID.trimmingCharacters(in: .whitespacesAndNewlines)
        let authCode = store.requires2FA ? code : nil

        Task {
            await store.login(appleID: email, password: password, code: authCode)
            if store.isAuthenticated {
                password = ""
                code = ""
                store.requires2FA = false
            }
        }
    }

    // MARK: - Поиск

    private var searchTabContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(L("Название приложения…"), text: $searchText)
                        .textFieldStyle(.plain)
                        .onSubmit {
                            Task { await store.search(query: searchText) }
                        }
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.1))
                )

                Button(L("Найти")) {
                    Task { await store.search(query: searchText) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if store.isSearching {
                statusRow(L("Поиск в App Store…"))
            } else if let error = store.searchError {
                NoticeCard(icon: "exclamationmark.triangle", title: L("Ошибка поиска"), text: error)
            } else if store.searchResults.isEmpty {
                if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    hint(L("Введите название приложения и нажмите «Найти»."))
                } else {
                    hint(L("Ничего не найдено. Попробуйте другое название."))
                }
            } else {
                if !isAuthenticated {
                    NoticeCard(
                        icon: "lock.shield",
                        title: L("Для скачивания нужен вход"),
                        text: L("Войдите в Apple ID выше. Бесплатные приложения тоже требуют лицензию, привязанную к аккаунту.")
                    )
                }

                appList(store.searchResults, showPurchaseDate: false)
            }
        }
    }

    // MARK: - Покупки

    private var purchasesTabContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !isAuthenticated {
                NoticeCard(
                    icon: "person.crop.circle.badge.questionmark",
                    title: L("Войдите в Apple ID"),
                    text: L("После входа здесь появится полная история покупок: бесплатные и платные приложения, а также приложения, удалённые из App Store.")
                )
            } else {
                purchasesHeader

                if let error = store.purchasesError {
                    NoticeCard(icon: "exclamationmark.triangle", title: L("Не удалось загрузить покупки"), text: error)
                }

                if store.isLoadingPurchases {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text(purchasesProgressText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if store.purchasesTotal > 0 {
                            ProgressView(
                                value: Double(store.purchasesLoaded) / Double(max(store.purchasesTotal, 1))
                            )
                            .progressViewStyle(.linear)
                        }
                    }
                    .padding(.vertical, 2)
                }

                if filteredPurchases.isEmpty {
                    if store.isLoadingPurchases {
                        EmptyView()
                    } else if store.purchasesError == nil {
                        hint(L("Покупки не найдены. Возможно, на этом Apple ID ещё нет загруженных приложений."))
                    }
                } else {
                    appList(sortedPurchases, showPurchaseDate: true)
                }
            }
        }
    }

    private var purchasesHeader: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(L("Фильтр по названию или bundle ID…"), text: $purchasesFilter)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.1))
            )
            .frame(maxWidth: 360)

            if !store.purchasedApps.isEmpty {
                Text(purchasesCountText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !store.purchasedApps.isEmpty {
                Picker(L("Сортировка"), selection: $purchaseSort) {
                    ForEach(PurchaseSort.allCases) { sort in
                        Label(sort.title, systemImage: sort.icon)
                            .tag(sort)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
                .help(Text(L("Сортировка покупок")))
            }

            if store.isEnrichingPurchases {
                ProgressView()
                    .controlSize(.small)
                Text(L("Догружаем иконки…"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if !store.isLoadingPurchases {
                Button {
                    Task { await store.fetchPurchases() }
                } label: {
                    Label(L("Обновить"), systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
            }
        }
    }

    // MARK: - Список приложений

    private func appList(_ apps: [AppStoreApp], showPurchaseDate: Bool) -> some View {
        LazyVStack(spacing: 8) {
            ForEach(apps) { app in
                appRow(app, showPurchaseDate: showPurchaseDate)
            }
        }
    }

    private func appRow(_ app: AppStoreApp, showPurchaseDate: Bool) -> some View {
        HStack(spacing: 12) {
            appIcon(app)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(app.name)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)

                    if app.isDeletedFromStore {
                        Text(L("Удалено из App Store"))
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.red.opacity(0.14)))
                            .foregroundStyle(.red)
                    }
                }

                Text(app.sellerName.isEmpty ? app.bundleID : app.sellerName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if !app.bundleID.isEmpty {
                        Text(app.bundleID)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }

                    if !app.version.isEmpty {
                        Text("v\(app.version)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if showPurchaseDate, let date = app.purchaseDate {
                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(L("Куплено %@", LDate(date)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 0)

            priceBadge(app)

            downloadControl(for: app, allowVersions: showPurchaseDate && isAuthenticated)
        }
        .padding(12)
        .background(cardBackground)
    }

    @ViewBuilder
    private func appIcon(_ app: AppStoreApp) -> some View {
        if let url = URL(string: app.iconUrl), !app.iconUrl.isEmpty {
            AsyncImage(url: url) { image in
                image.resizable()
            } placeholder: {
                placeholderIcon
            }
            .frame(width: 46, height: 46)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            placeholderIcon
                .frame(width: 46, height: 46)
        }
    }

    private var placeholderIcon: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.secondary.opacity(0.1))
            .overlay(
                Image(systemName: "app.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
            )
    }

    @ViewBuilder
    private func priceBadge(_ app: AppStoreApp) -> some View {
        if let price = app.price {
            if price <= 0 {
                Text(L("Бесплатно"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
            } else {
                Text(formattedPrice(price, currency: app.currency))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func downloadControl(for app: AppStoreApp, allowVersions: Bool) -> some View {
        if let active = downloads.activeDownload(for: app) {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text(active.phase == .queued ? L("В очереди") : L("Скачивается…"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 116, alignment: .trailing)
        } else if let failed = downloads.download(for: app),
                  failed.phase == .failed || failed.phase == .cancelled {
            HStack(spacing: 4) {
                Button {
                    downloads.retry(failed)
                } label: {
                    Label(L("Повторить"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if allowVersions {
                    versionButton(for: app)
                }
            }
        } else {
            HStack(spacing: 4) {
                Button {
                    store.download(app: app)
                } label: {
                    Label(L("Скачать"), systemImage: "arrow.down.app")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!isAuthenticated)
                .help(isAuthenticated ? L("Скачать .ipa в папку iManager") : L("Сначала войдите в Apple ID"))

                if allowVersions {
                    versionButton(for: app)
                }
            }
        }
    }

    private func versionButton(for app: AppStoreApp) -> some View {
        Button {
            versionApp = app
        } label: {
            Image(systemName: "clock.arrow.circlepath")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(Text(L("Выбрать версию для скачивания")))
    }

    // MARK: - Вспомогательное

    private var filteredPurchases: [AppStoreApp] {
        let query = purchasesFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.purchasedApps }
        return store.purchasedApps.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.bundleID.localizedCaseInsensitiveContains(query)
                || $0.sellerName.localizedCaseInsensitiveContains(query)
        }
    }

    private var sortedPurchases: [AppStoreApp] {
        filteredPurchases.sorted { lhs, rhs in
            switch purchaseSort {
            case .name:
                let result = lhs.name.localizedStandardCompare(rhs.name)
                if result == .orderedSame {
                    return lhs.bundleID.localizedStandardCompare(rhs.bundleID) == .orderedAscending
                }
                return result == .orderedAscending
            case .date:
                switch (lhs.purchaseDate, rhs.purchaseDate) {
                case let (l?, r?):
                    if l == r {
                        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                    }
                    return l > r
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
            }
        }
    }

    private var purchasesCountText: String {
        if purchasesFilter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return LCount(store.purchasedApps.count, ruOne: "приложение", ruFew: "приложения", ruMany: "приложений", enOne: "app", enMany: "apps")
        }
        return L("Найдено: %d", filteredPurchases.count)
    }

    private var purchasesProgressText: String {
        if let year = store.purchasesCurrentYear {
            if store.purchasesLoaded > 0 {
                return L("Загрузка покупок: %d · уже %d", year, store.purchasesLoaded)
            }
            return L("Загрузка покупок: %d…", year)
        }
        if store.purchasesTotal > 0 {
            return L("Загрузка покупок: %d из %d", store.purchasesLoaded, store.purchasesTotal)
        }
        if store.purchasesLoaded > 0 {
            return L("Загрузка покупок: %d…", store.purchasesLoaded)
        }
        return L("Загрузка истории покупок…")
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06))
            )
    }

    private func statusRow(_ text: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(text)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 18)
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.vertical, 18)
    }

    private func formattedPrice(_ price: Double, currency: String?) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 2
        if let currency, !currency.isEmpty {
            formatter.currencyCode = currency
        }
        return formatter.string(from: NSNumber(value: price)) ?? "\(price) \(currency ?? "")"
    }

    private func plural(_ count: Int, _ one: String, _ few: String, _ many: String) -> String {
        let mod10 = count % 10
        let mod100 = count % 100
        if mod10 == 1 && mod100 != 11 { return one }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) { return few }
        return many
    }
}
