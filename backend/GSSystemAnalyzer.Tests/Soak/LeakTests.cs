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
using Microsoft.AspNetCore.SignalR;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using Xunit;

namespace GSSystemAnalyzer.Tests.Soak;

// NOTE on DTO names: the mocked return types below (NukePreviewDto / NukeResultDto)
// must match the ACTUAL return types of INukeProtocolService.PreviewNukeAsync and
// ObliterateNodeAsync in your codebase. Adjust the type/property names if yours differ
// (PlanToken, DeletedFiles, FreedBytes, SkippedFiles are the fields CleanAsync reads).
[Trait("Category", "Soak")]
public class LeakTests : IDisposable
{
    private readonly string _fakeTempDir;
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

    public LeakTests()
    {
        // Controlled temp directory with seeded junk files (never touches real temp).
        _fakeTempDir = Path.Combine(Path.GetTempPath(), "gs_leak_soak_" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_fakeTempDir);
        for (int i = 0; i < 25; i++)
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
        var proc = Process.GetCurrentProcess();

        for (int i = 0; i < 20; i++) await svc.PreviewAsync();          // warm-up
        var (baseMem, baseThreads) = Baseline(proc);

        for (int i = 0; i < 1000; i++) await svc.PreviewAsync();        // soak
        AssertBounded(proc, baseMem, baseThreads);
    }

    [Fact]
    public async Task CleanLoop_DoesNotLeakMemoryOrThreads()
    {
        var svc = CreateService();
        var proc = Process.GetCurrentProcess();

        // The clean path is the riskier one for CancellationTokenSource churn.
        for (int i = 0; i < 20; i++) await svc.CleanAsync(new List<string> { _fakeTempDir });
        var (baseMem, baseThreads) = Baseline(proc);

        for (int i = 0; i < 1000; i++) await svc.CleanAsync(new List<string> { _fakeTempDir });
        AssertBounded(proc, baseMem, baseThreads);
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

        var engine = new DiskScannerEngine(hubMock.Object, settings.Object, NullLogger<DiskScannerEngine>.Instance);
        var scanDiff = new Mock<IScanDiffService>();
        var diskService = new DiskOperationsService(engine, hubMock.Object, NullLogger<DiskOperationsService>.Instance, scanDiff.Object);

        var proc = Process.GetCurrentProcess();

        for (int i = 0; i < 20; i++)
        {
            var id = diskService.BeginScan();
            await diskService.StreamDirectoryAsync(_fakeTempDir, id, _ => Task.CompletedTask);
        }
        var (baseMem, baseThreads) = Baseline(proc);

        for (int i = 0; i < 500; i++)
        {
            var id = diskService.BeginScan();
            await diskService.StreamDirectoryAsync(_fakeTempDir, id, _ => Task.CompletedTask);
        }
        AssertBounded(proc, baseMem, baseThreads);
    }

    private static (long mem, int threads) Baseline(Process proc)
    {
        GcSettle();
        proc.Refresh();
        return (GC.GetTotalMemory(true), proc.Threads.Count);
    }

    private static void AssertBounded(Process proc, long baseMem, int baseThreads)
    {
        GcSettle();
        proc.Refresh();
        long grownMem = GC.GetTotalMemory(true) - baseMem;
        int grownThreads = proc.Threads.Count - baseThreads;

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
        try { Directory.Delete(_fakeTempDir, recursive: true); } catch { /* best effort cleanup */ }
    }
}
