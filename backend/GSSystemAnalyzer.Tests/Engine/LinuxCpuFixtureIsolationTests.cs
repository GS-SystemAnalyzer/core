using System.Reflection;
#if !WINDOWS
using GSSystemAnalyzer.Services;
using Microsoft.Extensions.Logging.Abstractions;
#endif

namespace GSSystemAnalyzer.Tests.Engine;

public class LinuxCpuFixtureIsolationTests
{
    [Fact]
    public void LayoutBaseline()
    {
        var layout = Inspect(new LinuxCpuProviderTest());

        Assert.Equal(Path.Combine(layout.Root, "proc"), layout.ProcRoot);
        Assert.Equal(Path.Combine(layout.Root, "sys"), layout.SysRoot);
        Assert.Equal(Path.Combine(layout.ProcRoot, "stat"), layout.StatPath);
    }

    [Fact]
    public void OwnsUniqueTempRoots()
    {
        var first = Inspect(new LinuxCpuProviderTest());
        var second = Inspect(new LinuxCpuProviderTest());

        Assert.True(IsStrictlyUnder(Path.GetTempPath(), first.Root),
            $"Fixture root '{first.Root}' must be strictly beneath the temporary directory.");
        Assert.True(IsStrictlyUnder(Path.GetTempPath(), second.Root),
            $"Fixture root '{second.Root}' must be strictly beneath the temporary directory.");
        Assert.False(string.Equals(first.Root, second.Root, PathComparison));
        Assert.False(Directory.Exists(first.Root));
        Assert.False(Directory.Exists(second.Root));
    }

    [Fact]
    public void ContainmentAcceptsAChildOfAFilesystemRoot()
    {
        var root = Path.GetPathRoot(Path.GetFullPath(Path.GetTempPath()))!;
        var child = Path.Combine(root, "gs_linux_cpu_string_only");

        Assert.True(CheckContainment(root, child));
        Assert.False(CheckContainment(root, root));
    }

    [Fact]
    public void ContainmentRejectsTheParentAndPrefixSiblings()
    {
        var parent = Path.Combine(Path.GetTempPath(), "gs_linux_cpu_parent");

        Assert.True(CheckContainment(parent, Path.Combine(parent, "child")));
        Assert.False(CheckContainment(parent, parent));
        Assert.False(CheckContainment(parent, parent + "_sibling"));
        Assert.False(CheckContainment(parent, Path.GetDirectoryName(parent)!));
    }

    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public void DisposeRemovesOnlyTheOwnedTree(bool includeProc)
    {
        var fixture = new LinuxCpuProviderTest();
        var layout = InspectOwned(fixture);
        try
        {
            if (includeProc)
            {
                Directory.CreateDirectory(layout.ProcRoot);
                File.WriteAllText(layout.StatPath, "cpu0 1000 0 200 5000 0 0 0 0\n");
            }
            var nested = Path.Combine(layout.SysRoot, "nested");
            Directory.CreateDirectory(nested);
            File.WriteAllText(Path.Combine(nested, "data"), "owned");

            fixture.Dispose();

            Assert.False(Directory.Exists(layout.Root));
            fixture.Dispose();
        }
        finally
        {
            fixture.Dispose();
        }
    }

    [Fact]
    public void DisposeBeforeSetupIsRepeatable()
    {
        var fixture = new LinuxCpuProviderTest();
        var layout = InspectOwned(fixture);

        fixture.Dispose();
        fixture.Dispose();

        Assert.False(Directory.Exists(layout.Root));
    }

    [Fact]
    public void DisposingOneFixturePreservesSiblingBytes()
    {
        var first = new LinuxCpuProviderTest();
        var second = new LinuxCpuProviderTest();
        var a = InspectOwned(first);
        var b = InspectOwned(second);
        try
        {
            Directory.CreateDirectory(a.ProcRoot);
            File.WriteAllText(a.StatPath, "first");
            Directory.CreateDirectory(b.SysRoot);
            var sentinel = Path.Combine(b.SysRoot, "sentinel");
            byte[] bytes = [0, 1, 127, 128, 255];
            File.WriteAllBytes(sentinel, bytes);

            first.Dispose();

            Assert.False(Directory.Exists(a.Root));
            Assert.True(Directory.Exists(b.Root));
            Assert.Equal(bytes, File.ReadAllBytes(sentinel));
        }
        finally
        {
            first.Dispose();
            second.Dispose();
        }
    }

    [Fact]
    public void UnicodeConstructorRemainsPathOnlyAndCleanupStaysOwned()
    {
        var outer = Path.Combine(Path.GetTempPath(), "gs_cpu_unicode_" + Guid.NewGuid().ToString("N"));
        var basePath = Path.Combine(outer, "á 測試 space");
        LinuxCpuProviderTest? fixture = null;
        FixtureLayout? layout = null;
        try
        {
            Directory.CreateDirectory(basePath);
            fixture = new LinuxCpuProviderTest(basePath);
            layout = InspectOwned(fixture);
            Assert.True(IsStrictlyUnder(basePath, layout.Root));
            Assert.False(Directory.Exists(layout.Root));
            Directory.CreateDirectory(layout.SysRoot);
            var file = Path.Combine(layout.SysRoot, "内容.txt");
            File.WriteAllText(file, "é 測試");
            Assert.Equal("é 測試", File.ReadAllText(file));

            fixture.Dispose();

            Assert.False(Directory.Exists(layout.Root));
            Assert.True(Directory.Exists(basePath));
        }
        finally
        {
            if (layout != null) fixture?.Dispose();
            if (Directory.Exists(outer)) Directory.Delete(outer, true);
        }
    }

#if !WINDOWS
    [Fact]
    public async Task ProvidersUseIndependentRootsWhileOneFixtureIsDisposed()
    {
        var first = new LinuxCpuProviderTest();
        var second = new LinuxCpuProviderTest();
        var a = InspectOwned(first);
        var b = InspectOwned(second);
        using var barrier = new Barrier(2);
        var firstDisposed = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        try
        {
            Populate(a, "cpu0 1000 0 200 5000 0 0 0 0\n", 1_110_000, 11, 31, 1);
            Populate(b, "cpu0 2000 0 100 3000 0 0 0 0\n", 2_220_000, 22, 42, 2);
            var sentinel = Path.Combine(b.SysRoot, "sentinel");
            File.WriteAllText(sentinel, "second stays live");

            var firstTask = Task.Run(async () =>
            {
                try
                {
                    var provider = CreateProvider(a);
                    Assert.True(barrier.SignalAndWait(TimeSpan.FromSeconds(15)));
                    File.WriteAllText(a.StatPath, "cpu0 1100 0 200 5100 0 0 0 0\n");
                    var sample = await provider.GetNextSampleAsync();
                    first.Dispose();
                    firstDisposed.TrySetResult(true);
                    return sample;
                }
                catch (Exception ex)
                {
                    firstDisposed.TrySetException(ex);
                    throw;
                }
            });
            var secondTask = Task.Run(async () =>
            {
                var provider = CreateProvider(b);
                Assert.True(barrier.SignalAndWait(TimeSpan.FromSeconds(15)));
                await firstDisposed.Task.WaitAsync(TimeSpan.FromSeconds(15));
                Assert.Equal("second stays live", File.ReadAllText(sentinel));
                File.WriteAllText(b.StatPath, "cpu0 2400 0 200 3200 0 0 0 0\n");
                return await provider.GetNextSampleAsync();
            });

            var samples = await Task.WhenAll(firstTask, secondTask);

            Assert.Equal(50.0, samples[0].AverageLoad);
            Assert.Equal(1.11, samples[0].CurrentFrequencyGhz);
            Assert.Equal(11, samples[0].TotalHandles);
            Assert.Equal(31, samples[0].TotalThreads);
            Assert.Equal(1, samples[0].TotalProcesses);
            Assert.Equal(71.4, samples[1].AverageLoad);
            Assert.Equal(2.22, samples[1].CurrentFrequencyGhz);
            Assert.Equal(22, samples[1].TotalHandles);
            Assert.Equal(42, samples[1].TotalThreads);
            Assert.Equal(2, samples[1].TotalProcesses);
        }
        finally
        {
            first.Dispose();
            second.Dispose();
        }
    }

    [Fact]
    public async Task ProviderReadsAndCleansUnicodeFixturePaths()
    {
        var outer = Path.Combine(Path.GetTempPath(), "gs_cpu_unicode_" + Guid.NewGuid().ToString("N"));
        var basePath = Path.Combine(outer, "á 測試 space");
        LinuxCpuProviderTest? fixture = null;
        FixtureLayout? layout = null;
        try
        {
            Directory.CreateDirectory(basePath);
            fixture = new LinuxCpuProviderTest(basePath);
            layout = InspectOwned(fixture);
            Assert.False(Directory.Exists(layout.Root));
            Populate(layout, "cpu0 2000 0 100 3000 0 0 0 0\n", 2_220_000, 42, 7, 2);
            var provider = CreateProvider(layout);
            File.WriteAllText(layout.StatPath, "cpu0 2400 0 200 3200 0 0 0 0\n");

            var sample = await provider.GetNextSampleAsync();

            Assert.Equal(71.4, sample.AverageLoad);
            Assert.Equal(2.22, sample.CurrentFrequencyGhz);
            Assert.Equal(42, sample.TotalHandles);
            Assert.Equal(7, sample.TotalThreads);
            Assert.Equal(2, sample.TotalProcesses);
            Assert.Equal("64K", sample.L1Cache);
            Assert.Equal("512K", sample.L2Cache);
            Assert.Equal("16M", sample.L3Cache);
            fixture.Dispose();
            Assert.False(Directory.Exists(layout.Root));
        }
        finally
        {
            if (layout != null) fixture?.Dispose();
            if (Directory.Exists(outer)) Directory.Delete(outer, true);
        }
    }

    private static LinuxCpuProvider CreateProvider(FixtureLayout layout) =>
        new(NullLogger<LinuxCpuProvider>.Instance, layout.ProcRoot, layout.SysRoot);

    private static void Populate(FixtureLayout layout, string stat, int frequencyKhz, int handles, int threads, int processes)
    {
        Directory.CreateDirectory(layout.ProcRoot);
        File.WriteAllText(layout.StatPath, stat);
        var fs = Path.Combine(layout.ProcRoot, "sys", "fs");
        Directory.CreateDirectory(fs);
        File.WriteAllText(Path.Combine(fs, "file-nr"), $"{handles}\t0\t9223372036854775807\n");
        File.WriteAllText(Path.Combine(layout.ProcRoot, "loadavg"), $"0.10 0.15 0.12 2/{threads} 12345\n");
        for (var i = 0; i < processes; i++)
            Directory.CreateDirectory(Path.Combine(layout.ProcRoot, (101 + i).ToString()));
        Directory.CreateDirectory(Path.Combine(layout.ProcRoot, "not_a_process"));
        var cpu = Path.Combine(layout.SysRoot, "devices", "system", "cpu", "cpu0");
        var frequency = Path.Combine(cpu, "cpufreq");
        Directory.CreateDirectory(frequency);
        File.WriteAllText(Path.Combine(frequency, "scaling_cur_freq"), frequencyKhz.ToString());
        foreach (var (index, size) in new[] { (0, "64K"), (2, "512K"), (3, "16M") })
        {
            var cache = Path.Combine(cpu, "cache", "index" + index);
            Directory.CreateDirectory(cache);
            File.WriteAllText(Path.Combine(cache, "size"), size);
        }
    }
#endif

    private static FixtureLayout InspectOwned(LinuxCpuProviderTest fixture)
    {
        var layout = Inspect(fixture);
        Assert.True(IsStrictlyUnder(Path.GetTempPath(), layout.Root));
        Assert.True(IsStrictlyUnder(layout.Root, layout.ProcRoot));
        Assert.True(IsStrictlyUnder(layout.Root, layout.SysRoot));
        return layout;
    }

    private static StringComparison PathComparison =>
        OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal;

    private static bool CheckContainment(string parent, string path)
    {
        var method = typeof(LinuxCpuProviderTest).GetMethod("IsUnder",
            BindingFlags.Static | BindingFlags.NonPublic);
        Assert.NotNull(method);
        return Assert.IsType<bool>(method.Invoke(null, [parent, path]));
    }

    private static bool IsStrictlyUnder(string parent, string path)
    {
        var relative = Path.GetRelativePath(Path.GetFullPath(parent), Path.GetFullPath(path));
        return !Path.IsPathRooted(relative) && relative != "." && relative != ".." &&
            !relative.StartsWith(".." + Path.DirectorySeparatorChar, PathComparison);
    }

    private static FixtureLayout Inspect(LinuxCpuProviderTest fixture)
    {
        // Construction only computes paths; these legacy objects must never be disposed here.
        string ReadPath(string name)
        {
            var field = typeof(LinuxCpuProviderTest).GetField(name,
                BindingFlags.Instance | BindingFlags.NonPublic);
            Assert.NotNull(field);
            return Path.GetFullPath(Assert.IsType<string>(field.GetValue(fixture)));
        }

        var proc = ReadPath("_mockProcDir");
        var sys = ReadPath("_mockSysDir");
        var stat = ReadPath("_mockStatPath");
        return new FixtureLayout(Path.GetDirectoryName(proc)!, proc, stat, sys);
    }

    private sealed record FixtureLayout(string Root, string ProcRoot, string StatPath, string SysRoot);
}
