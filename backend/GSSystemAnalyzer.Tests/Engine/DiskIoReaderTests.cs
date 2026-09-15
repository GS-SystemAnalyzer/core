using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using GSSystemAnalyzer.Models;
using GSSystemAnalyzer.Services;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace GSSystemAnalyzer.Tests.Engine
{
	public class DiskIoReaderTests : IDisposable
	{
		private readonly string _tempDir;
		private readonly string _tempDiskstatsFile;
		private readonly string _tempMountsFile;

		public DiskIoReaderTests()
		{
			_tempDir = Path.Combine(Path.GetTempPath(), "gs_diskio_tests_" + Guid.NewGuid().ToString("N"));
			Directory.CreateDirectory(_tempDir);
			_tempDiskstatsFile = Path.Combine(_tempDir, "diskstats");
			_tempMountsFile = Path.Combine(_tempDir, "mounts");
		}

		public void Dispose()
		{
			try
			{
				if (Directory.Exists(_tempDir))
				{
					Directory.Delete(_tempDir, true);
				}
			}
			catch
			{
				// Ignore cleanup errors in tests
			}
		}

		#region Linux Reader Tests

		[Fact]
		public async Task LinuxDiskIoReader_ParsesDiskstats_MultipliesSectorsBy512_AndFiltersPartitionsAndLoop()
		{
			// /proc/diskstats fixture:
			// Fields: 0:major 1:minor 2:name 3:rio 4:rmerge 5:rsect 6:ruse 7:wio 8:wmerge 9:wsect 10:wuse 11:in_prog 12:io_ms 13:w_io_ms
			var sample1 = string.Join("\n", new[]
			{
				"   7       0 loop0 0 0 0 0 0 0 0 0 0 0 0",
				"   1       0 ram0 0 0 0 0 0 0 0 0 0 0 0",
				" 259       0 nvme0n1 1000 50 20000 400 500 20 10000 200 2 150 600",
				" 259       1 nvme0n1p1 100 5 2000 40 50 2 1000 20 0 15 60",
				"   8       0 sda 500 10 10000 200 250 5 5000 100 1 80 300",
				"   8       1 sda1 500 10 10000 200 250 5 5000 100 1 80 300"
			});

			File.WriteAllText(_tempDiskstatsFile, sample1);
			File.WriteAllText(_tempMountsFile, "/dev/nvme0n1p1 / ext4 rw 0 0\n/dev/sda1 /mnt/data ext4 rw 0 0\n");

			var reader = new LinuxDiskIoReader(NullLogger<LinuxDiskIoReader>.Instance, _tempDiskstatsFile, _tempMountsFile);

			// Baseline sample establishes previous values
			var firstPass = await reader.ReadSamplesAsync();

			Assert.Equal(2, firstPass.Count); // nvme0n1 and sda only (loop, ram, partitions excluded)
			var nvme = firstPass.First(d => d.Id == "nvme0n1");
			var sda = firstPass.First(d => d.Id == "sda");

			Assert.Contains("/", nvme.DriveLetters!);
			Assert.Contains("/mnt/data", sda.DriveLetters!);

			// Second sample with increased sectors and io_ms
			var sample2 = string.Join("\n", new[]
			{
				"   7       0 loop0 0 0 0 0 0 0 0 0 0 0 0",
				"   1       0 ram0 0 0 0 0 0 0 0 0 0 0 0",
				" 259       0 nvme0n1 1100 50 22000 440 600 20 12000 240 1 250 800", // +2000 sectors read, +2000 sectors written (+1,024,000 bytes each)
				" 259       1 nvme0n1p1 100 5 2000 40 50 2 1000 20 0 15 60",
				"   8       0 sda 550 10 11000 220 300 5 6000 120 0 120 400",          // +1000 sectors read, +1000 sectors written (+512,000 bytes each)
				"   8       1 sda1 500 10 10000 200 250 5 5000 100 1 80 300"
			});

			await Task.Delay(50); // Ensure small elapsed time
			File.WriteAllText(_tempDiskstatsFile, sample2);

			var secondPass = await reader.ReadSamplesAsync();
			var nvme2 = secondPass.First(d => d.Id == "nvme0n1");

			Assert.True(nvme2.ReadBytesPerSec > 0, "ReadBytesPerSec should be computed from sector delta * 512");
			Assert.True(nvme2.WriteBytesPerSec > 0, "WriteBytesPerSec should be computed from sector delta * 512");
			Assert.True(nvme2.ActiveTimePercent >= 0.0, "ActiveTimePercent should be non-negative");
		}

		#endregion

		#region Windows Reader Tests with Faked WMI

		private class FakeWmiDiskIoSource : IWmiDiskIoSource
		{
			public List<WmiPhysicalDiskPerfRecord> PerfRecords { get; set; } = new();
			public List<WmiDiskMappingRecord> DiskMappings { get; set; } = new();

			public IReadOnlyList<WmiPhysicalDiskPerfRecord> GetPerfRecords() => PerfRecords;
			public IReadOnlyList<WmiDiskMappingRecord> GetDiskMappings() => DiskMappings;
		}

		[Fact]
		public async Task WindowsDiskIoReader_SkipsTotal_MapsPartitionsAndDriveLettersCorrectly()
		{
			var fakeSource = new FakeWmiDiskIoSource
			{
				PerfRecords = new List<WmiPhysicalDiskPerfRecord>
				{
					new WmiPhysicalDiskPerfRecord("_Total", 50000000.0, 30000000.0, 80.0, 2.5),
					new WmiPhysicalDiskPerfRecord("0 C:", 30000000.0, 20000000.0, 45.0, 0.8),
					new WmiPhysicalDiskPerfRecord("1 D: E:", 20000000.0, 10000000.0, 35.0, 1.7)
				},
				DiskMappings = new List<WmiDiskMappingRecord>
				{
					new WmiDiskMappingRecord("0", "Samsung SSD 980 PRO 1TB", new[] { "C:" }),
					new WmiDiskMappingRecord("1", "Crucial CT2000MX500 2TB", new[] { "D:", "E:" })
				}
			};

			var reader = new WindowsDiskIoReader(fakeSource, NullLogger<WindowsDiskIoReader>.Instance);
			var samples = await reader.ReadSamplesAsync();

			// _Total must be skipped
			Assert.Equal(2, samples.Count);
			Assert.DoesNotContain(samples, s => s.Id == "_Total" || s.Name == "_Total");

			var disk0 = samples.First(s => s.Id == "0");
			Assert.Equal("Samsung SSD 980 PRO 1TB", disk0.Model);
			Assert.Contains("C:", disk0.DriveLetters!);
			Assert.Equal(30000000.0, disk0.ReadBytesPerSec);
			Assert.Equal(20000000.0, disk0.WriteBytesPerSec);
			Assert.Equal(45.0, disk0.ActiveTimePercent);
			Assert.Equal(0.8, disk0.AvgQueueLength);

			var disk1 = samples.First(s => s.Id == "1");
			Assert.Equal("Crucial CT2000MX500 2TB", disk1.Model);
			Assert.Contains("D:", disk1.DriveLetters!);
			Assert.Contains("E:", disk1.DriveLetters!);
			Assert.Equal(2, disk1.DriveLetters!.Count);
		}

		[Fact]
		public async Task WindowsDiskIoReader_FallsBackToExtractingLettersFromName_WhenMappingIsEmpty()
		{
			var fakeSource = new FakeWmiDiskIoSource
			{
				PerfRecords = new List<WmiPhysicalDiskPerfRecord>
				{
					new WmiPhysicalDiskPerfRecord("2 F:", 5000000.0, 2000000.0, 12.0, 0.3)
				},
				DiskMappings = new List<WmiDiskMappingRecord>() // Empty mapping
			};

			var reader = new WindowsDiskIoReader(fakeSource, NullLogger<WindowsDiskIoReader>.Instance);
			var samples = await reader.ReadSamplesAsync();

			Assert.Single(samples);
			var disk2 = samples[0];
			Assert.Equal("2", disk2.Id);
			Assert.Contains("F:", disk2.DriveLetters!);
		}

		#endregion
	}
}
