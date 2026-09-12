import Foundation
import AppKit
import CryptoKit

// MARK: - 更新错误

/// 更新流程错误（带用户可读中文文案）
enum UpdateError: LocalizedError {
    case network(String)
    case http(Int)
    case decoding(String)
    case noAsset
    case downloadIncomplete
    case checksumMismatch
    case translocated
    case notWritable
    case noAppBundle
    case tool(String, Int32)

    var errorDescription: String? { message }

    var message: String {
        switch self {
        case .network(let detail):
            return "网络错误：\(detail)"
        case .http(let code):
            return "HTTP \(code)"
        case .decoding(let detail):
            return "响应解析失败：\(detail)"
        case .noAsset:
            return "Release 中没有 macOS 更新包"
        case .downloadIncomplete:
            return "下载未完成"
        case .checksumMismatch:
            return "SHA256 校验不符，安装包可能已损坏"
        case .translocated:
            return "应用运行在临时隔离位置，请重新安装到「应用程序」文件夹后再更新"
        case .notWritable:
            return "应用所在目录不可写，请将应用移到「应用程序」文件夹后重试"
        case .noAppBundle:
            return "更新包内未找到 DeepSeekMeter.app"
        case .tool(let name, let code):
            return "\(name) 执行失败（退出码 \(code)）"
        }
    }
}

// MARK: - 更新服务

/// GitHub Release 应用内更新：检查 → 自动下载 → SHA256 校验 → 用户确认后覆盖安装并重启。
/// 网络仅 GET api.github.com 与 Release 资源（不上报任何本地数据，红线 5）；
/// 与 PlatformService（DeepSeek 平台接口）分属两个独立网络入口，互不依赖。
@MainActor
final class UpdateService: ObservableObject {

    /// 更新状态机（设置行按状态渲染）
    enum State: Equatable {
        case idle                          // 未检查
        case checking                      // 检查中
        case upToDate                      // 已是最新
        case downloading(progress: Double) // 自动下载中（0...1）
        case readyToInstall                // 已下载校验完毕，等待用户确认重启
        case installing                    // 覆盖替换中
        case failed(String)                // 失败（文案可直接展示）
    }

    /// 更新源仓库（GitHub Releases 提供 DMG / ZIP / APK 与 SHA256SUMS.txt）
    private static let repoSlug = "harmonarch/DSM"

    @Published private(set) var state: State = .idle

    private var pendingRelease: ReleaseInfo?
    private var stagedZipURL: URL?

    struct ReleaseInfo {
        let version: String
        let zipName: String // 更新包原始资源名（SHA256SUMS 按此名匹配行，本地文件沿用该名）
        let zipURL: URL
        let sumsURL: URL?
    }

    init() {}

    // MARK: 环境判定

    /// 当前安装的版本号（swift run 等非 .app 环境返回 nil）
    static var currentVersion: String? {
        guard Bundle.main.bundlePath.hasSuffix(".app") else { return nil }
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    /// 开发构建（swift run）：无应用包，不提供应用内更新
    var isDevBuild: Bool { Self.currentVersion == nil }

    /// 待安装 / 下载中的新版本号（UI 文案用）
    var pendingVersion: String? { pendingRelease?.version }

    private var isBusy: Bool {
        switch state {
        case .checking, .downloading, .installing: return true
        default: return false
        }
    }

    // MARK: 对外动作

    /// 检查更新；发现新版本后自动下载，完成后进入 readyToInstall 等用户确认
    func checkForUpdates() {
        guard !isBusy, !isDevBuild else { return }
        state = .checking
        Task { await checkAndDownload() }
    }

    /// 安装已下载好的更新：解包 → 验签 → 覆盖替换 → 重启
    func installDownloadedUpdate() {
        guard case .readyToInstall = state, let zipURL = stagedZipURL else { return }
        state = .installing
        Task { await performInstall(zipURL: zipURL) }
    }

    // MARK: 检查 + 下载

    private func checkAndDownload() async {
        do {
            let release = try await Self.fetchLatestRelease()
            guard isVersion(release.version, newerThan: Self.currentVersion ?? "0") else {
                state = .upToDate
                return
            }
            pendingRelease = release
            // 发现新版本即自动下载（安装仍需用户点击确认）
            state = .downloading(progress: 0)
            let zipURL = try await Self.downloadZip(release) { [weak self] progress in
                Task { @MainActor [weak self] in
                    guard let self, case .downloading = self.state else { return }
                    self.state = .downloading(progress: progress)
                }
            }
            try await Self.verifyChecksum(zipURL: zipURL, sumsURL: release.sumsURL)
            stagedZipURL = zipURL
            state = .readyToInstall
        } catch {
            if let staged = stagedZipURL {
                try? FileManager.default.removeItem(at: staged.deletingLastPathComponent())
            }
            stagedZipURL = nil
            pendingRelease = nil
            state = .failed((error as? UpdateError)?.message ?? error.localizedDescription)
        }
    }

    /// 拉取最新 Release（GET /releases/latest，未认证限额 60 次/小时/IP，启动级频率足够）
    private static func fetchLatestRelease() async throws -> ReleaseInfo {
        guard let url = URL(string: "https://api.github.com/repos/\(repoSlug)/releases/latest") else {
            throw UpdateError.decoding("无效 URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw UpdateError.network(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw UpdateError.http(http.statusCode)
        }
        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: URL?
            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
            }
        }
        struct Release: Decodable {
            let tagName: String
            let assets: [Asset]
            enum CodingKeys: String, CodingKey {
                case tagName = "tag_name"
                case assets
            }
        }
        let decoded: Release
        do {
            decoded = try JSONDecoder().decode(Release.self, from: data)
        } catch {
            throw UpdateError.decoding(error.localizedDescription)
        }
        var version = decoded.tagName.trimmingCharacters(in: .whitespaces)
        if version.hasPrefix("v") || version.hasPrefix("V") { version.removeFirst() }
        guard let asset = decoded.assets.first(where: { $0.name.hasPrefix("DSM-") && $0.name.hasSuffix("-macOS.zip") }),
              let zipURL = asset.browserDownloadURL else {
            throw UpdateError.noAsset
        }
        let sumsURL = decoded.assets.first(where: { $0.name == "SHA256SUMS.txt" })?.browserDownloadURL
        return ReleaseInfo(version: version, zipName: asset.name, zipURL: zipURL, sumsURL: sumsURL)
    }

    /// 下载更新包 ZIP 到临时目录（delegate 桥接 async，回调进度）
    private static func downloadZip(
        _ release: ReleaseInfo,
        onProgress: @escaping (Double) -> Void
    ) async throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dsm-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let destination = dir.appendingPathComponent(release.zipName)
        let downloader = ZipDownloader(destination: destination, onProgress: onProgress)
        return try await downloader.start(url: release.zipURL)
    }

    /// Release 附带 SHA256SUMS.txt 时校验哈希；没有则跳过（不强依赖）
    private static func verifyChecksum(zipURL: URL, sumsURL: URL?) async throws {
        guard let sumsURL else { return }
        var request = URLRequest(url: sumsURL)
        request.timeoutInterval = 15
        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(for: request)
        } catch {
            throw UpdateError.network(error.localizedDescription)
        }
        guard let text = String(data: data, encoding: .utf8) else { return }
        let fileName = zipURL.lastPathComponent
        // 行格式：<hex>  <文件名>
        let expected = text.split(whereSeparator: \.isNewline)
            .map { $0.split(whereSeparator: \.isWhitespace).map(String.init) }
            .first(where: { $0.count >= 2 && $0[1] == fileName })?.first
        guard let expected else { return }
        guard sha256Hex(of: zipURL).lowercased() == expected.lowercased() else {
            throw UpdateError.checksumMismatch
        }
    }

    private static func sha256Hex(of fileURL: URL) -> String {
        guard let data = try? Data(contentsOf: fileURL) else { return "" }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: 覆盖安装

    private func performInstall(zipURL: URL) async {
        let fm = FileManager.default
        do {
            let currentURL = Bundle.main.bundleURL
            // 带 quarantine 的包首次运行会被系统挪到随机只读位置（App Translocation），无法原位替换
            guard !currentURL.path.contains("AppTranslocation") else { throw UpdateError.translocated }
            guard fm.isWritableFile(atPath: currentURL.deletingLastPathComponent().path) else {
                throw UpdateError.notWritable
            }
            // 解包 + 验签（ad-hoc / Developer ID 均应通过结构校验）
            let staging = fm.temporaryDirectory
                .appendingPathComponent("dsm-update-staging-\(UUID().uuidString)", isDirectory: true)
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            try Self.runTool("/usr/bin/ditto", ["-x", "-k", zipURL.path, staging.path])
            let entries = try fm.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil)
            guard let newApp = entries.first(where: { $0.pathExtension == "app" }) else {
                throw UpdateError.noAppBundle
            }
            try Self.runTool("/usr/bin/codesign", ["--verify", "--deep", "--strict", newApp.path])
            // 原位替换：旧包改名备份（失败回滚用）→ 新包拷入原路径
            // Token 存 UserDefaults、开机自启按 bundle id 注册，路径不变，覆盖后均保留
            let backup = currentURL.appendingPathExtension("old-\(UUID().uuidString.prefix(6))")
            try fm.moveItem(at: currentURL, to: backup)
            do {
                try fm.copyItem(at: newApp, to: currentURL)
            } catch {
                try? fm.moveItem(at: backup, to: currentURL)
                throw error
            }
            try? fm.removeItem(at: backup)
            try? fm.removeItem(at: staging)
            try? fm.removeItem(at: zipURL.deletingLastPathComponent())
            stagedZipURL = nil
            // 重启到新版本：先挂一个等待旧进程退出的 watcher 再 open，
            // 避免旧进程仍在时 LaunchServices 只激活旧实例
            Self.relaunchAfterExit(of: currentURL)
            exit(0)
        } catch {
            state = .failed("安装更新失败：\((error as? UpdateError)?.message ?? error.localizedDescription)")
        }
    }

    /// 挂 detached watcher：等当前进程退出后 `open` 新包
    private static func relaunchAfterExit(of appURL: URL) {
        let escaped = appURL.path.replacingOccurrences(of: "'", with: "'\\''")
        let watcher = Process()
        watcher.executableURL = URL(fileURLWithPath: "/bin/sh")
        watcher.arguments = [
            "-c",
            "while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done; "
                + "exec /usr/bin/open '\(escaped)'"
        ]
        try? watcher.run()
    }

    // MARK: 工具

    private static func runTool(_ launchPath: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateError.tool((launchPath as NSString).lastPathComponent, process.terminationStatus)
        }
    }

    /// 清理上次覆盖安装留下的旧版本备份（DeepSeekMeter.app.old-*，启动时调用）
    static func cleanupStaleBackups() {
        guard Bundle.main.bundlePath.hasSuffix(".app") else { return }
        let fm = FileManager.default
        let container = Bundle.main.bundleURL.deletingLastPathComponent()
        guard let entries = try? fm.contentsOfDirectory(at: container, includingPropertiesForKeys: nil) else { return }
        for entry in entries where entry.lastPathComponent.hasPrefix("DeepSeekMeter.app.old-") {
            try? fm.removeItem(at: entry)
        }
    }
}

// MARK: - ZIP 下载会话

/// 单次 ZIP 下载：URLSessionDownloadDelegate 桥接 async/await，落盘到指定路径并回报进度
private final class ZipDownloader: NSObject, URLSessionDownloadDelegate {
    private let destination: URL
    private let onProgress: (Double) -> Void
    private var session: URLSession?
    private var continuation: CheckedContinuation<URL, Error>?
    private var movedFileURL: URL?
    private var moveError: Error?

    init(destination: URL, onProgress: @escaping (Double) -> Void) {
        self.destination = destination
        self.onProgress = onProgress
    }

    func start(url: URL) async throws -> URL {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 120
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        do {
            try FileManager.default.moveItem(at: location, to: destination)
            movedFileURL = destination
        } catch {
            moveError = error
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            finish(.failure(error))
        } else if let moved = movedFileURL {
            finish(.success(moved))
        } else {
            finish(.failure(moveError ?? UpdateError.downloadIncomplete))
        }
    }

    /// 只 resume 一次；结束后失效会话避免泄漏
    private func finish(_ result: Result<URL, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        session?.invalidateAndCancel()
        session = nil
        switch result {
        case .success(let url): continuation.resume(returning: url)
        case .failure(let error): continuation.resume(throwing: error)
        }
    }
}
