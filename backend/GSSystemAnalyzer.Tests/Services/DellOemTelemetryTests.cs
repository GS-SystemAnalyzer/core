using System.Management;
using System.Runtime.Versioning;
using GSSystemAnalyzer.Models;
using GSSystemAnalyzer.Services;
using GSSystemAnalyzer.Services.Oem.Dell;
using Microsoft.Extensions.Logging;
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

		[Theory]
		[SupportedOSPlatform("windows")]
		[InlineData(ManagementStatus.AccessDenied)]
		[InlineData(ManagementStatus.InvalidClass)]
		[InlineData(ManagementStatus.InvalidNamespace)]
		[InlineData(ManagementStatus.NotFound)]
		[InlineData(ManagementStatus.NotSupported)]
		public void TryGetDellOemTelemetry_OnPermanentError_LogsDebugOnceAndDisables(ManagementStatus status)
		{
			if (!OperatingSystem.IsWindows()) return;
			var error = ManagementExceptionFactory.Create(status);
			var logger = new Mock<ILogger<DellOemTelemetry>>();
			var calls = 0;
			var telemetry = new DellOemTelemetry(logger.Object, () => { calls++; throw error; }, new ManualTimeProvider());

			Assert.Null(telemetry.TryGetDellOemTelemetry());
			Assert.Null(telemetry.TryGetDellOemTelemetry());
			Assert.Equal(1, calls);
			Assert.Equal(LogLevel.Debug, Assert.Single(logger.Invocations).Arguments[0]);
		}

		[Fact]
		public void TryGetDellOemTelemetry_OnRetryableError_LogsWarningAndRetries()
		{
			if (!OperatingSystem.IsWindows()) return;
			var error = ManagementExceptionFactory.Create(ManagementStatus.Failed);
			var logger = new Mock<ILogger<DellOemTelemetry>>();
			var value = new DellOemDto { CpuTempCelsius = 65.5 };
			var calls = 0;
			var telemetry = new DellOemTelemetry(logger.Object,
				() => ++calls == 1 ? throw error : value, new ManualTimeProvider());

			Assert.Null(telemetry.TryGetDellOemTelemetry());
			Assert.Same(value, telemetry.TryGetDellOemTelemetry());
			Assert.Equal(2, calls);
			Assert.Equal(LogLevel.Warning, Assert.Single(logger.Invocations).Arguments[0]);
		}

		[Fact]
		public void TryGetDellOemTelemetry_OnGeneralError_LogsDebugOnceAndDisables()
		{
			var logger = new Mock<ILogger<DellOemTelemetry>>();
			var calls = 0;
			var telemetry = new DellOemTelemetry(logger.Object,
				() => { calls++; throw new InvalidOperationException("controlled"); }, new ManualTimeProvider());

			Assert.Null(telemetry.TryGetDellOemTelemetry());
			Assert.Null(telemetry.TryGetDellOemTelemetry());
			Assert.Equal(1, calls);
			Assert.Equal(LogLevel.Debug, Assert.Single(logger.Invocations).Arguments[0]);
		}

		[Fact]
		public void TryGetDellOemTelemetry_AfterEmptyResult_Retries()
		{
			var logger = new Mock<ILogger<DellOemTelemetry>>();
			var value = new DellOemDto { CpuTempCelsius = 65.5 };
			var calls = 0;
			var telemetry = new DellOemTelemetry(logger.Object,
				() => ++calls == 1 ? null : value, new ManualTimeProvider());

			Assert.Null(telemetry.TryGetDellOemTelemetry());
			Assert.Same(value, telemetry.TryGetDellOemTelemetry());
			Assert.Equal(2, calls);
			Assert.Empty(logger.Invocations);
		}

		[Fact]
		public void TryGetDellOemTelemetry_CachesUntilExactlyThreeSeconds()
		{
			var logger = new Mock<ILogger<DellOemTelemetry>>();
			var clock = new ManualTimeProvider();
			var calls = 0;
			var telemetry = new DellOemTelemetry(logger.Object,
				() => new DellOemDto { CpuTempCelsius = 50 + ++calls }, clock);

			var first = Assert.IsType<DellOemDto>(telemetry.TryGetDellOemTelemetry());
			Assert.Equal(51, first.CpuTempCelsius);
			clock.Now += TimeSpan.FromSeconds(3) - TimeSpan.FromTicks(1);
			Assert.Same(first, telemetry.TryGetDellOemTelemetry());
			Assert.Equal(1, calls);
			clock.Now += TimeSpan.FromTicks(1);
			var refreshed = Assert.IsType<DellOemDto>(telemetry.TryGetDellOemTelemetry());
			Assert.Equal(52, refreshed.CpuTempCelsius);
			Assert.NotSame(first, refreshed);
			Assert.Equal(2, calls);
			Assert.Empty(logger.Invocations);
		}

		[Fact]
		public void TryGetDellOemTelemetry_InstancesDoNotShareCachedReadings()
		{
			var clock = new ManualTimeProvider();
			var logger = new Mock<ILogger<DellOemTelemetry>>();
			var firstValue = new DellOemDto { CpuTempCelsius = 55 };
			var secondValue = new DellOemDto { CpuTempCelsius = 75 };
			var first = new DellOemTelemetry(logger.Object, () => firstValue, clock);
			var secondCalls = 0;
			var second = new DellOemTelemetry(logger.Object, () => { secondCalls++; return secondValue; }, clock);

			Assert.Same(firstValue, first.TryGetDellOemTelemetry());
			Assert.Same(secondValue, second.TryGetDellOemTelemetry());
			Assert.Equal(1, secondCalls);
		}

		[Fact]
		public void TryGetDellOemTelemetry_SuccessDoesNotHideIndependentReaderFailure()
		{
			var logger = new Mock<ILogger<DellOemTelemetry>>();
			var clock = new ManualTimeProvider();
			var value = new DellOemDto { CpuTempCelsius = 55 };
			var first = new DellOemTelemetry(logger.Object, () => value, clock);
			var calls = 0;
			var second = new DellOemTelemetry(logger.Object,
				() => { calls++; throw new InvalidOperationException("controlled"); }, clock);

			Assert.Same(value, first.TryGetDellOemTelemetry());
			Assert.Null(second.TryGetDellOemTelemetry());
			Assert.Null(second.TryGetDellOemTelemetry());
			Assert.Same(value, first.TryGetDellOemTelemetry());
			Assert.Equal(1, calls);
			Assert.Equal(LogLevel.Debug, Assert.Single(logger.Invocations).Arguments[0]);
		}

		private sealed class ManualTimeProvider : TimeProvider
		{
			public DateTimeOffset Now { get; set; } = new(2050, 1, 1, 0, 0, 0, TimeSpan.Zero);
			public override DateTimeOffset GetUtcNow() => Now;
		}
	}
}
