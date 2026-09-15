using System;
using System.Collections.Generic;
using System.Linq;
using System.Management;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using GSSystemAnalyzer.Interfaces;
using GSSystemAnalyzer.Models;
using Microsoft.Extensions.Logging;

namespace GSSystemAnalyzer.Services
{
	public record WmiPhysicalDiskPerfRecord(
		string Name,
		double DiskReadBytesPerSec,
		double DiskWriteBytesPerSec,
		double PercentDiskTime,
		double AvgDiskQueueLength);

	public record WmiDiskMappingRecord(
		string DiskIndex,
		string Model,
		IReadOnlyList<string> DriveLetters);

	public interface IWmiDiskIoSource
	{
		IReadOnlyList<WmiPhysicalDiskPerfRecord> GetPerfRecords();
		IReadOnlyList<WmiDiskMappingRecord> GetDiskMappings();
	}

	[SupportedOSPlatform("windows")]
	public class WindowsWmiDiskIoSource : IWmiDiskIoSource
	{
		private readonly ILogger<WindowsWmiDiskIoSource> _logger;

		public WindowsWmiDiskIoSource(ILogger<WindowsWmiDiskIoSource> logger)
		{
			_logger = logger;
		}

		public IReadOnlyList<WmiPhysicalDiskPerfRecord> GetPerfRecords()
		{
			var records = new List<WmiPhysicalDiskPerfRecord>();
			try
			{
				using var searcher = new ManagementObjectSearcher(
					"SELECT Name, DiskReadBytesPerSec, DiskWriteBytesPerSec, " +
					"PercentDiskTime, AvgDiskQueueLength " +
					"FROM Win32_PerfFormattedData_PerfDisk_PhysicalDisk");

				foreach (ManagementObject disk in searcher.Get().Cast<ManagementObject>())
				{
					var name = disk["Name"]?.ToString() ?? string.Empty;
					if (string.IsNullOrWhiteSpace(name) || name == "_Total") continue;

					double readBytes = Convert.ToDouble(disk["DiskReadBytesPerSec"] ?? 0.0);
					double writeBytes = Convert.ToDouble(disk["DiskWriteBytesPerSec"] ?? 0.0);
					double percentTime = Convert.ToDouble(disk["PercentDiskTime"] ?? 0.0);
					double queueLen = Convert.ToDouble(disk["AvgDiskQueueLength"] ?? 0.0);

					records.Add(new WmiPhysicalDiskPerfRecord(name, readBytes, writeBytes, percentTime, queueLen));
				}
			}
			catch (Exception ex)
			{
				_logger.LogWarning(ex, "Failed to query Win32_PerfFormattedData_PerfDisk_PhysicalDisk");
			}

			return records;
		}

		public IReadOnlyList<WmiDiskMappingRecord> GetDiskMappings()
		{
			var results = new List<WmiDiskMappingRecord>();
			try
			{
				// Query Win32_DiskDrive for basic disk index and model
				var drives = new Dictionary<string, (string DeviceId, string Model)>();
				using (var driveSearcher = new ManagementObjectSearcher("SELECT DeviceID, Index, Model FROM Win32_DiskDrive"))
				{
					foreach (ManagementObject drive in driveSearcher.Get().Cast<ManagementObject>())
					{
						var index = drive["Index"]?.ToString() ?? string.Empty;
						var deviceId = drive["DeviceID"]?.ToString() ?? string.Empty;
						var model = drive["Model"]?.ToString()?.Trim() ?? "Generic Physical Disk";
						if (!string.IsNullOrEmpty(index))
						{
							drives[index] = (deviceId, model);
						}
					}
				}

				// Query associations: Win32_DiskDriveToDiskPartition and Win32_LogicalDiskToPartition
				var partitionToDisk = new Dictionary<string, string>();
				using (var partSearcher = new ManagementObjectSearcher("SELECT Antecedent, Dependent FROM Win32_DiskDriveToDiskPartition"))
				{
					foreach (ManagementObject part in partSearcher.Get().Cast<ManagementObject>())
					{
						var antecedent = part["Antecedent"]?.ToString() ?? string.Empty;
						var dependent = part["Dependent"]?.ToString() ?? string.Empty;

						// Antecedent contains DeviceID, Dependent contains DeviceID of partition
						foreach (var kvp in drives)
						{
							if (antecedent.Contains(kvp.Value.DeviceId, StringComparison.OrdinalIgnoreCase))
							{
								partitionToDisk[dependent] = kvp.Key;
								break;
							}
						}
					}
				}

				var diskToLetters = new Dictionary<string, List<string>>();
				using (var logicalSearcher = new ManagementObjectSearcher("SELECT Antecedent, Dependent FROM Win32_LogicalDiskToPartition"))
				{
					foreach (ManagementObject logDisk in logicalSearcher.Get().Cast<ManagementObject>())
					{
						var antecedent = logDisk["Antecedent"]?.ToString() ?? string.Empty;
						var dependent = logDisk["Dependent"]?.ToString() ?? string.Empty;

						// Find which disk this partition belongs to
						string? diskIndex = null;
						foreach (var pKvp in partitionToDisk)
						{
							if (antecedent.Contains(pKvp.Key, StringComparison.OrdinalIgnoreCase))
							{
								diskIndex = pKvp.Value;
								break;
							}
						}

						if (diskIndex != null)
						{
							// Dependent is like Win32_LogicalDisk.DeviceID="C:"
							var match = Regex.Match(dependent, @"DeviceID=""([^""]+)""");
							if (match.Success)
							{
								var letter = match.Groups[1].Value;
								if (!diskToLetters.TryGetValue(diskIndex, out var letters))
								{
									letters = new List<string>();
									diskToLetters[diskIndex] = letters;
								}
								if (!letters.Contains(letter, StringComparer.OrdinalIgnoreCase))
								{
									letters.Add(letter);
								}
							}
						}
					}
				}

				foreach (var kvp in drives)
				{
					var letters = diskToLetters.TryGetValue(kvp.Key, out var list) ? list : new List<string>();
					results.Add(new WmiDiskMappingRecord(kvp.Key, kvp.Value.Model, letters));
				}
			}
			catch (Exception ex)
			{
				_logger.LogWarning(ex, "Failed to resolve physical disk to logical drive letter mappings via WMI");
			}

			return results;
		}
	}

	public class WindowsDiskIoReader : IDiskIoReader
	{
		private readonly IWmiDiskIoSource _wmiSource;
		private readonly ILogger<WindowsDiskIoReader> _logger;

		private IReadOnlyList<WmiDiskMappingRecord> _cachedMappings = Array.Empty<WmiDiskMappingRecord>();
		private DateTimeOffset _lastMappingRefresh = DateTimeOffset.MinValue;
		private static readonly TimeSpan MappingCacheTtl = TimeSpan.FromSeconds(60);
		private readonly object _mappingLock = new();

		public WindowsDiskIoReader(IWmiDiskIoSource wmiSource, ILogger<WindowsDiskIoReader> logger)
		{
			_wmiSource = wmiSource;
			_logger = logger;
		}

		public Task<IReadOnlyList<DiskIoRawSample>> ReadSamplesAsync()
		{
			EnsureMappings();

			var perfRecords = _wmiSource.GetPerfRecords();
			var samples = new List<DiskIoRawSample>();

			foreach (var perf in perfRecords)
			{
				if (string.IsNullOrWhiteSpace(perf.Name) || perf.Name.Equals("_Total", StringComparison.OrdinalIgnoreCase))
				{
					continue;
				}

				// Parse disk index from Name e.g. "0 C:" -> "0", or "1 D: E:" -> "1", or "2" -> "2"
				var name = perf.Name;
				var parts = name.Split(' ', StringSplitOptions.RemoveEmptyEntries);
				var diskId = parts.Length > 0 ? parts[0] : name;

				// Lookup mapping
				var mapping = _cachedMappings.FirstOrDefault(m => m.DiskIndex == diskId);
				var letters = mapping != null && mapping.DriveLetters.Count > 0
					? mapping.DriveLetters
					: ExtractLettersFromName(name);

				var model = mapping?.Model ?? "Physical Disk " + diskId;

				samples.Add(new DiskIoRawSample(
					Id: diskId,
					Name: name,
					ReadBytesPerSec: Math.Max(0.0, perf.DiskReadBytesPerSec),
					WriteBytesPerSec: Math.Max(0.0, perf.DiskWriteBytesPerSec),
					ActiveTimePercent: Math.Max(0.0, perf.PercentDiskTime),
					AvgQueueLength: Math.Max(0.0, perf.AvgDiskQueueLength),
					Model: model,
					DriveLetters: letters));
			}

			return Task.FromResult<IReadOnlyList<DiskIoRawSample>>(samples);
		}

		private void EnsureMappings()
		{
			var now = DateTimeOffset.UtcNow;
			if (now - _lastMappingRefresh < MappingCacheTtl && _cachedMappings.Count > 0)
			{
				return;
			}

			lock (_mappingLock)
			{
				if (now - _lastMappingRefresh < MappingCacheTtl && _cachedMappings.Count > 0)
				{
					return;
				}

				try
				{
					var mappings = _wmiSource.GetDiskMappings();
					if (mappings.Count > 0)
					{
						_cachedMappings = mappings;
						_lastMappingRefresh = now;
					}
				}
				catch (Exception ex)
				{
					_logger.LogWarning(ex, "Failed to refresh disk mappings in WindowsDiskIoReader");
				}
			}
		}

		private static IReadOnlyList<string> ExtractLettersFromName(string perfName)
		{
			var letters = new List<string>();
			var matches = Regex.Matches(perfName, @"[A-Za-z]:");
			foreach (Match m in matches)
			{
				if (!letters.Contains(m.Value, StringComparer.OrdinalIgnoreCase))
				{
					letters.Add(m.Value.ToUpperInvariant());
				}
			}
			return letters;
		}
	}
}
