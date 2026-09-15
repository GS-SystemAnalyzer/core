using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using GSSystemAnalyzer.Interfaces;
using GSSystemAnalyzer.Models;
using Microsoft.Extensions.Logging;

namespace GSSystemAnalyzer.Services
{
	public class LinuxDiskIoReader : IDiskIoReader
	{
		private readonly string _diskstatsPath;
		private readonly string _mountsPath;
		private readonly ILogger<LinuxDiskIoReader> _logger;

		private readonly Dictionary<string, (long ReadBytes, long WriteBytes, long IoMs, long TimestampTicks)> _prevSamples = new();
		private readonly object _syncLock = new();

		// Matches partition device names to filter them out (e.g. sda1, nvme0n1p1, mmcblk0p1, vda1)
		private static readonly Regex PartitionRegex = new(
			@"^(?:(?:sd[a-z]+|vd[a-z]+|hd[a-z]+)\d+|(?:nvme\d+n\d+|mmcblk\d+)p\d+)$",
			RegexOptions.Compiled | RegexOptions.IgnoreCase);

		public LinuxDiskIoReader(ILogger<LinuxDiskIoReader> logger, string diskstatsPath = "/proc/diskstats", string mountsPath = "/proc/mounts")
		{
			_logger = logger;
			_diskstatsPath = diskstatsPath;
			_mountsPath = mountsPath;
		}

		public Task<IReadOnlyList<DiskIoRawSample>> ReadSamplesAsync()
		{
			var samples = new List<DiskIoRawSample>();

			if (!File.Exists(_diskstatsPath))
			{
				_logger.LogDebug("Linux diskstats path '{Path}' not found", _diskstatsPath);
				return Task.FromResult<IReadOnlyList<DiskIoRawSample>>(samples);
			}

			var mountMap = ReadMountMap();
			var nowTicks = Stopwatch.GetTimestamp();

			lock (_syncLock)
			{
				try
				{
					var lines = File.ReadAllLines(_diskstatsPath);
					foreach (var line in lines)
					{
						var tokens = line.Split(' ', StringSplitOptions.RemoveEmptyEntries);
						if (tokens.Length < 14) continue;

						var devName = tokens[2];

						// Exclude virtual devices and loop/ram devices
						if (devName.StartsWith("loop", StringComparison.OrdinalIgnoreCase) ||
						    devName.StartsWith("ram", StringComparison.OrdinalIgnoreCase) ||
						    devName.StartsWith("dm-", StringComparison.OrdinalIgnoreCase))
						{
							continue;
						}

						// Exclude partitions
						if (PartitionRegex.IsMatch(devName))
						{
							continue;
						}

						// Field 6 (index 5): sectors read. Field 10 (index 9): sectors written.
						// Sectors in /proc/diskstats are ALWAYS 512 bytes per kernel doc.
						if (!long.TryParse(tokens[5], out var sectorsRead) ||
						    !long.TryParse(tokens[9], out var sectorsWritten) ||
						    !double.TryParse(tokens[10], out var inProgressIo) ||
						    !long.TryParse(tokens[12], out var ioMs))
						{
							continue;
						}

						var currentReadBytes = sectorsRead * 512L;
						var currentWriteBytes = sectorsWritten * 512L;

						double readRate = 0.0;
						double writeRate = 0.0;
						double activePercent = 0.0;

						if (_prevSamples.TryGetValue(devName, out var prev))
						{
							var elapsedSeconds = (double)(nowTicks - prev.TimestampTicks) / Stopwatch.Frequency;
							if (elapsedSeconds > 0.001)
							{
								var deltaRead = currentReadBytes - prev.ReadBytes;
								var deltaWrite = currentWriteBytes - prev.WriteBytes;
								var deltaIoMs = ioMs - prev.IoMs;

								readRate = Math.Max(0.0, deltaRead / elapsedSeconds);
								writeRate = Math.Max(0.0, deltaWrite / elapsedSeconds);
								activePercent = Math.Max(0.0, (deltaIoMs / (elapsedSeconds * 1000.0)) * 100.0);
							}
						}

						_prevSamples[devName] = (currentReadBytes, currentWriteBytes, ioMs, nowTicks);

						var mountPoints = mountMap.TryGetValue(devName, out var mounts)
							? mounts
							: new List<string> { devName };

						samples.Add(new DiskIoRawSample(
							Id: devName,
							Name: devName,
							ReadBytesPerSec: readRate,
							WriteBytesPerSec: writeRate,
							ActiveTimePercent: activePercent,
							AvgQueueLength: inProgressIo,
							Model: "Linux Block Device (" + devName + ")",
							DriveLetters: mountPoints));
					}
				}
				catch (Exception ex)
				{
					_logger.LogWarning(ex, "Error reading or parsing Linux diskstats at '{Path}'", _diskstatsPath);
				}
			}

			return Task.FromResult<IReadOnlyList<DiskIoRawSample>>(samples);
		}

		private Dictionary<string, List<string>> ReadMountMap()
		{
			var map = new Dictionary<string, List<string>>(StringComparer.OrdinalIgnoreCase);
			if (!File.Exists(_mountsPath)) return map;

			try
			{
				var lines = File.ReadAllLines(_mountsPath);
				foreach (var line in lines)
				{
					var parts = line.Split(' ', StringSplitOptions.RemoveEmptyEntries);
					if (parts.Length < 2) continue;

					var devPath = parts[0];
					var mountPoint = parts[1];

					if (!devPath.StartsWith("/dev/")) continue;
					var dev = devPath.Substring(5);

					// Strip partition suffix to associate partition mount point with base device
					var baseDev = dev;
					var partMatch = PartitionRegex.Match(dev);
					if (partMatch.Success)
					{
						// Match base device name
						var m = Regex.Match(dev, @"^(sd[a-z]+|vd[a-z]+|hd[a-z]+|nvme\d+n\d+|mmcblk\d+)");
						if (m.Success)
						{
							baseDev = m.Value;
						}
					}

					if (!map.TryGetValue(baseDev, out var list))
					{
						list = new List<string>();
						map[baseDev] = list;
					}

					if (!list.Contains(mountPoint))
					{
						list.Add(mountPoint);
					}
				}
			}
			catch (Exception ex)
			{
				_logger.LogDebug(ex, "Failed to parse mounts file at '{Path}'", _mountsPath);
			}

			return map;
		}
	}
}
