using GSSystemAnalyzer.Engine;
using GSSystemAnalyzer.Hubs;
using GSSystemAnalyzer.Interfaces;
using GSSystemAnalyzer.Models;
using GSSystemAnalyzer.Models.SettingDtos;
using GSSystemAnalyzer.Tests.Services;
using Microsoft.AspNetCore.SignalR;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using Xunit;

namespace GSSystemAnalyzer.Tests.Engine
{
	public class AgeHeatmapEngineTests : IDisposable
	{
		private readonly ScannerCacheTestScope _cacheScope = new();
		private readonly List<DiskScannerEngine> _scanners = new();
		private readonly List<MemoryCache> _caches = new();

		private static DateTime DaysAgo(int days) =>
			DateTime.UtcNow.AddDays(-days);

		/// <summary>
		/// Creates a real DiskScannerEngine with mocked hub + settings,
		/// then seeds its public DirectorySizeCache with the supplied entries.
		/// </summary>
		private DiskScannerEngine BuildScanner(
			params (string Path, long SizeBytes, DateTime LastModified)[] entries)
		{
			var hubMock = new Mock<IHubContext<SystemHub>>();
			var settingsMock = new Mock<ISettingService>();
			settingsMock.Setup(s => s.Current).Returns(new AppSettingDto());

			var scanner = new DiskScannerEngine(hubMock.Object, settingsMock.Object, NullLogger<DiskScannerEngine>.Instance,
				cacheFilePath: _cacheScope.CreateCachePath());
			_scanners.Add(scanner);

			foreach (var (path, sizeBytes, lastModified) in entries)
			{
				scanner.DirectorySizeCache[path] = new CacheEntry
				{
					Size = sizeBytes,
					LastUpdated = lastModified,
					Extensions = sizeBytes > 0
						? new Dictionary<string, FileTypeEntry>
						{
							["*"] = new FileTypeEntry { Count = 1, Bytes = sizeBytes }
						}
						: null
				};
			}

			return scanner;
		}

		private AgeHeatmapEngine BuildEngine(DiskScannerEngine scanner)
		{
			var cache = new MemoryCache(new MemoryCacheOptions());
			_caches.Add(cache);
			return new AgeHeatmapEngine(scanner, cache);
		}

		public void Dispose()
		{
			foreach (var cache in _caches) cache.Dispose();
			foreach (var scanner in _scanners) scanner.Dispose();
			_cacheScope.Dispose();
		}


		[Fact]
		public void Classify_ReturnsFresh_WhenModifiedWithin7Days()
		{
			var scanner = BuildScanner(
				("C:/root", 0, DaysAgo(1)),
				("C:/root/sub", 1024, DaysAgo(3))
			);
			var engine = BuildEngine(scanner);

			var result = engine.Analyze("C:/root");

			Assert.NotNull(result);
			var node = result!.Nodes.First(n =>
				n.Path.Replace("\\", "/").TrimEnd('/').EndsWith("sub"));
			Assert.Equal("fresh", node.AgeBucket);
		}

		[Fact]
		public void Classify_ReturnsRecent_WhenModified7DaysTo1Month()
		{
			var scanner = BuildScanner(
				("C:/root", 0, DaysAgo(1)),
				("C:/root/sub", 1024, DaysAgo(15))
			);
			var result = BuildEngine(scanner).Analyze("C:/root");

			var node = result!.Nodes.First(n =>
				n.Path.Replace("\\", "/").TrimEnd('/').EndsWith("sub"));
			Assert.Equal("recent", node.AgeBucket);
		}

		[Fact]
		public void Classify_ReturnsAging_WhenModified1MonthTo1Year()
		{
			var scanner = BuildScanner(
				("C:/root", 0, DaysAgo(1)),
				("C:/root/sub", 1024, DaysAgo(200))
			);
			var result = BuildEngine(scanner).Analyze("C:/root");

			var node = result!.Nodes.First(n =>
				n.Path.Replace("\\", "/").TrimEnd('/').EndsWith("sub"));
			Assert.Equal("aging", node.AgeBucket);
		}

		[Fact]
		public void Classify_ReturnsStale_WhenModifiedOver1Year()
		{
			var scanner = BuildScanner(
				("C:/root", 0, DaysAgo(1)),
				("C:/root/sub", 1024, DaysAgo(400))
			);
			var result = BuildEngine(scanner).Analyze("C:/root");

			var node = result!.Nodes.First(n =>
				n.Path.Replace("\\", "/").TrimEnd('/').EndsWith("sub"));
			Assert.Equal("stale", node.AgeBucket);
		}


		[Fact]
		public void Analyze_ReturnsNull_WhenCacheIsEmpty()
		{
			// No entries in DirectorySizeCache → nothing was scanned
			var scanner = BuildScanner();
			var result = BuildEngine(scanner).Analyze("C:/root");

			Assert.Null(result);
		}

		[Fact]
		public void Analyze_ReturnsNull_WhenCacheHasNoMatchingEntries()
		{
			// Cache has entries for a different root
			var scanner = BuildScanner(
				("D:/other", 1024, DaysAgo(5))
			);
			var result = BuildEngine(scanner).Analyze("C:/root");

			Assert.Null(result);
		}

		[Fact]
		public void Analyze_NormalizesBackslashPath_AndFindsCache()
		{
			var scanner = BuildScanner(
				("C:/root", 500, DaysAgo(10))
			);
			var engine = BuildEngine(scanner);

			// Call with Windows-style backslash
			var result = engine.Analyze(@"C:\root");

			Assert.NotNull(result);
		}

		[Fact]
		public void Analyze_NormalizesTrailingSlash_AndFindsCache()
		{
			var scanner = BuildScanner(
				("C:/root", 500, DaysAgo(10))
			);
			var engine = BuildEngine(scanner);

			var result = engine.Analyze("C:/root/");   // trailing slash

			Assert.NotNull(result);
		}

		[Fact]
		public void Summary_CorrectlyTotalsCountAndBytes_PerBucket()
		{
			var scanner = BuildScanner(
				("C:/root", 0, DaysAgo(1)),
				("C:/root/a", 1000, DaysAgo(2)),   // fresh
				("C:/root/b", 2000, DaysAgo(4)),   // fresh
				("C:/root/c", 500, DaysAgo(400))   // stale
			);
			var result = BuildEngine(scanner).Analyze("C:/root");

			Assert.Equal(2, result!.Summary["fresh"].Count);
			Assert.Equal(3000, result.Summary["fresh"].TotalBytes);
			Assert.Equal(1, result.Summary["stale"].Count);
			Assert.Equal(500, result.Summary["stale"].TotalBytes);
		}

		[Fact]
		public void Analyze_UsesCachedResult_OnSecondCall()
		{
			var scanner = BuildScanner(
				("C:/root", 500, DaysAgo(5))
			);
			using var cache = new MemoryCache(new MemoryCacheOptions());
			var engine = new AgeHeatmapEngine(scanner, cache);

			var first = engine.Analyze("C:/root");
			var second = engine.Analyze("C:/root");

			// Both should return the same cached instance
			Assert.NotNull(first);
			Assert.Same(first, second);
		}

		[Fact]
		public void Analyze_ClassifiesAllBuckets_InSingleResult()
		{
			var scanner = BuildScanner(
				("C:/root", 0, DaysAgo(1)),
				("C:/root/fresh_dir", 100, DaysAgo(3)),    // fresh
				("C:/root/recent_dir", 200, DaysAgo(15)),  // recent
				("C:/root/aging_dir", 300, DaysAgo(200)),  // aging
				("C:/root/stale_dir", 400, DaysAgo(400))   // stale
			);
			var result = BuildEngine(scanner).Analyze("C:/root");

			Assert.NotNull(result);

			var buckets = result!.Nodes.Select(n => n.AgeBucket).Distinct().ToHashSet();
			Assert.Contains("fresh", buckets);
			Assert.Contains("recent", buckets);
			Assert.Contains("aging", buckets);
			Assert.Contains("stale", buckets);
		}
	}
}
