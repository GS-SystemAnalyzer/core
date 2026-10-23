using System;
using Microsoft.Extensions.Logging;

namespace GSSystemAnalyzer.Services
{
	public class WmiThermalFallback : IWmiThermalFallback
	{
		private readonly ILogger<WmiThermalFallback> _logger;
		private bool _isAvailable = true;

		public WmiThermalFallback(ILogger<WmiThermalFallback> logger)
		{
			_logger = logger;
		}

		public double? GetCpuTemperatureCelsius()
		{
			if (!_isAvailable)
			{
				return null;
			}

			try
			{
#pragma warning disable CA1416
				using var searcher = new System.Management.ManagementObjectSearcher("root\\wmi", "SELECT CurrentTemperature FROM MSAcpi_ThermalZoneTemperature");
				foreach (System.Management.ManagementObject obj in searcher.Get())
				{
					var tempK = Convert.ToDouble(obj["CurrentTemperature"]);
					var validTemp = ConvertKelvinToCelsius(tempK);

					if (validTemp.HasValue)
					{
						return validTemp;
					}
				}
#pragma warning restore CA1416
			}
			catch (System.Management.ManagementException mex)
			{
				if (mex.ErrorCode == System.Management.ManagementStatus.AccessDenied ||
				    mex.ErrorCode == System.Management.ManagementStatus.InvalidClass ||
				    mex.ErrorCode == System.Management.ManagementStatus.InvalidNamespace ||
				    mex.ErrorCode == System.Management.ManagementStatus.NotFound)
				{
					_isAvailable = false;
					_logger.LogDebug("WMI thermal fallback unavailable ({Message}); disabling for session.", mex.Message);
				}
				else
				{
					_logger.LogWarning("WMI thermal fallback query encountered non-fatal error: {Message}", mex.Message);
				}
			}
			catch (Exception ex)
			{
				_isAvailable = false;
				_logger.LogDebug("WMI thermal fallback failed ({Message}); disabling for session.", ex.Message);
			}

			return null;
		}

		public static double? ConvertKelvinToCelsius(double tempK)
		{
			var celsius = (tempK / 10.0) - 273.15;

			if (celsius > 10 && celsius < 120)
			{
				return Math.Round(celsius, 1);
			}
			return null;
		}
	}
}
