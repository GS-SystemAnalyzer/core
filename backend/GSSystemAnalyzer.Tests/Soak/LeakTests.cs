using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
using GSSystemAnalyzer.Engine;
using GSSystemAnalyzer.Hubs;
using GSSystemAnalyzer.Interfaces;
using GSSystemAnalyzer.Models;
using GSSystemAnalyzer.Models.SettingDtos;
using GSSystemAnalyzer.Services;
using GSSystemAnalyzer.Tests.Services;
using Microsoft.AspNetCore.SignalR;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using Xunit;
using Xunit.Abstractions;

namespace GSSystemAnalyzer.Tests.Soak;

[Trait("Category", "Soak")]
[Collection("ForcedGarbageCollection")]
public class LeakTests : IDisposable
{
    private const int Iterations = 1000;
    private const int FileCount = 25;
    private const long WorkloadBytes = FileCount * 1024;
    private readonly string _fakeTempDir;
    private readonly ITestOutputHelper _output;
    private readonly ScannerCacheTestScope _cacheScope = new();
    private class FakeNukeService : INukeProtocolService
    {
        public Task<NukePreviewResponse> PreviewNukeAsync(List<string> paths, CancellationToken cancellationToken = default) =>
            Task.FromResult(new NukePreviewResponse { PlanToken = Guid.NewGuid().ToString() });

        public Task<NukeResultDto> ObliterateNodeAsync(List<string> paths, string planToken, bool useRecycleBin = false, CancellationToken cancellationToken = default) =>
            Task.FromResult(new NukeResultDto { DeletedFiles = 0, FreedBytes = 0, SkippedFiles = 0 });

        public void TriggerNukeAbort() {}
        public bool IsNuking => false;
        public NukeOperation? PeekUndo() => null;
        public NukeResultDto? UndoNuke(string? operationId = null) => null;
        public List<NukeOperation> GetUndoHistory() => new();
        public void ClearUndoStack() {}
    }

    public LeakTests(ITestOutputHelper output)
    {
        _output = output;
        // Controlled temp directory with seeded junk files (never touches real temp).
        _fakeTempDir = Path.Combine(Path.GetTempPath(), "gs_leak_soak_" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_fakeTempDir);
        SeedFiles();
        _output.WriteLine($"SOAK owned workload: {_fakeTempDir}");
    }

    private void SeedFiles()
    {
        for (int i = 0; i < FileCount; i++)
            File.WriteAllText(Path.Combine(_fakeTempDir, $"junk_{i}.tmp"), new string('x', 1024));
    }

    // Passing a real seeded dir exercises the override branch against controlled input.
    private TempFolderCleanerService CreateService() =>
        new TempFolderCleanerService(
            new FakeNukeService(),
            NullLogger<TempFolderCleanerService>.Instance,
            new[] { _fakeTempDir });

    [Fact]
    public async Task PreviewCleanLoop_DoesNotLeakMemoryOrThreads()
    {
        var svc = CreateService();
        try
        {
            await RunSoakAsync("preview", async () =>
            {
                var preview = await svc.PreviewAsync();
                var location = Assert.Single(preview.Locations);
                Assert.Equal(_fakeTempDir, location.Path);
                Assert.Equal(FileCount, location.FileCount);
                Assert.Equal(WorkloadBytes, location.SizeBytes);
                Assert.Equal(WorkloadBytes, preview.TotalBytes);
            });
        }
        finally
        {
            GC.KeepAlive(svc);
        }
    }

    [Fact]
    public async Task CleanLoop_DoesNotLeakMemoryOrThreads()
    {
        var svc = CreateService();
        try
        {
            await RunSoakAsync("clean", async () =>
            {
                SeedFiles();
                var result = await svc.CleanAsync(new List<string> { _fakeTempDir });
                Assert.Equal(FileCount, result.DeletedFiles);
                Assert.Equal(WorkloadBytes, result.FreedBytes);
                Assert.Equal(0, result.SkippedFiles);
                Assert.Empty(Directory.EnumerateFiles(_fakeTempDir));
            });
        }
        finally
        {
            GC.KeepAlive(svc);
        }
    }

    [Fact]
    public async Task StreamingScanLoop_DoesNotLeakMemoryOrThreads()
    {
        var hubMock = new Mock<IHubContext<SystemHub>>();
        var clientsMock = new Mock<IHubClients>();
        var proxyMock = new Mock<IClientProxy>();
        hubMock.Setup(h => h.Clients).Returns(clientsMock.Object);
        clientsMock.Setup(c => c.All).Returns(proxyMock.Object);
        proxyMock
            .Setup(c => c.SendCoreAsync(It.IsAny<string>(), It.IsAny<object?[]>(), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var settings = new Mock<ISettingService>();
        var defaults = AppSettingDto.GetFactoryDefaults();
        defaults.Scan.SkipHiddenFiles = false;
        defaults.Scan.SkipSystemFiles = false;
        settings.SetupGet(s => s.Current).Returns(defaults);

        var cachePath = _cacheScope.CreateCachePath();
        _output.WriteLine($"SOAK owned cache: {Path.GetDirectoryName(cachePath)}");
        using var engine = new DiskScannerEngine(hubMock.Object, settings.Object, NullLogger<DiskScannerEngine>.Instance,
            cacheFilePath: cachePath);
        var scanDiff = new Mock<IScanDiffService>();
        var diskService = new DiskOperationsService(engine, hubMock.Object, NullLogger<DiskOperationsService>.Instance, scanDiff.Object);

        var mocks = new Mock[] { hubMock, clientsMock, proxyMock, settings, scanDiff };
        try
        {
            await RunSoakAsync("streaming", async () =>
            {
                var files = 0;
                long bytes = 0;
                try
                {
                    var id = diskService.BeginScan();
                    var summary = await diskService.StreamDirectoryAsync(_fakeTempDir, id, chunk =>
                    {
                        foreach (var node in chunk)
                        {
                            Assert.Equal("File", node.Type);
                            Interlocked.Increment(ref files);
                            Interlocked.Add(ref bytes, node.SizeBytes);
                        }
                        return Task.CompletedTask;
                    });
                    Assert.Equal(FileCount, files);
                    Assert.Equal(WorkloadBytes, bytes);
                    Assert.Equal(_fakeTempDir, summary.Path);
                    Assert.Equal(WorkloadBytes, summary.OwnBytes);
                    Assert.Equal(WorkloadBytes, summary.RecursiveBytes);
                    Assert.True(summary.RecursiveBytesFinal);
                }
                finally
                {
                    // Release only test-double journals after the operation settles.
                    foreach (var mock in mocks) mock.Invocations.Clear();
                }
            });
        }
        finally
        {
            GC.KeepAlive(diskService);
            GC.KeepAlive(engine);
        }
    }

    private async Task RunSoakAsync(string workload, Func<Task> operation)
    {
        using var proc = Process.GetCurrentProcess();
        for (int i = 0; i < 20; i++) await operation();
        var baseline = Sample(proc);
        _output.WriteLine($"SOAK {workload} baseline at {baseline.Utc:O}: {baseline}");
        var completed = 0;
        ResourceSample final = default;
        try
        {
            for (; completed < Iterations; completed++) await operation();
        }
        finally
        {
            final = Sample(proc);
            _output.WriteLine($"SOAK {workload} final at {final.Utc:O}: {final}");
            _output.WriteLine($"SOAK {workload}: iterations={completed}; filesPerIteration={FileCount}; bytesPerIteration={WorkloadBytes}; " +
                $"heapDelta={final.Heap - baseline.Heap}; threadDelta={final.Threads - baseline.Threads}; " +
                $"elapsedMs={Stopwatch.GetElapsedTime(baseline.Timestamp, final.Timestamp).TotalMilliseconds:F1}");
        }
        AssertBounded(baseline, final);
        GC.KeepAlive(operation);
    }

    private readonly record struct ResourceSample(long Heap, int Threads, int PoolThreads,
        long PendingWork, long CompletedWork, DateTimeOffset Utc, long Timestamp);

    private static ResourceSample Sample(Process proc)
    {
        GcSettle();
        proc.Refresh();
        return new ResourceSample(GC.GetTotalMemory(true), proc.Threads.Count, ThreadPool.ThreadCount,
            ThreadPool.PendingWorkItemCount, ThreadPool.CompletedWorkItemCount, DateTimeOffset.UtcNow, Stopwatch.GetTimestamp());
    }

    private static void AssertBounded(ResourceSample baseline, ResourceSample final)
    {
        long grownMem = final.Heap - baseline.Heap;
        int grownThreads = final.Threads - baseline.Threads;
        Assert.True(grownMem < 5_000_000,
            $"Heap grew by {grownMem:n0} bytes across the soak loop \u2014 possible memory leak.");
        Assert.True(grownThreads < 10,
            $"Thread count grew by {grownThreads} across the soak loop \u2014 possible thread/CTS leak.");
    }

    private static void GcSettle()
    {
        GC.Collect();
        GC.WaitForPendingFinalizers();
        GC.Collect();
    }

    public void Dispose()
    {
        try
        {
            Directory.Delete(_fakeTempDir, recursive: true);
            Assert.False(Directory.Exists(_fakeTempDir));
        }
        finally
        {
            _cacheScope.Dispose();
        }
    }
}
