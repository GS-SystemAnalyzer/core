using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using GSSystemAnalyzer.Hubs;
using GSSystemAnalyzer.Interfaces;
using GSSystemAnalyzer.Models;
using Microsoft.AspNetCore.SignalR;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace GSSystemAnalyzer.Engine
{
	public class DiskIoEngine : BackgroundService, IDiskIoEngine
	{
		private readonly IDiskIoReader _reader;
		private readonly IHubContext<SystemHub> _hubContext;
		private readonly ISettingService _settings;
		private readonly ITelemetryHistoryBuffer _historyBuffer;
		private readonly ILogger<DiskIoEngine> _logger;

		private TimeSpan _pollInterval;
		private readonly Dictionary<string, (long SessionReadBytes, long SessionWriteBytes)> _sessionTotals = new();
		private long _lastSampleTicks;
		private readonly object _syncLock = new();
		private DiskIoSnapshotCollection _latestSnapshot;

		public DiskIoEngine(
			IDiskIoReader reader,
			IHubContext<SystemHub> hubContext,
			ISettingService settings,
			ITelemetryHistoryBuffer historyBuffer,
			ILogger<DiskIoEngine> logger)
		{
			_reader = reader;
			_hubContext = hubContext;
			_settings = settings;
			_historyBuffer = historyBuffer;
			_logger = logger;

			_pollInterval = TimeSpan.FromMilliseconds(Math.Clamp(_settings.Current.Monitoring.DiskIoPollIntervalMs, 500, 60000));
			_settings.OnSettingsChanged += (_, s) =>
			{
				_pollInterval = TimeSpan.FromMilliseconds(Math.Clamp(s.Monitoring.DiskIoPollIntervalMs, 500, 60000));
				_logger.LogDebug("Disk I/O engine poll interval updated to {IntervalMs}ms", _pollInterval.TotalMilliseconds);
			};

			_lastSampleTicks = Stopwatch.GetTimestamp();
			_latestSnapshot = new DiskIoSnapshotCollection(DateTimeOffset.UtcNow, Array.Empty<DiskIoSnapshot>());
		}

		public DiskIoSnapshotCollection GetCurrentSnapshot()
		{
			lock (_syncLock)
			{
				if (_latestSnapshot.Disks.Count == 0)
				{
					_latestSnapshot = SampleMetricsInternal();
				}
				return _latestSnapshot;
			}
		}

		public DiskIoSnapshotCollection SampleMetrics()
		{
			lock (_syncLock)
			{
				_latestSnapshot = SampleMetricsInternal();
				return _latestSnapshot;
			}
		}

		protected override async Task ExecuteAsync(CancellationToken stoppingToken)
		{
			_logger.LogInformation("Disk I/O Throughput Engine started with poll interval: {IntervalMs}ms", _pollInterval.TotalMilliseconds);

			while (!stoppingToken.IsCancellationRequested)
			{
				try
				{
					var snapshot = SampleMetrics();

					if (_hubContext?.Clients != null)
					{
						await _hubContext.Clients.All.SendAsync("DiskIoUpdate", snapshot, stoppingToken);
					}
				}
				catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
				{
					break;
				}
				catch (Exception ex)
				{
					_logger.LogError(ex, "Unexpected error in Disk I/O telemetry sampling loop");
				}

				try
				{
					await Task.Delay(_pollInterval, stoppingToken);
				}
				catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
				{
					break;
				}
			}

			_logger.LogInformation("Disk I/O Throughput Engine stopped.");
		}

		private DiskIoSnapshotCollection SampleMetricsInternal()
		{
			var nowTicks = Stopwatch.GetTimestamp();
			var timestamp = DateTimeOffset.UtcNow;

			double elapsedSeconds = 1.0;
			if (_lastSampleTicks > 0)
			{
				elapsedSeconds = (double)(nowTicks - _lastSampleTicks) / Stopwatch.Frequency;
				if (elapsedSeconds <= 0.001) elapsedSeconds = 1.0;
			}
			_lastSampleTicks = nowTicks;

			IReadOnlyList<DiskIoRawSample> rawSamples;
			try
			{
				rawSamples = _reader.ReadSamplesAsync().GetAwaiter().GetResult();
			}
			catch (Exception ex)
			{
				_logger.LogWarning(ex, "Failed to read disk I/O samples from reader");
				rawSamples = Array.Empty<DiskIoRawSample>();
			}

			var currentIds = rawSamples.Select(s => s.Id).ToHashSet();

			// Prune removed drives from session state
			var staleKeys = _sessionTotals.Keys.Where(k => !currentIds.Contains(k)).ToList();
			foreach (var stale in staleKeys)
			{
				_sessionTotals.Remove(stale);
			}

			var snapshots = new List<DiskIoSnapshot>();

			foreach (var sample in rawSamples)
			{
				long prevRead = 0;
				long prevWrite = 0;
				if (_sessionTotals.TryGetValue(sample.Id, out var existingTotals))
				{
					prevRead = existingTotals.SessionReadBytes;
					prevWrite = existingTotals.SessionWriteBytes;
				}

				long addedRead = (long)Math.Round(sample.ReadBytesPerSec * elapsedSeconds);
				long addedWrite = (long)Math.Round(sample.WriteBytesPerSec * elapsedSeconds);

				long newRead = Math.Max(0, prevRead + addedRead);
				long newWrite = Math.Max(0, prevWrite + addedWrite);

				_sessionTotals[sample.Id] = (newRead, newWrite);

				var letters = sample.DriveLetters ?? Array.Empty<string>();
				var model = !string.IsNullOrWhiteSpace(sample.Model) ? sample.Model : ("Physical Disk " + sample.Id);

				snapshots.Add(new DiskIoSnapshot(
					Id: sample.Id,
					Model: model,
					DriveLetters: letters,
					ReadBytesPerSec: Math.Max(0.0, sample.ReadBytesPerSec),
					WriteBytesPerSec: Math.Max(0.0, sample.WriteBytesPerSec),
					ActiveTimePercent: Math.Max(0.0, sample.ActiveTimePercent),
					AvgQueueLength: Math.Max(0.0, sample.AvgQueueLength),
					SessionReadBytes: newRead,
					SessionWriteBytes: newWrite));
			}

			// Record history for the system drive or first disk
			if (snapshots.Count > 0)
			{
				// Match disk containing "C:" or the first disk
				var primaryDisk = snapshots.FirstOrDefault(d => d.DriveLetters.Any(l => l.Contains("C:", StringComparison.OrdinalIgnoreCase)))
				                  ?? snapshots[0];

				_historyBuffer.Record("disk_io_read", primaryDisk.ReadBytesPerSec);
				_historyBuffer.Record("disk_io_write", primaryDisk.WriteBytesPerSec);
			}

			return new DiskIoSnapshotCollection(timestamp, snapshots);
		}
	}
}
