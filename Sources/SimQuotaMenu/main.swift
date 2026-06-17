import AppKit
import Foundation
import UserNotifications

struct AppConfig: Codable {
    var phoneNumber: String = ""
    var iccid: String = ""
    var refreshMinutes: Int = 30
    var launchAtLogin: Bool = false
    var savedCards: [SavedCard] = []

    enum CodingKeys: String, CodingKey {
        case phoneNumber
        case iccid
        case refreshMinutes
        case launchAtLogin
        case savedCards
    }

    init(
        phoneNumber: String = "",
        iccid: String = "",
        refreshMinutes: Int = 30,
        launchAtLogin: Bool = false,
        savedCards: [SavedCard] = []
    ) {
        self.phoneNumber = phoneNumber
        self.iccid = iccid
        self.refreshMinutes = refreshMinutes
        self.launchAtLogin = launchAtLogin
        self.savedCards = savedCards
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        phoneNumber = try container.decodeIfPresent(String.self, forKey: .phoneNumber) ?? ""
        iccid = try container.decodeIfPresent(String.self, forKey: .iccid) ?? ""
        refreshMinutes = try container.decodeIfPresent(Int.self, forKey: .refreshMinutes) ?? 30
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        savedCards = try container.decodeIfPresent([SavedCard].self, forKey: .savedCards) ?? []
    }
}

struct SavedCard: Codable, Equatable {
    let iccid: String
    let shortnum: String?
    let note: String?

    var displayTitle: String {
        [iccid, shortnum, note]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " / ")
    }

    init(iccid: String, shortnum: String?, note: String?) {
        self.iccid = iccid
        self.shortnum = shortnum
        self.note = note
    }
}

struct CardInfo: Decodable {
    let iccid: String
    let shortnum: String?
    let note: String?
    let status: Int?

    enum CodingKeys: String, CodingKey {
        case iccid
        case shortnum
        case note
        case status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        iccid = try container.decode(String.self, forKey: .iccid)
        shortnum = try container.decodeIfPresent(String.self, forKey: .shortnum)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        status = try container.decodeFlexibleIntIfPresent(forKey: .status)
    }

    var savedCard: SavedCard {
        SavedCard(iccid: iccid, shortnum: shortnum, note: note)
    }
}

struct PackageInfo: Decodable {
    let pkvaluelog: String?
    let pkusesize: Double?
    let pktotalsize: Double?
    let pkremainsize: Double?
    let starttime: String?
    let endtime: String?
    let pkmodule: [PackageModule]?

    enum CodingKeys: String, CodingKey {
        case pkvaluelog
        case pkusesize
        case pktotalsize
        case pkremainsize
        case starttime
        case endtime
        case pkmodule
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pkvaluelog = try container.decodeIfPresent(String.self, forKey: .pkvaluelog)
        pkusesize = try container.decodeFlexibleDoubleIfPresent(forKey: .pkusesize)
        pktotalsize = try container.decodeFlexibleDoubleIfPresent(forKey: .pktotalsize)
        pkremainsize = try container.decodeFlexibleDoubleIfPresent(forKey: .pkremainsize)
        starttime = try container.decodeIfPresent(String.self, forKey: .starttime)
        endtime = try container.decodeIfPresent(String.self, forKey: .endtime)
        pkmodule = try container.decodeIfPresent([PackageModule].self, forKey: .pkmodule)
    }
}

struct PackageModule: Decodable {
    let packname: String?
}

extension KeyedDecodingContainer {
    func decodeFlexibleIntIfPresent(forKey key: Key) throws -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Int(value)
        }
        return nil
    }

    func decodeFlexibleDoubleIfPresent(forKey key: Key) throws -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return Double(value)
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Double(value)
        }
        return nil
    }
}

struct CardsResponse: Decodable {
    let data: [CardInfo]?
    let success: Bool?
}

struct PackagesResponse: Decodable {
    let data: [PackageInfo]?
    let success: Bool?
    let succes: Bool?
    let err: String?
}

struct QuotaSnapshot {
    let totalGB: Double
    let usedGB: Double
    let remainGB: Double
    let packages: Int
    let latestExpiry: Date?
    let details: [PackageSummary]
    let fetchedAt: Date
}

struct PackageSummary {
    let name: String
    let totalGB: Double
    let usedGB: Double
    let remainGB: Double
    let expiry: Date?

    var remainRatio: Double {
        guard totalGB > 0 else {
            return 0
        }
        return max(min(remainGB / totalGB, 1), 0)
    }
}

enum APIError: LocalizedError {
    case invalidURL
    case network(String)
    case httpStatus(Int)
    case decoding
    case backend(String)
    case emptyCards
    case emptyPackages

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "接口地址无效"
        case .network(let message):
            return "网络连接失败：\(message)"
        case .httpStatus(let statusCode):
            return "服务暂时不可用：HTTP \(statusCode)"
        case .decoding:
            return "服务返回格式已变化，请更新App或反馈问题"
        case .backend(let message):
            return message
        case .emptyCards:
            return "没有查到绑定卡片，请确认手机号是否正确"
        case .emptyPackages:
            return "没有查到可用套餐，请确认卡片是否已激活或有套餐"
        }
    }
}

final class ConfigStore {
    private let fileURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("SimQuotaMenu", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent("config.json")
    }

    func load() -> AppConfig {
        guard let data = try? Data(contentsOf: fileURL) else {
            return AppConfig()
        }
        return (try? JSONDecoder().decode(AppConfig.self, from: data)) ?? AppConfig()
    }

    func save(_ config: AppConfig) {
        guard let data = try? JSONEncoder().encode(config) else {
            return
        }
        try? data.write(to: fileURL, options: [.atomic])
    }
}

final class LaunchAgentManager {
    private let label = "local.sim-quota.menu"
    private let plistURL: URL

    init() {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.plistURL = directory.appendingPathComponent("\(label).plist")
    }

    var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try writePlist()
        } else if isEnabled {
            try FileManager.default.removeItem(at: plistURL)
        }
    }

    private func writePlist() throws {
        let programArguments: [String]
        if Bundle.main.bundlePath.hasSuffix(".app") {
            programArguments = ["/usr/bin/open", "-a", Bundle.main.bundlePath]
        } else if let executablePath = Bundle.main.executablePath {
            programArguments = [executablePath]
        } else {
            programArguments = []
        }
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": programArguments,
            "RunAtLoad": true
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: plistURL, options: [.atomic])
    }
}

@MainActor
final class MnoiotClient {
    private let baseURL = URL(string: "https://web.mnoiot.com")!
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 MicroMessenger/8.0.49"
        ]
        self.session = URLSession(configuration: configuration)
    }

    func fetchCards(phoneNumber: String) async throws -> [CardInfo] {
        var components = URLComponents(url: baseURL.appendingPathComponent("/mina/get5giccidsnewnew"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "phoneNumber", value: phoneNumber),
            URLQueryItem(name: "current", value: "1"),
            URLQueryItem(name: "pageSize", value: "50"),
            URLQueryItem(name: "statefilter", value: "")
        ]
        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        let response: CardsResponse = try await request(url)
        let cards = response.data ?? []
        guard !cards.isEmpty else {
            throw APIError.emptyCards
        }
        return cards
    }

    func fetchQuota(iccid: String) async throws -> QuotaSnapshot {
        guard let escaped = iccid.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw APIError.invalidURL
        }
        let url = baseURL.appendingPathComponent("/mina/totalpackages/\(escaped)")
        let response: PackagesResponse = try await request(url)
        if let err = response.err {
            throw APIError.backend(err)
        }

        let packages = response.data ?? []
        guard !packages.isEmpty else {
            throw APIError.emptyPackages
        }

        let details = packages.map { package in
            let totalMB = convertToMB(value: package.pktotalsize, unit: package.pkvaluelog)
            let usedMB = convertToMB(value: package.pkusesize, unit: package.pkvaluelog)
            let remainMB = package.pkremainsize.map { convertToMB(value: $0, unit: package.pkvaluelog) } ?? max(totalMB - usedMB, 0)
            return PackageSummary(
                name: package.pkmodule?.first?.packname ?? "套餐",
                totalGB: totalMB / 1024,
                usedGB: usedMB / 1024,
                remainGB: remainMB / 1024,
                expiry: parseDate(package.endtime)
            )
        }.sorted { left, right in
            switch (left.expiry, right.expiry) {
            case let (leftDate?, rightDate?):
                return leftDate < rightDate
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return left.name < right.name
            }
        }

        let usedGB = details.reduce(0) { $0 + $1.usedGB }
        let totalGB = details.reduce(0) { $0 + $1.totalGB }
        let remainGB = details.reduce(0) { $0 + $1.remainGB }
        let latestExpiry = details
            .filter { $0.remainGB > 0 }
            .compactMap(\.expiry)
            .max()

        return QuotaSnapshot(
            totalGB: totalGB,
            usedGB: usedGB,
            remainGB: remainGB,
            packages: packages.count,
            latestExpiry: latestExpiry,
            details: details,
            fetchedAt: Date()
        )
    }

    private func request<T: Decodable>(_ url: URL) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch let error as URLError {
            throw APIError.network(error.localizedDescription)
        } catch {
            throw APIError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw APIError.httpStatus(statusCode)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decoding
        }
    }

    private func convertToMB(value: Double?, unit: String?) -> Double {
        guard let value else {
            return 0
        }

        switch unit?.uppercased() {
        case "GB":
            return value * 1024
        case "KB":
            return value / 1024
        default:
            return value
        }
    }

    private func parseDate(_ value: String?) -> Date? {
        guard let value else {
            return nil
        }
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: value) {
            return date
        }
        return ISO8601DateFormatter().date(from: value)
    }
}

@MainActor
final class SettingsWindowController: NSWindowController {
    private let phoneField = NSTextField()
    private let statusLabel = NSTextField(labelWithString: "")
    private let cardsPopup = NSPopUpButton()
    private var config: AppConfig = AppConfig()
    private var loadedCards: [SavedCard] = []

    var onSave: ((AppConfig) -> Void)?
    var onLoadCards: ((String, @escaping ([CardInfo], String?) -> Void) -> Void)?

    convenience init(config: AppConfig) {
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 178))
        let window = NSWindow(
            contentRect: contentView.frame,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "SIM流量余额设置"
        window.center()
        window.contentView = contentView
        self.init(window: window)
        self.config = config
        buildUI(config: config)
    }

    private func buildUI(config: AppConfig) {
        guard let contentView = window?.contentView else {
            return
        }

        let labels = ["手机号", "选择卡片"]
        for (index, text) in labels.enumerated() {
            let label = NSTextField(labelWithString: text)
            label.frame = NSRect(x: 22, y: 126 - index * 42, width: 106, height: 24)
            contentView.addSubview(label)
        }

        phoneField.frame = NSRect(x: 136, y: 126, width: 250, height: 24)
        phoneField.stringValue = config.phoneNumber
        contentView.addSubview(phoneField)

        cardsPopup.frame = NSRect(x: 136, y: 84, width: 250, height: 26)
        cardsPopup.addItem(withTitle: "先加载卡片")
        cardsPopup.target = self
        cardsPopup.action = #selector(saveSelectedCard)
        contentView.addSubview(cardsPopup)

        let loadButton = NSButton(title: "加载卡片", target: self, action: #selector(loadCards))
        loadButton.frame = NSRect(x: 136, y: 40, width: 92, height: 30)
        contentView.addSubview(loadButton)

        statusLabel.frame = NSRect(x: 22, y: 10, width: 364, height: 20)
        statusLabel.textColor = .secondaryLabelColor
        contentView.addSubview(statusLabel)
    }

    @objc private func loadCards() {
        let phone = phoneField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        statusLabel.stringValue = "正在加载..."
        guard !phone.isEmpty else {
            statusLabel.stringValue = "请先填写手机号"
            return
        }
        onLoadCards?(phone) { [weak self] cards, error in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }
                if let error {
                    self.statusLabel.stringValue = error
                    return
                }

                self.cardsPopup.removeAllItems()
                self.loadedCards = cards.map(\.savedCard)
                cards.forEach { card in
                    self.cardsPopup.addItem(withTitle: card.savedCard.displayTitle)
                    self.cardsPopup.lastItem?.representedObject = card.iccid
                }
                self.statusLabel.stringValue = "已加载\(cards.count)张卡"
            }
        }
    }

    @objc private func saveSelectedCard() {
        guard let iccid = cardsPopup.selectedItem?.representedObject as? String else {
            return
        }
        let newConfig = AppConfig(
            phoneNumber: phoneField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            iccid: iccid,
            refreshMinutes: config.refreshMinutes,
            launchAtLogin: config.launchAtLogin,
            savedCards: loadedCards
        )
        onSave?(newConfig)
        window?.close()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = ConfigStore()
    private let launchAgentManager = LaunchAgentManager()
    private let client = MnoiotClient()
    private var config = AppConfig()
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var relativeTimeTimer: Timer?
    private var settingsWindow: SettingsWindowController?
    private var lastSnapshot: QuotaSnapshot?
    private var lastNotificationKey: String?

    private let usedItem = NSMenuItem(title: "已用/总量: --", action: nil, keyEquivalent: "")
    private let updatedItem = NSMenuItem(title: "更新时间: --", action: nil, keyEquivalent: "")
    private let packageHeaderItem = NSMenuItem(title: "套餐明细", action: nil, keyEquivalent: "")
    private var packageItems: [NSMenuItem] = []
    private var switchCardItem: NSMenuItem!
    private var launchAtLoginItem: NSMenuItem!
    private var refreshIntervalItems: [Int: NSMenuItem] = [:]
    private let refreshOptions = [1, 5, 10, 30, 60, 120]
    private let lowRemainThresholdGB = 10.0
    private let expiryWarningDays = 3

    func applicationDidFinishLaunching(_ notification: Notification) {
        config = store.load()
        config.launchAtLogin = launchAgentManager.isEnabled
        requestNotificationPermission()
        setupMainMenu()
        setupMenu()
        scheduleRefresh()
        scheduleRelativeTimeUpdates()
        refreshQuota()
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        appMenuItem.submenu = NSMenu()

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "编辑")
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        NSApp.mainMenu = mainMenu
    }

    private func setupMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "--"

        let menu = NSMenu()
        menu.showsStateColumn = false
        menu.addItem(usedItem)
        menu.addItem(updatedItem)
        menu.addItem(.separator())
        menu.addItem(packageHeaderItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "刷新", action: #selector(refreshQuota), keyEquivalent: "r"))
        switchCardItem = makeSwitchCardMenuItem()
        menu.addItem(switchCardItem)
        menu.addItem(makeRefreshIntervalMenuItem())
        launchAtLoginItem = NSMenuItem(title: launchAtLoginTitle(), action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        menu.addItem(launchAtLoginItem)
        menu.addItem(makeSettingsMenuItem())
        menu.addItem(NSMenuItem(title: "重置配置", action: #selector(resetConfig), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
        rebuildSwitchCardMenu()
    }

    private func makeSwitchCardMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "切换卡片", action: nil, keyEquivalent: "")
        item.submenu = NSMenu(title: "切换卡片")
        return item
    }

    private func makeRefreshIntervalMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "刷新间隔", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "刷新间隔")
        submenu.showsStateColumn = false
        refreshOptions.forEach { minutes in
            let option = NSMenuItem(title: refreshIntervalTitle(minutes), action: #selector(selectRefreshInterval(_:)), keyEquivalent: "")
            option.representedObject = minutes
            option.target = self
            submenu.addItem(option)
            refreshIntervalItems[minutes] = option
        }
        item.submenu = submenu
        return item
    }

    private func makeSettingsMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "设置", action: #selector(openCardSelector), keyEquivalent: "")
        return item
    }

    private func scheduleRefresh() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(max(config.refreshMinutes, 1) * 60), repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshQuota()
            }
        }
    }

    private func scheduleRelativeTimeUpdates() {
        relativeTimeTimer?.invalidate()
        relativeTimeTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateRelativeTimeItem()
            }
        }
    }

    @objc private func selectRefreshInterval(_ sender: NSMenuItem) {
        guard let minutes = sender.representedObject as? Int else {
            return
        }
        config.refreshMinutes = minutes
        store.save(config)
        refreshIntervalItems.forEach { optionMinutes, item in
            item.title = refreshIntervalTitle(optionMinutes)
        }
        scheduleRefresh()
    }

    @objc private func toggleLaunchAtLogin() {
        config.launchAtLogin.toggle()
        do {
            try launchAgentManager.setEnabled(config.launchAtLogin)
            store.save(config)
            launchAtLoginItem.title = launchAtLoginTitle()
        } catch {
            config.launchAtLogin.toggle()
            statusItem.button?.title = "设置错误"
        }
    }

    private func launchAtLoginTitle() -> String {
        config.launchAtLogin ? "✓ 开机自启" : "开机自启"
    }

    private func rebuildSwitchCardMenu() {
        guard let submenu = switchCardItem?.submenu else {
            return
        }

        submenu.removeAllItems()
        if config.savedCards.isEmpty {
            let item = NSMenuItem(title: "暂无已加载卡片", action: nil, keyEquivalent: "")
            item.isEnabled = false
            submenu.addItem(item)
            switchCardItem.isEnabled = false
            return
        }

        switchCardItem.isEnabled = true
        config.savedCards.forEach { card in
            let item = NSMenuItem(title: switchCardTitle(card), action: #selector(selectSavedCard(_:)), keyEquivalent: "")
            item.representedObject = card.iccid
            item.target = self
            submenu.addItem(item)
        }
    }

    private func switchCardTitle(_ card: SavedCard) -> String {
        card.iccid == config.iccid ? "✓ \(card.displayTitle)" : card.displayTitle
    }

    @objc private func selectSavedCard(_ sender: NSMenuItem) {
        guard let iccid = sender.representedObject as? String, iccid != config.iccid else {
            return
        }

        config.iccid = iccid
        store.save(config)
        rebuildSwitchCardMenu()
        refreshQuota()
    }

    private func refreshIntervalTitle(_ minutes: Int) -> String {
        minutes == config.refreshMinutes ? "✓ \(minutes)分钟" : "\(minutes)分钟"
    }

    @objc private func refreshQuota() {
        guard !config.iccid.isEmpty else {
            statusItem.button?.title = "设置"
            usedItem.title = "已用/总量: --"
            updatedItem.title = "更新时间: --"
            lastSnapshot = nil
            replacePackageItems([])
            return
        }

        statusItem.button?.title = "..."
        Task {
            do {
                let snapshot = try await client.fetchQuota(iccid: config.iccid)
                await MainActor.run {
                    render(snapshot)
                }
            } catch {
                await MainActor.run {
                    statusItem.button?.title = "错误"
                    usedItem.title = "错误: \(Self.displayMessage(for: error))"
                    updatedItem.title = "更新时间: \(Self.timeString(Date()))"
                    replacePackageItems([])
                }
            }
        }
    }

    private func render(_ snapshot: QuotaSnapshot) {
        lastSnapshot = snapshot
        let expiryText = snapshot.latestExpiry.map { Self.shortDateString($0) } ?? "--"
        let warning = warningReason(for: snapshot)
        let prefix = warning == nil ? "" : "⚠ "
        statusItem.button?.title = "\(prefix)\(Self.sizeString(snapshot.remainGB)) \(expiryText)"
        usedItem.title = "已用/总量: \(Self.sizeString(snapshot.usedGB)) / \(Self.sizeString(snapshot.totalGB))"
        updateRelativeTimeItem()
        replacePackageItems(snapshot.details)
        notifyIfNeeded(snapshot: snapshot, warning: warning)
    }

    private func replacePackageItems(_ packages: [PackageSummary]) {
        guard let menu = statusItem.menu else {
            return
        }

        packageItems.forEach { menu.removeItem($0) }
        packageItems = []

        let insertIndex = menu.index(of: packageHeaderItem) + 1
        let visiblePackages = packages.prefix(5)
        if visiblePackages.isEmpty {
            let item = NSMenuItem(title: "暂无套餐", action: nil, keyEquivalent: "")
            menu.insertItem(item, at: insertIndex)
            packageItems.append(item)
            return
        }

        for (offset, package) in visiblePackages.enumerated() {
            let percent = Int((package.remainRatio * 100).rounded())
            let expiry = package.expiry.map { Self.shortDateString($0) } ?? "--"
            let title = "\(package.name) \(Self.sizeString(package.remainGB))/\(Self.sizeString(package.totalGB)) 到期\(expiry) 剩\(percent)%"
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            menu.insertItem(item, at: insertIndex + offset)
            packageItems.append(item)
        }

        if packages.count > visiblePackages.count {
            let item = NSMenuItem(title: "还有\(packages.count - visiblePackages.count)个套餐未显示", action: nil, keyEquivalent: "")
            menu.insertItem(item, at: insertIndex + visiblePackages.count)
            packageItems.append(item)
        }
    }

    @objc private func openCardSelector() {
        let controller = SettingsWindowController(config: config)
        controller.onSave = { [weak self] newConfig in
            guard let self else {
                return
            }
            self.config = newConfig
            self.store.save(newConfig)
            self.rebuildSwitchCardMenu()
            self.scheduleRefresh()
            self.refreshQuota()
        }
        controller.onLoadCards = { [weak self] phone, completion in
            guard let self else {
                return
            }
            Task {
                do {
                    let cards = try await self.client.fetchCards(phoneNumber: phone)
                    completion(cards, nil)
                } catch {
                    completion([], Self.displayMessage(for: error))
                }
            }
        }
        settingsWindow = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func resetConfig() {
        let alert = NSAlert()
        alert.messageText = "重置配置？"
        alert.informativeText = "将清除本地保存的手机号、ICCID、已加载卡片和开机自启设置。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "重置")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        try? launchAgentManager.setEnabled(false)
        config = AppConfig(refreshMinutes: config.refreshMinutes)
        store.save(config)
        lastSnapshot = nil
        lastNotificationKey = nil
        launchAtLoginItem.title = launchAtLoginTitle()
        rebuildSwitchCardMenu()
        statusItem.button?.title = "设置"
        usedItem.title = "已用/总量: --"
        updatedItem.title = "更新时间: --"
        replacePackageItems([])
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func warningReason(for snapshot: QuotaSnapshot) -> String? {
        if snapshot.remainGB < lowRemainThresholdGB {
            return "套餐余量低于\(Self.sizeString(lowRemainThresholdGB))"
        }

        guard let latestExpiry = snapshot.latestExpiry else {
            return nil
        }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: latestExpiry).day ?? Int.max
        if days < expiryWarningDays {
            return "套餐将在\(max(days, 0))天内到期"
        }
        return nil
    }

    private func notifyIfNeeded(snapshot: QuotaSnapshot, warning: String?) {
        guard let warning else {
            lastNotificationKey = nil
            return
        }

        let expiryText = snapshot.latestExpiry.map { Self.shortDateString($0) } ?? "--"
        let key = "\(config.iccid)-\(Self.sizeString(snapshot.remainGB))-\(expiryText)-\(warning)"
        guard key != lastNotificationKey else {
            return
        }
        lastNotificationKey = key

        let content = UNMutableNotificationContent()
        content.title = "SIM流量提醒"
        content.body = "\(warning)，当前剩余\(Self.sizeString(snapshot.remainGB))，最远到期\(expiryText)"
        content.sound = .default
        let request = UNNotificationRequest(identifier: "sim-quota-warning-\(config.iccid)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func updateRelativeTimeItem() {
        guard let snapshot = lastSnapshot else {
            updatedItem.title = "更新时间: --"
            return
        }
        updatedItem.title = "更新时间: \(Self.relativeTimeString(since: snapshot.fetchedAt))"
    }

    private static func sizeString(_ gb: Double) -> String {
        if gb >= 100 {
            return String(format: "%.0fG", gb)
        }
        if gb >= 10 {
            return String(format: "%.1fG", gb)
        }
        return String(format: "%.2fG", gb)
    }

    private static func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func shortDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M-dd"
        return formatter.string(from: date)
    }

    private static func relativeTimeString(since date: Date) -> String {
        let seconds = max(Int(Date().timeIntervalSince(date)), 0)
        if seconds < 60 {
            return "刚刚"
        }

        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes)分钟前"
        }

        let hours = minutes / 60
        if hours < 24 {
            return "\(hours)小时前"
        }

        let days = hours / 24
        return "\(days)天前"
    }

    private static func displayMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError, let description = localizedError.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
