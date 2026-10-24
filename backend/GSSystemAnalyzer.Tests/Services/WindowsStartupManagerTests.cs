using System;
using Xunit;
using GSSystemAnalyzer.Services;

namespace GSSystemAnalyzer.Tests.Services
{
    public class WindowsStartupManagerTests
    {
        private readonly WindowsStartupManager _manager;

        public WindowsStartupManagerTests()
        {
            _manager = new WindowsStartupManager();
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

        [Fact]
        public async Task ToggleStartupEntryAsync_SystemScope_Unelevated_ThrowsUnauthorizedAccessException()
        {
            if (OperatingSystem.IsWindows())
            {
                using var identity = System.Security.Principal.WindowsIdentity.GetCurrent();
                var principal = new System.Security.Principal.WindowsPrincipal(identity);
                bool isElevated = principal.IsInRole(System.Security.Principal.WindowsBuiltInRole.Administrator);

                if (!isElevated)
                {
                    var ex = await Assert.ThrowsAsync<UnauthorizedAccessException>(() =>
                        _manager.ToggleStartupEntryAsync("TestSystemApp", false, "system"));
                    Assert.Contains("Administrator privileges are required", ex.Message);
                }
            }
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

            string testPkg = $"_GSTest_Pkg_{Guid.NewGuid():N}";
            string testTask = "StartupTask";
            string testSubKeyPath = $@"Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData\{testPkg}\{testTask}";

            try
            {
                using (var taskKey = Microsoft.Win32.Registry.CurrentUser.CreateSubKey(testSubKeyPath))
                {
                    taskKey.SetValue("State", 2, Microsoft.Win32.RegistryValueKind.DWord);
                }

                await _manager.ToggleStartupEntryAsync($"appmodel|{testPkg}|{testTask}", false);

                using (var taskKey = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(testSubKeyPath))
                {
                    var state = taskKey?.GetValue("State") as int?;
                    Assert.Equal(1, state);
                }

                await _manager.ToggleStartupEntryAsync($"appmodel|{testPkg}|{testTask}", true);

                using (var taskKey = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(testSubKeyPath))
                {
                    var state = taskKey?.GetValue("State") as int?;
                    Assert.Equal(2, state);
                }
            }
            finally
            {
                using var root = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(@"Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData", writable: true);
                root?.DeleteSubKeyTree(testPkg, throwOnMissingSubKey: false);
            }
        }

        [Fact]
        public async Task ToggleStartupEntryAsync_StartupFolder_UpdatesStartupApprovedBytes()
        {
            if (!OperatingSystem.IsWindows()) return;

            string testItem = $"_GSTest_Folder_{Guid.NewGuid():N}.lnk";
            const string shadowPath = @"Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder";

            try
            {
                await _manager.ToggleStartupEntryAsync($"folder|user|{testItem}", false);

                using (var key = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(shadowPath))
                {
                    var bytes = key?.GetValue(testItem) as byte[];
                    Assert.NotNull(bytes);
                    Assert.False(WindowsStartupManager.IsStartupApprovedBytesEnabled(bytes));
                }

                await _manager.ToggleStartupEntryAsync($"folder|user|{testItem}", true);

                using (var key = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(shadowPath))
                {
                    var bytes = key?.GetValue(testItem) as byte[];
                    Assert.NotNull(bytes);
                    Assert.True(WindowsStartupManager.IsStartupApprovedBytesEnabled(bytes));
                }
            }
            finally
            {
                using var key = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(shadowPath, writable: true);
                key?.DeleteValue(testItem, throwOnMissingValue: false);
            }
        }

        [Fact]
        public async Task GetStartupEntriesAsync_ReturnsEntriesFromMultipleSources()
        {
            if (!OperatingSystem.IsWindows()) return;

            var entries = await _manager.GetStartupEntriesAsync();
            var list = System.Linq.Enumerable.ToList(entries);

            Assert.NotEmpty(list);
            Assert.All(list, e =>
            {
                Assert.False(string.IsNullOrWhiteSpace(e.Id));
                Assert.False(string.IsNullOrWhiteSpace(e.Name));
                Assert.Equal("windows", e.Platform);
            });
        }
    }
}