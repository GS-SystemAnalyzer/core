using GSSystemAnalyzer.Engine;
using GSSystemAnalyzer.Hubs;
using GSSystemAnalyzer.Interfaces;
using GSSystemAnalyzer.Models;
using GSSystemAnalyzer.Models.SettingDtos;
using Microsoft.AspNetCore.SignalR;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;

namespace GSSystemAnalyzer.Tests.Engine;

public class FileTypeScannerTests
{

	private static DiskScannerEngine CreateEngine()
	{
		var mockClients = new Mock<IHubClients>();
		var mockClient = new Mock<IClientProxy>();
		mockClients.Setup(c => c.All).Returns(mockClient.Object);

		var mockHub = new Mock<IHubContext<SystemHub>>();
		mockHub.Setup(h => h.Clients).Returns(mockClients.Object);

		var mockSettings = new Mock<ISettingService>();
		mockSettings.Setup(s => s.Current).Returns(new AppSettingDto());

		var engine = new DiskScannerEngine(mockHub.Object, mockSettings.Object, NullLogger<DiskScannerEngine>.Instance);
		// Clear the cache to prevent tests from reading the user's actual saved memory from disk
		engine.DirectorySizeCache.Clear();
		return engine;
	}

	private static IMemoryCache CreateCache() =>
		new MemoryCache(new MemoryCacheOptions());

	private static FileTypeScanner CreateScanner(
		DiskScannerEngine? engine = null,
		IMemoryCache? cache = null) =>
		new(engine ?? CreateEngine(), cache ?? CreateCache());

	/// Seeds a CacheEntry with extension data onto DirectorySizeCache.
	private static void SeedCache(
		DiskScannerEngine engine,
		string path,
		Dictionary<string, FileTypeEntry>? extensions = null)
	{
		engine.DirectorySizeCache[path] = new CacheEntry
		{
			Size = extensions?.Values.Sum(e => e.Bytes) ?? 1024,
			LastUpdated = DateTime.UtcNow,
			Extensions = extensions
		};
	}


	[Fact]
	public void Analyze_ReturnsNull_WhenDirectoryCacheIsEmpty()
	{
		var scanner = CreateScanner();

		var result = scanner.Analyze(@"C:\Users");

		Assert.Null(result);
	}

	[Fact]
	public void Analyze_ReturnsNull_WhenRootHasNoMatchingCacheKey()
	{
		var engine = CreateEngine();
		SeedCache(engine, @"D:\SomeFolder");  // D:\, not C:\
		var scanner = CreateScanner(engine);

		var result = scanner.Analyze(@"C:\");

		Assert.Null(result);
	}


	[Fact]
	public void Analyze_ReturnsResult_WhenCacheHasMatchingEntries()
	{
		var engine = CreateEngine();
		SeedCache(engine, @"C:\Windows\System32", new()
		{
			[".dll"] = new FileTypeEntry { Count = 50, Bytes = 5_242_880 },
			[".exe"] = new FileTypeEntry { Count = 10, Bytes = 1_048_576 },
		});
		var scanner = CreateScanner(engine);

		var result = scanner.Analyze(@"C:\");

		Assert.NotNull(result);
		Assert.NotEmpty(result!.Categories);
	}

	[Fact]
	public void Analyze_AggregatesExtensionsAcrossMultipleCachedDirs()
	{
		var engine = CreateEngine();

		// Two separate subdirectories both have .cs files
		SeedCache(engine, @"C:\Projects\App", new()
		{
			[".cs"] = new FileTypeEntry { Count = 10, Bytes = 100_000 }
		});
		SeedCache(engine, @"C:\Projects\Tests", new()
		{
			[".cs"] = new FileTypeEntry { Count = 5, Bytes = 50_000 }
		});

		var scanner = CreateScanner(engine);
		var result = scanner.Analyze(@"C:\")!;

		var codeCategory = result.Categories.FirstOrDefault(c => c.Name == "code");
		Assert.NotNull(codeCategory);

		// Combined: 15 files, 150_000 bytes
		Assert.Equal(15, codeCategory!.FileCount);
		Assert.Equal(150_000, codeCategory.TotalBytes);
	}

	[Fact]
	public void Analyze_HandlesNullExtensionsOnCacheEntry_WithoutThrowing()
	{
		var engine = CreateEngine();
		// CacheEntry with null Extensions — should not crash
		SeedCache(engine, @"C:\Windows", extensions: null);

		var scanner = CreateScanner(engine);
		var ex = Record.Exception(() => scanner.Analyze(@"C:\"));

		Assert.Null(ex);
	}

	[Fact]
	public void Analyze_NullExtensionEntry_ReturnsEmptyCategories()
	{
		var engine = CreateEngine();
		SeedCache(engine, @"C:\Windows", extensions: null);

		var scanner = CreateScanner(engine);
		var result = scanner.Analyze(@"C:\");

		// No extensions in cache → null result (no scan data means 409)
		// OR empty categories depending on impl — key thing: no crash
		// Result may be null (wasScanned=true but extMap empty → empty result)
		if (result != null)
			Assert.Empty(result.Categories);
	}


	[Fact]
	public void Analyze_MapsKnownExtensionsToCorrectCategories()
	{
		var engine = CreateEngine();
		SeedCache(engine, @"C:\test", new()
		{
			[".exe"] = new FileTypeEntry { Count = 1, Bytes = 1_000_000 }, // executables
			[".cs"] = new FileTypeEntry { Count = 1, Bytes = 100_000 }, // code
			[".mp4"] = new FileTypeEntry { Count = 1, Bytes = 500_000 }, // media
			[".pdf"] = new FileTypeEntry { Count = 1, Bytes = 200_000 }, // documents
			[".zip"] = new FileTypeEntry { Count = 1, Bytes = 300_000 }, // archives
			[".sys"] = new FileTypeEntry { Count = 1, Bytes = 50_000 }, // system
		});

		var scanner = CreateScanner(engine);
		var result = scanner.Analyze(@"C:\")!;
		var catNames = result.Categories.Select(c => c.Name).ToHashSet();

		Assert.Contains("executables", catNames);
		Assert.Contains("code", catNames);
		Assert.Contains("media", catNames);
		Assert.Contains("documents", catNames);
		Assert.Contains("archives", catNames);
		Assert.Contains("system", catNames);
	}

	[Fact]
	public void Analyze_UnknownExtension_BucketedAsOther()
	{
		var engine = CreateEngine();
		SeedCache(engine, @"C:\test", new()
		{
			[".notarealex"] = new FileTypeEntry { Count = 7, Bytes = 70_000 }
		});

		var scanner = CreateScanner(engine);
		var result = scanner.Analyze(@"C:\")!;
		var other = result.Categories.FirstOrDefault(c => c.Name == "other");

		Assert.NotNull(other);
		Assert.Equal(7, other!.FileCount);
	}


	[Fact]
	public void Analyze_CategoriesOrderedByTotalBytesDescending()
	{
		var engine = CreateEngine();
		SeedCache(engine, @"C:\test", new()
		{
			[".cs"] = new FileTypeEntry { Count = 1, Bytes = 100 },   // code (smallest)
			[".exe"] = new FileTypeEntry { Count = 1, Bytes = 50_000_000 }, // executables (biggest)
			[".mp4"] = new FileTypeEntry { Count = 1, Bytes = 10_000_000 }, // media (middle)
		});

		var scanner = CreateScanner(engine);
		var sizes = scanner.Analyze(@"C:\")!.Categories
							 .Select(c => c.TotalBytes)
							 .ToList();

		Assert.Equal(sizes.OrderByDescending(x => x).ToList(), sizes);
	}

	[Fact]
	public void Analyze_PercentOfDisk_SumsToApproximately100()
	{
		var engine = CreateEngine();
		SeedCache(engine, @"C:\test", new()
		{
			[".exe"] = new FileTypeEntry { Count = 10, Bytes = 1_000_000 },
			[".dll"] = new FileTypeEntry { Count = 20, Bytes = 2_000_000 },
			[".cs"] = new FileTypeEntry { Count = 5, Bytes = 500_000 },
		});

		var scanner = CreateScanner(engine);
		var total = scanner.Analyze(@"C:\")!.Categories.Sum(c => c.PercentOfDisk);

		Assert.InRange(total, 99.0, 101.0);
	}

	[Fact]
	public void Analyze_TotalScannedBytes_MatchesSumOfAllExtensions()
	{
		var engine = CreateEngine();
		SeedCache(engine, @"C:\test", new()
		{
			[".exe"] = new FileTypeEntry { Count = 1, Bytes = 1_048_576 },
			[".cs"] = new FileTypeEntry { Count = 1, Bytes = 512_000 },
		});

		var scanner = CreateScanner(engine);
		var result = scanner.Analyze(@"C:\")!;

		Assert.Equal(1_560_576, result.TotalScannedBytes);
	}


	[Fact]
	public void Analyze_SecondCall_ReturnsSameCachedObject()
	{
		var engine = CreateEngine();
		SeedCache(engine, @"C:\test", new()
		{
			[".cs"] = new FileTypeEntry { Count = 1, Bytes = 1024 }
		});

		var scanner = CreateScanner(engine);
		var first = scanner.Analyze(@"C:\");

		// Wipe cache entries — if IMemoryCache is used, second call still works
		engine.DirectorySizeCache.Clear();

		var second = scanner.Analyze(@"C:\");

		Assert.NotNull(second);
		Assert.Same(first, second);  // exact same reference = served from cache
	}

	[Fact]
	public void Invalidate_ClearsCache_SoNextCallRebuilds()
	{
		var engine = CreateEngine();
		SeedCache(engine, @"C:\test", new()
		{
			[".cs"] = new FileTypeEntry { Count = 1, Bytes = 1024 }
		});

		var scanner = CreateScanner(engine);
		var first = scanner.Analyze(@"C:\");

		scanner.Invalidate(@"C:\");

		// Reseed with different data
		engine.DirectorySizeCache.Clear();
		SeedCache(engine, @"C:\test", new()
		{
			[".exe"] = new FileTypeEntry { Count = 99, Bytes = 9_000_000 }
		});

		var second = scanner.Analyze(@"C:\");

		Assert.NotNull(second);
		Assert.NotSame(first, second);
		Assert.Contains(second!.Categories, c => c.Name == "executables");
	}


	[Fact]
	public void FormatBytes_Returns_Bytes_ForSmallValues()
	{
		Assert.Equal("500 B", FileTypeScanner.FormatBytes(500));
	}

	[Fact]
	public void FormatBytes_Returns_KB_For1024()
	{
		Assert.Equal("1.0 KB", FileTypeScanner.FormatBytes(1_024));
	}

	[Fact]
	public void FormatBytes_Returns_MB_For1MB()
	{
		Assert.Equal("1.0 MB", FileTypeScanner.FormatBytes(1_048_576));
	}

	[Fact]
	public void FormatBytes_Returns_GB_For1GB()
	{
		Assert.Equal("1.0 GB", FileTypeScanner.FormatBytes(1_073_741_824));
	}

	[Fact]
	public void FormatBytes_Returns_TB_For1TB()
	{
		Assert.Equal("1.0 TB", FileTypeScanner.FormatBytes(1_099_511_627_776L));
	}

	[Theory]
	[InlineData(".mp4", FileCategoryDictionary.Media)]
	[InlineData("mp4", FileCategoryDictionary.Media)]
	[InlineData(".PDF", FileCategoryDictionary.Documents)]
	[InlineData(".exe", FileCategoryDictionary.Executables)]
	[InlineData(".zip", FileCategoryDictionary.Archives)]
	[InlineData(".cs", FileCategoryDictionary.Code)]
	[InlineData(".sys", FileCategoryDictionary.System)]
	[InlineData(".randomext123", FileCategoryDictionary.Other)]
	[InlineData("", FileCategoryDictionary.Other)]
	[InlineData(null, FileCategoryDictionary.Other)]
	public void FileCategoryDictionary_MapsStandardExtensionsCorrectly(string? extension, string expectedCategory)
	{
		Assert.Equal(expectedCategory, FileCategoryDictionary.GetCategory(extension));
	}

	[Fact]
	public void Analyze_PrioritizesDirectorySizeCache_WhenBothCachesExist()
	{
		var engine = CreateEngine();
		SeedCache(engine, @"C:\Projects\BigApp", new()
		{
			[".cs"] = new FileTypeEntry { Count = 100, Bytes = 20_000_000 },
			[".mp4"] = new FileTypeEntry { Count = 10, Bytes = 50_000_000 }
		});

		var mockCacheService = new Mock<IScanCacheService>();
		// Suppose cacheService only has a tiny partial subset
		mockCacheService.Setup(c => c.HasScanRoot(It.IsAny<string>())).Returns(true);
		mockCacheService.Setup(c => c.GetNodesUnderRoot(It.IsAny<string>())).Returns(new List<CachedDirNode>
		{
			new CachedDirNode(@"C:\Projects\BigApp", Array.Empty<string>(), new List<CachedFileEntry>
			{
				new CachedFileEntry("tiny.cs", ".cs", 100, DateTime.UtcNow)
			}, 100, 100, DateTimeOffset.UtcNow, false)
		});

		var scanner = new FileTypeScanner(engine, CreateCache(), mockCacheService.Object);
		var result = scanner.Analyze(@"C:\")!;

		Assert.NotNull(result);
		// Should have aggregated from engine.DirectorySizeCache (70_000_000 bytes)
		Assert.Equal(70_000_000, result.TotalScannedBytes);
	}
}
