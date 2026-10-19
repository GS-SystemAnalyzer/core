using System.Globalization;
using System.Text;
using System.Text.Json;
using GSSystemAnalyzer.Interfaces;
using GSSystemAnalyzer.Models;

namespace GSSystemAnalyzer.Services;

public class ScanExportService : IScanExportService
{
	private readonly IScanCacheService _cacheService;
	private readonly ISettingService _settings;
	private readonly IFileTypeScanner? _fileTypeScanner;
	private readonly IDiskScannerEngine? _engine;
	private readonly string _userProfile;

	public ScanExportService(
		IScanCacheService cacheService,
		ISettingService settings,
		IFileTypeScanner? fileTypeScanner = null,
		IDiskScannerEngine? engine = null)
	{
		_cacheService = cacheService;
		_settings = settings;
		_fileTypeScanner = fileTypeScanner;
		_engine = engine;
		_userProfile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
	}

	public bool HasCachedScan(string root)
	{
		return _cacheService.HasScanRoot(root);
	}

	public long GetCachedNodeCount(string root)
	{
		var rootMeta = _cacheService.GetScanRoot(root);
		if (rootMeta != null && rootMeta.TotalFiles > 0)
		{
			return rootMeta.TotalFiles;
		}

		var nodes = _cacheService.GetNodesUnderRoot(root);
		return nodes.Sum(n => (long)n.Files.Count + 1);
	}

	public ScanReportSummaryDto? GetReportSummary(string root, bool redactPaths)
	{
		var rootMeta = _cacheService.GetScanRoot(root);
		var allNodes = _cacheService.GetNodesUnderRoot(root).ToList();
		if (rootMeta == null && allNodes.Count == 0) return null;

		var totalBytes = rootMeta?.TotalBytes ?? allNodes.Sum(n => n.OwnBytes);
		var totalFiles = rootMeta?.TotalFiles ?? allNodes.Sum(n => n.Files.Count);
		var scannedAt = rootMeta?.ScannedAt ?? DateTimeOffset.UtcNow;
		var displayRoot = Redact(root, redactPaths);

		var categoryTotals = new Dictionary<string, (long bytes, int count)>(StringComparer.OrdinalIgnoreCase)
		{
			["media"] = (0, 0),
			["documents"] = (0, 0),
			["code"] = (0, 0),
			["executables"] = (0, 0),
			["archives"] = (0, 0),
			["system"] = (0, 0),
			["other"] = (0, 0)
		};

		var fileTypeResult = _fileTypeScanner?.Analyze(root);
		if (fileTypeResult != null && fileTypeResult.Categories.Count > 0)
		{
			foreach (var cat in fileTypeResult.Categories)
			{
				var catKey = cat.Name.ToLowerInvariant();
				if (!categoryTotals.ContainsKey(catKey)) catKey = "other";
				categoryTotals[catKey] = (cat.TotalBytes, cat.FileCount);
			}

			if (totalBytes <= 0) totalBytes = fileTypeResult.TotalScannedBytes;
			var aggregatedFiles = fileTypeResult.Categories.Sum(c => c.FileCount);
			if (aggregatedFiles > totalFiles) totalFiles = aggregatedFiles;
		}
		else
		{
			foreach (var node in allNodes)
			{
				foreach (var file in node.Files)
				{
					var cat = FileCategoryDictionary.GetCategory(file.Extension);
					if (!categoryTotals.ContainsKey(cat)) cat = "other";
					var current = categoryTotals[cat];
					categoryTotals[cat] = (current.bytes + file.Length, current.count + 1);
				}
			}
		}

		var categories = categoryTotals
			.OrderByDescending(c => c.Value.bytes)
			.Select(c => new ScanCategorySummaryDto(c.Key, c.Value.count, c.Value.bytes))
			.ToList();

		var topDirectories = allNodes
			.OrderByDescending(n => n.RecursiveBytes)
			.Take(100)
			.Select(n => new TopDirectorySummaryDto(Redact(n.Path, redactPaths), n.Files.Count, n.OwnBytes, n.RecursiveBytes))
			.ToList();

		return new ScanReportSummaryDto(
			displayRoot,
			scannedAt,
			DateTimeOffset.UtcNow,
			totalBytes,
			totalFiles,
			allNodes.Count,
			categories,
			topDirectories);
	}

	public async Task ExportAsync(string root, string format, bool redactPaths, Stream outputStream, CancellationToken ct = default)
	{
		var normFormat = (format ?? "json").Trim().ToLowerInvariant();
		switch (normFormat)
		{
			case "csv":
				await ExportCsvAsync(root, redactPaths, outputStream, ct);
				break;
			case "html":
				throw new NotSupportedException("HTML report generation has been moved to the client. Use GetReportSummary instead.");
			case "json":
			default:
				await ExportJsonAsync(root, redactPaths, outputStream, ct);
				break;
		}
	}

	#region JSON Streaming

	private async Task ExportJsonAsync(string root, bool redactPaths, Stream outputStream, CancellationToken ct)
	{
		var rootMeta = _cacheService.GetScanRoot(root);
		var scannedAt = rootMeta?.ScannedAt ?? DateTimeOffset.UtcNow;
		var totalBytes = rootMeta?.TotalBytes ?? 0;
		var totalFiles = rootMeta?.TotalFiles ?? 0;

		var allNodes = _cacheService.GetNodesUnderRoot(root).ToList();
		if (totalBytes == 0 && allNodes.Count > 0)
		{
			totalBytes = allNodes.Sum(n => n.OwnBytes);
			totalFiles = allNodes.Sum(n => n.Files.Count);
		}

		var fileTypeResult = _fileTypeScanner?.Analyze(root);
		if (fileTypeResult != null && fileTypeResult.Categories.Count > 0)
		{
			if (totalBytes <= 0) totalBytes = fileTypeResult.TotalScannedBytes;
			var aggregatedFiles = fileTypeResult.Categories.Sum(c => c.FileCount);
			if (aggregatedFiles > totalFiles) totalFiles = aggregatedFiles;
		}

		var nodeLookup = allNodes.ToDictionary(n => NormalizePathKey(n.Path), StringComparer.OrdinalIgnoreCase);

		CachedDirNode? rootNode = null;
		if (rootMeta != null && nodeLookup.TryGetValue(NormalizePathKey(rootMeta.RootNodeKey), out var foundRoot))
		{
			rootNode = foundRoot;
		}
		else if (nodeLookup.TryGetValue(NormalizePathKey(root), out var foundDirect))
		{
			rootNode = foundDirect;
		}
		else if (allNodes.Count > 0)
		{
			var exactMatch = allNodes.FirstOrDefault(n => NormalizePathKey(n.Path).Equals(NormalizePathKey(root), StringComparison.OrdinalIgnoreCase));
			if (exactMatch != null) rootNode = exactMatch;
		}

		if (rootNode == null || (!rootNode.Path.Equals(root, StringComparison.OrdinalIgnoreCase) && !NormalizePathKey(rootNode.Path).Equals(NormalizePathKey(root), StringComparison.OrdinalIgnoreCase)))
		{
			// Synthesize root node pointing to top-level children under root
			var normRoot = NormalizePathKey(root);
			var topLevelChildren = allNodes
				.Where(n => CalculateDepth(normRoot, NormalizePathKey(n.Path)) == 1)
				.Select(n => n.Path)
				.ToList();

			rootNode = new CachedDirNode(
				Path: root,
				ChildDirectoryPaths: topLevelChildren,
				Files: Array.Empty<CachedFileEntry>(),
				OwnBytes: 0,
				RecursiveBytes: totalBytes,
				CachedAt: scannedAt,
				RecursiveBytesStale: false
			);
			nodeLookup[normRoot] = rootNode;
		}

		var jsonOptions = new JsonWriterOptions
		{
			Indented = true
		};

		await using var writer = new Utf8JsonWriter(outputStream, jsonOptions);

		writer.WriteStartObject();
		writer.WriteString("root", Redact(root, redactPaths));
		writer.WriteString("scannedAt", scannedAt.ToString("o"));
		writer.WriteString("exportedAt", DateTimeOffset.UtcNow.ToString("o"));
		writer.WriteNumber("totalBytes", totalBytes);
		writer.WriteNumber("totalFiles", totalFiles);
		writer.WriteString("appVersion", "2.0.0");

		writer.WritePropertyName("tree");
		if (rootNode != null)
		{
			WriteDirectoryNodeJson(writer, rootNode, nodeLookup, redactPaths, 0);
		}
		else
		{
			writer.WriteStartObject();
			writer.WriteString("path", Redact(root, redactPaths));
			writer.WriteString("name", Redact(Path.GetFileName(root) is { Length: > 0 } fn ? fn : root, redactPaths));
			writer.WriteNumber("sizeBytes", 0);
			writer.WriteString("sizeFormatted", "0.0 B");
			writer.WriteString("lastModified", scannedAt.ToString("o"));
			writer.WriteStartArray("files");
			writer.WriteEndArray();
			writer.WriteStartArray("directories");
			writer.WriteEndArray();
			writer.WriteEndObject();
		}

		writer.WriteEndObject();
		await writer.FlushAsync(ct);
	}

	private void WriteDirectoryNodeJson(
		Utf8JsonWriter writer,
		CachedDirNode node,
		Dictionary<string, CachedDirNode> nodeLookup,
		bool redactPaths,
		int depth)
	{
		writer.WriteStartObject();
		writer.WriteString("path", Redact(node.Path, redactPaths));
		var dirName = Path.GetFileName(node.Path);
		writer.WriteString("name", Redact(string.IsNullOrEmpty(dirName) ? node.Path : dirName, redactPaths));
		writer.WriteNumber("sizeBytes", node.RecursiveBytes);
		writer.WriteString("sizeFormatted", FormatBytes(node.RecursiveBytes));
		writer.WriteString("lastModified", node.CachedAt.ToString("o"));
		writer.WriteNumber("depth", depth);

		writer.WriteStartArray("files");
		foreach (var file in node.Files)
		{
			writer.WriteStartObject();
			writer.WriteString("name", file.Name);
			writer.WriteString("path", Redact(Path.Combine(node.Path, file.Name), redactPaths));
			writer.WriteString("extension", file.Extension);
			writer.WriteString("category", GetCategory(file.Extension));
			writer.WriteNumber("sizeBytes", file.Length);
			writer.WriteString("sizeFormatted", FormatBytes(file.Length));
			writer.WriteString("lastModified", file.LastModifiedUtc.ToString("o"));
			writer.WriteEndObject();
		}
		writer.WriteEndArray();

		writer.WriteStartArray("directories");
		foreach (var childPath in node.ChildDirectoryPaths)
		{
			if (nodeLookup.TryGetValue(NormalizePathKey(childPath), out var childNode))
			{
				WriteDirectoryNodeJson(writer, childNode, nodeLookup, redactPaths, depth + 1);
			}
		}
		writer.WriteEndArray();

		writer.WriteEndObject();
	}

	#endregion

	#region CSV Streaming

	private async Task ExportCsvAsync(string root, bool redactPaths, Stream outputStream, CancellationToken ct)
	{
		await using var writer = new StreamWriter(outputStream, new UTF8Encoding(false), 8192, leaveOpen: true);

		// Header
		await writer.WriteLineAsync("path,name,isDirectory,sizeBytes,sizeFormatted,extension,category,lastModified,depth");

		var allNodes = _cacheService.GetNodesUnderRoot(root).ToList();
		var normRoot = NormalizePathKey(root);

		foreach (var node in allNodes.OrderBy(n => n.Path))
		{
			ct.ThrowIfCancellationRequested();

			var depth = CalculateDepth(normRoot, NormalizePathKey(node.Path));
			var dirName = Path.GetFileName(node.Path);
			if (string.IsNullOrEmpty(dirName)) dirName = node.Path;

			// Write directory row
			var dirRow = string.Join(",",
				EscapeCsvField(Redact(node.Path, redactPaths)),
				EscapeCsvField(Redact(dirName, redactPaths)),
				"true",
				node.RecursiveBytes.ToString(CultureInfo.InvariantCulture),
				EscapeCsvField(FormatBytes(node.RecursiveBytes)),
				"",
				"directory",
				EscapeCsvField(node.CachedAt.ToString("o")),
				depth.ToString(CultureInfo.InvariantCulture)
			);
			await writer.WriteLineAsync(dirRow.AsMemory(), ct);

			// Write file rows
			foreach (var file in node.Files)
			{
				var filePath = Path.Combine(node.Path, file.Name);
				var fileRow = string.Join(",",
					EscapeCsvField(Redact(filePath, redactPaths)),
					EscapeCsvField(file.Name),
					"false",
					file.Length.ToString(CultureInfo.InvariantCulture),
					EscapeCsvField(FormatBytes(file.Length)),
					EscapeCsvField(file.Extension),
					EscapeCsvField(GetCategory(file.Extension)),
					EscapeCsvField(file.LastModifiedUtc.ToString("o")),
					(depth + 1).ToString(CultureInfo.InvariantCulture)
				);
				await writer.WriteLineAsync(fileRow.AsMemory(), ct);
			}
		}

		await writer.FlushAsync(ct);
	}

	/// <summary>
	/// Sanitizes and escapes a CSV field:
	/// 1. Formula injection prevention: prefixes =, +, -, @, \t, \r with '
	/// 2. RFC 4180 escaping: doubles internal quotes, wraps with quotes if containing comma, quote, or newline
	/// </summary>
	public static string EscapeCsvField(string? field)
	{
		if (string.IsNullOrEmpty(field)) return "";

		var result = field;

		// CSV formula injection mitigation: prefix dangerous leading characters with a single quote
		if (result.Length > 0 && (result[0] == '=' || result[0] == '+' || result[0] == '-' || result[0] == '@' || result[0] == '\t' || result[0] == '\r'))
		{
			result = "'" + result;
		}

		// RFC 4180 quote doubling and comma/newline wrapping
		if (result.Contains('"') || result.Contains(',') || result.Contains('\n') || result.Contains('\r'))
		{
			result = "\"" + result.Replace("\"", "\"\"") + "\"";
		}

		return result;
	}

	#endregion

	#region Helpers

	private string Redact(string path, bool redactPaths)
	{
		if (!redactPaths || string.IsNullOrEmpty(path) || string.IsNullOrEmpty(_userProfile))
		{
			return path;
		}

		var result = path;
		if (result.StartsWith(_userProfile, StringComparison.OrdinalIgnoreCase))
		{
			result = "~" + result.Substring(_userProfile.Length);
		}

		var altProfile = _userProfile.Replace('\\', '/');
		if (result.StartsWith(altProfile, StringComparison.OrdinalIgnoreCase))
		{
			result = "~" + result.Substring(altProfile.Length);
		}

		return result;
	}

	private static string GetCategory(string extension)
	{
		return FileCategoryDictionary.GetCategory(extension);
	}

	private static int CalculateDepth(string root, string path)
	{
		if (string.IsNullOrEmpty(path) || path.Equals(root, StringComparison.OrdinalIgnoreCase))
		{
			return 0;
		}

		var relative = path.Length > root.Length ? path.Substring(root.Length).TrimStart('\\', '/') : "";
		if (string.IsNullOrEmpty(relative)) return 0;

		return relative.Split(['\\', '/'], StringSplitOptions.RemoveEmptyEntries).Length;
	}

	private static string NormalizePathKey(string path)
	{
		if (string.IsNullOrWhiteSpace(path)) return string.Empty;
		return path.TrimEnd('\\', '/');
	}

	public static string FormatBytes(long bytes)
	{
		string[] suffixes = ["B", "KB", "MB", "GB", "TB", "PB"];
		int counter = 0;
		decimal number = bytes;
		while (Math.Round(number / 1024) >= 1 && counter < suffixes.Length - 1)
		{
			number /= 1024;
			counter++;
		}
		return $"{number:n1} {suffixes[counter]}";
	}

	#endregion
}
