using System.IO;
using System.IO.Compression;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text.Json;

namespace DeepSeekMeter.Core;

/// <summary>更新流程状态。</summary>
public enum UpdateStateKind
{
    Idle,           // 未检查
    Checking,       // 检查中
    UpToDate,       // 已是最新
    Downloading,    // 自动下载中
    ReadyToInstall, // 已下载校验完毕，等待上层替换重启
    Installing,     // 替换中
    Failed,         // 失败（Message 可直接展示）
}

/// <summary>更新状态快照（UI 渲染依据）。</summary>
public sealed record UpdateSnapshot(
    UpdateStateKind Kind,
    double Progress = 0,
    string? Version = null,
    string? Message = null);

/// <summary>
/// GitHub Release 应用内更新（对齐 macOS 版 UpdateService.swift）：
/// 检查 → 自动下载 → SHA256 校验 → 解包到暂存目录，替换与重启由上层（WPF）执行。
/// 网络仅 GET api.github.com 与 Release 资源，不上报任何本地数据。
/// </summary>
public sealed class UpdateService
{
    /// <summary>更新源仓库（GitHub Releases 提供 macOS ZIP / Windows ZIP / APK 与 SHA256SUMS.txt）。</summary>
    public const string RepoSlug = "harmonarch/DSM";

    private static readonly string ReleasesApiUrl = $"https://api.github.com/repos/{RepoSlug}/releases/latest";

    private static readonly HttpClient Http = CreateHttp();

    /// <summary>最新 Release 信息。</summary>
    public sealed record LatestRelease(string Version, string ZipUrl, string? SumsUrl);

    public UpdateSnapshot State { get; private set; } = new(UpdateStateKind.Idle);

    /// <summary>状态变化通知（上层据此刷新 UI）。</summary>
    public event Action? StateChanged;

    /// <summary>已下载并解包完成的暂存目录（ReadyToInstall 后非空）。</summary>
    public string? StagingDirectory { get; private set; }

    /// <summary>待安装的新版本号。</summary>
    public string? PendingVersion { get; private set; }

    public bool IsBusy =>
        State.Kind is UpdateStateKind.Checking or UpdateStateKind.Downloading or UpdateStateKind.Installing;

    private static HttpClient CreateHttp()
    {
        var client = new HttpClient();
        client.DefaultRequestHeaders.UserAgent.ParseAdd("DeepSeekMeter");
        client.DefaultRequestHeaders.Accept.ParseAdd("application/vnd.github+json");
        client.Timeout = TimeSpan.FromSeconds(120);
        return client;
    }

    // MARK: - 对外动作

    /// <summary>检查更新；发现新版本后自动下载、校验、解包，完成后进入 ReadyToInstall。</summary>
    public void CheckForUpdate() => _ = CheckForUpdateAsync();

    public async Task CheckForUpdateAsync()
    {
        if (IsBusy) return;
        try
        {
            Set(new UpdateSnapshot(UpdateStateKind.Checking));
            var release = await FetchLatestReleaseAsync();
            var current = CurrentVersion();
            if (!Formatting.IsVersion(release.Version, current))
            {
                PendingVersion = null;
                Set(new UpdateSnapshot(UpdateStateKind.UpToDate, Version: current));
                return;
            }

            PendingVersion = release.Version;
            // 发现新版本即自动下载（替换重启仍需用户点击确认）
            Set(new UpdateSnapshot(UpdateStateKind.Downloading, 0, release.Version));
            var zipPath = await DownloadAsync(release.ZipUrl, progress =>
                Set(new UpdateSnapshot(UpdateStateKind.Downloading, progress, release.Version)));
            await VerifyChecksumAsync(zipPath, release.SumsUrl);

            var staging = Path.Combine(Path.GetTempPath(), $"dsm-update-{Guid.NewGuid():N}");
            ZipFile.ExtractToDirectory(zipPath, staging, overwriteFiles: true);
            CleanupFile(zipPath);

            CleanupStaging();
            StagingDirectory = staging;
            Set(new UpdateSnapshot(UpdateStateKind.ReadyToInstall, Version: release.Version));
        }
        catch (Exception ex)
        {
            CleanupStaging();
            Set(new UpdateSnapshot(UpdateStateKind.Failed, Message: $"更新失败：{ex.Message}"));
        }
    }

    /// <summary>上层开始执行替换重启时置状态（防止重复触发）。</summary>
    public void BeginInstall()
    {
        if (State.Kind == UpdateStateKind.ReadyToInstall)
        {
            Set(new UpdateSnapshot(UpdateStateKind.Installing, Version: PendingVersion));
        }
    }

    // MARK: - 检查 / 下载 / 校验

    private async Task<LatestRelease> FetchLatestReleaseAsync()
    {
        using var response = await Http.GetAsync(ReleasesApiUrl);
        if (!response.IsSuccessStatusCode)
        {
            throw new InvalidOperationException($"HTTP {(int)response.StatusCode}");
        }
        using var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        var root = doc.RootElement;
        var tag = root.GetProperty("tag_name").GetString() ?? "";
        string? zipUrl = null;
        string? sumsUrl = null;
        foreach (var asset in root.GetProperty("assets").EnumerateArray())
        {
            var name = asset.GetProperty("name").GetString() ?? "";
            var url = asset.TryGetProperty("browser_download_url", out var u) ? u.GetString() : null;
            if (url is null) continue;
            if (zipUrl is null && name.StartsWith("DSM-", StringComparison.Ordinal) && name.EndsWith("-win-x64.zip", StringComparison.Ordinal))
            {
                zipUrl = url;
            }
            if (sumsUrl is null && name == "SHA256SUMS.txt")
            {
                sumsUrl = url;
            }
        }
        if (zipUrl is null)
        {
            throw new InvalidOperationException("Release 中没有 Windows 更新包");
        }
        var version = tag.Trim();
        if (version.StartsWith("v") || version.StartsWith("V")) version = version[1..];
        return new LatestRelease(version, zipUrl, sumsUrl);
    }

    /// <summary>下载更新包 ZIP 到临时文件（流式写入，按 1% 步进回报进度）。</summary>
    private static async Task<string> DownloadAsync(string url, Action<double> onProgress)
    {
        using var response = await Http.GetAsync(url, HttpCompletionOption.ResponseHeadersRead);
        response.EnsureSuccessStatusCode();
        var total = response.Content.Headers.ContentLength ?? 0;
        var path = Path.Combine(Path.GetTempPath(), $"dsm-update-{Guid.NewGuid():N}.zip");
        await using var source = await response.Content.ReadAsStreamAsync();
        await using var target = File.Create(path);
        var buffer = new byte[81920];
        long written = 0;
        double lastReported = 0;
        int read;
        while ((read = await source.ReadAsync(buffer)) > 0)
        {
            await target.WriteAsync(buffer.AsMemory(0, read));
            written += read;
            if (total > 0)
            {
                var progress = Math.Min(1.0, (double)written / total);
                if (progress - lastReported >= 0.01)
                {
                    lastReported = progress;
                    onProgress(progress);
                }
            }
        }
        return path;
    }

    /// <summary>Release 附带 SHA256SUMS.txt 时校验哈希；没有则跳过（不强依赖）。</summary>
    private static async Task VerifyChecksumAsync(string zipPath, string? sumsUrl)
    {
        if (sumsUrl is null) return;
        var text = await Http.GetStringAsync(sumsUrl);
        var fileName = Path.GetFileName(zipPath);
        string? expected = null;
        foreach (var line in text.Split('\n'))
        {
            var parts = line.Split(' ', StringSplitOptions.RemoveEmptyEntries);
            if (parts.Length >= 2 && parts[1] == fileName)
            {
                expected = parts[0];
                break;
            }
        }
        if (expected is null) return;

        await using var stream = File.OpenRead(zipPath);
        using var sha = SHA256.Create();
        var hash = await sha.ComputeHashAsync(stream);
        var actual = Convert.ToHexString(hash).ToLowerInvariant();
        if (!string.Equals(actual, expected, StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException("SHA256 校验不符，安装包可能已损坏");
        }
    }

    // MARK: - 环境

    /// <summary>当前版本号（取程序集版本，格式 major.minor.patch）。</summary>
    public static string CurrentVersion()
    {
        var version = typeof(UpdateService).Assembly.GetName().Version;
        if (version is null) return "0";
        return $"{version.Major}.{Math.Max(version.Minor, 0)}.{Math.Max(version.Build, 0)}";
    }

    // MARK: - 清理

    private void CleanupStaging()
    {
        if (StagingDirectory is not { } staging) return;
        try { Directory.Delete(staging, recursive: true); } catch { /* 临时目录清理失败可忽略 */ }
        StagingDirectory = null;
    }

    private static void CleanupFile(string path)
    {
        try { File.Delete(path); } catch { /* 临时文件清理失败可忽略 */ }
    }

    private void Set(UpdateSnapshot state)
    {
        State = state;
        StateChanged?.Invoke();
    }
}
