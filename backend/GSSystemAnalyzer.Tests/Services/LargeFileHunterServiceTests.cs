using System;
using System.IO;
using System.Threading.Tasks;
using GSSystemAnalyzer.Interfaces;
using GSSystemAnalyzer.Engine;
using GSSystemAnalyzer.Models.SettingDtos;
using Xunit;
using GSSystemAnalyzer.Services;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;

namespace GSSystemAnalyzer.Tests.Services;

public class LargeFileHunterServiceTests : IDisposable
{
	private readonly string _tempRoot;
	private readonly LargeFileHunterService _hunterService;

	public LargeFileHunterServiceTests()
	{
		_tempRoot = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
		Directory.CreateDirectory(_tempRoot);

		var mockSettings = new Mock<ISettingService>();
		mockSettings.Setup(s => s.Current)
			.Returns(AppSettingDto.GetFactoryDefaults());

		var indexer = new FileSystemIndexer(mockSettings.Object, NullLogger<FileSystemIndexer>.Instance);
		_hunterService = new LargeFileHunterService(indexer, NullLogger<LargeFileHunterService>.Instance);
	}

	[Fact]
	public async Task GetTopLargeFilesAsync_ReturnsCorrectTopNFiles_OrderedDescending()
	{
		// Arrange
		File.WriteAllBytes(Path.Combine(_tempRoot, "file_tiny.txt"), new byte[10]);
		File.WriteAllBytes(Path.Combine(_tempRoot, "file_huge.txt"), new byte[5000]);
		File.WriteAllBytes(Path.Combine(_tempRoot, "file_medium.txt"), new byte[500]);
		File.WriteAllBytes(Path.Combine(_tempRoot, "file_large.txt"), new byte[1000]);
		File.WriteAllBytes(Path.Combine(_tempRoot, "file_small.txt"), new byte[100]);

		// Act
		var results = await _hunterService.GetTopLargeFilesAsync(_tempRoot, 3);

		// Assert
		Assert.Equal(3, results.Count);

		// First rank
		Assert.Equal(5000, results[0].SizeBytes);
		Assert.EndsWith("file_huge.txt", results[0].Path);

		// Second
		Assert.Equal(1000, results[1].SizeBytes);
		Assert.EndsWith("file_large.txt", results[1].Path);

		Assert.Equal(500, results[2].SizeBytes);
		Assert.EndsWith("file_medium.txt", results[2].Path);
	}

	[Fact]
	public async Task GetTopLargeFilesAsync_UsesPreWarmedIndex_WithoutDiskEnumeration()
	{
		var mockIndexer = new Mock<IFileSystemIndexer>();
		var fakeIndex = new Dictionary<string, GSSystemAnalyzer.Models.IndexEntry>
		{
			["C:/fake/tiny.txt"] = new GSSystemAnalyzer.Models.IndexEntry("C:/fake/tiny.txt", "C:/fake", false, 10, DateTime.UtcNow, FileAttributes.Normal),
			["C:/fake/giant.bin"] = new GSSystemAnalyzer.Models.IndexEntry("C:/fake/giant.bin", "C:/fake", false, 999999, DateTime.UtcNow, FileAttributes.Normal),
			["C:/fake/folder"] = new GSSystemAnalyzer.Models.IndexEntry("C:/fake/folder", "C:/fake", true, 0, DateTime.UtcNow, FileAttributes.Directory)
		};

		IReadOnlyDictionary<string, GSSystemAnalyzer.Models.IndexEntry> outDict = fakeIndex;
		mockIndexer.Setup(i => i.TryGetIndex("C:/fake", out outDict)).Returns(true);

		var service = new LargeFileHunterService(mockIndexer.Object, NullLogger<LargeFileHunterService>.Instance);
		var results = await service.GetTopLargeFilesAsync("C:/fake", 1);

		Assert.Single(results);
		Assert.Equal(999999, results[0].SizeBytes);
		Assert.Equal("C:/fake/giant.bin", results[0].Path);
		mockIndexer.Verify(i => i.IndexRootAsync(It.IsAny<string>(), It.IsAny<Guid>(), It.IsAny<CancellationToken>()), Times.Never);
	}

	public void Dispose()
	{
		// Global Cleanup!
		if (Directory.Exists(_tempRoot))
		{
			Directory.Delete(_tempRoot, true);
		}
	}
}
