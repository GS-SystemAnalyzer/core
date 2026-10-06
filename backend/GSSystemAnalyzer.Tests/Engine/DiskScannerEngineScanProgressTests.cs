using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Threading;
using System.Threading.Tasks;
using GSSystemAnalyzer.Engine;
using GSSystemAnalyzer.Hubs;
using GSSystemAnalyzer.Interfaces;
using GSSystemAnalyzer.Models.SettingDtos;
using Microsoft.AspNetCore.SignalR;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using Xunit;

namespace GSSystemAnalyzer.Tests.Engine
{
	// Regression tests for issue #206 — the backend EMIT side of the ScanProgress contract.
	// Pins payload field names, per-directory status, status vocabulary, and the terminal
	// message on a fully-cached rescan. See plans/206-scan-abort-and-rescan-stall.md.
	public class DiskScannerEngineScanProgressTests : IDisposable
	{
		private readonly DiskScannerEngine _engine;
		private readonly ConcurrentQueue<(string Method, object? Payload)> _sends = new();
		private readonly string _root;
		private readonly string _tempCacheFile;

		public DiskScannerEngineScanProgressTests()
		{
			var hubMock = new Mock<IHubContext<SystemHub>>();
			var clientsMock = new Mock<IHubClients>();
			var proxyMock = new Mock<IClientProxy>();
			hubMock.Setup(h => h.Clients).Returns(clientsMock.Object);
			clientsMock.Setup(c => c.All).Returns(proxyMock.Object);
			proxyMock
				.Setup(c => c.SendCoreAsync(It.IsAny<string>(), It.IsAny<object?[]>(), It.IsAny<CancellationToken>()))
				.Callback<string, object?[], CancellationToken>((method, args, _) =>
					_sends.Enqueue((method, args.Length > 0 ? args[0] : null)))
				.Returns(Task.CompletedTask);

			var settings = new Mock<ISettingService>();
			settings.SetupGet(s => s.Current).Returns(AppSettingDto.GetFactoryDefaults());

			_engine = new DiskScannerEngine(hubMock.Object, settings.Object, NullLogger<DiskScannerEngine>.Instance);
			_engine.DirectorySizeCache.Clear();

			// Redirect the on-disk cache so SaveMemoryToDisk() during a scan never touches the
			// real %APPDATA%/GSAnalyzer/scanner_memory.json (P-7). The field is private readonly.
			_tempCacheFile = Path.Combine(Path.GetTempPath(), "gsa_206_" + Guid.NewGuid().ToString("N") + ".json");
			typeof(DiskScannerEngine)
				.GetField("_cacheFilePath", BindingFlags.Instance | BindingFlags.NonPublic)!
				.SetValue(_engine, _tempCacheFile);

			_root = Path.Combine(Path.GetTempPath(), "gsa_206_root_" + Guid.NewGuid().ToString("N"));
			Directory.CreateDirectory(_root);
		}

		// Two uncached subdirectories, each with a file: totalNodes == 2, so progress is emitted.
		private List<FileSystemInfo> SeedTree()
		{
			var dirs = new List<FileSystemInfo>();
			foreach (var name in new[] { "alpha", "beta" })
			{
				var sub = Path.Combine(_root, name);
				Directory.CreateDirectory(sub);
				File.WriteAllText(Path.Combine(sub, "f.txt"), new string('x', 128));
				dirs.Add(new DirectoryInfo(sub));
			}
			return dirs;
		}

		private List<object> ScanProgressPayloads() =>
			_sends.Where(s => s.Method == "ScanProgress" && s.Payload != null)
				.Select(s => s.Payload!)
				.ToList();

		private static object? Prop(object payload, string name) =>
			payload.GetType().GetProperty(name)?.GetValue(payload);

		private static string? Status(object payload) => Prop(payload, "status") as string;

		[Fact]
		public async Task PerDirectoryProgress_UsesPercentCompleteKey_NotPercentageComplete()
		{
			var scanId = _engine.BeginScanSession();
			await _engine.CalculateMissingSizesAsync(SeedTree(), scanId);

			var payloads = ScanProgressPayloads();
			// 2b: the contract field is `percentComplete` (techspec v2 §2), never `percentageComplete`.
			Assert.DoesNotContain(payloads, p => Prop(p, "percentageComplete") != null);
			Assert.Contains(payloads, p => Prop(p, "percentComplete") != null);
		}

		[Fact]
		public async Task PerDirectoryProgress_CarriesStatus_SoUiLeavesInitializing()
		{
			var scanId = _engine.BeginScanSession();
			await _engine.CalculateMissingSizesAsync(SeedTree(), scanId);

			// 2a: the per-directory payload (the one carrying `completed`) must also carry a
			// `status`; otherwise copyWith(status: null) pins the UI on INITIALIZING for the scan.
			var progress = ScanProgressPayloads().Where(p => Prop(p, "completed") != null).ToList();
			Assert.NotEmpty(progress);
			Assert.All(progress, p => Assert.False(string.IsNullOrEmpty(Status(p))));
		}

		[Fact]
		public async Task EmittedStatuses_StayWithinKnownVocabulary()
		{
			var scanId = _engine.BeginScanSession();
			await _engine.CalculateMissingSizesAsync(SeedTree(), scanId);

			// Contract guard: the backend must only emit statuses the frontend knows about.
			var known = new HashSet<string> { "INITIALIZING", "SCANNING", "COMPLETED", "CANCELED" };
			var emitted = ScanProgressPayloads().Select(Status).Where(s => s != null).Select(s => s!).Distinct();
			Assert.All(emitted, s => Assert.Contains(s, known));
		}

		[Fact]
		public async Task FullyCachedRescan_StillEmitsTerminalCompleted()
		{
			var items = SeedTree();
			// Pre-cache every top-level item so directoriesToScan is empty and totalNodes == 0.
			foreach (var d in items)
			{
				_engine.DirectorySizeCache[d.FullName] = new CacheEntry
				{
					Size = 1,
					LastUpdated = d.LastWriteTimeUtc,
					CachedAtUtc = DateTime.UtcNow,
					ScanRoot = _root
				};
			}

			var scanId = _engine.BeginScanSession();
			await _engine.CalculateMissingSizesAsync(items, scanId);

			// Part 4: a fully-cached rescan must still reach a terminal COMPLETED, or the UI is
			// left on its previous state with no terminal event ever arriving.
			Assert.Contains(ScanProgressPayloads(), p => Status(p) == "COMPLETED");
		}

		[Fact]
		public async Task CancelledScan_EmitsCanceled_AndSurfacesOperationCanceled()
		{
			var scanId = _engine.BeginScanSession();
			_engine.TriggerScanAbort(scanId); // token is already cancelled when the scan starts

			// Contract guard (keeps the HTTP 499 path intact): the engine still surfaces OCE
			// (TaskCanceledException derives from it), so ThrowsAny, not the exact-type ThrowsAsync.
			await Assert.ThrowsAnyAsync<OperationCanceledException>(
				() => _engine.CalculateMissingSizesAsync(SeedTree(), scanId));

			// ...and still broadcasts a terminal CANCELED for the UI.
			Assert.Contains(ScanProgressPayloads(), p => Status(p) == "CANCELED");
		}

		public void Dispose()
		{
			try { if (Directory.Exists(_root)) Directory.Delete(_root, recursive: true); } catch { /* best-effort */ }
			try { if (File.Exists(_tempCacheFile)) File.Delete(_tempCacheFile); } catch { /* best-effort */ }
		}
	}
}
