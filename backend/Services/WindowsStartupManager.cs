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
        private const string RunKeypath = @"Software\Microsoft\Windows\CurrentVersion\Run";
        private const string ShadowKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run";

        public Task<IEnumerable<StartupProgramDto>> GetStartupEntriesAsync()
        {
            var entries = new List<StartupProgramDto>();

            using (var userKey = Registry.CurrentUser.OpenSubKey(RunKeypath))
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
                    }
                }
            }

            using (var systemKey = Registry.LocalMachine.OpenSubKey(RunKeypath))
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

                    }
                }
            }

            return Task.FromResult<IEnumerable<StartupProgramDto>>(entries);
        }

        public Task ToggleStartupEntryAsync(string id, bool enable, string? scope = null)
        {
            bool isSystem;
            if (string.Equals(scope, "system", StringComparison.OrdinalIgnoreCase))
            {
                isSystem = true;
            }
            else if (string.Equals(scope, "user", StringComparison.OrdinalIgnoreCase))
            {
                isSystem = false;
            }
            else
            {
                using var userKey = Registry.CurrentUser.OpenSubKey(RunKeypath);
                if (userKey?.GetValue(id) != null)
                {
                    isSystem = false;
                }
                else
                {
                    using var sysKey = Registry.LocalMachine.OpenSubKey(RunKeypath);
                    isSystem = sysKey?.GetValue(id) != null;
                }
            }

            if (isSystem)
            {
                try
                {
                    using var shadowKey = Registry.LocalMachine.OpenSubKey(ShadowKeyPath, writable: true)
                        ?? Registry.LocalMachine.CreateSubKey(ShadowKeyPath);
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
                using var shadowKey = Registry.CurrentUser.OpenSubKey(ShadowKeyPath, writable: true)
                    ?? Registry.CurrentUser.CreateSubKey(ShadowKeyPath);
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
            using (var userKey = Registry.CurrentUser.OpenSubKey(RunKeypath, writable: true))
            {
                if (userKey?.GetValue(id) != null)
                {
                    userKey.DeleteValue(id, throwOnMissingValue: false);
                }
            }

            using (var systemKeyRead = Registry.LocalMachine.OpenSubKey(RunKeypath, writable: false))
            {
                if (systemKeyRead?.GetValue(id) != null)
                {
                    try
                    {
                        using var systemKeyWrite = Registry.LocalMachine.OpenSubKey(RunKeypath, writable: true);
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
                ? Registry.LocalMachine.OpenSubKey(ShadowKeyPath)
                : Registry.CurrentUser.OpenSubKey(ShadowKeyPath);
            var bytes = shadowKey?.GetValue(id) as byte[];

            return IsStartupApprovedBytesEnabled(bytes);
        }

        internal static bool IsStartupApprovedBytesEnabled(byte[]? bytes)
        {
            return bytes == null || bytes.Length == 0 || (bytes[0] & 1) == 0;
        }
    }
}