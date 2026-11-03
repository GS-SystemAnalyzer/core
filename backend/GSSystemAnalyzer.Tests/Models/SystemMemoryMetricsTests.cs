using GSSystemAnalyzer.Models;

namespace GSSystemAnalyzer.Tests.Models;

public class SystemMemoryMetricsTests
{
	[Fact]
	public void NativeMapping_PreservesExactMeasuredPhysicalCapacityAndAvailability()
	{
		var result = SystemMemoryMetrics.FromNativeStatus(new SystemMemoryMetrics.MEMORYSTATUSEX
		{
			ullTotalPhys = 17179869184,
			ullAvailPhys = 123456789,
			ulTotalPagePhys = 34359738368,
			ulAvailPagePhys = 8589934592
		});
		Assert.NotNull(result);
		Assert.Equal(17179869184, result.PhysicalTotalBytes);
		Assert.Equal(123456789, result.AvailablePhysicalBytes);
		Assert.Equal(16, result.TotalGb);
	}

	[Theory]
	[InlineData(0UL, 0UL)]
	[InlineData(100UL, 101UL)]
	[InlineData(ulong.MaxValue, 0UL)]
	public void InvalidNativeCapacity_IsUnavailable(ulong total, ulong available)
	{
		Assert.Null(SystemMemoryMetrics.FromNativeStatus(new SystemMemoryMetrics.MEMORYSTATUSEX
		{
			ullTotalPhys = total, ullAvailPhys = available
		}));
	}

	[Fact]
	public void LegacyOrFallbackGlobals_DoNotManufactureMeasuredCapacity()
	{
		Assert.Null(new SystemMemoryMetrics.GlobalMemoryMetrics { TotalGb = 16 }.PhysicalTotalBytes);
	}
}
