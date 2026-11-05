using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Net.NetworkInformation;
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
	public class NetworkSamplerEngine : BackgroundService, INetworkEngine
	{
		private readonly INetworkInterfaceProvider _interfaceProvider;
		private readonly IHubContext<SystemHub> _hubContext;
		private readonly ISettingService _settings;
		private readonly ITelemetryHistoryBuffer _historyBuffer;
		private readonly ILogger<NetworkSamplerEngine> _logger;
		private readonly TimeProvider _clock;

		private TimeSpan _pollInterval;
		private readonly Dictionary<string, (long rx, long tx, long timestampTicks)> _prevSamples = new();
		private readonly Dictionary<string, (long sessionRx, long sessionTx)> _sessionTotals = new();
		private readonly object _syncLock = new();
		private NetworkSnapshot _latestSnapshot;

		public NetworkSamplerEngine(
			INetworkInterfaceProvider interfaceProvider,
			IHubContext<SystemHub> hubContext,
			ISettingService settings,
			ITelemetryHistoryBuffer historyBuffer,
			ILogger<NetworkSamplerEngine> logger)
			: this(interfaceProvider, hubContext, settings, historyBuffer, logger, TimeProvider.System) { }

		internal NetworkSamplerEngine(
			INetworkInterfaceProvider interfaceProvider,
			IHubContext<SystemHub> hubContext,
			ISettingService settings,
			ITelemetryHistoryBuffer historyBuffer,
			ILogger<NetworkSamplerEngine> logger,
			TimeProvider clock)
		{
			_clock = clock;
			_interfaceProvider = interfaceProvider;
			_hubContext = hubContext;
			_settings = settings;
			_historyBuffer = historyBuffer;
			_logger = logger;

			_pollInterval = TimeSpan.FromMilliseconds(Math.Clamp(_settings.Current.Monitoring.NetworkPollIntervalMs, 500, 60000));
			_settings.OnSettingsChanged += (_, s) =>
			{
				_pollInterval = TimeSpan.FromMilliseconds(Math.Clamp(s.Monitoring.NetworkPollIntervalMs, 500, 60000));
				_logger.LogDebug("Network sampler poll interval updated to {IntervalMs}ms", _pollInterval.TotalMilliseconds);
			};

			_latestSnapshot = new NetworkSnapshot(DateTimeOffset.UtcNow, null, Array.Empty<NetInterfaceSnapshot>());
		}

		public NetworkSnapshot GetCurrentSnapshot()
		{
			lock (_syncLock)
			{
				if (_latestSnapshot.Interfaces.Count == 0)
				{
					_latestSnapshot = SampleMetricsInternal();
				}
				return _latestSnapshot;
			}
		}

		/// <summary>
		/// Performs a single sampling pass across all network interfaces, updates session totals & history, and returns the snapshot.
		/// </summary>
		public NetworkSnapshot SampleMetrics()
		{
			lock (_syncLock)
			{
				_latestSnapshot = SampleMetricsInternal();
				return _latestSnapshot;
			}
		}

		private NetworkSnapshot SampleMetricsInternal()
		{
			var nowTicks = _clock.GetTimestamp();
			var timestamp = DateTimeOffset.UtcNow;
			var rawInterfaces = _interfaceProvider.GetInterfaces();

			// Filter non-loopback and non-tunnel adapters
			var candidates = rawInterfaces
				.Where(n => n.NetworkInterfaceType != NetworkInterfaceType.Loopback &&
				            n.NetworkInterfaceType != NetworkInterfaceType.Tunnel)
				.ToList();

			var currentIds = candidates.Select(n => n.Id).ToHashSet();

			// Prune stale adapters from state dictionaries
			var staleKeys = _prevSamples.Keys.Where(k => !currentIds.Contains(k)).ToList();
			foreach (var staleKey in staleKeys)
			{
				_prevSamples.Remove(staleKey);
				_sessionTotals.Remove(staleKey);
			}

			var interfaceSnapshots = new List<NetInterfaceSnapshot>();

			foreach (var nic in candidates)
			{
				try
				{
					bool isUp = nic.OperationalStatus == OperationalStatus.Up;
					double rxRate = 0.0;
					double txRate = 0.0;
					double? utilisation = null;

					if (!_sessionTotals.TryGetValue(nic.Id, out var session))
					{
						session = (0L, 0L);
						_sessionTotals[nic.Id] = session;
					}

					if (isUp)
					{
						if (!_prevSamples.TryGetValue(nic.Id, out var prev))
						{
							// First tick for this adapter — establish the baseline, emit zero.
							_prevSamples[nic.Id] = (nic.BytesReceived, nic.BytesSent, nowTicks);
						}
						else
						{
							double elapsedSeconds = _clock.GetElapsedTime(prev.timestampTicks, nowTicks).TotalSeconds;
							if (elapsedSeconds > 0)
							{
								long rxDelta = nic.BytesReceived - prev.rx;
								long txDelta = nic.BytesSent - prev.tx;

								// Counter reset or 32-bit wraparound produces a negative delta.
								// Clamp to 0 and re-baseline rather than emitting a garbage spike.
								if (rxDelta < 0 || txDelta < 0)
								{
									rxDelta = 0;
									txDelta = 0;
								}

								rxRate = rxDelta / elapsedSeconds;
								txRate = txDelta / elapsedSeconds;

								session = (session.sessionRx + rxDelta, session.sessionTx + txDelta);
								_sessionTotals[nic.Id] = session;
							}

							_prevSamples[nic.Id] = (nic.BytesReceived, nic.BytesSent, nowTicks);
						}

						if (nic.Speed > 0)
						{
							utilisation = Math.Round((rxRate + txRate) * 8.0 / nic.Speed * 100.0, 2);
						}
					}

					interfaceSnapshots.Add(new NetInterfaceSnapshot(
						Id: nic.Id,
						Name: nic.Name,
						Description: nic.Description,
						InterfaceType: nic.NetworkInterfaceType.ToString(),
						IsUp: isUp,
						LinkSpeedBitsPerSec: nic.Speed,
						RxBytesPerSec: Math.Round(rxRate, 2),
						TxBytesPerSec: Math.Round(txRate, 2),
						UtilisationPercent: utilisation,
						SessionRxBytes: session.sessionRx,
						SessionTxBytes: session.sessionTx));
				}
				catch (Exception ex)
				{
					_logger.LogWarning(ex, "Failed to compute statistics for adapter {AdapterId} ({AdapterName})", nic.Id, nic.Name);
				}
			}

			// Select primary interface
			string? primaryId = SelectPrimaryInterfaceId(candidates, interfaceSnapshots);

			return new NetworkSnapshot(timestamp, primaryId, interfaceSnapshots);
		}

		private string? SelectPrimaryInterfaceId(
			List<NetworkInterfaceInfo> rawCandidates,
			List<NetInterfaceSnapshot> snapshots)
		{
			var upSnapshots = snapshots.Where(s => s.IsUp).ToList();
			if (upSnapshots.Count == 0)
			{
				return null;
			}

			// 1. User preferred adapter (if set and currently Up)
			var preferredId = _settings.Current.Monitoring.PreferredNetworkInterfaceId;
			if (!string.IsNullOrWhiteSpace(preferredId))
			{
				var preferred = upSnapshots.FirstOrDefault(s => string.Equals(s.Id, preferredId, StringComparison.OrdinalIgnoreCase));
				if (preferred != null)
				{
					return preferred.Id;
				}
			}

			// 2. Adapter with highest cumulative traffic (BytesReceived + BytesSent)
			// Map snapshot IDs to raw candidates for cumulative byte lookup
			var rawMap = rawCandidates.ToDictionary(c => c.Id, c => c);

			var ranked = upSnapshots
				.OrderByDescending(s =>
				{
					if (rawMap.TryGetValue(s.Id, out var raw))
					{
						return raw.BytesReceived + raw.BytesSent;
					}
					return 0L;
				})
				.ThenBy(s =>
				{
					// 3. Tie-breaker: Ethernet over Wireless80211
					if (string.Equals(s.InterfaceType, "Ethernet", StringComparison.OrdinalIgnoreCase)) return 0;
					if (string.Equals(s.InterfaceType, "Wireless80211", StringComparison.OrdinalIgnoreCase)) return 1;
					return 2;
				})
				.ToList();

			return ranked.FirstOrDefault()?.Id;
		}

		protected override async Task ExecuteAsync(CancellationToken stoppingToken)
		{
			_logger.LogInformation("Network Sampler Engine is starting.");

			while (!stoppingToken.IsCancellationRequested)
			{
				try
				{
					var snapshot = SampleMetrics();

					// Push payload over SignalR
					await _hubContext.Clients.All.SendAsync("NetworkUpdate", snapshot, cancellationToken: stoppingToken);

					// Record primary interface rates to history buffer
					if (!string.IsNullOrEmpty(snapshot.PrimaryInterfaceId))
					{
						var primary = snapshot.Interfaces.FirstOrDefault(i => i.Id == snapshot.PrimaryInterfaceId);
						if (primary != null)
						{
							_historyBuffer.Record("network_rx", primary.RxBytesPerSec);
							_historyBuffer.Record("network_tx", primary.TxBytesPerSec);
						}
					}
				}
				catch (OperationCanceledException)
				{
					break;
				}
				catch (Exception ex)
				{
					_logger.LogError(ex, "Network sampler engine fault during sample loop");
				}

				await Task.Delay(_pollInterval, stoppingToken);
			}

			_logger.LogInformation("Network Sampler Engine stopped.");
		}
	}
}
