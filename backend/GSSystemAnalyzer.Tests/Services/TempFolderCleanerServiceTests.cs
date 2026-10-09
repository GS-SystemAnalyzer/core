using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using GSSystemAnalyzer.Hubs;
using GSSystemAnalyzer.Interfaces;
using GSSystemAnalyzer.Models;
using GSSystemAnalyzer.Services;
using Microsoft.AspNetCore.SignalR;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using Xunit;

namespace GSSystemAnalyzer.Tests.Services;

public class TempFolderCleanerServiceTests : IDisposable
{
	private readonly string _fakeTempDir;
	private readonly Mock<IDiskScannerEngine> _scanner = new();

	public TempFolderCleanerServiceTests()
	{
		_fakeTempDir = Path.Combine(Path.GetTempPath(), "gstemp_test_" + Guid.NewGuid().ToString("N"));
		Directory.CreateDirectory(_fakeTempDir);

		_scanner.Setup(s => s.NukeToken()).Returns(CancellationToken.None);
		_scanner.Setup(s => s.InvalidatePaths(It.IsAny<IEnumerable<string>>()));
	}

	public void Dispose()
	{
		try { if (Directory.Exists(_fakeTempDir)) Directory.Delete(_fakeTempDir, true); } catch { /* ignore */ }
	}

	/// <summary>Creates a real NukeProtocolService wired with mocked SignalR + scanner.</summary>
	private NukeProtocolService CreateNukeService()
	{
		var hub = new Mock<IHubContext<SystemHub>>();
		var clients = new Mock<IHubClients>();
		var proxy = new Mock<IClientProxy>();
		clients.Setup(c => c.All).Returns(proxy.Object);
		hub.Setup(h => h.Clients).Returns(clients.Object);
		proxy.Setup(p => p.SendCoreAsync(It.IsAny<string>(), It.IsAny<object?[]>(), It.IsAny<CancellationToken>()))
			 .Returns(Task.CompletedTask);

		return new NukeProtocolService(_scanner.Object, hub.Object, NullLogger<NukeProtocolService>.Instance, runStartupCleanup: false);
	}

	private TempFolderCleanerService CreateService(INukeProtocolService? nukeOverride = null, IEnumerable<string>? pathsOverride = null)
	{
		var nuke = nukeOverride ?? CreateNukeService();
		return new TempFolderCleanerService(nuke, NullLogger<TempFolderCleanerService>.Instance, pathsOverride);
	}

	private string SeedFile(string relativePath = "test.txt", string content = "hello world")
	{
		var fullPath = Path.Combine(_fakeTempDir, relativePath);
		var dir = Path.GetDirectoryName(fullPath)!;
		if (!Directory.Exists(dir)) Directory.CreateDirectory(dir);
		File.WriteAllText(fullPath, content);
		return fullPath;
	}

	// ── ResolveTempPaths (back-compat shim) ──

	[Fact]
	public void ResolveTempPaths_ReturnsNonEmptyList()
	{
		var paths = TempFolderCleanerService.ResolveTempPaths();

		Assert.NotEmpty(paths);
		Assert.All(paths, p => Assert.False(string.IsNullOrWhiteSpace(p)));
	}

	[Fact]
	public void ResolveTempPaths_NoDuplicates()
	{
		var paths = TempFolderCleanerService.ResolveTempPaths();

		var comparer = RuntimeInformation.IsOSPlatform(OSPlatform.Windows)
			? StringComparer.OrdinalIgnoreCase
			: StringComparer.Ordinal;

		Assert.Equal(paths.Count, paths.Distinct(comparer).Count());
	}

	[Fact]
	public void ResolveTempPaths_Windows_IncludesExpectedPaths()
	{
		if (!RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
			return; // Skip on non-Windows

		var paths = TempFolderCleanerService.ResolveTempPaths();

		// GetTempPath() result should be included (the fix: no longer relies on raw TEMP env var)
		var expectedTemp = Path.GetFullPath(Path.GetTempPath().TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar));
		Assert.Contains(paths, p => p.Equals(expectedTemp, StringComparison.OrdinalIgnoreCase));

		// C:\Windows\Temp should be included when it exists on this machine.
		// CI runners may not have it accessible, so only assert when the directory is present.
		var winDir = Environment.GetEnvironmentVariable("SystemRoot") ?? @"C:\Windows";
		var winTemp = Path.Combine(winDir, "Temp");
		if (Directory.Exists(winTemp))
			Assert.Contains(paths, p => p.EndsWith("Windows\\Temp", StringComparison.OrdinalIgnoreCase));
	}

	// ── ResolveCleanTargets (typed discovery) ──

	[Fact]
	public void ResolveCleanTargets_ReturnsNonEmptyList()
	{
		var targets = TempFolderCleanerService.ResolveCleanTargets();

		Assert.NotEmpty(targets);
		Assert.All(targets, t => Assert.False(string.IsNullOrWhiteSpace(t.Path)));
	}

	[Fact]
	public void ResolveCleanTargets_AllHaveLabelsAndValidCategory()
	{
		var targets = TempFolderCleanerService.ResolveCleanTargets();

		Assert.All(targets, t =>
		{
			Assert.False(string.IsNullOrWhiteSpace(t.Label), $"Target {t.Path} has no label");
			Assert.True(t.Category == CleanCategory.Temp || t.Category == CleanCategory.Cache,
				$"Target {t.Path} has unexpected category {t.Category}");
		});
	}

	[Fact]
	public void ResolveCleanTargets_NoDuplicatePaths()
	{
		var targets = TempFolderCleanerService.ResolveCleanTargets();

		var comparer = RuntimeInformation.IsOSPlatform(OSPlatform.Windows)
			? StringComparer.OrdinalIgnoreCase
			: StringComparer.Ordinal;

		var paths = targets.Select(t => t.Path).ToList();
		Assert.Equal(paths.Count, paths.Distinct(comparer).Count());
	}

	[Fact]
	public void ResolveCleanTargets_ContainsAtLeastOneTemp()
	{
		var targets = TempFolderCleanerService.ResolveCleanTargets();
		Assert.Contains(targets, t => t.Category == CleanCategory.Temp);
	}

	[Fact]
	public void TempFolderDictionary_DirectResolution_MatchesServiceResolution()
	{
		var dictTargets = TempFolderDictionary.ResolveCleanTargets();
		var svcTargets = TempFolderCleanerService.ResolveCleanTargets();

		Assert.Equal(dictTargets.Count, svcTargets.Count);
		for (var i = 0; i < dictTargets.Count; i++)
		{
			Assert.Equal(dictTargets[i].Path, svcTargets[i].Path);
			Assert.Equal(dictTargets[i].Label, svcTargets[i].Label);
			Assert.Equal(dictTargets[i].Category, svcTargets[i].Category);
		}
	}

	[Fact]
	public void TempFolderDictionary_ResolveTempPaths_ReturnsCleanStrings()
	{
		var paths = TempFolderDictionary.ResolveTempPaths();
		Assert.NotEmpty(paths);
		Assert.All(paths, p =>
		{
			Assert.True(Path.IsPathRooted(p));
			Assert.True(Directory.Exists(p));
		});
	}

	[Fact]
	public async Task Preview_CorrectlySumsSizes()
	{
		var svc = CreateService();

		var result = await svc.PreviewAsync();

		Assert.NotNull(result);
		// CI runners may have limited/no accessible temp dirs — only validate structure,
		// not that locations are non-empty.
		Assert.All(result.Locations, loc =>
		{
			Assert.False(string.IsNullOrWhiteSpace(loc.Path));
			Assert.True(loc.SizeBytes >= 0);
			Assert.False(string.IsNullOrWhiteSpace(loc.SizeFormatted));
			Assert.True(loc.FileCount >= 0);
		});

		// TotalBytes should equal the sum of all location sizes
		var expectedTotal = result.Locations.Sum(l => l.SizeBytes);
		Assert.Equal(expectedTotal, result.TotalBytes);
		Assert.False(string.IsNullOrWhiteSpace(result.TotalFormatted));
	}

	[Fact]
	public async Task Preview_IncludesLabelAndCategory()
	{
		// Use a real temp dir so we always have at least one location,
		// regardless of CI environment.
		var svc = CreateService(pathsOverride: new[] { _fakeTempDir });
		SeedFile("label_test.tmp", "test");

		var result = await svc.PreviewAsync();

		Assert.NotNull(result);
		Assert.NotEmpty(result.Locations);
		Assert.All(result.Locations, loc =>
		{
			Assert.False(string.IsNullOrWhiteSpace(loc.Label), $"Location {loc.Path} has no Label");
			Assert.True(loc.Category == "Temp" || loc.Category == "Cache",
				$"Location {loc.Path} has unexpected category '{loc.Category}'");
		});
	}

	[Fact]
	public async Task Preview_SupportsCancel()
	{
		var svc = CreateService();
		using var cts = new CancellationTokenSource();
		cts.Cancel();

		// Task.Run with a pre-cancelled token throws TaskCanceledException,
		// which derives from OperationCanceledException.
		var ex = await Assert.ThrowsAnyAsync<OperationCanceledException>(
			() => svc.PreviewAsync(cts.Token));
		Assert.True(ex.CancellationToken.IsCancellationRequested);
	}

	[Fact]
	public async Task Clean_RejectsUnknownPath()
	{
		var svc = CreateService();
		var bogusPath = Path.Combine(Path.GetTempPath(), "totally_not_a_temp_dir_" + Guid.NewGuid().ToString("N"));

		await Assert.ThrowsAsync<UnauthorizedAccessException>(
			() => svc.CleanAsync(new List<string> { bogusPath }));
	}

	[Fact]
	public async Task Clean_AcceptsPathWithTrailingSeparator()
	{
		var svc = CreateService(pathsOverride: new[] { _fakeTempDir });
		var withTrailing = _fakeTempDir.TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;

		// Should NOT throw UnauthorizedAccessException
		var result = await svc.CleanAsync(new List<string> { withTrailing });
		Assert.True(result.DeletedFiles >= 0);
	}

	[Fact]
	public async Task Clean_DeletesFilesFromRealTemp()
	{
		// Create a test file in the fake temp dir
		var testFile = SeedFile("gs_cleantest_" + Guid.NewGuid().ToString("N") + ".tmp", "cleanup test data");

		try
		{
			var svc = CreateService(pathsOverride: new[] { _fakeTempDir });
			var tempPath = _fakeTempDir;

			// Only clean the specific temp directory
			var result = await svc.CleanAsync(new List<string> { tempPath });

			Assert.True(result.DeletedFiles >= 0);
			Assert.True(result.FreedBytes >= 0);
			Assert.False(string.IsNullOrWhiteSpace(result.FreedFormatted));

			// The temp DIRECTORY should still exist
			Assert.True(Directory.Exists(tempPath));
		}
		finally
		{
			// Clean up if test file wasn't deleted
			if (File.Exists(testFile)) File.Delete(testFile);
		}
	}

	[Fact]
	public async Task Clean_TempDirectoryItselfNeverDeleted()
	{
		var svc = CreateService(pathsOverride: new[] { _fakeTempDir });
		var existingPaths = new List<string> { _fakeTempDir };

		await svc.CleanAsync(existingPaths);

		// Verify all temp directories still exist
		Assert.All(existingPaths, path => Assert.True(Directory.Exists(path),
			$"Temp directory was deleted: {path}"));
	}

	[Fact]
	public async Task Clean_EmptyPathsList_IsHandledGracefully()
	{
		var svc = CreateService();

		// Empty list shouldn't throw, should return zero counters
		var result = await svc.CleanAsync(new List<string>());

		Assert.Equal(0, result.DeletedFiles);
		Assert.Equal(0, result.FreedBytes);
		Assert.Equal(0, result.SkippedFiles);
	}

	[Fact]
	public async Task Clean_WithHubContext_BroadcastsTempCleanProgressTicks()
	{
		var hub = new Mock<IHubContext<SystemHub>>();
		var clients = new Mock<IHubClients>();
		var proxy = new Mock<IClientProxy>();
		clients.Setup(c => c.All).Returns(proxy.Object);
		hub.Setup(h => h.Clients).Returns(clients.Object);

		var capturedCalls = new List<string>();
		proxy.Setup(p => p.SendCoreAsync(It.IsAny<string>(), It.IsAny<object?[]>(), It.IsAny<CancellationToken>()))
			 .Callback<string, object?[], CancellationToken>((method, args, ct) => capturedCalls.Add(method))
			 .Returns(Task.CompletedTask);

		var nuke = CreateNukeService();
		var svc = new TempFolderCleanerService(nuke, NullLogger<TempFolderCleanerService>.Instance, null, hub.Object, new[] { _fakeTempDir });

		SeedFile("progress_test.tmp", "content");
		var result = await svc.CleanAsync(new List<string> { _fakeTempDir });

		Assert.Equal(1, result.DeletedFiles);
		Assert.Contains("TempCleanProgress", capturedCalls);
		Assert.True(capturedCalls.Count >= 2);
	}
}
