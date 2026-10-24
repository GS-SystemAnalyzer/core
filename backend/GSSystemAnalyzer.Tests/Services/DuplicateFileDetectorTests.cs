using System;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using GSSystemAnalyzer.Interfaces;
using GSSystemAnalyzer.Models.SettingDtos;
using GSSystemAnalyzer.Services;
using Moq;
using Xunit;

namespace GSSystemAnalyzer.Tests.Services
{
	public class DuplicateFileDetectorTests : IDisposable
	{
		private readonly string _testBaseDir;
		private readonly DuplicateFileDetector _detector;

		public DuplicateFileDetectorTests()
		{
			_testBaseDir = Path.Combine(Path.GetTempPath(), "GS_Duplicate_Tests_" + Guid.NewGuid().ToString().Substring(0, 8));
			Directory.CreateDirectory(_testBaseDir);

			var mockSettings = new Mock<ISettingService>();
			mockSettings.Setup(s => s.Current)
				.Returns(AppSettingDto.GetFactoryDefaults());

			var mockScanner = new Mock<IDiskScannerEngine>();
			mockScanner.Setup(s => s.GetScanToken(It.IsAny<Guid>())).Returns(CancellationToken.None);

			_detector = new DuplicateFileDetector(mockSettings.Object, mockScanner.Object);
		}

		public void Dispose()
		{
			if (Directory.Exists(_testBaseDir))
			{
				Directory.Delete(_testBaseDir, true);
			}
		}

		private void CreateTestFile(string fileName, string content)
		{
			File.WriteAllText(Path.Combine(_testBaseDir, fileName), content);
		}

		[Fact]
		public async Task Detector_IdenticalContentDifferentNames_FlaggedAsDuplicates()
		{
			CreateTestFile("alpha_copy.txt", "MATRIX_CORE_DATA");
			CreateTestFile("beta_copy.log", "MATRIX_CORE_DATA");
			CreateTestFile("unique_file.txt", "ISOLATED_DATA");

			var results = await _detector.FindDuplicatesAsync(_testBaseDir, Guid.NewGuid());

			Assert.Single(results); // Only one group of duplicates should exist
			var group = results.First();
			Assert.Equal(2, group.FilePaths.Count);
			Assert.Contains(group.FilePaths, p => p.EndsWith("alpha_copy.txt"));
			Assert.Contains(group.FilePaths, p => p.EndsWith("beta_copy.log"));
		}

		[Fact]
		public async Task Detector_ZeroByteFiles_AreSkipped()
		{
			CreateTestFile("empty1.txt", "");
			CreateTestFile("empty2.txt", "");
			CreateTestFile("valid1.txt", "REAL_DATA");
			CreateTestFile("valid2.txt", "REAL_DATA");

			var results = await _detector.FindDuplicatesAsync(_testBaseDir, Guid.NewGuid());

			Assert.Single(results);
			Assert.DoesNotContain(results.First().FilePaths, p => p.Contains("empty1.txt"));
		}

		[Fact]
		public async Task Detector_LockedFiles_DoNotCrashScanAndAreSkipped()
		{
			string lockedPath = Path.Combine(_testBaseDir, "locked_data.txt");
			File.WriteAllText(lockedPath, "SECRET_DATA");

			CreateTestFile("duplicate1.txt", "SAFE_DATA");
			CreateTestFile("duplicate2.txt", "SAFE_DATA");

			using (var lockedStream = new FileStream(lockedPath, FileMode.Open, FileAccess.Read, FileShare.None))
			{
				var exception = await Record.ExceptionAsync(async () => await _detector.FindDuplicatesAsync(_testBaseDir, Guid.NewGuid()));
				var results = await _detector.FindDuplicatesAsync(_testBaseDir, Guid.NewGuid());

				Assert.Null(exception);
				Assert.Single(results);
				Assert.Equal(2, results.First().FilePaths.Count);
			}
		}

		[Fact]
		public async Task Detector_WastedBytes_IsCalculatedCorrectly()
		{
			string content = "1234567890"; // Exactly 10 bytes
			CreateTestFile("fileA.txt", content);
			CreateTestFile("fileB.txt", content);
			CreateTestFile("fileC.txt", content); // 3 copies = 1 original + 2 wasted

			var results = await _detector.FindDuplicatesAsync(_testBaseDir, Guid.NewGuid());

			var group = results.First();
			Assert.Equal(10, group.FileSizeBytes);
			Assert.Equal(20, group.WastedBytes); // 10 bytes * 2 redundant copies
		}

		[Fact]
		public async Task Detector_Groups_AreOrderedByWastedBytesDescending()
		{
			CreateTestFile("small1.txt", "ABCDE");
			CreateTestFile("small2.txt", "ABCDE");
			CreateTestFile("small3.txt", "ABCDE");
			CreateTestFile("small4.txt", "ABCDE");
			CreateTestFile("small5.txt", "ABCDE");

			CreateTestFile("large1.txt", "123456789012345");
			CreateTestFile("large2.txt", "123456789012345");

			var results = await _detector.FindDuplicatesAsync(_testBaseDir, Guid.NewGuid());

			Assert.Equal(2, results.Count);

			Assert.Equal(20, results[0].WastedBytes);
			Assert.Equal(15, results[1].WastedBytes);
		}

		[Fact]
		public async Task Detector_Cancellation_ThrowsOperationCanceledException()
		{
			CreateTestFile("cancel1.txt", "ABCDE");
			CreateTestFile("cancel2.txt", "ABCDE");

			using var cts = new CancellationTokenSource(0);

			var mockSettings = new Mock<ISettingService>();
			mockSettings.Setup(s => s.Current)
				.Returns(AppSettingDto.GetFactoryDefaults());

			var mockScanner = new Mock<IDiskScannerEngine>();
			var scanId = Guid.NewGuid();
			mockScanner.Setup(s => s.GetScanToken(scanId)).Returns(cts.Token);

			var detector = new DuplicateFileDetector(mockSettings.Object, mockScanner.Object);

			await Assert.ThrowsAsync<OperationCanceledException>(async () => await detector.FindDuplicatesAsync(_testBaseDir, scanId));
		}

		[Fact]
		public async Task Detector_StagedHashing_DistinguishesFilesWithSameSizeDifferentContent()
		{
			// Two files with identical length (5000 bytes) but different content
			byte[] dataA = new byte[5000];
			Array.Fill(dataA, (byte)'A');
			byte[] dataB = new byte[5000];
			Array.Fill(dataB, (byte)'B');

			File.WriteAllBytes(Path.Combine(_testBaseDir, "fileA.bin"), dataA);
			File.WriteAllBytes(Path.Combine(_testBaseDir, "fileB.bin"), dataB);

			var results = await _detector.FindDuplicatesAsync(_testBaseDir, Guid.NewGuid());
			Assert.Empty(results);
		}

		[Fact]
		public async Task Detector_ConsumesPreWarmedIndexer_WithoutDiskEnumeration()
		{
			var mockScanner = new Mock<IDiskScannerEngine>();
			mockScanner.Setup(s => s.GetScanToken(It.IsAny<Guid>())).Returns(CancellationToken.None);

			var mockSettings = new Mock<ISettingService>();
			mockSettings.Setup(s => s.Current).Returns(AppSettingDto.GetFactoryDefaults());

			var mockIndexer = new Mock<IFileSystemIndexer>();
			string dup1 = Path.Combine(_testBaseDir, "dup1.txt");
			string dup2 = Path.Combine(_testBaseDir, "dup2.txt");
			File.WriteAllText(dup1, "DUPLICATE_PAYLOAD");
			File.WriteAllText(dup2, "DUPLICATE_PAYLOAD");

			long size = new FileInfo(dup1).Length;
			var fakeIndex = new Dictionary<string, GSSystemAnalyzer.Models.IndexEntry>
			{
				[dup1] = new GSSystemAnalyzer.Models.IndexEntry(dup1, _testBaseDir, false, size, DateTime.UtcNow, FileAttributes.Normal),
				[dup2] = new GSSystemAnalyzer.Models.IndexEntry(dup2, _testBaseDir, false, size, DateTime.UtcNow, FileAttributes.Normal)
			};

			IReadOnlyDictionary<string, GSSystemAnalyzer.Models.IndexEntry> outDict = fakeIndex;
			mockIndexer.Setup(i => i.TryGetIndex(_testBaseDir, out outDict)).Returns(true);

			var detector = new DuplicateFileDetector(mockSettings.Object, mockScanner.Object, mockIndexer.Object);
			var results = await detector.FindDuplicatesAsync(_testBaseDir, Guid.NewGuid());

			Assert.Single(results);
			Assert.Equal(2, results[0].FilePaths.Count);
			Assert.Equal(size, results[0].FileSizeBytes);
			mockIndexer.Verify(i => i.IndexRootAsync(It.IsAny<string>(), It.IsAny<Guid>(), It.IsAny<CancellationToken>()), Times.Never);
		}
	}
}
