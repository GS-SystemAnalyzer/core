using BlackSharp.Core.Extensions;
using GSSystemAnalyzer.Interfaces;
using GSSystemAnalyzer.Models;
using System.Runtime.Versioning;
using GSSystemAnalyzer.Services.Oem.Dell;
#if WINDOWS
using LibreHardwareMonitor.Hardware;
#endif

namespace GSSystemAnalyzer.Services
{
#if WINDOWS
	public class LibreThermalProvider : IThermalProvider
	{
		private readonly IComputerEngine _computer;
		private readonly UpdateVisitor _visitor;
		private readonly IWmiThermalFallback _wmiFallback;
		private readonly IDellOemTelemetry _dellOemTelemetry;

		private ThermalTelemetryDto _lastGoodPayLoad = new ThermalTelemetryDto();
		private float _maxObservedClock = 0f;

		public LibreThermalProvider(IWmiThermalFallback wmiFallback, IDellOemTelemetry dellOemFanReader, IComputerEngine? computer = null)
		{
			_visitor = new UpdateVisitor();
			_wmiFallback = wmiFallback;
			_dellOemTelemetry = dellOemFanReader;

			if (computer != null)
			{
				// TEST ENVIRONMENT
				_computer = computer;
			}
			else
			{
				// PRODUCTION ENVIRONMENT
				_computer = new LibreComputerWrapper();
				_computer.Open();
			}
		}

		public async Task<ThermalTelemetryDto> GetThermalDataAsync()
		{
			return await Task.Run(() =>
			{
				var payload = new ThermalTelemetryDto
				{
					CpuFanRpm = 0,
					ChassisFan1Rpm = 0,
					ChassisFan2Rpm = 0,
					CoreCelsius = new List<double>(),
					IsThermalThrottling = false
				};
				try
				{
					_computer.Accept(_visitor);

					foreach (var hardware in _computer.Hardware)
					{
						hardware.Update();

						// CPU Sensors
						if (hardware.HardwareType == HardwareType.Cpu)
						{
							foreach (var sensor in hardware.Sensors)
							{
								if (sensor.SensorType == SensorType.Temperature)
								{
									if (!sensor.Value.HasValue) continue;

									var temp = Math.Round(sensor.Value.Value, 1);

									if (sensor.Name.Contains("Package") || sensor.Name.Contains("Tctl/Tdie"))
									{
										payload.CpuPackageCelsius = temp;
									}
									else if (sensor.Name.StartsWith("CPU Core #") || (sensor.Name.StartsWith("Core #") &&
												 !sensor.Name.Contains("Distance")))
									{
										payload.CoreCelsius!.Add(temp);
									}
								}
								else if (sensor.SensorType == SensorType.Power && sensor.Name.Contains("Package") && sensor.Value.HasValue)
								{
									payload.CpuPowerWatts = Math.Round(sensor.Value.Value, 1);
								}
								else if (sensor.SensorType == SensorType.Clock &&
										 (sensor.Name == "CPU Core #0" || sensor.Name == "CPU Core #1"))
								{
									var currentClock = sensor.Value.Value;

									// Track the highest turbo frequency ever seen
									if (currentClock > _maxObservedClock) _maxObservedClock = currentClock;

									// If clock drops below 80% of the max rated speed, flag it!
									if (_maxObservedClock > 0 && currentClock < (_maxObservedClock * 0.8f))
									{
										payload.IsThermalThrottling = true;
									}
								}
							}
						}

						// GPU Sensors
						if (hardware.HardwareType == HardwareType.GpuNvidia || hardware.HardwareType == HardwareType.GpuAmd)
						{
							foreach (var sensor in hardware.Sensors)
							{
								if (!sensor.Value.HasValue) continue; //  ADDED NULL PROTECTION

								if (sensor.SensorType == SensorType.Temperature)
								{
									if (sensor.Name.Contains("Core") || sensor.Name == "GPU Core")
										payload.GpuCoreCelsius = Math.Round(sensor.Value.Value, 1);
									else if (sensor.Name.Contains("Hot Spot"))
										payload.GpuHotSpotCelsius = Math.Round(sensor.Value.Value, 1);
									else if (sensor.Name.Contains("Memory") || sensor.Name == "GPU Memory")
										payload.GpuVramCelsius = Math.Round(sensor.Value.Value, 1);
								}
								else if (sensor.SensorType == SensorType.Fan)
								{
									payload.GpuFanRpm = (int)sensor.Value.Value;
								}
							}
						}

						// Motherboard Sensors
						if (hardware.HardwareType == HardwareType.Motherboard)
						{
							foreach (var subHw in hardware.SubHardware)
							{
								foreach (var sensor in subHw.Sensors)
								{
									if (!sensor.Value.HasValue) continue;

									if (sensor.SensorType == SensorType.Temperature)
									{
										var temp = Math.Round(sensor.Value.Value, 1);
										if (sensor.Name.Contains("System") || sensor.Name.Contains("Motherboard"))
											payload.MotherboardCelsius = temp;
										if (sensor.Name.Contains("Chipset")) payload.ChipsetCelsius = temp;
									}
									else if (sensor.SensorType == SensorType.Fan)
									{
										int rpm = (int)sensor.Value.Value;
										if (rpm <= 0) continue;

										if (sensor.Name.Contains("CPU")) payload.CpuFanRpm = rpm;
										else if (sensor.Name.Contains("Pump") || sensor.Name.Contains("AIO"))
											payload.PumpRpm = rpm;
										else if (sensor.Name.Contains("Chassis") || sensor.Name.Contains("System"))
										{
											if (payload.ChassisFan1Rpm == null) payload.ChassisFan1Rpm = rpm;
											else payload.ChassisFan2Rpm = rpm;
										}
									}
								}
							}
						}

						// NVMe / STORAGE
						if (hardware.HardwareType == HardwareType.Storage)
						{
							foreach (var sensor in hardware.Sensors.Where(s => s.SensorType == SensorType.Temperature))
							{
								if (!sensor.Value.HasValue) continue; //  ADDED NULL PROTECTION

								var temp = Math.Round(sensor.Value.Value, 1);
								if (payload.NvmeCelsius == null || temp > payload.NvmeCelsius)
								{
									payload.NvmeCelsius = temp;
								}
							}
						}
					}

				}
				catch (Exception)
				{
					payload.CpuFanRpm = _lastGoodPayLoad.CpuFanRpm;
					payload.ChassisFan1Rpm = _lastGoodPayLoad.ChassisFan1Rpm;
					payload.ChassisFan2Rpm = _lastGoodPayLoad.ChassisFan2Rpm;
					payload.CpuPowerWatts = _lastGoodPayLoad.CpuPowerWatts;
					payload.GpuCoreCelsius = _lastGoodPayLoad.GpuCoreCelsius;
					payload.GpuHotSpotCelsius = _lastGoodPayLoad.GpuHotSpotCelsius;
					payload.GpuVramCelsius = _lastGoodPayLoad.GpuVramCelsius;
					payload.GpuFanRpm = _lastGoodPayLoad.GpuFanRpm;
					payload.MotherboardCelsius = _lastGoodPayLoad.MotherboardCelsius;
					payload.ChipsetCelsius = _lastGoodPayLoad.ChipsetCelsius;
					payload.PumpRpm = _lastGoodPayLoad.PumpRpm;
					payload.NvmeCelsius = _lastGoodPayLoad.NvmeCelsius;
					payload.CoreCelsius = _lastGoodPayLoad.CoreCelsius;
					payload.CpuPackageCelsius = null;
				}

				// Tier 2: WMI Fallback
				if (payload.CpuPackageCelsius == 0 || payload.CpuPackageCelsius == null)
				{
					payload.CpuPackageCelsius = _wmiFallback.GetCpuTemperatureCelsius();
				}

				// Tier 3: OEM Fallback
				bool needsTemp = payload.CpuPackageCelsius == 0 || payload.CpuPackageCelsius == null;
				bool needsFan = payload.CpuFanRpm == 0 || payload.CpuFanRpm == null;

				if (needsTemp || needsFan)
				{
					var dell = _dellOemTelemetry.TryGetDellOemTelemetry();

					if (dell != null)
					{
						// Fans
						if ((payload.CpuFanRpm == 0 || payload.CpuFanRpm == null) && dell.CpuFanRpm.HasValue)
							payload.CpuFanRpm = dell.CpuFanRpm;
						if ((payload.ChassisFan1Rpm == 0 || payload.ChassisFan1Rpm == null) && dell.ChassisFanRpm.HasValue)
							payload.ChassisFan1Rpm = dell.ChassisFanRpm;
						if ((payload.GpuFanRpm == 0 || payload.GpuFanRpm == null) && dell.GpuFanRpm.HasValue)
							payload.GpuFanRpm = dell.GpuFanRpm;

						// Temps
						if ((payload.CpuPackageCelsius == 0 || payload.CpuPackageCelsius == null) &&
							dell.CpuTempCelsius.HasValue) payload.CpuPackageCelsius = dell.CpuTempCelsius;
						if ((payload.MotherboardCelsius == 0 || payload.MotherboardCelsius == null) &&
							dell.MotherboardCelsius.HasValue) payload.MotherboardCelsius = dell.MotherboardCelsius;
						if (payload.RamCelsius == null && dell.RamCelsius.HasValue) payload.RamCelsius = dell.RamCelsius;
						if (payload.AmbientCelsius == null && dell.AmbientCelsius.HasValue) payload.AmbientCelsius = dell.AmbientCelsius;
					}
				}

				// Exception shield, in case everything falls(Cache restoration)
				if (payload.CpuPackageCelsius == null && _lastGoodPayLoad.CpuPackageCelsius > 0)
				{
					payload.CpuPackageCelsius = _lastGoodPayLoad.CpuPackageCelsius;
				}
				if (payload.CpuFanRpm == 0 && _lastGoodPayLoad.CpuFanRpm > 0)
				{
					payload.CpuFanRpm = _lastGoodPayLoad.CpuFanRpm;
				}

				_lastGoodPayLoad = payload;
				return payload;

			});
		}

		public void Dispose()
		{
			_computer.Close();
		}
	}
#else
    public class LibreThermalProvider : IThermalProvider
    {
        public Task<ThermalTelemetryDto> GetThermalDataAsync() =>
            throw new PlatformNotSupportedException("LibreThermalProvider is only supported on Windows.");

        public void Dispose() { }
    }
#endif
}
