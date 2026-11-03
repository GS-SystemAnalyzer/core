using System;
using System.Collections.Generic;
using System.IO;
using System.Security;
using System.Threading.Tasks;
using GSSystemAnalyzer.Models;
using GSSystemAnalyzer.Interfaces;
using Microsoft.Win32;
using System.Text.RegularExpressions;

namespace GSSystemAnalyzer.Services
{
    public class WindowsStartupManager : IStartupManager
    {
        private const string RunKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
        private const string ShadowRunKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run";
        private const string Wow64RunKeyPath = @"Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run";
        private const string ShadowRun32KeyPath = @"Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32";
        private const string ShadowStartupFolderKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder";
        private const string AppModelPath = @"Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData";

        private static readonly Dictionary<string, string> KnownPackageTitles = new(StringComparer.OrdinalIgnoreCase)
        {
            { "MSTeams", "Microsoft Teams" },
            { "Microsoft.GamingApp", "Xbox" },
            { "Microsoft.WindowsTerminal", "Windows Terminal" },
            { "Microsoft.MicrosoftOfficeHub", "Microsoft 365 (Office)" },
            { "com.notion.app.desktop.notion", "Notion" },
            { "7EE7776C.LinkedInforWindows", "LinkedIn for Windows" },
            { "LinkedInforWindows", "LinkedIn for Windows" },
            { "SpotifyAB.SpotifyMusic", "Spotify Music" },
            { "SpotifyMusic", "Spotify Music" },
            { "Claude", "Claude" },
        };

        private readonly Func<RegistryHive, string, bool, RegistryKey?> _openKey;
        private readonly Func<RegistryHive, string, RegistryKey?> _createKey;
        private readonly Func<Environment.SpecialFolder, string> _folderPath;

        public WindowsStartupManager() : this(
            (hive, path, writable) => (hive == RegistryHive.CurrentUser ? Registry.CurrentUser : Registry.LocalMachine).OpenSubKey(path, writable),
            (hive, path) => (hive == RegistryHive.CurrentUser ? Registry.CurrentUser : Registry.LocalMachine).CreateSubKey(path),
            Environment.GetFolderPath)
        {
        }

        internal WindowsStartupManager(Func<RegistryHive, string, bool, RegistryKey?> openKey,
            Func<RegistryHive, string, RegistryKey?> createKey, Func<Environment.SpecialFolder, string> folderPath)
        {
            _openKey = openKey;
            _createKey = createKey;
            _folderPath = folderPath;
        }

        public Task<IEnumerable<StartupProgramDto>> GetStartupEntriesAsync()
        {
            var entries = new List<StartupProgramDto>();
            var seenIds = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

            using (var userKey = _openKey(RegistryHive.CurrentUser, RunKeyPath, false))
            {
                if (userKey != null)
                {
                    foreach (var valueName in userKey.GetValueNames())
                    {
                        var command = userKey.GetValue(valueName)?.ToString() ?? string.Empty;
                        var (path, args) = ParseCommand(command);

                        entries.Add(new StartupProgramDto
                        {
                            Id = valueName,
                            Name = valueName,
                            ExecutablePath = path,
                            Arguments = args,
                            IsEnabled = CheckIfEnabled(valueName, isSystem: false),
                            Scope = "user",
                            Platform = "windows"
                        });
                        seenIds.Add(valueName);
                    }
                }
            }

            using (var systemKey = _openKey(RegistryHive.LocalMachine, RunKeyPath, false))
            {
                if (systemKey != null)
                {
                    foreach (var valueName in systemKey.GetValueNames())
                    {
                        var command = systemKey.GetValue(valueName)?.ToString() ?? string.Empty;
                        var (path, args) = ParseCommand(command);

                        entries.Add(new StartupProgramDto
                        {
                            Id = valueName,
                            Name = valueName,
                            ExecutablePath = path,
                            Arguments = args,
                            IsEnabled = CheckIfEnabled(valueName, isSystem: true),
                            Scope = "system",
                            Platform = "windows"
                        });
                        seenIds.Add(valueName);
                    }
                }
            }

            using (var wowKey = _openKey(RegistryHive.LocalMachine, Wow64RunKeyPath, false))
            {
                if (wowKey != null)
                {
                    foreach (var valueName in wowKey.GetValueNames())
                    {
                        if (seenIds.Contains(valueName)) continue;

                        var command = wowKey.GetValue(valueName)?.ToString() ?? string.Empty;
                        var (path, args) = ParseCommand(command);

                        entries.Add(new StartupProgramDto
                        {
                            Id = $"wow64|{valueName}",
                            Name = valueName,
                            ExecutablePath = path,
                            Arguments = args,
                            IsEnabled = CheckIfWow64Enabled(valueName),
                            Scope = "system",
                            Platform = "windows"
                        });
                        seenIds.Add(valueName);
                    }
                }
            }

            EnumerateStartupFolder(Environment.SpecialFolder.Startup, isSystem: false, entries);
            EnumerateStartupFolder(Environment.SpecialFolder.CommonStartup, isSystem: true, entries);

            EnumerateAppModelEntries(entries);

            return Task.FromResult<IEnumerable<StartupProgramDto>>(entries);
        }

        private void EnumerateStartupFolder(Environment.SpecialFolder folder, bool isSystem, List<StartupProgramDto> entries)
        {
            string folderPath;
            try
            {
                folderPath = _folderPath(folder);
                if (string.IsNullOrWhiteSpace(folderPath) || !Directory.Exists(folderPath))
                    return;
            }
            catch
            {
                return;
            }

            try
            {
                var files = Directory.GetFiles(folderPath);
                foreach (var file in files)
                {
                    string ext = Path.GetExtension(file);
                    if (!string.Equals(ext, ".lnk", StringComparison.OrdinalIgnoreCase) &&
                        !string.Equals(ext, ".exe", StringComparison.OrdinalIgnoreCase) &&
                        !string.Equals(ext, ".bat", StringComparison.OrdinalIgnoreCase) &&
                        !string.Equals(ext, ".cmd", StringComparison.OrdinalIgnoreCase))
                    {
                        continue;
                    }

                    string fileName = Path.GetFileName(file);
                    string name = Path.GetFileNameWithoutExtension(fileName);
                    string scope = isSystem ? "system" : "user";
                    string id = $"folder|{scope}|{fileName}";

                    entries.Add(new StartupProgramDto
                    {
                        Id = id,
                        Name = name,
                        ExecutablePath = file,
                        Arguments = string.Empty,
                        IsEnabled = CheckIfFolderEnabled(fileName, isSystem),
                        Scope = scope,
                        Platform = "windows"
                    });
                }
            }
            catch
            {
                // Directory access failure
            }
        }

        private void EnumerateAppModelEntries(List<StartupProgramDto> entries)
        {
            try
            {
                using var appModelRoot = _openKey(RegistryHive.CurrentUser, AppModelPath, false);
                if (appModelRoot == null) return;

                foreach (var packageSubKeyName in appModelRoot.GetSubKeyNames())
                {
                    using var packageKey = appModelRoot.OpenSubKey(packageSubKeyName);
                    if (packageKey == null) continue;

                    foreach (var taskSubKeyName in packageKey.GetSubKeyNames())
                    {
                        using var taskKey = packageKey.OpenSubKey(taskSubKeyName);
                        if (taskKey == null) continue;

                        var stateVal = taskKey.GetValue("State");
                        if (stateVal is int stateInt)
                        {
                            string cleanName = FormatAppModelName(packageSubKeyName, taskSubKeyName);
                            entries.Add(new StartupProgramDto
                            {
                                Id = $"appmodel|{packageSubKeyName}|{taskSubKeyName}",
                                Name = cleanName,
                                ExecutablePath = packageSubKeyName,
                                Arguments = taskSubKeyName,
                                IsEnabled = IsAppModelStateEnabled(stateInt),
                                Scope = "user",
                                Platform = "windows"
                            });
                        }
                    }
                }
            }
            catch
            {
                // Registry access failure
            }
        }

        public Task ToggleStartupEntryAsync(string id, bool enable, string? scope = null)
        {
            if (id.StartsWith("appmodel|", StringComparison.OrdinalIgnoreCase))
            {
                var parts = id.Split('|');
                if (parts.Length >= 3)
                {
                    string pkg = parts[1];
                    string task = parts[2];
                    string taskPath = $@"{AppModelPath}\{pkg}\{task}";

                    using var taskKey = _openKey(RegistryHive.CurrentUser, taskPath, true)
                        ?? _createKey(RegistryHive.CurrentUser, taskPath);
                    if (taskKey != null)
                    {
                        taskKey.SetValue("State", enable ? 2 : 1, RegistryValueKind.DWord);
                    }
                }
                return Task.CompletedTask;
            }

            if (id.StartsWith("folder|", StringComparison.OrdinalIgnoreCase))
            {
                var parts = id.Split('|');
                if (parts.Length >= 3)
                {
                    bool isSystem = string.Equals(parts[1], "system", StringComparison.OrdinalIgnoreCase) ||
                                    string.Equals(scope, "system", StringComparison.OrdinalIgnoreCase);
                    string fileName = parts[2];

                    if (isSystem)
                    {
                        try
                        {
                            using var shadowKey = _openKey(RegistryHive.LocalMachine, ShadowStartupFolderKeyPath, true)
                                ?? _createKey(RegistryHive.LocalMachine, ShadowStartupFolderKeyPath);
                            if (shadowKey != null)
                            {
                                ApplyShadowValue(shadowKey, fileName, enable);
                            }
                        }
                        catch (Exception ex) when (ex is UnauthorizedAccessException || ex is SecurityException)
                        {
                            throw new UnauthorizedAccessException($"Administrator privileges are required to modify the system-level application: {fileName}");
                        }
                    }
                    else
                    {
                        using var shadowKey = _openKey(RegistryHive.CurrentUser, ShadowStartupFolderKeyPath, true)
                            ?? _createKey(RegistryHive.CurrentUser, ShadowStartupFolderKeyPath);
                        if (shadowKey != null)
                        {
                            ApplyShadowValue(shadowKey, fileName, enable);
                        }
                    }
                }
                return Task.CompletedTask;
            }

            if (id.StartsWith("wow64|", StringComparison.OrdinalIgnoreCase))
            {
                string valueName = id["wow64|".Length..];
                try
                {
                    using var shadowKey = _openKey(RegistryHive.LocalMachine, ShadowRun32KeyPath, true)
                        ?? _createKey(RegistryHive.LocalMachine, ShadowRun32KeyPath);
                    if (shadowKey != null)
                    {
                        ApplyShadowValue(shadowKey, valueName, enable);
                    }
                }
                catch (Exception ex) when (ex is UnauthorizedAccessException || ex is SecurityException)
                {
                    throw new UnauthorizedAccessException($"Administrator privileges are required to modify the system-level application: {valueName}");
                }
                return Task.CompletedTask;
            }

            bool isSys;
            if (string.Equals(scope, "system", StringComparison.OrdinalIgnoreCase))
            {
                isSys = true;
            }
            else if (string.Equals(scope, "user", StringComparison.OrdinalIgnoreCase))
            {
                isSys = false;
            }
            else
            {
                using var userKey = _openKey(RegistryHive.CurrentUser, RunKeyPath, false);
                if (userKey?.GetValue(id) != null)
                {
                    isSys = false;
                }
                else
                {
                    using var sysKey = _openKey(RegistryHive.LocalMachine, RunKeyPath, false);
                    isSys = sysKey?.GetValue(id) != null;
                }
            }

            if (isSys)
            {
                try
                {
                    using var shadowKey = _openKey(RegistryHive.LocalMachine, ShadowRunKeyPath, true)
                        ?? _createKey(RegistryHive.LocalMachine, ShadowRunKeyPath);
                    if (shadowKey != null)
                    {
                        ApplyShadowValue(shadowKey, id, enable);
                    }
                }
                catch (Exception ex) when (ex is UnauthorizedAccessException || ex is SecurityException)
                {
                    throw new UnauthorizedAccessException($"Administrator privileges are required to modify the system-level application: {id}");
                }
            }
            else
            {
                using var shadowKey = _openKey(RegistryHive.CurrentUser, ShadowRunKeyPath, true)
                    ?? _createKey(RegistryHive.CurrentUser, ShadowRunKeyPath);
                if (shadowKey != null)
                {
                    ApplyShadowValue(shadowKey, id, enable);
                }
            }

            return Task.CompletedTask;
        }

        private static void ApplyShadowValue(RegistryKey shadowKey, string id, bool enable)
        {
            byte[]? currentValue = shadowKey.GetValue(id) as byte[];
            byte[] newValue = (currentValue != null && currentValue.Length >= 12)
                ? (byte[])currentValue.Clone()
                : new byte[12];

            newValue[0] = enable ? (byte)0x02 : (byte)0x03;
            var timestamp = BitConverter.GetBytes(DateTime.UtcNow.ToFileTimeUtc());
            Array.Copy(timestamp, 0, newValue, 4, 8);

            shadowKey.SetValue(id, newValue, RegistryValueKind.Binary);
        }

        public Task DeleteStartupEntryAsync(string id)
        {
            if (id.StartsWith("appmodel|", StringComparison.OrdinalIgnoreCase))
            {
                var parts = id.Split('|');
                if (parts.Length >= 3)
                {
                    string pkg = parts[1];
                    string task = parts[2];
                    string taskPath = $@"{AppModelPath}\{pkg}\{task}";

                    using var taskKey = _openKey(RegistryHive.CurrentUser, taskPath, true);
                    taskKey?.SetValue("State", 1, RegistryValueKind.DWord);
                }
                return Task.CompletedTask;
            }

            if (id.StartsWith("folder|", StringComparison.OrdinalIgnoreCase))
            {
                var parts = id.Split('|');
                if (parts.Length >= 3)
                {
                    bool isSystem = string.Equals(parts[1], "system", StringComparison.OrdinalIgnoreCase);
                    string fileName = parts[2];
                    var folder = isSystem ? Environment.SpecialFolder.CommonStartup : Environment.SpecialFolder.Startup;
                    string folderPath = _folderPath(folder);
                    string filePath = Path.Combine(folderPath, fileName);

                    try
                    {
                        if (File.Exists(filePath))
                        {
                            File.Delete(filePath);
                        }

                        using var shadowKey = isSystem
                            ? _openKey(RegistryHive.LocalMachine, ShadowStartupFolderKeyPath, true)
                            : _openKey(RegistryHive.CurrentUser, ShadowStartupFolderKeyPath, true);
                        shadowKey?.DeleteValue(fileName, throwOnMissingValue: false);
                    }
                    catch (Exception ex) when (ex is UnauthorizedAccessException || ex is SecurityException)
                    {
                        throw new UnauthorizedAccessException($"Administrator privileges are required to delete the system-level application: {fileName}");
                    }
                }
                return Task.CompletedTask;
            }

            if (id.StartsWith("wow64|", StringComparison.OrdinalIgnoreCase))
            {
                string valueName = id["wow64|".Length..];
                try
                {
                    using var wowKey = _openKey(RegistryHive.LocalMachine, Wow64RunKeyPath, true);
                    wowKey?.DeleteValue(valueName, throwOnMissingValue: false);
                }
                catch (Exception ex) when (ex is UnauthorizedAccessException || ex is SecurityException)
                {
                    throw new UnauthorizedAccessException($"Administrator privileges are required to delete the system-level application: {valueName}");
                }
                return Task.CompletedTask;
            }

            using (var userKey = _openKey(RegistryHive.CurrentUser, RunKeyPath, true))
            {
                if (userKey?.GetValue(id) != null)
                {
                    userKey.DeleteValue(id, throwOnMissingValue: false);
                }
            }

            using (var systemKeyRead = _openKey(RegistryHive.LocalMachine, RunKeyPath, false))
            {
                if (systemKeyRead?.GetValue(id) != null)
                {
                    try
                    {
                        using var systemKeyWrite = _openKey(RegistryHive.LocalMachine, RunKeyPath, true);
                        systemKeyWrite?.DeleteValue(id, throwOnMissingValue: false);
                    }
                    catch (Exception ex) when (ex is UnauthorizedAccessException || ex is SecurityException)
                    {
                        throw new UnauthorizedAccessException($"Administrator privileges are required to delete the system-level application: {id}");
                    }
                }
            }

            return Task.CompletedTask;
        }

        public (string path, string args) ParseCommand(string command)
        {
            var match = Regex.Match(command, @"^(?:""([^""]+)""|([^""]+\.(?:exe|bat|cmd)))\s*(.*)$", RegexOptions.IgnoreCase);
            if (match.Success)
            {
                string path = !string.IsNullOrEmpty(match.Groups[1].Value) ? match.Groups[1].Value : match.Groups[2].Value;
                return (path, match.Groups[3].Value);
            }
            return (command, string.Empty);
        }

        internal bool CheckIfEnabled(string id, bool isSystem)
        {
            using var shadowKey = isSystem
                ? _openKey(RegistryHive.LocalMachine, ShadowRunKeyPath, false)
                : _openKey(RegistryHive.CurrentUser, ShadowRunKeyPath, false);
            var bytes = shadowKey?.GetValue(id) as byte[];

            return IsStartupApprovedBytesEnabled(bytes);
        }

        internal bool CheckIfFolderEnabled(string fileName, bool isSystem)
        {
            try
            {
                using var shadowKey = isSystem
                    ? _openKey(RegistryHive.LocalMachine, ShadowStartupFolderKeyPath, false)
                    : _openKey(RegistryHive.CurrentUser, ShadowStartupFolderKeyPath, false);
                var bytes = shadowKey?.GetValue(fileName) as byte[];
                return IsStartupApprovedBytesEnabled(bytes);
            }
            catch
            {
                return true;
            }
        }

        internal bool CheckIfWow64Enabled(string valueName)
        {
            try
            {
                using var shadowKey = _openKey(RegistryHive.LocalMachine, ShadowRun32KeyPath, false);
                var bytes = shadowKey?.GetValue(valueName) as byte[];
                return IsStartupApprovedBytesEnabled(bytes);
            }
            catch
            {
                return true;
            }
        }

        internal static bool IsStartupApprovedBytesEnabled(byte[]? bytes)
        {
            return bytes == null || bytes.Length == 0 || (bytes[0] & 1) == 0;
        }

        internal static string FormatAppModelName(string packageFamilyName, string taskId)
        {
            if (string.IsNullOrWhiteSpace(packageFamilyName))
                return taskId ?? string.Empty;

            int underscoreIdx = packageFamilyName.LastIndexOf('_');
            string baseName = underscoreIdx > 0 ? packageFamilyName[..underscoreIdx] : packageFamilyName;

            if (KnownPackageTitles.TryGetValue(baseName, out var exactTitle))
                return exactTitle;

            baseName = Regex.Replace(baseName, @"^[0-9A-Fa-f]{8}\.", "");

            if (KnownPackageTitles.TryGetValue(baseName, out var titleAfterHex))
                return titleAfterHex;

            if (baseName.StartsWith("com.", StringComparison.OrdinalIgnoreCase) ||
                baseName.StartsWith("org.", StringComparison.OrdinalIgnoreCase) ||
                baseName.StartsWith("io.", StringComparison.OrdinalIgnoreCase))
            {
                int lastDot = baseName.LastIndexOf('.');
                if (lastDot >= 0 && lastDot < baseName.Length - 1)
                {
                    baseName = baseName[(lastDot + 1)..];
                    if (baseName.Length > 0)
                        baseName = char.ToUpperInvariant(baseName[0]) + baseName[1..];
                    return baseName;
                }
            }

            string[] prefixesToStrip = ["SpotifyAB.", "AppUp.", "TelegramMessengerLLP.", "SAMSUNGELECTRONICSCoLtd.", "Microsoft."];
            foreach (var prefix in prefixesToStrip)
            {
                if (baseName.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
                {
                    baseName = baseName[prefix.Length..];
                    break;
                }
            }

            if (KnownPackageTitles.TryGetValue(baseName, out var titleAfterPrefix))
                return titleAfterPrefix;

            baseName = Regex.Replace(baseName, @"(?<=[a-zA-Z])for(?=[A-Z])", " for ");
            baseName = Regex.Replace(baseName, @"(?<=[a-z])(?=[A-Z])", " ");

            return baseName.Trim();
        }

        internal static bool IsAppModelStateEnabled(int? state)
        {
            return state.HasValue && (state.Value == 2 || state.Value == 3);
        }
    }
}
