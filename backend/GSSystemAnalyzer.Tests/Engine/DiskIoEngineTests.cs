using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using GSSystemAnalyzer.Engine;
using GSSystemAnalyzer.Hubs;
using GSSystemAnalyzer.Interfaces;
using GSSystemAnalyzer.Models;
using GSSystemAnalyzer.Models.SettingDtos;
using Microsoft.AspNetCore.SignalR;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using Xunit;

namespace GSSystemAnalyzer.Tests.Engine
{
	public class DiskIoEngineTests
	{
		private readonly Mock<IDiskIoReader> _mockReader;
		private readonly Mock<IHubContext<SystemHub>> _mockHubContext;
		private readonly Mock<ISettingService> _mockSettings;
		private readonly Mock<ITelemetryHistoryBuffer> _mockHistoryBuffer;

		public DiskIoEngineTests()
		{
			_mockReader = new Mock<IDiskIoReader>();
			_mockHubContext = new Mock<IHubContext<SystemHub>>();
			_mockSettings = new Mock<ISettingService>();
			_mockHistoryBuffer = new Mock<ITelemetryHistoryBuffer>();

			_mockSettings.Setup(s => s.Current).Returns(new AppSettingDto());
		}

		[Fact]
		public void SampleMetrics_AggregatesSessionTotals_AndRecordsToHistoryBuffer()
		{
			var rawSamples = new List<DiskIoRawSample>
			{
				new DiskIoRawSample(
					Id: "0",
					Name: "0 C:",
					ReadBytesPerSec: 10485760.0,  // 10 MB/s
					WriteBytesPerSec: 5242880.0,   // 5 MB/s
					ActiveTimePercent: 25.0,
					AvgQueueLength: 0.5,
					Model: "Samsung 980",
					DriveLetters: new[] { "C:" })
			};

			_mockReader.Setup(r => r.ReadSamplesAsync()).ReturnsAsync(rawSamples);

			var engine = new DiskIoEngine(
				_mockReader.Object,
				_mockHubContext.Object,
				_mockSettings.Object,
				_mockHistoryBuffer.Object,
				NullLogger<DiskIoEngine>.Instance);

			var snapshot = engine.SampleMetrics();

			Assert.NotNull(snapshot);
			Assert.Single(snapshot.Disks);
			var disk0 = snapshot.Disks[0];

			Assert.Equal("0", disk0.Id);
			Assert.Equal("Samsung 980", disk0.Model);
			Assert.Contains("C:", disk0.DriveLetters);
			Assert.Equal(10485760.0, disk0.ReadBytesPerSec);
			Assert.Equal(5242880.0, disk0.WriteBytesPerSec);
			Assert.True(disk0.SessionReadBytes > 0);
			Assert.True(disk0.SessionWriteBytes > 0);

			// Must record read & write to history buffer for the primary drive
			_mockHistoryBuffer.Verify(h => h.Record("disk_io_read", 10485760.0), Times.Once);
			_mockHistoryBuffer.Verify(h => h.Record("disk_io_write", 5242880.0), Times.Once);
		}

		[Fact]
		public void GetCurrentSnapshot_ReturnsCachedSnapshotWithoutRedundantSampling()
		{
			var rawSamples = new List<DiskIoRawSample>
			{
				new DiskIoRawSample("0", "0 C:", 1000.0, 500.0, 10.0, 0.1, "Disk 0", new[] { "C:" })
			};

			_mockReader.Setup(r => r.ReadSamplesAsync()).ReturnsAsync(rawSamples);

			var engine = new DiskIoEngine(
				_mockReader.Object,
				_mockHubContext.Object,
				_mockSettings.Object,
				_mockHistoryBuffer.Object,
				NullLogger<DiskIoEngine>.Instance);

			var snap1 = engine.GetCurrentSnapshot();
			var snap2 = engine.GetCurrentSnapshot();

			Assert.NotNull(snap1);
			Assert.NotNull(snap2);
			// Should only have sampled once on lazy seed
			_mockReader.Verify(r => r.ReadSamplesAsync(), Times.Once);
		}
	}
}
