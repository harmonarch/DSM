using System.Diagnostics;
using System.IO;

namespace DeepSeekMeter;

/// <summary>
/// 覆盖安装执行器：写一个批处理 helper，等本进程退出后用 robocopy 镜像替换应用目录并重启。
/// 运行中的 exe 无法自我覆盖，必须由外部进程在本进程退出后完成替换。
/// </summary>
public static class UpdateInstaller
{
    /// <summary>启动替换 helper 并返回（调用方随后自行退出应用）。</summary>
    public static void ReplaceAndRestart(string stagingDirectory)
    {
        var appDir = AppContext.BaseDirectory;
        var exeName = Path.GetFileName(Environment.ProcessPath) ?? "DeepSeekMeter.exe";
        var source = LocatePayload(stagingDirectory);
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
    /// helper 脚本：等 2 秒（确保应用已退出）→ robocopy 镜像替换 → 重启 → 自删。
    /// robocopy 退出码 &lt; 8 视为成功（1 = 已复制文件）。
    /// </summary>
    private static string BuildScript(string source, string appDir, string exeName) =>
        string.Join("\r\n",
            "@echo off",
            "timeout /t 2 /nobreak >nul",
            $"robocopy \"{source}\" \"{appDir}\" /MIR /NFL /NDL /NJH /NJS /NP",
            "if %errorlevel% lss 8 (",
            $"  start \"\" \"{Path.Combine(appDir, exeName)}\"",
            ")",
            "del \"%~f0\"");
}
