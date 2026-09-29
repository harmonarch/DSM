using System.Diagnostics;
using System.IO;

namespace DeepSeekMeter;

/// <summary>
/// 覆盖安装执行器：写一个批处理 helper，等本进程退出后用 robocopy 覆盖替换应用目录并重启。
/// 运行中的 exe 无法自我覆盖，必须由外部进程在本进程退出后完成替换。
/// 复制使用非破坏性的 /E（只补齐目标缺失的文件，绝不删除）：安装目录里与更新包无关的文件一律保留。
/// 代价是旧版本遗留的多余文件不会被清理，但远好于误删用户数据。
/// </summary>
public static class UpdateInstaller
{
    /// <summary>
    /// 启动替换 helper 并返回（调用方随后自行退出应用）。
    /// 写脚本前先预检安装目录可写性：不可写时抛中文异常，调用方弹窗提示，应用保持运行而不退出。
    /// </summary>
    public static void ReplaceAndRestart(string stagingDirectory)
    {
        var appDir = AppContext.BaseDirectory;
        var exeName = Path.GetFileName(Environment.ProcessPath) ?? "DeepSeekMeter.exe";
        var source = LocatePayload(stagingDirectory);
        EnsureInstallDirectoryWritable(appDir);
        var scriptPath = Path.Combine(Path.GetTempPath(), $"dsm-update-{Guid.NewGuid():N}.cmd");
        File.WriteAllText(scriptPath, BuildScript(source, appDir, exeName));
        Process.Start(new ProcessStartInfo
        {
            FileName = "cmd.exe",
            Arguments = $"/c \"{scriptPath}\"",
            CreateNoWindow = true,
            UseShellExecute = false,
        });
    }

    /// <summary>定位更新包内真正含 exe 的目录（ZIP 可能带一层 DSM-win-x64 外壳）。</summary>
    private static string LocatePayload(string staging)
    {
        if (Directory.EnumerateFiles(staging, "*.exe").Any()) return staging;
        foreach (var dir in Directory.EnumerateDirectories(staging))
        {
            if (Directory.EnumerateFiles(dir, "*.exe").Any()) return dir;
        }
        throw new InvalidOperationException("更新包内未找到应用文件");
    }

    /// <summary>
    /// 预检安装目录可写性：写一个探针文件再立刻删除，确认覆盖更新不会因为权限/磁盘问题白跑一趟。
    /// 不可写时抛中文 InvalidOperationException，由 MainViewModel.InstallUpdate 弹窗告知用户。
    /// </summary>
    private static void EnsureInstallDirectoryWritable(string appDir)
    {
        var probePath = Path.Combine(appDir, $".dsm-write-test-{Guid.NewGuid():N}.tmp");
        try
        {
            File.WriteAllText(probePath, string.Empty);
            File.Delete(probePath);
        }
        catch (Exception ex)
        {
            throw new InvalidOperationException(
                $"安装目录不可写，无法自动更新：{appDir}。请将程序移动到有写入权限的目录后重试",
                ex);
        }
    }

    /// <summary>
    /// 转义要写进批处理文件的路径：% 会被 cmd 当成变量引用展开，必须写成 %%。
    /// 路径一律包在双引号内，空格、&amp; 等字符在双引号内按字面处理；" 不是合法的 Windows 路径字符。
    /// </summary>
    private static string EscapeBatchPath(string path) => path.Replace("%", "%%");

    /// <summary>
    /// helper 脚本：尽力等约 2 秒 → robocopy /E 非破坏性覆盖 → 追加日志 → 无条件重启 → 自删。
    /// /E 只复制不删除，所以即使 robocopy 因为 exe 仍被占用而失败（退出码 ≥ 8），旧版本依然完整可运行；
    /// 因此无论复制成功与否都重启，用户最差只会看到「应用重新打开、版本没变」，而不是应用消失。
    /// 复制输出与退出码追加到 %TEMP%\dsm-update.log（该行里的 %TEMP% 是故意保留的变量引用，不能转义）。
    /// 等待用 ping 而不是 timeout：本脚本由 GUI 进程无窗口拉起，没有可用的控制台输入，
    /// timeout 会直接报「Input redirection is not supported」而根本不等待，robocopy 就会撞上仍被占用的 exe。
    /// 注意：脚本正文保持纯 ASCII，避免 cmd 按 OEM 代码页读取 UTF-8 时中文变乱码。
    /// </summary>
    private static string BuildScript(string source, string appDir, string exeName) =>
        string.Join("\r\n",
            "@echo off",
            "ping -n 3 127.0.0.1 >nul",
            $"robocopy \"{EscapeBatchPath(source)}\" \"{EscapeBatchPath(appDir)}\" /E /NFL /NDL /NJH /NJS /NP >> \"%TEMP%\\dsm-update.log\" 2>&1",
            "echo [%date% %time%] robocopy exit=%errorlevel% >> \"%TEMP%\\dsm-update.log\"",
            $"start \"\" \"{EscapeBatchPath(Path.Combine(appDir, exeName))}\"",
            "del \"%~f0\"");
}
