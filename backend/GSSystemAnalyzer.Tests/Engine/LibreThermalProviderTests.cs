using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading.Tasks;
using GSSystemAnalyzer.Interfaces;
using GSSystemAnalyzer.Models;
using GSSystemAnalyzer.Services;

#if WINDOWS
using LibreHardwareMonitor.Hardware;
#endif
using Moq;
using Xunit;
using DellOemTelemetry = GSSystemAnalyzer.Services.Oem.Dell.DellOemTelemetry;

namespace GSSystemAnalyzer.Tests.Engine
{
	public class LibreThermalProviderTests
	{
		private readonly bool _isWindows = RuntimeInformation.IsOSPlatform(OSPlatform.Windows);

#if WINDOWS
		// ??? HELPERS
		private Mock<IHardware> CreateMockHardware(HardwareType type, List<ISensor> sensors)
		{
			var mockHw = new Mock<IHardware>();
			mockHw.Setup(h => h.HardwareType).Returns(type);
			mockHw.Setup(h => h.Sensors).Returns(sensors.ToArray()); // ?? FIXED: Added () to ToArray
			mockHw.Setup(h => h.SubHardware).Returns(Array.Empty<IHardware>());
			return mockHw;
		}

		private ISensor CreateMockSensor(SensorType type, string name, float? value)
		{
			var mockSensor = new Mock<ISensor>();
			mockSensor.Setup(s => s.SensorType).Returns(type);
			mockSensor.Setup(s => s.Name).Returns(name);
			mockSensor.Setup(s => s.Value).Returns(value);
			return mockSensor.Object;
		}

		private LibreThermalProvider CreateProvider(
			Mock<IComputerEngine> mockComputer,
			Mock<IWmiThermalFallback>? mockWmi = null,
			Mock<IDellOemTelemetry>? mockDell = null)
		{
			var wmi = mockWmi ?? new Mock<IWmiThermalFallback>();
			var dell = mockDell ?? new Mock<IDellOemTelemetry>();
			if (mockDell == null)
			{
				dell.Setup(d => d.TryGetDellOemTelemetry()).Returns((DellOemDto?)null);
			}
			return new LibreThermalProvider(wmi.Object, dell.Object, mockComputer.Object);
		}

		// ??? ORIGINAL CPU & GHOST UI TESTS
		[Fact]
		public async Task GetThermalData_CpuPackageAndCores_MappedCorrectly_ExcludingNulls()
		{
			if (!_isWindows) return;

			var sensors = new List<ISensor>
			{
				CreateMockSensor(SensorType.Temperature, "CPU Package", 68.5f),
				CreateMockSensor(SensorType.Temperature, "CPU Core #1", 65.0f),
				CreateMockSensor(SensorType.Temperature, "CPU Core #2", null),
				CreateMockSensor(SensorType.Temperature, "CPU Core #3", 67.2f),
			};

			var mockCpu = CreateMockHardware(HardwareType.Cpu, sensors);
			var mockComputer = new Mock<IComputerEngine>();
			mockComputer.Setup(c => c.Hardware).Returns(new[] { mockCpu.Object });

			var provider = new LibreThermalProvider(new Mock<IWmiThermalFallback>().Object, new Mock<IDellOemTelemetry>().Object, mockComputer.Object);
			var result = await provider.GetThermalDataAsync();

			Assert.Equal(68.5, result.CpuPackageCelsius);
			Assert.Equal(2, result.CoreCelsius.Count);
			Assert.Equal(65.0, result.CoreCelsius[0]);
			Assert.Equal(67.2, result.CoreCelsius[1]);
		}

		[Fact]
		public async Task GetThermalData_WhenAllCoreNull_ReturnsEmptyArrayNotZeros()
		{
			if (!_isWindows) return;

			var sensors = new List<ISensor>
			{
				CreateMockSensor(SensorType.Temperature, "CPU Core #1", null),
				CreateMockSensor(SensorType.Temperature, "CPU Core #2", null),
			};

			var mockCpu = CreateMockHardware(HardwareType.Cpu, sensors);
			var mockComputer = new Mock<IComputerEngine>();
			mockComputer.Setup(c => c.Hardware).Returns(new[] { mockCpu.Object });

			var provider = new LibreThermalProvider(new Mock<IWmiThermalFallback>().Object, new Mock<IDellOemTelemetry>().Object, mockComputer.Object);
			var result = await provider.GetThermalDataAsync();

			Assert.NotNull(result.CoreCelsius);
			Assert.Empty(result.CoreCelsius);
		}

		[Fact]
		public async Task GetThermalData_GhostUIVerification_MissingSensorsReturnNull()
		{
			if (!_isWindows) return;

			var mockCpu = CreateMockHardware(HardwareType.Cpu, new List<ISensor>
			{
				CreateMockSensor(SensorType.Temperature, "CPU Package", 45.0f)
			});

			var mockMobo = CreateMockHardware(HardwareType.Motherboard, new List<ISensor>());
			var mockComputer = new Mock<IComputerEngine>();
			mockComputer.Setup(c => c.Hardware).Returns(new[] { mockCpu.Object, mockMobo.Object });

			var mockDell = new Mock<IDellOemTelemetry>();
			mockDell.Setup(d => d.TryGetDellOemTelemetry()).Returns((DellOemDto?)null);

			var provider = CreateProvider(mockComputer, null, mockDell);

			var result = await provider.GetThermalDataAsync();

			Assert.Null(result.CpuPowerWatts);
			Assert.Null(result.MotherboardCelsius);
			Assert.Null(result.ChipsetCelsius);
			Assert.Null(result.NvmeCelsius);
			Assert.Null(result.PumpRpm);
		}

		// ??? EXCEPTION SHIELD & DISPOSE TESTS
		[Fact]
		public async Task GetThermalData_ThermalThrottling_DetectedOnClockDrop()
		{
			var mockSensor = new Mock<ISensor>();
			mockSensor.Setup(s => s.SensorType).Returns(SensorType.Clock);
			mockSensor.Setup(s => s.Name).Returns("CPU Core #0");

			var mockCpu = CreateMockHardware(HardwareType.Cpu, new List<ISensor> { mockSensor.Object });
			var mockComputer = new Mock<IComputerEngine>();
			mockComputer.Setup(c => c.Hardware).Returns(new[] { mockCpu.Object });

			var provider = new LibreThermalProvider(new Mock<IWmiThermalFallback>().Object, new Mock<IDellOemTelemetry>().Object, mockComputer.Object);

			mockSensor.Setup(s => s.Value).Returns(4000f);
			var result1 = await provider.GetThermalDataAsync();
			Assert.False(result1.IsThermalThrottling);

			mockSensor.Setup(s => s.Value).Returns(3500f);
			var result2 = await provider.GetThermalDataAsync();
			Assert.False(result2.IsThermalThrottling);

			mockSensor.Setup(s => s.Value).Returns(3000f);
			var result3 = await provider.GetThermalDataAsync();
			Assert.True(result3.IsThermalThrottling);
		}

		[Fact]
		public async Task GetThermalData_WhenHardwareThrows_ReturnsLastGoodPayload()
		{
			var mockComputer = new Mock<IComputerEngine>();
			var provider = CreateProvider(mockComputer);

			var mockCpu = CreateMockHardware(HardwareType.Cpu, new List<ISensor> {
				CreateMockSensor(SensorType.Temperature, "CPU Package", 70.0f)
			});
			mockComputer.Setup(c => c.Hardware).Returns(new[] { mockCpu.Object });
			var firstResult = await provider.GetThermalDataAsync();
			Assert.Equal(70.0, firstResult.CpuPackageCelsius);

			mockComputer.Setup(c => c.Accept(It.IsAny<IVisitor>())).Throws(new InvalidOperationException("VBS Lockout"));
			var secondResult = await provider.GetThermalDataAsync();

			Assert.NotNull(secondResult);
			Assert.Equal(70.0, secondResult.CpuPackageCelsius);
		}

		[Fact]
		public void Dispose_CallsComputerClose_ExactlyOnce()
		{
			var mockComputer = new Mock<IComputerEngine>();
			var provider = new LibreThermalProvider(new Mock<IWmiThermalFallback>().Object, new Mock<IDellOemTelemetry>().Object, mockComputer.Object);

			provider.Dispose();

			mockComputer.Verify(c => c.Close(), Times.Once);
		}

		[Fact]
		public void UpdateVisitor_CallsUpdate_OnTopLevelAndSubHardware()
		{
			var mockSubHw = new Mock<IHardware>();
			var mockTopHw = new Mock<IHardware>();

			mockTopHw.Setup(h => h.SubHardware).Returns(new[] { mockSubHw.Object });
			var visitor = new UpdateVisitor();

			visitor.VisitHardware(mockTopHw.Object);

			mockTopHw.Verify(h => h.Update(), Times.Once);
			mockSubHw.Verify(h => h.Accept(visitor), Times.Once);
		}

		// THE FINAL WMI FALLBACK TESTS 
		[Fact]
		public void WmiThermalFallback_ConvertsKelvinToCelsius_Correctly()
		{
			// CRITERIA: (currentTemperature / 10.0) - 273.15
			double rawWmiKelvin = 3100; // 3100 = 310.0K = 36.85�C. Math.Round(36.85, 1) = 36.9�C

			var result = WmiThermalFallback.ConvertKelvinToCelsius(rawWmiKelvin);

			Assert.Equal(36.9, result);
		}

		[Fact]
		public async Task GetThermalData_WhenLhmIsNull_UsesAcpiFallbackValue()
		{
			// CRITERIA: cpuPackageCelsius uses ACPI fallback value when LHM CPU Package sensor is null
			var mockComputer = new Mock<IComputerEngine>();
			var mockCpu = CreateMockHardware(HardwareType.Cpu, new List<ISensor>()); // NO sensors
			mockComputer.Setup(c => c.Hardware).Returns(new[] { mockCpu.Object });

			var mockWmi = new Mock<IWmiThermalFallback>();
			mockWmi.Setup(w => w.GetCpuTemperatureCelsius()).Returns(45.5); // Mock WMI reads 45.5
			var mockDell = new Mock<IDellOemTelemetry>();
			// ?? THE FIX: Force the Dell mock to be completely silent for this test
			mockDell.Setup(d => d.TryGetDellOemTelemetry()).Returns((DellOemDto?)null);

			var provider = CreateProvider(mockComputer, mockWmi, mockDell);

			var result = await provider.GetThermalDataAsync();

			Assert.Equal(45.5, result.CpuPackageCelsius); // Proves the fallback was triggered
			mockWmi.Verify(w => w.GetCpuTemperatureCelsius(), Times.Once);
		}

		[Fact]
		public async Task GetThermalData_WhenWmiReturnsNoInstances_ReturnsNull_DoesNotThrow()
		{
			// CRITERIA: When WMI ACPI returns no instances, fallback returns null � does not throw
			var mockComputer = new Mock<IComputerEngine>();
			var mockCpu = CreateMockHardware(HardwareType.Cpu, new List<ISensor>());
			mockComputer.Setup(c => c.Hardware).Returns(new[] { mockCpu.Object });

			var mockWmi = new Mock<IWmiThermalFallback>();
			mockWmi.Setup(w => w.GetCpuTemperatureCelsius()).Returns((double?)null); // WMI fails/locked

			var mockDell = new Mock<IDellOemTelemetry>();
			mockDell.Setup(d => d.TryGetDellOemTelemetry()).Returns((DellOemDto?)null);

			var provider = CreateProvider(mockComputer, mockWmi, mockDell);

			var exception = await Record.ExceptionAsync(() => provider.GetThermalDataAsync());
			var result = await provider.GetThermalDataAsync();

			Assert.Null(exception); // Did not throw a crash!
			Assert.Null(result.CpuPackageCelsius); // Safely degraded to null for the Ghost UI
		}

		[Fact]
		public async Task GetThermalData_ExecutesTiersInDocumentedOrder_WmiBeforeDell()
		{
			if (!_isWindows) return;

			var callOrder = new List<string>();

			var mockComputer = new Mock<IComputerEngine>();
			var mockCpu = CreateMockHardware(HardwareType.Cpu, new List<ISensor>());
			mockComputer.Setup(c => c.Hardware).Returns(new[] { mockCpu.Object });

			var mockWmi = new Mock<IWmiThermalFallback>();
			mockWmi.Setup(w => w.GetCpuTemperatureCelsius())
				.Callback(() => callOrder.Add("Wmi"))
				.Returns((double?)null);

			var mockDell = new Mock<IDellOemTelemetry>();
			mockDell.Setup(d => d.TryGetDellOemTelemetry())
				.Callback(() => callOrder.Add("Dell"))
				.Returns((DellOemDto?)null);

			var provider = CreateProvider(mockComputer, mockWmi, mockDell);
			await provider.GetThermalDataAsync();

			Assert.Equal(new[] { "Wmi", "Dell" }, callOrder);
		}

		[Fact]
		public async Task GetThermalData_WhenLhmProvidesCpuAndFans_SkipsDellOem()
		{
			if (!_isWindows) return;

			var mockCpu = CreateMockHardware(HardwareType.Cpu, new List<ISensor>
			{
				CreateMockSensor(SensorType.Temperature, "CPU Package", 55.0f)
			});

			var mockSubHw = new Mock<IHardware>();
			mockSubHw.Setup(h => h.Sensors).Returns(new[] { CreateMockSensor(SensorType.Fan, "CPU Fan", 2100f) });
			mockSubHw.Setup(h => h.SubHardware).Returns(Array.Empty<IHardware>());

			var mockMobo = new Mock<IHardware>();
			mockMobo.Setup(h => h.HardwareType).Returns(HardwareType.Motherboard);
			mockMobo.Setup(h => h.Sensors).Returns(Array.Empty<ISensor>());
			mockMobo.Setup(h => h.SubHardware).Returns(new[] { mockSubHw.Object });

			var mockComputer = new Mock<IComputerEngine>();
			mockComputer.Setup(c => c.Hardware).Returns(new[] { mockCpu.Object, mockMobo.Object });

			var mockWmi = new Mock<IWmiThermalFallback>();
			var mockDell = new Mock<IDellOemTelemetry>();

			var provider = CreateProvider(mockComputer, mockWmi, mockDell);
			var result = await provider.GetThermalDataAsync();

			Assert.Equal(55.0, result.CpuPackageCelsius);
			Assert.Equal(2100, result.CpuFanRpm);
			mockWmi.Verify(w => w.GetCpuTemperatureCelsius(), Times.Never);
			mockDell.Verify(d => d.TryGetDellOemTelemetry(), Times.Never);
		}

#endif

		//  PLATFORM SUPPORT TEST
		[Fact]
		public async Task LibreThermalProvider_NonWindowsOS_ThrowsPlatformNotSupportedException()
		{
#if WINDOWS
			return;
#else
            var provider = new LibreThermalProvider();
            var exception = await Record.ExceptionAsync(() => provider.GetThermalDataAsync());
            Assert.NotNull(exception);
            Assert.IsType<PlatformNotSupportedException>(exception);
#endif
		}
	}
}
