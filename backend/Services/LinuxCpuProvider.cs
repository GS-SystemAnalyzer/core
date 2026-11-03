using GSSystemAnalyzer.Interfaces;
using GSSystemAnalyzer.Models;
using Microsoft.Extensions.Logging;

#if !WINDOWS
using System.IO;
#endif

namespace GSSystemAnalyzer.Services
{
	public class LinuxCpuProvider : ICpuMetricsProvider
	{
#if !WINDOWS
        // Stores the previous tick data for every core to calculate the delta
        private readonly Dictionary<string, (long Idle, long Total)> _prevCoreData = new();
        private readonly ILogger<LinuxCpuProvider> _logger;
        private readonly string _procRoot;
        private readonly string _sysRoot;
        private double _previousAverage = 0;

        public LinuxCpuProvider(ILogger<LinuxCpuProvider> logger, string? procRoot = null, string? sysRoot = null)
        {
            _logger = logger;
            _procRoot = procRoot ?? "/proc";
            _sysRoot = sysRoot ?? "/sys";
            // Do an initial read to populate the baseline data, just like discarding the first PerformanceCounter read
            var initialSnapshot = ReadProcStat();
            foreach (var core in initialSnapshot)
            {
                _prevCoreData[core.Key] = core.Value;
            }
        }

        public Task<CpuTelemetryDto> GetNextSampleAsync()
        {
            var dto = new CpuTelemetryDto();
            var currentData = ReadProcStat();
            var currentCoreLoads = new List<double>();

            foreach (var core in currentData)
            {
                string coreId = core.Key;
                long currentIdle = core.Value.Idle;
                long currentTotal = core.Value.Total;

                if (_prevCoreData.TryGetValue(coreId, out var prev))
                {
                    long totalDelta = currentTotal - prev.Total;
                    long idleDelta = currentIdle - prev.Idle;

                    double load = 0;
                    if (totalDelta > 0)
                    {
                        // The Linux CPU % Formula
                        load = (1.0 - ((double)idleDelta / totalDelta)) * 100.0;
                    }
                    currentCoreLoads.Add(Math.Clamp(Math.Round(load, 1), 0, 100));
                }
                else
                {
                    currentCoreLoads.Add(0); // Fallback for the very first tick
                }

                // Save current state for the next tick's math
                _prevCoreData[coreId] = (currentIdle, currentTotal);
            }

            if (currentCoreLoads.Count > 0)
            {
                // 1. Averages and Deltas
                double currentAverage = Math.Round(currentCoreLoads.Average(), 1);
                dto.AverageLoad = currentAverage;
                dto.Delta = Math.Round(currentAverage - _previousAverage, 1);
                _previousAverage = currentAverage;

                // 2. Dynamic Grouping Algorithm (Chunks of 4)
                for (int i = 0; i < currentCoreLoads.Count; i += 4)
                {
                    int end = Math.Min(i + 3, currentCoreLoads.Count - 1);
                    dto.CoreGroups.Add($"CORE {i}-{end}", currentCoreLoads.Skip(i).Take(4).ToList());
                }
            }

            try
            {
                // This system file holds the current frequency in kHz (e.g., 2400000 = 2.4 GHz)
                string freqText = File.ReadAllText(Path.Combine(_sysRoot, "devices", "system", "cpu", "cpu0", "cpufreq", "scaling_cur_freq"));
                if (long.TryParse(freqText.Trim(), out long freqKhz))
                {
                    // Convert kHz to GHz and round to 2 decimal places
                    dto.CurrentFrequencyGhz = Math.Round(freqKhz / 1000000.0, 2);
                }
            }
            catch
            {
                // Failsafe: Some Linux VMs (like WSL) or locked down containers don't expose hardware frequency
                dto.CurrentFrequencyGhz = 0.0;
            }

            try
            {
                // File-nr contains allocated file descriptors (Linux equivalent of Handles)
                string[] fileNr = File.ReadAllText(Path.Combine(_procRoot, "sys", "fs", "file-nr")).Split('\t', StringSplitOptions.RemoveEmptyEntries);
                if (fileNr.Length > 0 && int.TryParse(fileNr[0], out int handles))
                {
                    dto.TotalHandles = handles;
                }

                // Count numerical directories in /proc to get the exact Process Count
                dto.TotalProcesses = Directory.GetDirectories(_procRoot).Count(d => int.TryParse(Path.GetFileName(d), out _));

                // Read /proc/loadavg for active scheduling threads
                string loadAvg = File.ReadAllText(Path.Combine(_procRoot, "loadavg"));
                var parts = loadAvg.Split(' ', StringSplitOptions.RemoveEmptyEntries);
                if (parts.Length > 3)
                {
                    // Format is "active/total" (e.g., "1/456")
                    var threadParts = parts[3].Split('/');
                    if (threadParts.Length == 2 && int.TryParse(threadParts[1], out int totalThreads))
                    {
                        dto.TotalThreads = totalThreads;
                    }
                }
                
                // Hardware Caches (Linux exposes these directly in the filesystem)
                var cacheRoot = Path.Combine(_sysRoot, "devices", "system", "cpu", "cpu0", "cache");
                var l1Path = Path.Combine(cacheRoot, "index0", "size");
                var l2Path = Path.Combine(cacheRoot, "index2", "size");
                var l3Path = Path.Combine(cacheRoot, "index3", "size");
                if (File.Exists(l1Path))
                    dto.L1Cache = File.ReadAllText(l1Path).Trim();
                if (File.Exists(l2Path))
                    dto.L2Cache = File.ReadAllText(l2Path).Trim();
                if (File.Exists(l3Path))
                    dto.L3Cache = File.ReadAllText(l3Path).Trim();
            }
            catch 
            {
                // Silently bypass if Linux permissions restrict reading system states
            }

            return Task.FromResult(dto);
        }

        private Dictionary<string, (long Idle, long Total)> ReadProcStat()
        {
            var result = new Dictionary<string, (long Idle, long Total)>();
            var statPath = Path.Combine(_procRoot, "stat");
            try
            {
                var lines = File.ReadAllLines(statPath);
                foreach (var line in lines)
                {
                    // We only want the individual cores: cpu0, cpu1, cpu2, etc.
                    if (line.StartsWith("cpu") && line.Length > 3 && char.IsDigit(line[3]))
                    {
                        var parts = line.Split(' ', StringSplitOptions.RemoveEmptyEntries);
                        string coreId = parts[0];

                        // /proc/stat columns: user nice system idle iowait irq softirq steal guest
                        long user = long.Parse(parts[1]);
                        long nice = long.Parse(parts[2]);
                        long system = long.Parse(parts[3]);
                        long idle = long.Parse(parts[4]);
                        long iowait = parts.Length > 5 ? long.Parse(parts[5]) : 0;
                        long irq = parts.Length > 6 ? long.Parse(parts[6]) : 0;
                        long softirq = parts.Length > 7 ? long.Parse(parts[7]) : 0;
                        long steal = parts.Length > 8 ? long.Parse(parts[8]) : 0;

                        long totalIdle = idle + iowait;
                        long nonIdle = user + nice + system + irq + softirq + steal;
                        long total = totalIdle + nonIdle;

                        result[coreId] = (totalIdle, total);
                    }
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to read CPU statistics from {Path}", statPath);
            }
            return result;
        }
#else
		public Task<CpuTelemetryDto> GetNextSampleAsync() =>
			throw new PlatformNotSupportedException("LinuxCpuProvider is only supported on Linux.");
#endif
	}
}
