using System.Collections.Concurrent;
using System.Diagnostics;
using System.Runtime.InteropServices;
using GSSystemAnalyzer.Hubs;
using GSSystemAnalyzer.Interfaces;
using GSSystemAnalyzer.Models;
using GSSystemAnalyzer.Services;
using Microsoft.AspNetCore.SignalR;
using Microsoft.Extensions.Logging;

namespace GSSystemAnalyzer.Engine
{
	public class RamMonitoringEngine : IAsyncDisposable
	{
		private CancellationTokenSource? _radarCts;
		private Task? _radarTask;
		private long _generation;
		private bool _disposed;
		private readonly IHubContext<SystemHub> _hub;
		private readonly ISettingService _settings;
		private readonly IProcessOwnerResolver _ownerResolver;
		private readonly ITelemetryHistoryBuffer _historyBuffer;
		private readonly ILogger<RamMonitoringEngine> _logger;
		private readonly Func<DateTimeOffset> _timeProvider;
		private readonly TimeProvider _clock;
		private readonly Func<IReadOnlyList<ProcessMemorySample>> _processReader;
		private readonly Func<SystemMemoryMetrics.GlobalMemoryMetrics?> _globalReader;
		private readonly ThresholdAlertTracker _alertTracker;
		private readonly object _lock = new object();
		private int _pollIntervalMs;
		private int _configurationVersion;
		private double _thresholdPercent;
		private int _minimumFreeMb;
		private long? _pressureSince;
		private long? _lastPhysicalObservation;
		private int _previousPhysicalPeriod;
		private int _observedConfigurationVersion;
		private long? _lastHistoryObservation;

		/// <summary>True while the RAM alert is active (debounce passed, not yet cleared).</summary>
		public bool IsRamAlerting => _alertTracker.IsAlerting;

		private const long CriticalAvailableBytes = 256L * 1024L * 1024L; // 256 MB

		// Per-process CPU baseline from the previous tick
		private readonly ConcurrentDictionary<int, (long CpuTicks, long Timestamp, long CreationTicks)> _prevCpuSnapshot = new();

		// Consecutive zero-CPU-tick counter per PID for status heuristic
		private readonly ConcurrentDictionary<int, int> _zeroTickCounts = new();

		public RamMonitoringEngine(
			IHubContext<SystemHub> hub,
			ISettingService settings,
			IProcessOwnerResolver ownerResolver,
			ITelemetryHistoryBuffer historyBuffer,
			ILogger<RamMonitoringEngine> logger,
			Func<DateTimeOffset>? timeProvider = null,
			ThresholdAlertTracker? alertTracker = null,
			WindowsProcessMetricsProvider? processMetricsProvider = null)
			: this(hub, settings, ownerResolver, historyBuffer, logger,
				OperatingSystem.IsWindows()
					? (processMetricsProvider ?? new WindowsProcessMetricsProvider()).ReadSnapshot
					: ReadLegacyProcesses,
				SystemMemoryMetrics.GetLiveMetrics, TimeProvider.System, timeProvider, alertTracker)
		{ }

		internal RamMonitoringEngine(
			IHubContext<SystemHub> hub,
			ISettingService settings,
			IProcessOwnerResolver ownerResolver,
			ITelemetryHistoryBuffer historyBuffer,
			ILogger<RamMonitoringEngine> logger,
			Func<IReadOnlyList<ProcessMemorySample>> processReader,
			Func<SystemMemoryMetrics.GlobalMemoryMetrics?> globalReader,
			TimeProvider clock,
			Func<DateTimeOffset>? timeProvider = null,
			ThresholdAlertTracker? alertTracker = null)
		{
			_hub = hub;
			_settings = settings;
			_ownerResolver = ownerResolver;
			_historyBuffer = historyBuffer;
			_logger = logger;
			_clock = clock;
			_processReader = processReader;
			_globalReader = globalReader;
			_timeProvider = timeProvider ?? clock.GetUtcNow;
			_alertTracker = alertTracker ?? new ThresholdAlertTracker(
				requiredConsecutive: 1,
				hysteresisBand: 5.0,
				reAlertIncrease: 5.0,
				cooldownInterval: TimeSpan.FromMinutes(60));
			_pollIntervalMs = settings.Current.Monitoring.RamPollIntervalMs;
			_thresholdPercent = settings.Current.Alerts.RamThresholdPercent;
			_minimumFreeMb = settings.Current.Alerts.RamMinimumFreeMb;
			settings.OnSettingsChanged += OnSettingsChanged;
		}

		private void OnSettingsChanged(object? sender, Models.SettingDtos.AppSettingDto settings)
		{
			lock (_lock)
			{
				Volatile.Write(ref _pollIntervalMs, settings.Monitoring.RamPollIntervalMs);
				if (_thresholdPercent != settings.Alerts.RamThresholdPercent || _minimumFreeMb != settings.Alerts.RamMinimumFreeMb)
				{
					_thresholdPercent = settings.Alerts.RamThresholdPercent;
					_minimumFreeMb = settings.Alerts.RamMinimumFreeMb;
					_configurationVersion++;
				}
			}
		}

		public void StartRadar()
		{
			lock (_lock)
			{
				ObjectDisposedException.ThrowIf(_disposed, this);
				if (_radarCts != null && !_radarCts.IsCancellationRequested) return;

				var previous = _radarTask;
				_radarCts = new CancellationTokenSource();
				var generation = Interlocked.Increment(ref _generation);
				_radarTask = RunSerializedAsync(previous, _radarCts, generation);
				_logger.LogInformation("RAM radar started");
			}
		}

		public void StopRadar()
		{
			lock (_lock) _radarCts?.Cancel();
			_logger.LogInformation("RAM radar stopped");
		}

		private async Task RunSerializedAsync(Task? previous, CancellationTokenSource source, long generation)
		{
			if (previous != null) await previous.ConfigureAwait(false);
			Task? owners = null;
			try
			{
				if (source.IsCancellationRequested) return;
				ResetQualification();
				_lastHistoryObservation = null;
				owners = Task.Run(() => RefreshOwnersAsync(source.Token));
				await RadarLoopAsync(source.Token, generation).ConfigureAwait(false);
			}
			finally
			{
				source.Cancel();
				if (owners != null) await owners.ConfigureAwait(false);
				lock (_lock)
				{
					if (ReferenceEquals(_radarCts, source)) _radarCts = null;
				}
				source.Dispose();
			}
		}

		private async Task RefreshOwnersAsync(CancellationToken token)
		{
			try
			{
				while (!token.IsCancellationRequested)
				{
					try { _ownerResolver.RefreshCache(); }
					catch { }
					await Task.Delay(TimeSpan.FromSeconds(5), _clock, token).ConfigureAwait(false);
				}
			}
			catch (OperationCanceledException) { }
		}

		public async ValueTask DisposeAsync()
		{
			Task? task;
			lock (_lock)
			{
				if (_disposed) return;
				_disposed = true;
				_radarCts?.Cancel();
				task = _radarTask;
			}
			_settings.OnSettingsChanged -= OnSettingsChanged;
			if (task != null) await task.ConfigureAwait(false);
		}

		private async Task RadarLoopAsync(CancellationToken token, long generation)
		{
			try
			{
				while (!token.IsCancellationRequested)
				{
					var started = _clock.GetTimestamp();

					try
					{
						var snapshot = CaptureProcessSnapshot(token);
						var globalMetrics = _globalReader();
						var observed = _clock.GetTimestamp();
						var utc = _timeProvider();
						var pressure = globalMetrics != null ? ObservePressure(globalMetrics, observed, utc, generation) : null;
						if (globalMetrics != null && (_lastHistoryObservation == null ||
							_clock.GetElapsedTime(_lastHistoryObservation.Value, observed) >= TimeSpan.FromSeconds(2)))
						{
							_historyBuffer.Record("ram", globalMetrics.ActiveGb);
							_historyBuffer.Record("ram_percent", globalMetrics.TotalGb > 0
								? Math.Round(globalMetrics.ActiveGb / globalMetrics.TotalGb * 100, 1) : 0);
							_lastHistoryObservation = observed;
						}
						if (globalMetrics == null) ResetQualification();
						token.ThrowIfCancellationRequested();

						var payload = new
						{
							Global = globalMetrics ?? new SystemMemoryMetrics.GlobalMemoryMetrics
							{
								ActiveGb = 0.0,
								CacheGb = 0.0,
								SwapGb = 0.0,
								TotalSwapGb = 0.0,
								TotalGb = 16.0,
							},
							Processes = snapshot,
							ProcessMemorySemantics = OperatingSystem.IsWindows() ? "windows-private-ws" : "unavailable"
						};

						await _hub.Clients.All.SendAsync("RamUpdate", payload, cancellationToken: token).ConfigureAwait(false);
						if (pressure != null) await PublishPressureAsync(pressure, snapshot, token).ConfigureAwait(false);

						_logger.LogDebug("RAM sweep at {Time} — sent {ProcessCount} processes", DateTime.Now.ToString("HH:mm:ss"), snapshot.Count);
					}
					catch (Exception ex) when (ex is not OperationCanceledException)
					{
						ResetQualification();
						_logger.LogWarning(ex, "RAM engine tick error");
					}
					var remaining = TimeSpan.FromMilliseconds(Volatile.Read(ref _pollIntervalMs)) - _clock.GetElapsedTime(started);
					if (remaining > TimeSpan.Zero) await Task.Delay(remaining, _clock, token).ConfigureAwait(false);
					else await Task.Yield();
				}
			}
			catch (OperationCanceledException) { }
			catch (Exception ex)
			{
				_logger.LogError(ex, "RAM engine fatal radar error");
			}
		}

		internal List<ProcessTelemetry> CaptureProcessSnapshot(CancellationToken token = default)
		{
			var samples = _processReader();
			token.ThrowIfCancellationRequested();
			var now = _clock.GetTimestamp();
			var telemetryList = new List<ProcessTelemetry>(samples.Count);
			var seenPids = new HashSet<int>(samples.Count);
			foreach (var sample in samples)
			{
				seenPids.Add(sample.ProcessId);
				double cpuPercent = 0;
				if (_prevCpuSnapshot.TryGetValue(sample.ProcessId, out var previous) &&
					previous.CreationTicks == sample.CreationTimeTicks)
				{
					var elapsed = _clock.GetElapsedTime(previous.Timestamp, now).TotalMilliseconds;
					if (elapsed > 0 && sample.CpuTimeTicks >= previous.CpuTicks)
						cpuPercent = Math.Round(Math.Clamp((sample.CpuTimeTicks - previous.CpuTicks) / 10000.0 /
							(elapsed * Environment.ProcessorCount) * 100, 0, 100), 1);
					else _zeroTickCounts.TryRemove(sample.ProcessId, out _);
				}
				else
				{
					_zeroTickCounts.TryRemove(sample.ProcessId, out _);
				}
				_prevCpuSnapshot[sample.ProcessId] = (sample.CpuTimeTicks, now, sample.CreationTimeTicks);
				string user;
				try { user = _ownerResolver.Resolve(sample.ProcessId); }
				catch { user = "UNKNOWN"; }
				telemetryList.Add(new ProcessTelemetry
				{
					ProcessId = sample.ProcessId,
					Name = sample.Name,
					WorkingSetBytes = sample.WorkingSetBytes,
					PrivateWorkingSetBytes = sample.PrivateWorkingSetBytes,
					CommitBytes = sample.CommitBytes,
					CpuPercent = cpuPercent,
					Status = OperatingSystem.IsLinux() ? GetLinuxProcessStatus(sample.ProcessId) : GetStatusHeuristic(sample.ProcessId, cpuPercent),
					User = user
				});
			}

			foreach (var stalePid in _prevCpuSnapshot.Keys.Where(pid => !seenPids.Contains(pid)).ToList())
			{
				_prevCpuSnapshot.TryRemove(stalePid, out _);
				_zeroTickCounts.TryRemove(stalePid, out _);
			}

			return telemetryList
				.OrderByDescending(p => p.CpuPercent)
				.ThenByDescending(p => p.WorkingSetBytes)
				.ToList();
		}

		private static IReadOnlyList<ProcessMemorySample> ReadLegacyProcesses()
		{
			var result = new List<ProcessMemorySample>();
			foreach (var process in Process.GetProcesses())
			{
				try
				{
					long cpu = 0;
					long creation = 0;
					try { cpu = process.TotalProcessorTime.Ticks; } catch { }
					try { creation = process.StartTime.ToUniversalTime().Ticks; } catch { }
					result.Add(new ProcessMemorySample(process.Id, process.ProcessName, creation, cpu,
						process.WorkingSet64, null, null));
				}
				catch { }
				finally { process.Dispose(); }
			}
			return result;
		}

		private string GetStatusHeuristic(int pid, double cpuPercent)
		{
			if (cpuPercent == 0.0)
			{
				var count = _zeroTickCounts.AddOrUpdate(pid, 1, (_, prev) => prev + 1);
				if (count >= 5) return "SLEEPING";
			}
			else
			{
				_zeroTickCounts[pid] = 0;
			}

			return "RUNNING";
		}

		private string GetLinuxProcessStatus(int pid)
		{
#if !WINDOWS
            try
            {
                var statPath = $"/proc/{pid}/stat";
                if (!File.Exists(statPath)) return "STOPPED";

                var content = File.ReadAllText(statPath);

                // The state character is field 3, but field 2 (comm) can contain spaces and parens
                // Find the last ')' to skip the comm field safely
                var lastParen = content.LastIndexOf(')');
                if (lastParen < 0 || lastParen + 2 >= content.Length) return "RUNNING";

                var stateChar = content[lastParen + 2]; // space + state character

                return stateChar switch
                {
                    'R' => "RUNNING",
                    'S' or 'D' or 'I' => "SLEEPING",
                    'T' or 't' => "STOPPED",
                    'Z' => "ZOMBIE",
                    _ => "RUNNING"
                };
            }
            catch
            {
                return "RUNNING";
            }
#else
			return "RUNNING";
#endif
		}

		internal async Task EvaluateRamPressureAsync(
			SystemMemoryMetrics.GlobalMemoryMetrics globalMetrics,
			List<ProcessTelemetry> processList,
			CancellationToken token)
		{
			var candidate = ObservePressure(globalMetrics, _clock.GetTimestamp(), _timeProvider(), Volatile.Read(ref _generation));
			if (candidate != null) await PublishPressureAsync(candidate, processList, token).ConfigureAwait(false);
		}

		private sealed record PressureCandidate(AlertAction Action, double UsedPercent, long AvailableBytes,
			double ThresholdPercent, int MinimumFreeMb, int SustainedSeconds, DateTimeOffset ObservedUtc,
			int ConfigurationVersion, long Generation);

		private PressureCandidate? ObservePressure(SystemMemoryMetrics.GlobalMemoryMetrics metrics, long observed,
			DateTimeOffset utc, long generation)
		{
			if (!double.IsFinite(metrics.TotalGb) || metrics.TotalGb <= 0 || !double.IsFinite(metrics.ActiveGb) ||
				!double.IsFinite(metrics.CacheGb) || metrics.CacheGb < 0 || metrics.CacheGb > metrics.TotalGb ||
				metrics.ActiveGb < 0 || metrics.ActiveGb > metrics.TotalGb)
			{
				ResetQualification();
				return null;
			}
			double threshold;
			int minimumFree;
			int version;
			int period;
			lock (_lock)
			{
				threshold = _thresholdPercent;
				minimumFree = _minimumFreeMb;
				version = _configurationVersion;
				period = _pollIntervalMs;
			}
			if (_observedConfigurationVersion != version || (_lastPhysicalObservation != null &&
				_clock.GetElapsedTime(_lastPhysicalObservation.Value, observed).TotalMilliseconds >
				2L * Math.Max(_previousPhysicalPeriod, period)))
			{
				_pressureSince = null;
			}
			_observedConfigurationVersion = version;
			_lastPhysicalObservation = observed;
			_previousPhysicalPeriod = period;
			var available = metrics.AvailablePhysicalBytes ?? (long)(metrics.CacheGb * 1024 * 1024 * 1024);
			var percent = metrics.PhysicalTotalBytes is > 0
				? Math.Round((metrics.PhysicalTotalBytes.Value - available) / (double)metrics.PhysicalTotalBytes.Value * 100, 1)
				: Math.Round(metrics.ActiveGb / metrics.TotalGb * 100, 1);
			var high = percent >= threshold && available <= minimumFree * 1024L * 1024L;
			if (high)
			{
				_pressureSince ??= observed;
			}
			else
			{
				_pressureSince = null;
			}
			var sustained = _pressureSince != null ? _clock.GetElapsedTime(_pressureSince.Value, observed).TotalSeconds : 0;
			var qualified = high && sustained >= 10;
			var evaluation = _alertTracker.Evaluate(qualified, percent, threshold, utc);
			if (evaluation.Action == AlertAction.None || (evaluation.Action == AlertAction.Fire && !qualified)) return null;
			return new PressureCandidate(evaluation.Action, percent, available, threshold, minimumFree,
				(int)Math.Min(int.MaxValue, Math.Max(0, sustained)), utc, version, generation);
		}

		private void ResetQualification()
		{
			_pressureSince = null;
			_lastPhysicalObservation = null;
			if (!_alertTracker.IsAlerting) _alertTracker.Evaluate(false, 0, _thresholdPercent, _timeProvider());
		}

		private bool IsCurrent(PressureCandidate candidate, CancellationToken token) =>
			!token.IsCancellationRequested && candidate.Generation == Volatile.Read(ref _generation) &&
			candidate.ConfigurationVersion == Volatile.Read(ref _configurationVersion);

		private async Task PublishPressureAsync(PressureCandidate candidate, List<ProcessTelemetry> processes, CancellationToken token)
		{
			if (!IsCurrent(candidate, token)) return;
			if (candidate.Action == AlertAction.Clear)
			{
				await _hub.Clients.All.SendAsync("RamAlertCleared", new
				{
					usedPercent = candidate.UsedPercent,
					availableFormatted = FormatSize(candidate.AvailableBytes)
				}, cancellationToken: token).ConfigureAwait(false);
				if (IsCurrent(candidate, token)) _alertTracker.RecordCleared();
				return;
			}
			var payload = new RamAlertPayload
			{
				UsedPercent = candidate.UsedPercent,
				AvailablePhysicalBytes = candidate.AvailableBytes,
				AvailableFormatted = FormatSize(candidate.AvailableBytes),
				ThresholdPercent = candidate.ThresholdPercent,
				MinimumFreeMb = candidate.MinimumFreeMb,
				Severity = candidate.AvailableBytes < CriticalAvailableBytes ? "critical" : "warning",
				SustainedForSeconds = candidate.SustainedSeconds,
				TopConsumers = processes.OrderByDescending(p => p.WorkingSetBytes).Take(3).Select(p => new TopConsumerEntry
				{
					Pid = p.ProcessId,
					Name = p.Name,
					RamMb = p.RamMb
				}).ToList()
			};
			await _hub.Clients.All.SendAsync("RamAlert", payload, cancellationToken: token).ConfigureAwait(false);
			if (IsCurrent(candidate, token)) _alertTracker.RecordAlertFired(candidate.UsedPercent, candidate.ObservedUtc);
		}

		private static string FormatSize(long bytes)
		{
			string[] suffixes = { "B", "KB", "MB", "GB", "TB", "PB", "EB" };
			int counter = 0;
			decimal number = bytes;
			while (Math.Round(number / 1024) >= 1 && counter < suffixes.Length - 1)
			{
				number /= 1024;
				counter++;
			}
			return string.Format("{0:n1} {1}", number, suffixes[counter]);
		}

		public int ExecuteOrder66(List<int> processIds)
		{
			int killCount = 0;
			foreach (var pid in processIds)
			{
				try
				{
					using var process = Process.GetProcessById(pid);
					process.Kill();
					killCount++;
					_logger.LogDebug("Process killed: PID {Pid}", pid);
				}
				catch
				{

				}
			}
			_logger.LogInformation("Process termination completed: {KillCount} processes terminated", killCount);
			return killCount;
		}
	}
}
