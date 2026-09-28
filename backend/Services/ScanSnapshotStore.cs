using System.Text.Json;
using GSSystemAnalyzer.Interfaces;
using GSSystemAnalyzer.Models;
using Microsoft.Extensions.Logging;

namespace GSSystemAnalyzer.Services;

public class ScanSnapshotStore : IScanSnapshotStore
{
	private readonly string _snapshotDir;
	private readonly JsonSerializerOptions _jsonOptions;
	private readonly ILogger<ScanSnapshotStore> _logger;
	private readonly object _fileLock = new();

	public ScanSnapshotStore(ILogger<ScanSnapshotStore>? logger = null, string? testDir = null)
	{
		_logger = logger ?? Microsoft.Extensions.Logging.Abstractions.NullLogger<ScanSnapshotStore>.Instance;

		if (testDir != null)
		{
			_snapshotDir = testDir;
		}
		else
		{
			var appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
			_snapshotDir = Path.Combine(appData, "GSAnalyzer", "scan_snapshots");
		}

		Directory.CreateDirectory(_snapshotDir);

		_jsonOptions = new JsonSerializerOptions
		{
			WriteIndented = false,
			PropertyNamingPolicy = JsonNamingPolicy.CamelCase
		};
	}

	public ScanSnapshot? Load(string root, int depth)
	{
		var path = SnapshotPath(root, depth);
		if (!File.Exists(path)) return null;

		string? json = null;
		int retries = 5;

		while (true)
		{
			try
			{
				lock (_fileLock)
				{
					if (!File.Exists(path)) return null;
					json = File.ReadAllText(path);
				}
				break;
			}
			catch (Exception ex) when (ex is IOException || ex is UnauthorizedAccessException)
			{
				retries--;
				if (retries == 0)
				{
					_logger.LogWarning(ex, "Failed to read scan snapshot at {Path} due to I/O lock", path);
					return null;
				}
				Thread.Sleep(20);
			}
		}

		try
		{
			return JsonSerializer.Deserialize<ScanSnapshot>(json, _jsonOptions);
		}
		catch (JsonException ex)
		{
			_logger.LogWarning(ex, "Corrupt scan snapshot at {Path}, discarding", path);
			try { File.Delete(path); } catch { /* best effort */ }
			return null;
		}
	}

	public void Save(string root, int depth, ScanSnapshot snapshot)
	{
		var path = SnapshotPath(root, depth);
		var json = JsonSerializer.Serialize(snapshot, _jsonOptions);
		var tempPath = path + "." + Guid.NewGuid().ToString("N") + ".tmp";

		lock (_fileLock)
		{
			File.WriteAllText(tempPath, json);
			int retries = 5;
			while (true)
			{
				try
				{
					File.Move(tempPath, path, overwrite: true);
					break;
				}
				catch (Exception ex) when (ex is UnauthorizedAccessException || ex is IOException)
				{
					retries--;
					if (retries == 0)
					{
						try { File.Delete(tempPath); } catch { /* best effort */ }
						throw;
					}
					Thread.Sleep(20);
				}
			}
		}
	}

	public void Delete(string root, int depth)
	{
		var path = SnapshotPath(root, depth);
		lock (_fileLock)
		{
			try
			{
				if (File.Exists(path)) File.Delete(path);
			}
			catch (Exception ex)
			{
				_logger.LogWarning(ex, "Failed to delete scan snapshot at {Path}", path);
			}
		}
	}

	private string SnapshotPath(string root, int depth)
	{
		var driveKey = NormalizeDriveKey(root);
		var safeKey = driveKey
			.Replace(':', '_')
			.Replace('/', '_')
			.Replace('\\', '_');
		return Path.Combine(_snapshotDir, $"{safeKey}_{depth}.json");
	}

	public static string NormalizeDriveKey(string root)
	{
		var fullPath = Path.GetFullPath(root);
		return fullPath.Replace('\\', '/').ToLowerInvariant().TrimEnd('/');
	}
}
