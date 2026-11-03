using System;
using System.Linq;
using Microsoft.AspNetCore.SignalR;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using Xunit;
using GSSystemAnalyzer.Engine;
using GSSystemAnalyzer.Interfaces;
using GSSystemAnalyzer.Models.SettingDtos;
using GSSystemAnalyzer.Tests.Services;

namespace GSSystemAnalyzer.Tests.Engine;

public class CacheTtlTests : IDisposable
{
    private readonly ScannerCacheTestScope _cacheScope = new();
    private readonly List<DiskScannerEngine> _engines = new();

    private DiskScannerEngine CreateEngine(int ttlMinutes, int maxScans)
    {
        var hub = new Mock<IHubContext<Hubs.SystemHub>>().Object;

        var appSettings = AppSettingDto.GetFactoryDefaults();
        appSettings.Cache = new CacheSettingDto
        {
            ScanCacheTtlMinutes = ttlMinutes,
            MaxCacheScans = maxScans
        };

        var settings = new Mock<ISettingService>();
        settings.SetupGet(s => s.Current).Returns(appSettings);

        var engine = new DiskScannerEngine(hub, settings.Object, NullLogger<DiskScannerEngine>.Instance,
            cacheFilePath: _cacheScope.CreateCachePath());
        _engines.Add(engine);
        return engine;
    }

    public void Dispose()
    {
        foreach (var engine in _engines) engine.Dispose();
        _cacheScope.Dispose();
    }

    [Fact]
    public void Prune_keeps_entries_scanned_within_ttl_even_if_folder_is_old()
    {
        var engine = CreateEngine(ttlMinutes: 15, maxScans: 5);
        engine.DirectorySizeCache.Clear();

        engine.DirectorySizeCache["C:/fresh"] = new CacheEntry
        {
            Size = 100,
            LastUpdated = DateTime.UtcNow.AddDays(-30),    // folder old on disk...
            CachedAtUtc = DateTime.UtcNow.AddMinutes(-5),  // ...but scanned 5 min ago
            ScanRoot = "C:/"
        };
        engine.DirectorySizeCache["C:/expired"] = new CacheEntry
        {
            Size = 200,
            LastUpdated = DateTime.UtcNow.AddMinutes(-1),  // folder changed recently...
            CachedAtUtc = DateTime.UtcNow.AddMinutes(-60), // ...but scan is 60 min old
            ScanRoot = "C:/"
        };

        engine.PruneStaleCacheEntries();

        Assert.True(engine.DirectorySizeCache.ContainsKey("C:/fresh"));
        Assert.False(engine.DirectorySizeCache.ContainsKey("C:/expired"));
    }

    [Fact]
    public void EnforceMaxCacheScans_keeps_only_n_most_recent_roots()
    {
        var engine = CreateEngine(ttlMinutes: 100000, maxScans: 2);
        engine.DirectorySizeCache.Clear();

        AddRoot(engine, "C:/", DateTime.UtcNow.AddMinutes(-30)); // oldest -> evicted
        AddRoot(engine, "D:/", DateTime.UtcNow.AddMinutes(-20));
        AddRoot(engine, "E:/", DateTime.UtcNow.AddMinutes(-10)); // newest

        engine.EnforceMaxCacheScans();

        Assert.DoesNotContain(engine.DirectorySizeCache.Keys, k => k.StartsWith("C:/"));
        Assert.Contains(engine.DirectorySizeCache.Keys, k => k.StartsWith("D:/"));
        Assert.Contains(engine.DirectorySizeCache.Keys, k => k.StartsWith("E:/"));
    }

    private static void AddRoot(DiskScannerEngine engine, string root, DateTime scannedAt)
    {
        for (var i = 0; i < 2; i++)
        {
            engine.DirectorySizeCache[$"{root}folder{i}"] = new CacheEntry
            {
                Size = 1,
                LastUpdated = scannedAt,
                CachedAtUtc = scannedAt,
                ScanRoot = root
            };
        }
    }
}
