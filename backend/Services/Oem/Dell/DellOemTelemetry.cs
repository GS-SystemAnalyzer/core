using System.Management;
using GSSystemAnalyzer.Interfaces;
using GSSystemAnalyzer.Models;
using Microsoft.Extensions.Logging;

namespace GSSystemAnalyzer.Services.Oem.Dell
{
	/// <summary>
	/// Tier-3 fallback: reads fan RPM from Dell Command | Monitor's WMI provider
	/// (root\dcim\sysman). No ring-0 driver, so it survives HVCI / Memory Integrity.
	/// Returns null if DCM isn't installed or the namespace is unavailable.
	/// </summary>
	public sealed class DellOemTelemetry : IDellOemTelemetry
	{
		private DellOemDto? _cachedReading = null;
		private DateTime _lastPollTime = DateTime.MinValue;
		private static readonly TimeSpan _cacheDuration = TimeSpan.FromSeconds(3);
		private readonly ILogger<DellOemTelemetry> _logger;
		private readonly Func<DellOemDto?> _readTelemetry;
		private readonly TimeProvider _timeProvider;
		private bool _isAvailable = true;

		public DellOemTelemetry(ILogger<DellOemTelemetry> logger)
			: this(logger, ReadTelemetry, TimeProvider.System)
		{
		}

		internal DellOemTelemetry(ILogger<DellOemTelemetry> logger, Func<DellOemDto?> readTelemetry, TimeProvider timeProvider)
		{
			_logger = logger;
			_readTelemetry = readTelemetry;
			_timeProvider = timeProvider;
		}

		public DellOemDto? TryGetDellOemTelemetry()
		{
			if (!_isAvailable)
			{
				return null;
			}

			if (_timeProvider.GetUtcNow().UtcDateTime - _lastPollTime < _cacheDuration && _cachedReading != null)
			{
				return _cachedReading;
			}
			try
			{
				var reading = _readTelemetry();
				if (reading != null)
				{
					_cachedReading = reading;
					_lastPollTime = _timeProvider.GetUtcNow().UtcDateTime;
					return _cachedReading;
				}
				return null;
			}
			catch (ManagementException mex)
			{
				if (mex.ErrorCode == ManagementStatus.AccessDenied ||
				    mex.ErrorCode == ManagementStatus.InvalidClass ||
				    mex.ErrorCode == ManagementStatus.InvalidNamespace ||
				    mex.ErrorCode == ManagementStatus.NotFound ||
				    mex.ErrorCode == ManagementStatus.NotSupported)
				{
					_isAvailable = false;
					_logger.LogDebug("Dell OEM telemetry unavailable ({Message}); disabling for session.", mex.Message);
				}
				else
				{
					_logger.LogWarning("Dell OEM telemetry query encountered non-fatal error: {Message}", mex.Message);
				}
				return null;
			}
			catch (Exception ex)
			{
				_isAvailable = false;
				_logger.LogDebug("Dell OEM telemetry failed ({Message}); disabling for session.", ex.Message);
				return null;
			}
		}

		private static DellOemDto? ReadTelemetry()
		{
			using var searcher = new ManagementObjectSearcher("root\\dcim\\sysman", "SELECT * FROM DCIM_NumericSensor");
			using var results = searcher.Get();
			var reading = new DellOemDto();
			var found = false;

			foreach (ManagementBaseObject o in results)
			{
				using (o)
				{
					if (o["SensorType"] != null)
					{
						int sensorType = Convert.ToInt32(o["SensorType"]);
						var name = o["ElementName"]?.ToString() ?? "";
						var raw = Convert.ToInt64(o["CurrentReading"]);

						// Fan logic
						if (sensorType == 5)
						{
							var mod = Convert.ToInt32(o["UnitModifier"]);
							var rpm = (int)(raw * Math.Pow(10, mod));

							if (name.IndexOf("CPU", StringComparison.OrdinalIgnoreCase) >= 0)
								reading.CpuFanRpm = rpm;
							else if (name.IndexOf("GPU", StringComparison.OrdinalIgnoreCase) >= 0)
								reading.GpuFanRpm = rpm;
							else if (name.IndexOf("Chassis", StringComparison.OrdinalIgnoreCase) >= 0)
								reading.ChassisFanRpm = rpm;

							found = true;
						}
						// Temp logic
						else if (sensorType == 2)
						{
							double temp = raw;

							if (name.IndexOf("CPU", StringComparison.OrdinalIgnoreCase) >= 0)
								reading.CpuTempCelsius = temp;
							else if (name.IndexOf("Memory", StringComparison.OrdinalIgnoreCase) >= 0) reading.RamCelsius = temp;
							else if (name.IndexOf("Ambient", StringComparison.OrdinalIgnoreCase) >= 0) reading.AmbientCelsius = temp;
							else if (name.IndexOf("Other", StringComparison.OrdinalIgnoreCase) >= 0) reading.MotherboardCelsius = temp;

							found = true;
						}
					}
				}
			}

			return found ? reading : null;
		}

		public static int CalculateRpm(long rawReading, int unitModifier)
		{
			return (int)(rawReading * Math.Pow(10, unitModifier));
		}
	}

}
