using System;
using System.Runtime.InteropServices;
using GSSystemAnalyzer.Services;
using Microsoft.Extensions.Logging;
using Moq;
using Xunit;

namespace GSSystemAnalyzer.Tests.Services
{
	public class WmiThermalFallbackTests
	{
		[Fact]
		public void GetCpuTemperatureCelsius_OnManagementException_LogsDebugOnceAndDisablesForSession()
		{
			if (!RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
				return;

			var mockLogger = new Mock<ILogger<WmiThermalFallback>>();
			var fallback = new WmiThermalFallback(mockLogger.Object);

			var first = fallback.GetCpuTemperatureCelsius();
			var second = fallback.GetCpuTemperatureCelsius();

			Assert.Null(first);
			Assert.Null(second);

			mockLogger.Verify(
				x => x.Log(
					LogLevel.Error,
					It.IsAny<EventId>(),
					It.IsAny<It.IsAnyType>(),
					It.IsAny<Exception>(),
					It.IsAny<Func<It.IsAnyType, Exception?, string>>()),
				Times.Never);

			mockLogger.Verify(
				x => x.Log(
					LogLevel.Debug,
					It.IsAny<EventId>(),
					It.IsAny<It.IsAnyType>(),
					It.IsAny<Exception>(),
					It.IsAny<Func<It.IsAnyType, Exception?, string>>()),
				Times.Once);
		}
	}
}
