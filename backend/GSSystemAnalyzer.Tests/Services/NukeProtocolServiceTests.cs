using System;
using System.Collections.Generic;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
using GSSystemAnalyzer.Hubs;
using GSSystemAnalyzer.Interfaces;
using GSSystemAnalyzer.Services;
using Microsoft.AspNetCore.SignalR;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using Xunit;
using Microsoft.Extensions.Logging;
using Xunit.Abstractions;

namespace GSSystemAnalyzer.Tests.Services;

public class NukeProtocolServiceTests : IDisposable
{
	private readonly string _workDir;
	private readonly string _stagingBase;
	private readonly Mock<IDiskScannerEngine> _scanner = new();
	private readonly ITestOutputHelper _output;

	public NukeProtocolServiceTests(ITestOutputHelper output)
	{
		_output = output;
		_workDir = Path.Combine(Path.GetTempPath(), "gsnuke_work_" + Guid.NewGuid().ToString("N"));
		_stagingBase = Path.Combine(Path.GetTempPath(), "gsnuke_stage_" + Guid.NewGuid().ToString("N"));
		foreach (var path in new[] { _workDir, _stagingBase })
			_output.WriteLine($"OWNED FILE {Environment.ProcessId} {DateTimeOffset.UtcNow:O} {path}");
		try
		{
			Directory.CreateDirectory(_workDir);
			Directory.CreateDirectory(_stagingBase);
		}
		catch
		{
			Dispose();
			throw;
		}

		_scanner.Setup(s => s.NukeToken()).Returns(CancellationToken.None);
		_scanner.Setup(s => s.InvalidatePaths(It.IsAny<IEnumerable<string>>()));
	}

	public void Dispose()
	{
		foreach (var d in new[] { _workDir, _stagingBase })
		{
			if (Directory.Exists(d))
			{
				foreach (var entry in new DirectoryInfo(d).EnumerateFileSystemInfos("*", SearchOption.AllDirectories))
					entry.Attributes &= ~FileAttributes.ReadOnly;
				Directory.Delete(d, true);
			}
			Assert.False(Directory.Exists(d));
			_output.WriteLine($"REMOVED FILE {Environment.ProcessId} {DateTimeOffset.UtcNow:O} {d}");
		}
	}

	private class TestRecycleBinProvider : IRecycleBinProvider
	{
		private readonly string _testTrashDir;
		public TestRecycleBinProvider(string testTrashDir)
		{
			_testTrashDir = testTrashDir;
			Directory.CreateDirectory(_testTrashDir);
		}

		public void SendFileToRecycleBin(string path)
		{
			var dest = Path.Combine(_testTrashDir, Path.GetFileName(path));
			if (File.Exists(dest)) File.Delete(dest);
			File.Move(path, dest);
		}

		public void SendDirectoryToRecycleBin(string path)
		{
			var dest = Path.Combine(_testTrashDir, Path.GetFileName(path));
			if (Directory.Exists(dest)) Directory.Delete(dest, true);
			Directory.Move(path, dest);
		}

		public bool TryRestore(string originalPath)
		{
			var dest = Path.Combine(_testTrashDir, Path.GetFileName(originalPath));
			if (File.Exists(dest))
			{
				var target = originalPath;
				if (File.Exists(target))
				{
					var dir = Path.GetDirectoryName(target)!;
					var name = Path.GetFileNameWithoutExtension(target);
					var ext = Path.GetExtension(target);
					target = Path.Combine(dir, $"{name}_Restored_1{ext}");
				}
				File.Move(dest, target);
				return true;
			}
			else if (Directory.Exists(dest))
			{
				var target = originalPath;
				if (Directory.Exists(target))
				{
					var dir = Path.GetDirectoryName(target)!;
					var name = Path.GetFileName(target);
					target = Path.Combine(dir, $"{name}_Restored_1");
				}
				Directory.Move(dest, target);
				return true;
			}
			return false;
		}
	}

	private NukeProtocolService CreateService(ILogger<NukeProtocolService>? logger = null, IRecycleBinProvider? provider = null)
	{
		var hub = new Mock<IHubContext<SystemHub>>();
		var clients = new Mock<IHubClients>();
		var proxy = new Mock<IClientProxy>();
		clients.Setup(c => c.All).Returns(proxy.Object);
		hub.Setup(h => h.Clients).Returns(clients.Object);
		proxy.Setup(p => p.SendCoreAsync(It.IsAny<string>(), It.IsAny<object?[]>(), It.IsAny<CancellationToken>()))
			 .Returns(Task.CompletedTask);

		var recycleProvider = provider ?? new TestRecycleBinProvider(Path.Combine(_stagingBase, "test_recycle"));
		return new NukeProtocolService(_scanner.Object, hub.Object, logger ?? NullLogger<NukeProtocolService>.Instance, recycleProvider, runStartupCleanup: false)
		{
			StagingBaseResolver = _ => _stagingBase
		};
	}

	private string NewFile(string content = "hello world")
	{
		var path = Path.Combine(_workDir, $"f_{Guid.NewGuid():N}.txt");
		File.WriteAllText(path, content);
		return path;
	}

	private static async Task<string> TokenFor(NukeProtocolService svc, params string[] paths)
		=> (await svc.PreviewNukeAsync(new List<string>(paths))).PlanToken;

	[Fact]
	public async Task Obliterate_EmptyToken_Throws()
	{
		var svc = CreateService();
		await Assert.ThrowsAsync<UnauthorizedAccessException>(
			() => svc.ObliterateNodeAsync(new() { NewFile() }, "", useRecycleBin: false));
	}

	[Fact]
	public async Task Obliterate_UnknownToken_Throws()
	{
		var svc = CreateService();
		await Assert.ThrowsAsync<UnauthorizedAccessException>(
			() => svc.ObliterateNodeAsync(new() { NewFile() }, "not-a-real-token", useRecycleBin: false));
	}

	[Fact]
	public async Task Obliterate_PathNotInPlan_Throws_AndDoesNotDelete()
	{
		var svc = CreateService();
		var planned = NewFile();
		var notPlanned = NewFile();
		var token = await TokenFor(svc, planned); // token bound to `planned` only

		await Assert.ThrowsAsync<UnauthorizedAccessException>(
			() => svc.ObliterateNodeAsync(new() { planned, notPlanned }, token, useRecycleBin: false));

		Assert.True(File.Exists(planned)); // nothing deleted — validation runs first
		Assert.True(File.Exists(notPlanned));
	}

	[Fact]
	public async Task Obliterate_TokenIsSingleUse()
	{
		var svc = CreateService();
		var file = NewFile();
		var token = await TokenFor(svc, file);

		await svc.ObliterateNodeAsync(new() { file }, token, useRecycleBin: true); // consumes token

		var file2 = NewFile();
		await Assert.ThrowsAsync<UnauthorizedAccessException>(
			() => svc.ObliterateNodeAsync(new() { file2 }, token, useRecycleBin: true));
	}

	[Fact]
	public async Task RecycleBin_Stages_SetsStagedBytes_AndIsRecoverable()
	{
		var svc = CreateService();
		var file = NewFile("123456"); // 6 bytes
		var token = await TokenFor(svc, file);

		var result = await svc.ObliterateNodeAsync(new() { file }, token, useRecycleBin: true);

		Assert.False(File.Exists(file));
		Assert.True(result.RecycleBinUsed);
		Assert.True(result.Recoverable);
		Assert.Equal(1, result.DeletedFiles);
		Assert.Equal(6, result.StagedBytes);
		Assert.Equal(0, result.FreedBytes);
		Assert.NotNull(svc.PeekUndo()); // recoverable op is peekable
		Assert.Single(svc.GetUndoHistory());
	}

	[Fact]
	public async Task Permanent_Deletes_SetsFreedBytes_NotRecoverable_NotPeekable()
	{
		var svc = CreateService();
		var file = NewFile("123456");
		var token = await TokenFor(svc, file);

		var result = await svc.ObliterateNodeAsync(new() { file }, token, useRecycleBin: false);

		Assert.False(File.Exists(file));
		Assert.False(result.Recoverable);
		Assert.Equal(6, result.FreedBytes);
		Assert.Equal(0, result.StagedBytes);
		Assert.Null(svc.PeekUndo()); // permanent op is filtered out of peek
		Assert.Single(svc.GetUndoHistory()); // still recorded in history
	}

	[Fact]
	public async Task GhostPath_IsSkipped()
	{
		var svc = CreateService();
		var ghost = Path.Combine(_workDir, "does_not_exist.txt");
		var token = await TokenFor(svc, ghost);

		var result = await svc.ObliterateNodeAsync(new() { ghost }, token, useRecycleBin: false);

		Assert.Equal(1, result.SkippedFiles);
		Assert.Equal(0, result.DeletedFiles);
	}

	[Fact]
	public async Task Permanent_LockedFile_IsSkipped_WithoutErrorLog()
	{
		var logger = new Mock<ILogger<NukeProtocolService>>();
		var svc = CreateService(logger.Object);

		var file = NewFile();
		var token = await TokenFor(svc, file);

		using var lockStream = new FileStream(
			file,
			FileMode.Open,
			FileAccess.ReadWrite,
			FileShare.None);

		var result = await svc.ObliterateNodeAsync(
			new() { file },
			token,
			useRecycleBin: false);

		Assert.Equal(1, result.SkippedFiles);
		Assert.True(File.Exists(file));

		logger.Verify(
			x => x.Log(
				LogLevel.Error,
				It.IsAny<EventId>(),
				It.Is<It.IsAnyType>((_, _) => true),
				It.IsAny<Exception>(),
				It.IsAny<Func<It.IsAnyType, Exception?, string>>()),
			Times.Never);
	}

	[Fact]
	public async Task Undo_RestoresFile_ToOriginalPath()
	{
		var svc = CreateService();
		var file = NewFile("payload");
		var token = await TokenFor(svc, file);
		await svc.ObliterateNodeAsync(new() { file }, token, useRecycleBin: true);

		var undo = svc.UndoNuke();

		Assert.NotNull(undo);
		Assert.Equal(1, undo!.DeletedFiles); // reused field = restored count
		Assert.Equal(0, undo.SkippedFiles);

		// Allow a brief moment for file system propagation in CI
		for (int i = 0; i < 10 && !File.Exists(file); i++)
			await Task.Delay(20);

		if (!File.Exists(file))
		{
			var files = Directory.GetFiles(Path.GetDirectoryName(file)!);
			Assert.Fail($"File not found at {file}. Files in dir: {string.Join(", ", files)}");
		}

		Assert.True(File.Exists(file));
		Assert.Equal("payload", File.ReadAllText(file));
		Assert.Null(svc.PeekUndo()); // op consumed
	}

	[Fact]
	public async Task Undo_SkipsPermanentOnTop_RestoresRecoverableBeneath()
	{
		var svc = CreateService();
		var recoverable = NewFile("keepme");
		var permanent = NewFile("byebye");

		var t1 = await TokenFor(svc, recoverable);
		await svc.ObliterateNodeAsync(new() { recoverable }, t1, useRecycleBin: true); // op A (bottom)

		var t2 = await TokenFor(svc, permanent);
		await svc.ObliterateNodeAsync(new() { permanent }, t2, useRecycleBin: false); // op B (top, permanent)

		var peeked = svc.PeekUndo();
		Assert.NotNull(peeked);
		Assert.True(peeked!.UsedRecycleBin); // skipped the permanent op

		svc.UndoNuke();
		Assert.True(File.Exists(recoverable)); // recoverable restored
		Assert.False(File.Exists(permanent)); // permanent stays gone
	}

	[Fact]
	public async Task Undo_RestoreCollision_RestoresToUniquePath()
	{
		var svc = CreateService();
		var file = NewFile("original");
		var token = await TokenFor(svc, file);
		await svc.ObliterateNodeAsync(new() { file }, token, useRecycleBin: true);

		// Recreate a different file at the original path before undo
		File.WriteAllText(file, "new occupant");

		svc.UndoNuke();

		Assert.Equal("new occupant", File.ReadAllText(file)); // current file untouched
		var dir = Path.GetDirectoryName(file)!;
		var name = Path.GetFileNameWithoutExtension(file);
		var restored = Path.Combine(dir, $"{name}_Restored_1.txt");
		Assert.True(File.Exists(restored));
		Assert.Equal("original", File.ReadAllText(restored));
	}

	[Fact]
	public async Task Clear_EmptiesStack_AndRemovesStaging()
	{
		var svc = CreateService();
		var file = NewFile();
		var token = await TokenFor(svc, file);
		var result = await svc.ObliterateNodeAsync(new() { file }, token, useRecycleBin: true);

		svc.ClearUndoStack();

		Assert.Empty(svc.GetUndoHistory());
		Assert.False(Directory.Exists(Path.Combine(_stagingBase, ".gsanalyzer_trash", result.OperationId)));
	}

	[Fact]
	public async Task UndoStack_CapsAtFive_EvictsOldest_AndCleansItsStaging()
	{
		var svc = CreateService();
		string? oldestOpId = null;

		for (int i = 0; i < 6; i++)
		{
			var file = NewFile();
			var token = await TokenFor(svc, file);
			var result = await svc.ObliterateNodeAsync(new() { file }, token, useRecycleBin: true);
			oldestOpId ??= result.OperationId; // first one = oldest, should be evicted
		}

		Assert.Equal(5, svc.GetUndoHistory().Count);
		Assert.False(Directory.Exists(Path.Combine(_stagingBase, ".gsanalyzer_trash", oldestOpId!)));
	}

	[Fact]
	public async Task SoftDelete_DoesNotUseCustomStagingFolder()
	{
		var svc = CreateService();
		var file = NewFile("payload");
		var token = await TokenFor(svc, file);

		var result = await svc.ObliterateNodeAsync(new() { file }, token, useRecycleBin: true);

		Assert.False(File.Exists(file));
		Assert.True(result.RecycleBinUsed);
		Assert.False(Directory.Exists(Path.Combine(_stagingBase, ".gsanalyzer_trash")));
	}

	[Fact]
	public async Task Startup_DoesNotSilentlyDeleteStagedOrRecoverableFiles()
	{
		var fakeTrashRoot = Path.Combine(_stagingBase, ".gsanalyzer_trash", "op_previous");
		Directory.CreateDirectory(fakeTrashRoot);
		var userFile = Path.Combine(fakeTrashRoot, "user_doc.txt");
		File.WriteAllText(userFile, "precious content");

		var hub = new Mock<IHubContext<SystemHub>>();
		var clients = new Mock<IHubClients>();
		var proxy = new Mock<IClientProxy>();
		clients.Setup(c => c.All).Returns(proxy.Object);
		hub.Setup(h => h.Clients).Returns(clients.Object);

		var svc = new NukeProtocolService(_scanner.Object, hub.Object, NullLogger<NukeProtocolService>.Instance, runStartupCleanup: true)
		{
			StagingBaseResolver = _ => _stagingBase
		};

		await Task.Delay(200);

		Assert.True(File.Exists(userFile));
	}

	[Fact]
	public void LinuxRecycleBinProvider_OwnedDestination_IsEstablishedBeforeUse()
	{
		var constructor = typeof(LinuxRecycleBinProvider).GetConstructor(
			System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic,
			null, new[] { typeof(string) }, null);
		Assert.True(constructor != null, "Linux recycle requires an explicit owned Trash destination before use.");
		var trash = Path.Combine(_stagingBase, "owned Trash");
		var provider = (LinuxRecycleBinProvider)constructor.Invoke(new object[] { trash });
		var file = NewFile("owned payload");
		provider.SendFileToRecycleBin(file);
		Assert.False(File.Exists(file));
		Assert.Equal("owned payload", File.ReadAllText(Path.Combine(trash, "files", Path.GetFileName(file))));
		Assert.True(provider.TryRestore(file));
		Assert.Equal("owned payload", File.ReadAllText(file));
	}

	[Fact]
	public void WindowsRecycleBinProvider_OwnedDispatch_IsEstablishedBeforeUse()
	{
		var constructor = typeof(WindowsRecycleBinProvider).GetConstructor(
			System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic,
			null, new[] { typeof(Action<string>), typeof(Action<string>) }, null);
		Assert.True(constructor != null, "Windows recycle requires controlled file and directory dispatch before use.");
		if (!OperatingSystem.IsWindows()) return;
		var file = NewFile("owned dispatch");
		var destination = Path.Combine(_stagingBase, "owned.txt");
		Action<string> move = path => { Assert.Equal(file, path); File.Move(path, destination); };
		Action<string> unexpected = _ => Assert.Fail("Unexpected directory dispatch.");
		var provider = (WindowsRecycleBinProvider)constructor.Invoke(new object[] { move, unexpected });
		provider.SendFileToRecycleBin(file);
		Assert.False(File.Exists(file));
		Assert.Equal("owned dispatch", File.ReadAllText(destination));
	}

	[Theory]
	[InlineData(false)]
	[InlineData(true)]
	public void LinuxRecycleBinProvider_OwnedTrash_PreservesMetadataCollisionsAndPeers(bool directory)
	{
		var trash = Path.Combine(_stagingBase, "Trash 測試");
		var provider = new LinuxRecycleBinProvider(trash);
		var input = Path.Combine(_workDir, "résumé 測試.bin");
		var payload = directory ? Path.Combine(input, "nested", "payload.bin") : input;
		Directory.CreateDirectory(Path.GetDirectoryName(payload)!);
		byte[] bytes = { 0, 1, 127, 255 };
		File.WriteAllBytes(payload, bytes);
		var peer = NewFile("peer stays");
		var files = Directory.CreateDirectory(Path.Combine(trash, "files")).FullName;
		var info = Directory.CreateDirectory(Path.Combine(trash, "info")).FullName;
		var name = Path.GetFileName(input);
		File.WriteAllText(Path.Combine(files, name), "collision");
		File.WriteAllText(Path.Combine(info, name + ".1.trashinfo"), "metadata collision");
		Assert.False(provider.TryRestore(input));

		if (directory) provider.SendDirectoryToRecycleBin(input);
		else provider.SendFileToRecycleBin(input);

		Assert.False(Path.Exists(input));
		var moved = Path.Combine(files, name + ".2");
		Assert.Equal(bytes, File.ReadAllBytes(directory ? Path.Combine(moved, "nested", "payload.bin") : moved));
		var metadata = Path.Combine(info, name + ".2.trashinfo");
		var lines = File.ReadAllLines(metadata);
		Assert.Equal("[Trash Info]", lines[0]);
		Assert.Equal("Path=" + Uri.EscapeDataString(Path.GetFullPath(input)), lines[1]);
		Assert.True(DateTime.TryParseExact(lines[2]["DeletionDate=".Length..], "yyyy-MM-ddTHH:mm:ss",
			System.Globalization.CultureInfo.InvariantCulture, System.Globalization.DateTimeStyles.None, out _));
		File.WriteAllText(input, "new occupant");
		Assert.False(provider.TryRestore(input));
		Assert.Equal("new occupant", File.ReadAllText(input));
		Assert.True(File.Exists(metadata));
		File.Delete(input);
		Assert.True(provider.TryRestore(input));
		Assert.Equal(bytes, File.ReadAllBytes(payload));
		Assert.False(Path.Exists(moved));
		Assert.False(File.Exists(metadata));
		Assert.Equal("collision", File.ReadAllText(Path.Combine(files, name)));
		Assert.Equal("metadata collision", File.ReadAllText(Path.Combine(info, name + ".1.trashinfo")));
		Assert.Equal("peer stays", File.ReadAllText(peer));
	}

	[Theory]
	[InlineData(false)]
	[InlineData(true)]
	public void WindowsRecycleBinProvider_OwnedDispatch_ClearsReadonlyAndPreservesPeers(bool directory)
	{
		if (!OperatingSystem.IsWindows()) return;
		var input = Path.Combine(_workDir, "résumé 測試.bin");
		var payload = directory ? Path.Combine(input, "nested", "payload.bin") : input;
		Directory.CreateDirectory(Path.GetDirectoryName(payload)!);
		byte[] bytes = { 0, 127, 255 };
		File.WriteAllBytes(payload, bytes);
		File.SetAttributes(payload, File.GetAttributes(payload) | FileAttributes.ReadOnly);
		if (directory)
		{
			File.SetAttributes(input, File.GetAttributes(input) | FileAttributes.ReadOnly);
			File.SetAttributes(Path.GetDirectoryName(payload)!, FileAttributes.Directory | FileAttributes.ReadOnly);
		}
		var peer = NewFile("untouched");
		var destination = Path.Combine(_stagingBase, "owned destination");
		var calls = 0;
		Action<string> move = path =>
		{
			Assert.Equal(input, path);
			Assert.False(File.GetAttributes(path).HasFlag(FileAttributes.ReadOnly));
			Assert.False(File.GetAttributes(payload).HasFlag(FileAttributes.ReadOnly));
			if (directory)
			{
				Assert.False(File.GetAttributes(Path.GetDirectoryName(payload)!).HasFlag(FileAttributes.ReadOnly));
				Directory.Move(path, destination);
			}
			else File.Move(path, destination);
			calls++;
		};
		Action<string> unexpected = _ => Assert.Fail("Wrong dispatch kind.");
		var provider = new WindowsRecycleBinProvider(directory ? unexpected : move, directory ? move : unexpected);
		if (directory) provider.SendDirectoryToRecycleBin(input);
		else provider.SendFileToRecycleBin(input);
		Assert.Equal(1, calls);
		Assert.False(Path.Exists(input));
		Assert.Equal(bytes, File.ReadAllBytes(directory ? Path.Combine(destination, "nested", "payload.bin") : destination));
		Assert.Equal("untouched", File.ReadAllText(peer));
	}

	[Theory]
	[InlineData(false)]
	[InlineData(true)]
	public void WindowsRecycleBinProvider_DispatchFailure_PropagatesWithoutMovingInput(bool directory)
	{
		if (!OperatingSystem.IsWindows()) return;
		var input = directory ? Directory.CreateDirectory(Path.Combine(_workDir, "empty")).FullName : NewFile("keep");
		var failure = new IOException("controlled failure");
		var calls = 0;
		Action<string> fail = path => { Assert.Equal(input, path); calls++; throw failure; };
		var provider = new WindowsRecycleBinProvider(fail, fail);
		var actual = Assert.Throws<IOException>(() =>
		{
			if (!OperatingSystem.IsWindows()) return;
			if (directory) provider.SendDirectoryToRecycleBin(input);
			else provider.SendFileToRecycleBin(input);
		});
		Assert.Same(failure, actual);
		Assert.Equal(1, calls);
		Assert.True(Path.Exists(input));
		Assert.Empty(Directory.GetFileSystemEntries(_stagingBase));
	}

	[Fact]
	public void OwnedRecycleCleanup_IsRepeatableAndPreservesPeerFixture()
	{
		using var peer = new NukeProtocolServiceTests(_output);
		var sentinel = peer.NewFile("peer fixture");
		var file = NewFile();
		new LinuxRecycleBinProvider(Path.Combine(_stagingBase, "Trash")).SendFileToRecycleBin(file);
		Dispose();
		Dispose();
		Assert.Equal("peer fixture", File.ReadAllText(sentinel));
		Assert.True(Directory.Exists(peer._stagingBase));
	}
}
