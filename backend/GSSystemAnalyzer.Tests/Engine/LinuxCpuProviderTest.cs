using System;
using System.Collections.Generic;
using System.Text;
using GSSystemAnalyzer.Services;

namespace GSSystemAnalyzer.Tests.Engine
{
	public class LinuxCpuProviderTest : IDisposable
	{
		private readonly string _mockProcDir;
		private readonly string _mockStatPath;
		private readonly string _mockSysDir;
		private readonly string _ownedTempRoot;

		public LinuxCpuProviderTest() : this(Path.GetTempPath())
		{
		}

		internal LinuxCpuProviderTest(string tempBasePath)
		{
			var temp = Path.TrimEndingDirectorySeparator(Path.GetFullPath(Path.GetTempPath()));
			var basePath = Path.TrimEndingDirectorySeparator(Path.GetFullPath(tempBasePath));
			if (!string.Equals(basePath, temp, PathComparison) && !IsUnder(temp, basePath))
				throw new ArgumentException("Fixture base must be within the temporary directory.", nameof(tempBasePath));

			_ownedTempRoot = Path.Combine(basePath, "gs_linux_cpu_" + Guid.NewGuid().ToString("N"));
			_mockProcDir = Path.Combine(_ownedTempRoot, "proc");
			_mockStatPath = Path.Combine(_mockProcDir, "stat");
			_mockSysDir = Path.Combine(_ownedTempRoot, "sys");
		}

		public void Dispose()
		{
			var temp = Path.TrimEndingDirectorySeparator(Path.GetFullPath(Path.GetTempPath()));
			var owned = Path.TrimEndingDirectorySeparator(Path.GetFullPath(_ownedTempRoot));
			if (!IsUnder(temp, owned) || !Path.GetFileName(owned).StartsWith("gs_linux_cpu_", StringComparison.Ordinal))
				throw new InvalidOperationException("Fixture cleanup must target its owned temporary root.");
			if (Directory.Exists(owned)) Directory.Delete(owned, true);
		}

		private static StringComparison PathComparison =>
			OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal;

		private static bool IsUnder(string parent, string path)
		{
			var relative = Path.GetRelativePath(parent, path);
			return !Path.IsPathRooted(relative) && relative != "." && relative != ".." &&
				!relative.StartsWith(".." + Path.DirectorySeparatorChar, PathComparison);
		}

		private void WriteMockProcStat(string content)
		{
			Directory.CreateDirectory(_mockProcDir);
			File.WriteAllText(_mockStatPath, content);
		}

		#region LINUX METRICS METRICS ENGINE TESTS

#if !WINDOWS
        [Fact]
        public async Task LinuxProvider_FirstSample_IsDiscardedAndEstablishesBaseline()
        {
            string baselineTicks =
                "cpu0 1000 0 200 5000 0 0 0 0\n" +
                "cpu1 1000 0 200 5000 0 0 0 0\n";
            WriteMockProcStat(baselineTicks);
            var provider = new LinuxCpuProvider(Microsoft.Extensions.Logging.Abstractions.NullLogger<GSSystemAnalyzer.Services.LinuxCpuProvider>.Instance, _mockProcDir, _mockSysDir);

            string activeTicks =
                "cpu0 1200 0 250 5100 0 0 0 0\n" +
                "cpu1 1200 0 250 5100 0 0 0 0\n";
            WriteMockProcStat(activeTicks);

            var result = await provider.GetNextSampleAsync();

            Assert.NotNull(result);
            Assert.Equal(71.4, result.AverageLoad);
            Assert.True(result.AverageLoad > 0.0, $"Expected calculated load, got {result.AverageLoad}");
        }

        [Fact]
        public async Task LinuxProvider_Delta_IsAccurateAndCalculatedCorrectly()
        {
            WriteMockProcStat("cpu0 1000 0 100 5000 0 0 0 0\n");
            var provider = new LinuxCpuProvider(Microsoft.Extensions.Logging.Abstractions.NullLogger<GSSystemAnalyzer.Services.LinuxCpuProvider>.Instance, _mockProcDir, _mockSysDir);

            WriteMockProcStat("cpu0 1100 0 110 5050 0 0 0 0\n");
            var sample1 = await provider.GetNextSampleAsync();

            WriteMockProcStat("cpu0 1300 0 150 5060 0 0 0 0\n");
            var sample2 = await provider.GetNextSampleAsync();

            Assert.True(sample2.Delta != 0.0, $"Expected non-zero delta, got {sample2.Delta}");
            Assert.Equal(Math.Round(sample2.AverageLoad - sample1.AverageLoad, 1), sample2.Delta);
        }

        [Fact]
        public async Task LinuxProvider_CoreGroupingLogic_GeneratesCorrectLabelsFor8Cores()
        {
            string baseline = "";
            string active = "";
            for (int i = 0; i < 8; i++)
            {
                baseline += $"cpu{i} 1000 0 100 5000 0 0 0 0\n";
                active += $"cpu{i} 1100 0 150 5050 0 0 0 0\n";
            }

            WriteMockProcStat(baseline);
            var provider = new LinuxCpuProvider(Microsoft.Extensions.Logging.Abstractions.NullLogger<GSSystemAnalyzer.Services.LinuxCpuProvider>.Instance, _mockProcDir, _mockSysDir);
            WriteMockProcStat(active);

            var result = await provider.GetNextSampleAsync();


            Assert.True(result.CoreGroups.ContainsKey("CORE 0-3"));
            Assert.True(result.CoreGroups.ContainsKey("CORE 4-7"));
            Assert.Equal(4, result.CoreGroups["CORE 0-3"].Count);
            Assert.Equal(4, result.CoreGroups["CORE 4-7"].Count);
        }

        [Fact]
        public async Task LinuxProvider_SingleCoreMachine_DoesNotCrashAndGroupsCorrectly()
        {
            WriteMockProcStat("cpu0 1000 0 100 5000 0 0 0 0\n");
            var provider = new LinuxCpuProvider(Microsoft.Extensions.Logging.Abstractions.NullLogger<GSSystemAnalyzer.Services.LinuxCpuProvider>.Instance, _mockProcDir, _mockSysDir);
            WriteMockProcStat("cpu0 1100 0 150 5050 0 0 0 0\n");

            var exception = await Record.ExceptionAsync(async () => await provider.GetNextSampleAsync());
            Assert.Null(exception);

            var result = await provider.GetNextSampleAsync();
            Assert.True(result.CoreGroups.ContainsKey("CORE 0-0"));
            Assert.Single(result.CoreGroups["CORE 0-0"]);
        }

        [Fact]
        public async Task LinuxProvider_GodPayload_ParsesSystemTotalsAndCaches()
        {
            WriteMockProcStat("cpu0 1000 0 100 5000 0 0 0 0\n");

            // Mock Live Frequency (2450000 kHz = 2.45 GHz)
            string sysCpuDir = Path.Combine(_mockSysDir, "devices", "system", "cpu", "cpu0", "cpufreq");
            Directory.CreateDirectory(sysCpuDir);
            File.WriteAllText(Path.Combine(sysCpuDir, "scaling_cur_freq"), "2450000\n");

            // Mock File Handles (Linux format: allocated \t unused \t max)
            string fsDir = Path.Combine(_mockProcDir, "sys", "fs");
            Directory.CreateDirectory(fsDir);
            File.WriteAllText(Path.Combine(fsDir, "file-nr"), "12500\t0\t9223372036854775807\n");

            // Mock Active Threads (Inside the loadavg file)
            File.WriteAllText(Path.Combine(_mockProcDir, "loadavg"), "0.10 0.15 0.12 2/850 12345\n");

            // Mock L1, L2, L3 Caches
            string cacheDir = Path.Combine(_mockSysDir, "devices", "system", "cpu", "cpu0", "cache");
            Directory.CreateDirectory(Path.Combine(cacheDir, "index0"));
            Directory.CreateDirectory(Path.Combine(cacheDir, "index2"));
            Directory.CreateDirectory(Path.Combine(cacheDir, "index3"));
            File.WriteAllText(Path.Combine(cacheDir, "index0", "size"), "64K\n");
            File.WriteAllText(Path.Combine(cacheDir, "index2", "size"), "512K\n");
            File.WriteAllText(Path.Combine(cacheDir, "index3", "size"), "16M\n");

            // Mock Running Processes (Linux uses numbered folders for Process IDs)
            Directory.CreateDirectory(Path.Combine(_mockProcDir, "101")); // Process 1
            Directory.CreateDirectory(Path.Combine(_mockProcDir, "102")); // Process 2
            Directory.CreateDirectory(Path.Combine(_mockProcDir, "not_a_process")); // Engine should ignore this

            // Act: Fire up the engine!
            var provider = new LinuxCpuProvider(Microsoft.Extensions.Logging.Abstractions.NullLogger<GSSystemAnalyzer.Services.LinuxCpuProvider>.Instance, _mockProcDir, _mockSysDir);
            var result = await provider.GetNextSampleAsync();

            // Assert: Verify the engine extracted everything from the raw text files
            Assert.Equal(2.45, result.CurrentFrequencyGhz);
            Assert.Equal(12500, result.TotalHandles);
            Assert.Equal(850, result.TotalThreads);
            Assert.Equal(2, result.TotalProcesses);
            Assert.Equal("64K", result.L1Cache);
            Assert.Equal("512K", result.L2Cache);
            Assert.Equal("16M", result.L3Cache);
        }
#endif
		#endregion
	}
}
