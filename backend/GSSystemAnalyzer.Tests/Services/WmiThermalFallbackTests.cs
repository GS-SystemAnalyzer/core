using System;
using System.Management;
using System.Reflection;
using System.Runtime.Versioning;
using GSSystemAnalyzer.Services;
using Microsoft.Extensions.Logging;
using Moq;
using Xunit;

namespace GSSystemAnalyzer.Tests.Services
{
	public class WmiThermalFallbackTests
	{
		[Theory]
		[SupportedOSPlatform("windows")]
		[InlineData(ManagementStatus.AccessDenied)]
		[InlineData(ManagementStatus.InvalidClass)]
		[InlineData(ManagementStatus.InvalidNamespace)]
		[InlineData(ManagementStatus.NotFound)]
		[InlineData(ManagementStatus.NotSupported)]
		public void GetCpuTemperatureCelsius_OnPermanentError_LogsDebugOnceAndDisables(ManagementStatus status)
		{
			if (!OperatingSystem.IsWindows()) return;
			var error = ManagementExceptionFactory.Create(status);
			var logger = new Mock<ILogger<WmiThermalFallback>>();
			var calls = 0;
			var fallback = new WmiThermalFallback(logger.Object, () => { calls++; throw error; });

			Assert.Null(fallback.GetCpuTemperatureCelsius());
			Assert.Null(fallback.GetCpuTemperatureCelsius());
			Assert.Equal(1, calls);
			Assert.Equal(LogLevel.Debug, Assert.Single(logger.Invocations).Arguments[0]);
		}

		[Fact]
		public void GetCpuTemperatureCelsius_OnRetryableError_LogsWarningAndRetries()
		{
			if (!OperatingSystem.IsWindows()) return;
			var error = ManagementExceptionFactory.Create(ManagementStatus.Failed);
			var logger = new Mock<ILogger<WmiThermalFallback>>();
			var calls = 0;
			var fallback = new WmiThermalFallback(logger.Object, () => ++calls == 1 ? throw error : 65.5);

			Assert.Null(fallback.GetCpuTemperatureCelsius());
			Assert.Equal(65.5, fallback.GetCpuTemperatureCelsius());
			Assert.Equal(2, calls);
			Assert.Equal(LogLevel.Warning, Assert.Single(logger.Invocations).Arguments[0]);
		}

		[Fact]
		public void GetCpuTemperatureCelsius_OnGeneralError_LogsDebugOnceAndDisables()
		{
			var logger = new Mock<ILogger<WmiThermalFallback>>();
			var calls = 0;
			var fallback = new WmiThermalFallback(logger.Object,
				() => { calls++; throw new InvalidOperationException("controlled"); });

			Assert.Null(fallback.GetCpuTemperatureCelsius());
			Assert.Null(fallback.GetCpuTemperatureCelsius());
			Assert.Equal(1, calls);
			Assert.Equal(LogLevel.Debug, Assert.Single(logger.Invocations).Arguments[0]);
		}

		[Fact]
		public void GetCpuTemperatureCelsius_AfterEmptyResult_RetriesAndReturnsValidReadings()
		{
			var logger = new Mock<ILogger<WmiThermalFallback>>();
			var calls = 0;
			var fallback = new WmiThermalFallback(logger.Object, () => ++calls == 1 ? null : 65.5);

			Assert.Null(fallback.GetCpuTemperatureCelsius());
			Assert.Equal(65.5, fallback.GetCpuTemperatureCelsius());
			Assert.Equal(65.5, fallback.GetCpuTemperatureCelsius());
			Assert.Equal(3, calls);
			Assert.Empty(logger.Invocations);
		}
	}

	internal static class ManagementExceptionFactory
	{
		[SupportedOSPlatform("windows")]
		internal static ManagementException Create(ManagementStatus status)
		{
			var constructor = typeof(ManagementException).GetConstructor(BindingFlags.Instance | BindingFlags.NonPublic,
				null, new[] { typeof(ManagementStatus), typeof(string), typeof(ManagementBaseObject) }, null);
			Assert.NotNull(constructor);
			var error = Assert.IsType<ManagementException>(constructor.Invoke(new object?[] { status, "controlled", null }));
			Assert.Equal(status, error.ErrorCode);
			return error;
		}
	}
}
