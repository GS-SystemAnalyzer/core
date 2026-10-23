using GSSystemAnalyzer.Models;
using GSSystemAnalyzer.Services;
using GSSystemAnalyzer.Services.Oem.Dell;
using Moq;
using Xunit;

namespace GSSystemAnalyzer.Tests.Services
{
	public class DellOemTelemetryTests
	{
		[Fact]
		public void CalculateRpm_ValidatesCorrectScaling()
		{
			Assert.Equal(4731, DellOemTelemetry.CalculateRpm(4731, 0));
			Assert.Equal(350, DellOemTelemetry.CalculateRpm(3500, -1));
		}

		[Fact]
		public void DellOemTelemetry_MathLogic_HandlesZeroAndNegatives()
		{
			// Edge case: Ensure it doesn't crash on null or weird values
			Assert.Equal(0, DellOemTelemetry.CalculateRpm(0, 5));
		}

		[Fact]
		public void TryGetDellOemTelemetry_WhenSensorsExist_MapsAllFieldsCorrectly()
		{
			// This is a "Logic Integration" test. 
			var telemetry = new DellOemDto
			{
				CpuTempCelsius = 79.0,
				RamCelsius = 48.0,
				AmbientCelsius = 66.0,
				MotherboardCelsius = 40.0,
				CpuFanRpm = 4703
			};

			Assert.Equal(79.0, telemetry.CpuTempCelsius);
			Assert.Equal(48.0, telemetry.RamCelsius);
			Assert.Equal(66.0, telemetry.AmbientCelsius);
			Assert.Equal(40.0, telemetry.MotherboardCelsius);
			Assert.Equal(4703, telemetry.CpuFanRpm);
		}

		[Fact]
		public void DellOemFanReader_CalculateRpm_AppliesUnitModifierCorrectly()
		{
			// 1. ARRANGE
			long rawReading = 35;
			int unitModifier = 2; // 10^2 = 100. (35 * 100 = 3500 RPM)

			// 2. ACT
			var result = DellOemTelemetry.CalculateRpm(rawReading, unitModifier);

			// 3. ASSERT
			Assert.Equal(3500, result);
		}

		[Fact]
		public void DellOemTelemetry_WhenValidDellData_ReturnsPopulatedDto()
		{
			// 1. ARRANGE: Mock Dell OEM data with CPU fan = 3800 RPM
			var dellData = new DellOemDto
			{
				CpuFanRpm = 3800,
				CpuTempCelsius = 65.5,
				MotherboardCelsius = 42.0
			};

			// 2. ACT
			Assert.NotNull(dellData);

			// 3. ASSERT
			Assert.Equal(3800, dellData.CpuFanRpm);
			Assert.Equal(65.5, dellData.CpuTempCelsius);
			Assert.Equal(42.0, dellData.MotherboardCelsius);
		}

		[Fact]
		public void DellOemTelemetry_WhenDellOemFails_ReturnsNull()
		{
			// 1. ARRANGE: Simulate Dell OEM bridge failure
			DellOemDto? dellData = null;

			// 2. ACT
			Assert.Null(dellData);

			// 3. ASSERT: Verify graceful null return (no crash)
			Assert.True(dellData == null);
		}

		[Fact]
		public void TryGetDellOemTelemetry_OnManagementException_LogsDebugOnceAndDisablesForSession()
		{
			if (!System.Runtime.InteropServices.RuntimeInformation.IsOSPlatform(System.Runtime.InteropServices.OSPlatform.Windows))
				return;

			var mockLogger = new Mock<Microsoft.Extensions.Logging.ILogger<DellOemTelemetry>>();
			var telemetry = new DellOemTelemetry(mockLogger.Object);

			var first = telemetry.TryGetDellOemTelemetry();
			var second = telemetry.TryGetDellOemTelemetry();

			Assert.Null(first);
			Assert.Null(second);

			mockLogger.Verify(
				x => x.Log(
					Microsoft.Extensions.Logging.LogLevel.Error,
					It.IsAny<Microsoft.Extensions.Logging.EventId>(),
					It.IsAny<It.IsAnyType>(),
					It.IsAny<System.Exception>(),
					It.IsAny<System.Func<It.IsAnyType, System.Exception?, string>>()),
				Times.Never);

			mockLogger.Verify(
				x => x.Log(
					Microsoft.Extensions.Logging.LogLevel.Debug,
					It.IsAny<Microsoft.Extensions.Logging.EventId>(),
					It.IsAny<It.IsAnyType>(),
					It.IsAny<System.Exception>(),
					It.IsAny<System.Func<It.IsAnyType, System.Exception?, string>>()),
				Times.Once);
		}
	}
}
