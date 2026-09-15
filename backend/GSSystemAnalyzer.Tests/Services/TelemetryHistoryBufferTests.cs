using GSSystemAnalyzer.Interfaces;
using GSSystemAnalyzer.Services;
using Moq;

namespace GSSystemAnalyzer.Tests.Services
{
	public class TelemetryHistoryBufferTests
	{
		private readonly Mock<TimeProvider> _mockTime;
		private readonly ITelemetryHistoryBuffer _buffer;
		private DateTimeOffset _currentTime;

		public TelemetryHistoryBufferTests()
		{
			_mockTime = new Mock<TimeProvider>();
			_currentTime = new DateTimeOffset(2024, 1, 1, 12, 0, 0, TimeSpan.Zero);
			_mockTime.Setup(t => t.GetUtcNow()).Returns(() => _currentTime);
			_buffer = new TelemetryHistoryBuffer(_mockTime.Object);
		}

		private void AdvanceTime(TimeSpan duration)
		{
			_currentTime = _currentTime.Add(duration);
		}

		[Fact]
		public void Record_AddsPointToBuffer()
		{
			_buffer.Record("cpu", 42.5);

			var result = _buffer.GetHistory("cpu", 5);

			Assert.NotNull(result);
			Assert.Single(result!.Points);
			Assert.Equal(42.5, result.Points[0].Value);
			Assert.Equal(_currentTime.UtcDateTime, result.Points[0].Timestamp);
		}

		[Fact]
		public void GetHistory_ExcludesPointsOutsideRequestedWindow()
		{
			// Record at T=0
			_buffer.Record("cpu", 10.0);

			AdvanceTime(TimeSpan.FromMinutes(10));

			// Record at T=10
			_buffer.Record("cpu", 20.0);

			// Query last 5 minutes (from T=10, looks back to T=5)
			// The T=0 point should be excluded
			var result = _buffer.GetHistory("cpu", 5);

			Assert.NotNull(result);
			Assert.Single(result!.Points);
			Assert.Equal(20.0, result.Points[0].Value); // Only the recent one
		}

		[Fact]
		public void Record_PrunesPointsOlderThan60Minutes()
		{
			// T=0
			_buffer.Record("cpu", 10.0);

			AdvanceTime(TimeSpan.FromMinutes(30));
			// T=30
			_buffer.Record("cpu", 20.0);

			AdvanceTime(TimeSpan.FromMinutes(35));
			// T=65 (The T=0 point is now older than 60m and should be pruned when we Record)
			_buffer.Record("cpu", 30.0);

			// Ask for 60 minutes history
			var result = _buffer.GetHistory("cpu", 60);

			Assert.NotNull(result);
			Assert.Equal(2, result!.Points.Count);
			Assert.Equal(20.0, result.Points[0].Value); // T=30 point
			Assert.Equal(30.0, result.Points[1].Value); // T=65 point
		}

		[Fact]
		public void GetHistory_ComputesStatsCorrectly()
		{
			_buffer.Record("cpu", 10.0);
			_buffer.Record("cpu", 50.0);
			_buffer.Record("cpu", 30.0);
			_buffer.Record("cpu", 90.0);

			var result = _buffer.GetHistory("cpu", 5);

			Assert.NotNull(result);
			Assert.Equal(10.0, result!.Stats.Min);
			Assert.Equal(90.0, result.Stats.Max);
			Assert.Equal(45.0, result.Stats.Avg);
			Assert.Equal(90.0, result.Stats.Current); // Last recorded point
		}

		[Fact]
		public void GetHistory_ReturnsNullForUnknownMetric()
		{
			var result = _buffer.GetHistory("does_not_exist", 5);

			Assert.Null(result);
		}

		[Fact]
		public void GetHistory_ReturnsEmptyPointsWhenNoData()
		{
			var result = _buffer.GetHistory("cpu", 5);

			Assert.NotNull(result);
			Assert.Empty(result!.Points);
			Assert.Equal(0, result.Stats.Min);
			Assert.Equal(0, result.Stats.Max);
			Assert.Equal(0, result.Stats.Avg);
			Assert.Equal(0, result.Stats.Current);
		}

		[Fact]
		public void GetSupportedMetrics_ReturnsAllRegisteredKeys()
		{
			var metrics = _buffer.GetSupportedMetrics();

			Assert.Contains("cpu", metrics);
			Assert.Contains("ram", metrics);
			Assert.Contains("ram_percent", metrics);
			Assert.Contains("thermal_cpu_package", metrics);
			Assert.Contains("network_rx", metrics);
			Assert.Contains("network_tx", metrics);
			Assert.Contains("disk_io_read", metrics);
			Assert.Contains("disk_io_write", metrics);
			Assert.Equal(8, metrics.Count);
		}

		[Fact]
		public void Record_IgnoresUnknownMetric()
		{
			_buffer.Record("unknown_metric", 99.0);

			var result = _buffer.GetHistory("unknown_metric", 5);
			Assert.Null(result);
		}

		[Fact]
		public void Record_BothRamMetrics_StoresSeparately()
		{
			_buffer.Record("ram", 8.5);
			_buffer.Record("ram_percent", 53.1);

			var ramResult = _buffer.GetHistory("ram", 5);
			var pctResult = _buffer.GetHistory("ram_percent", 5);

			Assert.NotNull(ramResult);
			Assert.NotNull(pctResult);
			Assert.Single(ramResult!.Points);
			Assert.Single(pctResult!.Points);
			Assert.Equal(8.5, ramResult.Points[0].Value);
			Assert.Equal(53.1, pctResult.Points[0].Value);
			Assert.Equal("GB", ramResult.Unit);
			Assert.Equal("%", pctResult.Unit);
		}

		[Fact]
		public void GetHistory_RoundsValuesToTwoDecimals()
		{
			_buffer.Record("cpu", 42.5678);

			var result = _buffer.GetHistory("cpu", 5);

			Assert.NotNull(result);
			Assert.Equal(42.57, result!.Points[0].Value);
		}

		[Fact]
		public void GetHistory_ClampsMinutesToValidRange()
		{
			_buffer.Record("cpu", 50.0);

			var tooLow = _buffer.GetHistory("cpu", -10);
			var tooHigh = _buffer.GetHistory("cpu", 200);

			Assert.NotNull(tooLow);
			Assert.Equal(1, tooLow!.Minutes);

			Assert.NotNull(tooHigh);
			Assert.Equal(60, tooHigh!.Minutes);
		}

		[Fact]
		public async Task ConcurrentAccess_DoesNotThrow()
		{
			var exceptions = new System.Collections.Concurrent.ConcurrentBag<Exception>();

			var writeTask = Task.Run(() =>
			{
				Parallel.For(0, 1000, i =>
				{
					try
					{
						_buffer.Record("cpu", i % 100);
					}
					catch (Exception ex)
					{
						exceptions.Add(ex);
					}
				});
			});

			var readTask = Task.Run(() =>
			{
				Parallel.For(0, 500, _ =>
				{
					try
					{
						_buffer.GetHistory("cpu", 5);
					}
					catch (Exception ex)
					{
						exceptions.Add(ex);
					}
				});
			});

			await Task.WhenAll(writeTask, readTask);

			Assert.Empty(exceptions);
		}
	}
}
