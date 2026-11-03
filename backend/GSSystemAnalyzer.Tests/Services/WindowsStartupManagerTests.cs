using System;
using System.IO;
using System.Reflection;
using System.Runtime.Versioning;
using System.Security;
using Xunit;
using Xunit.Abstractions;
using GSSystemAnalyzer.Services;
using GSSystemAnalyzer.Interfaces;
using Microsoft.Win32;
using Microsoft.Extensions.DependencyInjection;

namespace GSSystemAnalyzer.Tests.Services
{
    public class WindowsStartupManagerTests
    {
        private readonly WindowsStartupManager _manager;
        private readonly ITestOutputHelper _output;

        public WindowsStartupManagerTests(ITestOutputHelper output)
        {
            _manager = new WindowsStartupManager();
            _output = output;
        }

        [Theory]
        [InlineData(@"C:\Windows\System32\cmd.exe", @"C:\Windows\System32\cmd.exe", "")]
        [InlineData(@"""C:\Program Files\Discord\Update.exe""", @"C:\Program Files\Discord\Update.exe", "")]
        [InlineData(@"""C:\Program Files\Discord\Update.exe"" --processStart Discord.exe", @"C:\Program Files\Discord\Update.exe", "--processStart Discord.exe")]
        [InlineData(@"C:\MyApp\app.exe -silent -minimized", @"C:\MyApp\app.exe", "-silent -minimized")]
        public void ParseCommand_HandlesVariousPathFormats_SafelyExtractsArgs(
            string rawCommand, string expectedPath, string expectedArgs)
        {
            var (path, args) = _manager.ParseCommand(rawCommand);

            Assert.Equal(expectedPath, path);
            Assert.Equal(expectedArgs, args);
        }

        [Fact]
        public async Task NativeIsolation_IsEstablishedBeforeStartupAccess()
        {
            RequireOwnedConstructor();
            if (!OperatingSystem.IsWindows()) return;
            using var fixture = new OwnedStartupFixture(_output);
            fixture.Set(RegistryHive.CurrentUser, Run, "owned", @"C:\owned.exe --quiet");
            fixture.Accesses.Clear();
            var entry = Assert.Single(await fixture.Manager.GetStartupEntriesAsync());
            Assert.Equal("owned", entry.Id);
            Assert.Equal(@"C:\owned.exe", entry.ExecutablePath);
            Assert.Equal("--quiet", entry.Arguments);
            Assert.Contains(("open", RegistryHive.CurrentUser, Run, false), fixture.Accesses);
        }

        [Fact]
        public void IsStartupApprovedBytesEnabled_HandlesNullAndEmpty()
        {
            Assert.True(WindowsStartupManager.IsStartupApprovedBytesEnabled(null));
            Assert.True(WindowsStartupManager.IsStartupApprovedBytesEnabled(Array.Empty<byte>()));
        }

        [Theory]
        [InlineData(new byte[] { 0x02, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }, true)]
        [InlineData(new byte[] { 0x04, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }, true)]
        [InlineData(new byte[] { 0x00, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }, true)]
        [InlineData(new byte[] { 0x06, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }, true)]
        [InlineData(new byte[] { 0x08, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }, true)]
        [InlineData(new byte[] { 0x03, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }, false)]
        [InlineData(new byte[] { 0x01, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }, false)]
        [InlineData(new byte[] { 0x09, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }, false)]
        public void IsStartupApprovedBytesEnabled_EvaluatesBit0FlagsCorrectly(byte[] bytes, bool expected)
        {
            var actual = WindowsStartupManager.IsStartupApprovedBytesEnabled(bytes);
            Assert.Equal(expected, actual);
        }

        [Theory]
        [InlineData("run", false)]
        [InlineData("run", true)]
        [InlineData("wow64", false)]
        [InlineData("wow64", true)]
        [InlineData("folder", false)]
        [InlineData("folder", true)]
        public async Task ToggleStartupEntryAsync_SystemDenial_IsDeterministic(string source, bool denyCreate)
        {
            if (!OperatingSystem.IsWindows()) return;
            using var fixture = new OwnedStartupFixture(_output);
            using var peer = new OwnedStartupFixture(_output);
            var shadow = source == "run" ? ShadowRun : source == "wow64" ? Shadow32 : ShadowFolder;
            var id = source == "run" ? "target" : source == "wow64" ? "wow64|target" : "folder|system|target";
            peer.Set(RegistryHive.LocalMachine, shadow, "sentinel", new byte[] { 2, 9, 8 });
            fixture.Set(RegistryHive.LocalMachine, Run, "sentinel", "unchanged");
            fixture.BeforeAccess = (operation, hive, path, writable) =>
            {
                if (hive == RegistryHive.LocalMachine && path == shadow &&
                    (denyCreate ? operation == "create" : writable))
                {
                    if (denyCreate) throw new SecurityException("controlled create denial");
                    throw new UnauthorizedAccessException("controlled open denial");
                }
            };
            var manager = fixture.Manager;
            var ex = await Assert.ThrowsAsync<UnauthorizedAccessException>(() => manager.ToggleStartupEntryAsync(id, false, "system"));
            Assert.Contains("Administrator privileges are required", ex.Message);
            Assert.Contains((denyCreate ? "create" : "open", RegistryHive.LocalMachine, shadow, true), fixture.Accesses);
            fixture.BeforeAccess = null;
            Assert.Null(fixture.Read(RegistryHive.LocalMachine, shadow, "target"));
            Assert.Equal("unchanged", fixture.Read(RegistryHive.LocalMachine, Run, "sentinel"));
            Assert.Equal(new byte[] { 2, 9, 8 }, peer.Read(RegistryHive.LocalMachine, shadow, "sentinel"));
        }

        [Theory]
        [InlineData("Claude_pzs8sxrjxfjjc", "ClaudeStartup", "Claude")]
        [InlineData("com.notion.app.desktop.notion_87smfmv0eebam", "com.notion.app.desktop.notion.Startup", "Notion")]
        [InlineData("Microsoft.WindowsTerminal_8wekyb3d8bbwe", "StartTerminalOnLoginTask", "Windows Terminal")]
        [InlineData("MSTeams_8wekyb3d8bbwe", "TeamsTfwStartupTask", "Microsoft Teams")]
        [InlineData("7EE7776C.LinkedInforWindows_w1wdnht996qgy", "LinkedInAppStartUpId", "LinkedIn for Windows")]
        [InlineData("SpotifyAB.SpotifyMusic_zpdnekdrzrea0", "Spotify", "Spotify Music")]
        [InlineData("Microsoft.GamingApp_8wekyb3d8bbwe", "Xbox.App.Tasks.FullTrustComponent", "Xbox")]
        public void FormatAppModelName_CleansPackageNamesIntoHumanTitles(string package, string task, string expected)
        {
            var actual = WindowsStartupManager.FormatAppModelName(package, task);
            Assert.Equal(expected, actual);
        }

        [Theory]
        [InlineData(2, true)]
        [InlineData(3, true)]
        [InlineData(1, false)]
        [InlineData(0, false)]
        [InlineData(null, false)]
        public void IsAppModelStateEnabled_EvaluatesStateDwordCorrectly(int? state, bool expected)
        {
            var actual = WindowsStartupManager.IsAppModelStateEnabled(state);
            Assert.Equal(expected, actual);
        }

        [Fact]
        public async Task ToggleStartupEntryAsync_AppModel_UpdatesStateDword()
        {
            if (!OperatingSystem.IsWindows()) return;
            using var fixture = new OwnedStartupFixture(_output);
            var path = AppModel + @"\MSTeams_owned\StartupTask";
            var peer = AppModel + @"\MSTeams_owned\PeerTask";
            fixture.Set(RegistryHive.CurrentUser, peer, "State", 3);
            await fixture.Manager.ToggleStartupEntryAsync("appmodel|MSTeams_owned|StartupTask", false);
            Assert.Contains(("create", RegistryHive.CurrentUser, path, true), fixture.Accesses);
            Assert.Equal(1, fixture.Read(RegistryHive.CurrentUser, path, "State"));
            await fixture.Manager.ToggleStartupEntryAsync("appmodel|MSTeams_owned|StartupTask", true);
            Assert.Equal(2, fixture.Read(RegistryHive.CurrentUser, path, "State"));
            await fixture.Manager.DeleteStartupEntryAsync("appmodel|MSTeams_owned|StartupTask");
            Assert.Equal(1, fixture.Read(RegistryHive.CurrentUser, path, "State"));
            Assert.Equal(3, fixture.Read(RegistryHive.CurrentUser, peer, "State"));
        }

        [Theory]
        [InlineData(false)]
        [InlineData(true)]
        public async Task StartupFolder_ToggleAndDelete_PreservePeer(bool system)
        {
            if (!OperatingSystem.IsWindows()) return;
            using var fixture = new OwnedStartupFixture(_output);
            var hive = system ? RegistryHive.LocalMachine : RegistryHive.CurrentUser;
            var scope = system ? "system" : "user";
            var folder = system ? fixture.CommonFolder : fixture.UserFolder;
            var file = Path.Combine(folder, "résumé 測試.lnk");
            var peer = Path.Combine(folder, "peer.cmd");
            File.WriteAllBytes(file, new byte[] { 5, 6 });
            File.WriteAllBytes(peer, new byte[] { 7, 8 });
            var id = $"folder|{scope}|{Path.GetFileName(file)}";
            await fixture.Manager.ToggleStartupEntryAsync(id, false);
            Assert.Contains(("create", hive, ShadowFolder, true), fixture.Accesses);
            Assert.False(fixture.Manager.CheckIfFolderEnabled(Path.GetFileName(file), system));
            fixture.Set(hive, ShadowFolder, "peer.cmd", new byte[] { 2, 9 });
            await fixture.Manager.ToggleStartupEntryAsync(id, true);
            Assert.True(fixture.Manager.CheckIfFolderEnabled(Path.GetFileName(file), system));
            await fixture.Manager.DeleteStartupEntryAsync(id);
            Assert.False(File.Exists(file));
            Assert.Null(fixture.Read(hive, ShadowFolder, Path.GetFileName(file)));
            Assert.Equal(new byte[] { 7, 8 }, File.ReadAllBytes(peer));
            Assert.Equal(new byte[] { 2, 9 }, fixture.Read(hive, ShadowFolder, "peer.cmd"));
        }

        [Fact]
        public async Task GetStartupEntriesAsync_ReturnsEntriesFromMultipleSources()
        {
            if (!OperatingSystem.IsWindows()) return;
            using var fixture = new OwnedStartupFixture(_output);
            fixture.Set(RegistryHive.CurrentUser, Run, "duplicate", @"C:\User.exe --user");
            fixture.Set(RegistryHive.LocalMachine, Run, "duplicate", @"C:\System.exe --system");
            fixture.Set(RegistryHive.LocalMachine, WowRun, "duplicate", @"C:\Suppressed.exe");
            fixture.Set(RegistryHive.LocalMachine, WowRun, "wow", @"C:\Wow.exe");
            fixture.Set(RegistryHive.CurrentUser, ShadowRun, "duplicate", new byte[] { 3 });
            fixture.Set(RegistryHive.LocalMachine, ShadowRun, "duplicate", new byte[] { 2 });
            fixture.Set(RegistryHive.LocalMachine, Shadow32, "wow", new byte[] { 3 });
            fixture.Set(RegistryHive.CurrentUser, AppModel + @"\MSTeams_owned\StartupTask", "State", 3);
            var userFile = Path.Combine(fixture.UserFolder, "résumé 測試.lnk");
            var systemFile = Path.Combine(fixture.CommonFolder, "common.cmd");
            File.WriteAllText(userFile, "shortcut");
            File.WriteAllText(systemFile, "command");
            File.WriteAllText(Path.Combine(fixture.UserFolder, "ignored.txt"), "ignored");
            fixture.Set(RegistryHive.CurrentUser, ShadowFolder, Path.GetFileName(userFile), new byte[] { 3 });
            fixture.Set(RegistryHive.LocalMachine, ShadowFolder, Path.GetFileName(systemFile), new byte[] { 2 });
            fixture.Accesses.Clear();
            var list = (await fixture.Manager.GetStartupEntriesAsync()).OrderBy(e => e.Id).ThenBy(e => e.Scope).ToArray();
            var expected = new (string, string, string, string?, bool, string)[]
            {
                ("appmodel|MSTeams_owned|StartupTask", "Microsoft Teams", "MSTeams_owned", "StartupTask", true, "user"),
                ("duplicate", "duplicate", @"C:\System.exe", "--system", true, "system"),
                ("duplicate", "duplicate", @"C:\User.exe", "--user", false, "user"),
                ("folder|system|common.cmd", "common", systemFile, "", true, "system"),
                ("folder|user|résumé 測試.lnk", "résumé 測試", userFile, "", false, "user"),
                ("wow64|wow", "wow", @"C:\Wow.exe", "", false, "system")
            }.OrderBy(e => e.Item1).ThenBy(e => e.Item6).ToArray();
            Assert.Equal(expected, list.Select(e => (e.Id, e.Name, e.ExecutablePath, e.Arguments, e.IsEnabled, e.Scope)).ToArray());
            Assert.All(list, e => Assert.Equal("windows", e.Platform));
            foreach (var (hive, path) in new[] {
                (RegistryHive.CurrentUser, Run), (RegistryHive.LocalMachine, Run),
                (RegistryHive.LocalMachine, WowRun), (RegistryHive.CurrentUser, ShadowRun),
                (RegistryHive.LocalMachine, ShadowRun), (RegistryHive.LocalMachine, Shadow32),
                (RegistryHive.CurrentUser, ShadowFolder), (RegistryHive.LocalMachine, ShadowFolder),
                (RegistryHive.CurrentUser, AppModel) })
                Assert.Contains(("open", hive, path, false), fixture.Accesses);
            Assert.Equal(new[] { Environment.SpecialFolder.Startup, Environment.SpecialFolder.CommonStartup }, fixture.Folders);
        }

        [Theory]
        [InlineData("user")]
        [InlineData("system")]
        [InlineData("wow64")]
        public async Task RegistryRun_ToggleAndDelete_AreConfinedToOwnedValues(string source)
        {
            if (!OperatingSystem.IsWindows()) return;
            using var fixture = new OwnedStartupFixture(_output);
            var hive = source == "user" ? RegistryHive.CurrentUser : RegistryHive.LocalMachine;
            var run = source == "wow64" ? WowRun : Run;
            var shadow = source == "wow64" ? Shadow32 : ShadowRun;
            var id = source == "wow64" ? "wow64|target" : "target";
            fixture.Set(hive, run, "target", @"C:\target.exe");
            fixture.Set(hive, run, "peer", @"C:\peer.exe");
            await fixture.Manager.ToggleStartupEntryAsync(id, false);
            Assert.Contains(("create", hive, shadow, true), fixture.Accesses);
            var bytes = Assert.IsType<byte[]>(fixture.Read(hive, shadow, "target"));
            Assert.Equal(12, bytes.Length);
            Assert.Equal(3, bytes[0]);
            bytes[1] = 91;
            fixture.Set(hive, shadow, "target", bytes);
            await fixture.Manager.ToggleStartupEntryAsync(id, true);
            var enabled = Assert.IsType<byte[]>(fixture.Read(hive, shadow, "target"));
            Assert.Equal(2, enabled[0]);
            Assert.Equal(91, enabled[1]);
            Assert.True(source == "wow64" ? fixture.Manager.CheckIfWow64Enabled("target") : fixture.Manager.CheckIfEnabled("target", source == "system"));
            await fixture.Manager.DeleteStartupEntryAsync(id);
            Assert.Null(fixture.Read(hive, run, "target"));
            Assert.Equal(@"C:\peer.exe", fixture.Read(hive, run, "peer"));
        }

        [Theory]
        [InlineData(false)]
        [InlineData(true)]
        public async Task DeleteSystemRun_DenialPreservesValues(bool wow64)
        {
            if (!OperatingSystem.IsWindows()) return;
            using var fixture = new OwnedStartupFixture(_output);
            var path = wow64 ? WowRun : Run;
            fixture.Set(RegistryHive.LocalMachine, path, "target", "keep");
            fixture.BeforeAccess = (_, hive, key, writable) =>
            {
                if (hive == RegistryHive.LocalMachine && key == path && writable)
                    throw new UnauthorizedAccessException("controlled denial");
            };
            var manager = fixture.Manager;
            var ex = await Assert.ThrowsAsync<UnauthorizedAccessException>(() => manager.DeleteStartupEntryAsync(wow64 ? "wow64|target" : "target"));
            Assert.Contains("Administrator privileges are required", ex.Message);
            Assert.Equal("keep", fixture.Read(RegistryHive.LocalMachine, path, "target"));
        }

        [Fact]
        public async Task EmptyOwnedState_AndRepeatCleanup_PreservePeerNamespace()
        {
            if (!OperatingSystem.IsWindows()) return;
            using var fixture = new OwnedStartupFixture(_output);
            using var peer = new OwnedStartupFixture(_output);
            peer.Set(RegistryHive.CurrentUser, Run, "sentinel", "peer");
            var file = Path.Combine(peer.UserFolder, "peer.lnk");
            File.WriteAllBytes(file, new byte[] { 8, 9 });
            Assert.Empty(await fixture.Manager.GetStartupEntriesAsync());
            fixture.Dispose();
            fixture.Dispose();
            Assert.Equal("peer", peer.Read(RegistryHive.CurrentUser, Run, "sentinel"));
            Assert.Equal(new byte[] { 8, 9 }, File.ReadAllBytes(file));
        }

        [Fact]
        public void PartialFixtureSetup_CleansOnlyItsOwnedRoots()
        {
            if (!OperatingSystem.IsWindows()) return;
            using var peer = new OwnedStartupFixture(_output);
            peer.Set(RegistryHive.CurrentUser, Run, "sentinel", "peer");
            var failure = new IOException("controlled setup failure");
            Assert.Same(failure, Assert.Throws<IOException>(() =>
            {
                if (!OperatingSystem.IsWindows()) return;
                using var fixture = new OwnedStartupFixture(_output, () => throw failure);
            }));
            Assert.Equal("peer", peer.Read(RegistryHive.CurrentUser, Run, "sentinel"));
        }

        [Fact]
        public void PublicConstructors_PreserveLazyProductRegistrations()
        {
            foreach (var type in new[] { typeof(WindowsStartupManager), typeof(WindowsRecycleBinProvider), typeof(LinuxRecycleBinProvider) })
                Assert.Empty(Assert.Single(type.GetConstructors()).GetParameters());
            var services = new ServiceCollection();
            services.AddScoped<IStartupManager, WindowsStartupManager>();
            services.AddSingleton<LinuxRecycleBinProvider>();
            if (OperatingSystem.IsWindows()) services.AddSingleton<IRecycleBinProvider, WindowsRecycleBinProvider>();
            using var provider = services.BuildServiceProvider();
            using var scope = provider.CreateScope();
            var manager = Assert.IsType<WindowsStartupManager>(scope.ServiceProvider.GetRequiredService<IStartupManager>());
            Assert.Equal((@"C:\owned.exe", "--quiet"), manager.ParseCommand(@"C:\owned.exe --quiet"));
            Assert.NotNull(provider.GetRequiredService<LinuxRecycleBinProvider>());
            if (OperatingSystem.IsWindows()) Assert.IsType<WindowsRecycleBinProvider>(provider.GetRequiredService<IRecycleBinProvider>());
        }

        private const string Run = @"Software\Microsoft\Windows\CurrentVersion\Run";
        private const string WowRun = @"Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run";
        private const string ShadowRun = @"Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run";
        private const string Shadow32 = @"Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32";
        private const string ShadowFolder = @"Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder";
        private const string AppModel = @"Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData";

        private static ConstructorInfo RequireOwnedConstructor()
        {
            var constructor = typeof(WindowsStartupManager).GetConstructor(BindingFlags.Instance | BindingFlags.NonPublic,
                null, new[] { typeof(Func<RegistryHive, string, bool, RegistryKey>),
                    typeof(Func<RegistryHive, string, RegistryKey>), typeof(Func<Environment.SpecialFolder, string>) }, null);
            Assert.True(constructor != null, "Startup requires owned registry open/create and folder resolution before access.");
            return constructor;
        }

        [SupportedOSPlatform("windows")]
        private sealed class OwnedStartupFixture : IDisposable
        {
            private readonly ITestOutputHelper _output;
            private readonly string _registryRoot = @"Software\GSSystemAnalyzer.Tests\" + Guid.NewGuid().ToString("N");
            private readonly string _fileRoot = Path.Combine(Path.GetTempPath(), "gsstartup_" + Guid.NewGuid().ToString("N"));
            public string UserFolder => Path.Combine(_fileRoot, "user 測試");
            public string CommonFolder => Path.Combine(_fileRoot, "common é");
            public WindowsStartupManager Manager { get; }
            public List<(string Operation, RegistryHive Hive, string Path, bool Writable)> Accesses { get; } = new();
            public List<Environment.SpecialFolder> Folders { get; } = new();
            public Action<string, RegistryHive, string, bool>? BeforeAccess { get; set; }

            public OwnedStartupFixture(ITestOutputHelper output, Action? afterRegistryCreated = null)
            {
                var constructor = RequireOwnedConstructor();
                _output = output;
                Manager = (WindowsStartupManager)constructor.Invoke(new object[] {
                    (Func<RegistryHive, string, bool, RegistryKey?>)Open,
                    (Func<RegistryHive, string, RegistryKey?>)Create,
                    (Func<Environment.SpecialFolder, string>)Folder });
                Log("OWNED", "REGISTRY", _registryRoot);
                Log("OWNED", "FILE", _fileRoot);
                try
                {
                    using (Registry.CurrentUser.CreateSubKey(_registryRoot)) { }
                    Directory.CreateDirectory(UserFolder);
                    afterRegistryCreated?.Invoke();
                    Directory.CreateDirectory(CommonFolder);
                }
                catch
                {
                    Dispose();
                    throw;
                }
            }

            private string Map(RegistryHive hive, string path)
            {
                Assert.True(hive == RegistryHive.CurrentUser || hive == RegistryHive.LocalMachine);
                Assert.True(new[] { Run, ShadowRun, ShadowFolder }.Contains(path) ||
                    (hive == RegistryHive.LocalMachine && new[] { WowRun, Shadow32 }.Contains(path)) ||
                    (hive == RegistryHive.CurrentUser && (path == AppModel || path.StartsWith(AppModel + "\\", StringComparison.Ordinal))));
                Assert.DoesNotContain("..", path);
                return $@"{_registryRoot}\{hive}\{path}";
            }

            private void Record(string operation, RegistryHive hive, string path, bool writable)
            {
                Accesses.Add((operation, hive, path, writable));
                _output.WriteLine($"ACCESS {operation} {hive} {writable} {path}");
                BeforeAccess?.Invoke(operation, hive, path, writable);
            }

            private RegistryKey? Open(RegistryHive hive, string path, bool writable)
            {
                var mapped = Map(hive, path);
                Record("open", hive, path, writable);
                return Registry.CurrentUser.OpenSubKey(mapped, writable);
            }

            private RegistryKey Create(RegistryHive hive, string path)
            {
                var mapped = Map(hive, path);
                Record("create", hive, path, true);
                return Registry.CurrentUser.CreateSubKey(mapped);
            }

            private string Folder(Environment.SpecialFolder folder)
            {
                Folders.Add(folder);
                return folder switch {
                    Environment.SpecialFolder.Startup => UserFolder,
                    Environment.SpecialFolder.CommonStartup => CommonFolder,
                    _ => throw new InvalidOperationException("Unexpected startup folder.")
                };
            }

            public void Set(RegistryHive hive, string path, string name, object value)
            {
                using var key = Create(hive, path);
                key.SetValue(name, value);
            }

            public object? Read(RegistryHive hive, string path, string name)
            {
                using var key = Open(hive, path, false);
                return key?.GetValue(name);
            }

            public void Dispose()
            {
                try
                {
                    Registry.CurrentUser.DeleteSubKeyTree(_registryRoot, throwOnMissingSubKey: false);
                    using var remaining = Registry.CurrentUser.OpenSubKey(_registryRoot);
                    Assert.Null(remaining);
                    Log("REMOVED", "REGISTRY", _registryRoot);
                }
                finally
                {
                    if (Directory.Exists(_fileRoot)) Directory.Delete(_fileRoot, true);
                    Assert.False(Directory.Exists(_fileRoot));
                    Log("REMOVED", "FILE", _fileRoot);
                }
            }

            private void Log(string operation, string kind, string path) =>
                _output.WriteLine($"{operation} {kind} {Environment.ProcessId} {DateTimeOffset.UtcNow:O} {path}");
        }
    }
}
