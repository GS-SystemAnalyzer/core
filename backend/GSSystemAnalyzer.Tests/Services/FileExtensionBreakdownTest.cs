using GSSystemAnalyzer.Engine;
using GSSystemAnalyzer.Hubs;
using GSSystemAnalyzer.Interfaces;
using GSSystemAnalyzer.Models;
using Microsoft.AspNetCore.SignalR;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;

namespace GSSystemAnalyzer.Tests.Services
{
	public class FileExtensionBreakdownTest : IDisposable
	{
		private readonly MemoryCache _cache;
		private readonly DiskScannerEngine _engine;
		private readonly FileTypeScanner _scanner;
		private readonly string _root;

		public FileExtensionBreakdownTest()
		{
			var hub = new Mock<IHubContext<SystemHub>>().Object;
			var settings = new Mock<ISettingService>().Object;

			_cache = new MemoryCache(new MemoryCacheOptions());
			_engine = new DiskScannerEngine(hub, settings, NullLogger<DiskScannerEngine>.Instance);

			_engine.DirectorySizeCache.Clear();

			_scanner = new FileTypeScanner(_engine, _cache);

			_root = Path.Combine(Path.GetTempPath(), "gsa_ebtest_" + Guid.NewGuid().ToString("N"));
			Directory.CreateDirectory(_root);
		}

		private void SeedScan(Dictionary<string, FileTypeEntry> extensions)
		{
			_engine.DirectorySizeCache[Path.GetFullPath(_root)] = new CacheEntry
			{
				Size = extensions.Sum(e => e.Value.Bytes),
				LastUpdated = DateTime.UtcNow,
				Extensions = extensions
			};
		}

		[Fact]
		public void GetExtensionBreakdown_WhenScanCached_ReturnsAggregatedBreakdownSortedBySize()
		{
			SeedScan(new Dictionary<string, FileTypeEntry>(StringComparer.OrdinalIgnoreCase)
			{
				[".mp4"] = new FileTypeEntry
				{
					Count = 2,
					Bytes = 8000,
					LargestFileBytes = 6000,
					LargestFileName = "movie.mp4"
				},
				[".txt"] = new FileTypeEntry
				{
					Count = 3,
					Bytes = 1500,
					LargestFileBytes = 700,
					LargestFileName = "notes.txt"
				},
				["no extension"] = new FileTypeEntry
				{
					Count = 1,
					Bytes = 500,
					LargestFileBytes = 500,
					LargestFileName = "LICENSE"
				},
			});

			var result = _scanner.GetExtensionBreakdown(_root);

			Assert.NotNull(result);
			Assert.Equal(3, result!.Extensions.Count);

			// Sorted by TotalBytes desc: .mp4 (8000) > .txt (1500) > (none) (500)
			var mp4 = result.Extensions[0];
			var txt = result.Extensions[1];
			var none = result.Extensions[2];

			Assert.Equal(".mp4", mp4.Ext);
			Assert.Equal("media", mp4.Category);
			Assert.Equal(2, mp4.FileCount);
			Assert.Equal(8000, mp4.TotalBytes);
			Assert.Equal(4000, mp4.AverageFileSizeBytes);
			Assert.Equal(80.0, mp4.PercentOfDisk);
			Assert.Equal(6000, mp4.LargestFileBytes);
			Assert.Equal(Path.Combine(Path.GetFullPath(_root), "movie.mp4"), mp4.LargestFilePath);
			Assert.False(string.IsNullOrEmpty(mp4.SizeFormatted));

			Assert.Equal(".txt", txt.Ext);
			Assert.Equal("documents", txt.Category);
			Assert.Equal(15.0, txt.PercentOfDisk);
			Assert.Equal(500, txt.AverageFileSizeBytes);

			// "no extension" is surfaced as "(none)" and falls back to category "other".
			Assert.Equal("(none)", none.Ext);
			Assert.Equal("other", none.Category);
			Assert.Equal(5.0, none.PercentOfDisk);
		}

		[Fact]
		public void GetExtensionBreakdown_WhenNoScanCached_ReturnsNull()
		{
			// Nothing seeded -> scanner reports "not scanned" -> controller maps this to 409 NO_SCAN_CACHED.
			var result = _scanner.GetExtensionBreakdown(_root);

			Assert.Null(result);
		}

		[Fact]
		public void GetExtensionBreakdown_OnSecondCall_ReturnsCachedInstance()
		{
			SeedScan(new Dictionary<string, FileTypeEntry>(StringComparer.OrdinalIgnoreCase)
			{
				[".cs"] = new FileTypeEntry { Count = 1, Bytes = 1024, LargestFileBytes = 1024, LargestFilePath = @"C:\src\Program.cs" },
			});

			var first = _scanner.GetExtensionBreakdown(_root);
			var second = _scanner.GetExtensionBreakdown(_root);

			Assert.NotNull(first);
			// Result is memoized for 15 minutes under extbreakdown:{root}; same reference returned.
			Assert.Same(first, second);
		}

		[Fact]
		public void GetExtensionBreakdown_RebuildsLargestFilePath_FromWinningFolderKey()
		{
			var folderA = Path.Combine(Path.GetFullPath(_root), "A");
			var folderB = Path.Combine(Path.GetFullPath(_root), "B");
			_engine.DirectorySizeCache[folderA] = new CacheEntry
			{
				Size = 100,
				LastUpdated = DateTime.UtcNow,
				Extensions = new Dictionary<string, FileTypeEntry>(StringComparer.OrdinalIgnoreCase)
				{
					[".mp4"] = new FileTypeEntry { Count = 1, Bytes = 100, LargestFileBytes = 100, LargestFileName = "small.mp4" }
				}
			};
			_engine.DirectorySizeCache[folderB] = new CacheEntry
			{
				Size = 900,
				LastUpdated = DateTime.UtcNow,
				Extensions = new Dictionary<string, FileTypeEntry>(StringComparer.OrdinalIgnoreCase)
				{
					[".mp4"] = new FileTypeEntry { Count = 1, Bytes = 900, LargestFileBytes = 900, LargestFileName = "big.mp4" }
				}
			};

			var result = _scanner.GetExtensionBreakdown(_root);

			Assert.NotNull(result);
			var mp4 = result!.Extensions.Single(e => e.Ext == ".mp4");
			Assert.Equal(900, mp4.LargestFileBytes);
			// Rebuilt from the WINNING folder key (B), not whichever folder was merged last.
			Assert.Equal(Path.Combine(folderB, "big.mp4"), mp4.LargestFilePath);
		}

		[Fact]
		public void GetExtensionBreakdown_ReportsFullScannedTotal_AcrossFolders()
		{
			var folderA = Path.Combine(Path.GetFullPath(_root), "A");
			var folderB = Path.Combine(Path.GetFullPath(_root), "B");
			_engine.DirectorySizeCache[folderA] = new CacheEntry
			{
				Size = 300,
				LastUpdated = DateTime.UtcNow,
				Extensions = new Dictionary<string, FileTypeEntry>(StringComparer.OrdinalIgnoreCase)
				{
					[".txt"] = new FileTypeEntry { Count = 3, Bytes = 300, LargestFileBytes = 200, LargestFileName = "a.txt" }
				}
			};
			_engine.DirectorySizeCache[folderB] = new CacheEntry
			{
				Size = 700,
				LastUpdated = DateTime.UtcNow,
				Extensions = new Dictionary<string, FileTypeEntry>(StringComparer.OrdinalIgnoreCase)
				{
					[".txt"] = new FileTypeEntry { Count = 2, Bytes = 700, LargestFileBytes = 500, LargestFileName = "b.txt" }
				}
			};

			var result = _scanner.GetExtensionBreakdown(_root);

			Assert.NotNull(result);
			var txt = result!.Extensions.Single(e => e.Ext == ".txt");
			Assert.Equal(1000, txt.TotalBytes);
			Assert.Equal(5, txt.FileCount);
		}

		[Fact]
		public void InternLoadedCache_FoldsDuplicateStrings_AndNullsEmptyExtensions()
		{
			var root1 = new string("C:\\".ToCharArray());
			var root2 = new string("C:\\".ToCharArray());
			var ext1 = new string(".txt".ToCharArray());
			var ext2 = new string(".txt".ToCharArray());
			var name1 = new string("a.txt".ToCharArray());
			var name2 = new string("a.txt".ToCharArray());

			var loaded = new Dictionary<string, CacheEntry>
			{
				[@"C:\A"] = new CacheEntry
				{
					ScanRoot = root1,
					Extensions = new Dictionary<string, FileTypeEntry> { [ext1] = new FileTypeEntry { LargestFileName = name1 } }
				},
				[@"C:\B"] = new CacheEntry
				{
					ScanRoot = root2,
					Extensions = new Dictionary<string, FileTypeEntry> { [ext2] = new FileTypeEntry { LargestFileName = name2 } }
				},
				[@"C:\Empty"] = new CacheEntry
				{
					ScanRoot = root1,
					Extensions = new Dictionary<string, FileTypeEntry>()
				}
			};

			DiskScannerEngine.InternLoadedCache(loaded);

			Assert.Same(loaded[@"C:\A"].ScanRoot, loaded[@"C:\B"].ScanRoot);
			var keyA = loaded[@"C:\A"].Extensions!.Keys.Single();
			var keyB = loaded[@"C:\B"].Extensions!.Keys.Single();
			Assert.Same(keyA, keyB);
			Assert.Same(loaded[@"C:\A"].Extensions![keyA].LargestFileName, loaded[@"C:\B"].Extensions![keyB].LargestFileName);
			Assert.Null(loaded[@"C:\Empty"].Extensions);
		}

		[Fact]
		public void OldFormatCache_WithLargestFilePath_DeserializesWithoutThrowing()
		{
			// Old file: LargestFilePath present, LargestFileName absent. Must load, not throw —
			// otherwise the engine's corrupt-catch would delete the cache file.
			var oldJson = "{\"C:\\\\A\":{\"Size\":10,\"LastUpdated\":\"2026-01-01T00:00:00Z\",\"CachedAtUtc\":\"2026-01-01T00:00:00Z\",\"ScanRoot\":\"C:\\\\\",\"Extensions\":{\".txt\":{\"Count\":1,\"Bytes\":10,\"LargestFileBytes\":10,\"LargestFilePath\":\"C:\\\\A\\\\a.txt\"}}}}";

			var reloaded = System.Text.Json.JsonSerializer.Deserialize<Dictionary<string, CacheEntry>>(oldJson);

			Assert.NotNull(reloaded);
			var fte = reloaded![@"C:\A"].Extensions![".txt"];
			Assert.Equal(1, fte.Count);
			Assert.Equal(string.Empty, fte.LargestFileName);
		}

		public void Dispose()
		{
			_cache.Dispose();
			try { if (Directory.Exists(_root)) Directory.Delete(_root, recursive: true); }
			catch { /* best-effort cleanup */ }
		}
	}
}
