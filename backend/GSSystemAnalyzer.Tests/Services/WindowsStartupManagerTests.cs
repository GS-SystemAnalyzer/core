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
        
    }
}