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

	public async Task ExportAsync(string root, string format, bool redactPaths, Stream outputStream, CancellationToken ct = default)
	{
		var normFormat = (format ?? "json").Trim().ToLowerInvariant();
		switch (normFormat)
		{
			case "csv":
				await ExportCsvAsync(root, redactPaths, outputStream, ct);
				break;
			case "html":
				await ExportHtmlAsync(root, redactPaths, outputStream, ct);
				break;
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

	#region HTML Streaming

	private async Task ExportHtmlAsync(string root, bool redactPaths, Stream outputStream, CancellationToken ct)
	{
		await using var writer = new StreamWriter(outputStream, new UTF8Encoding(false), 8192, leaveOpen: true);

		var rootMeta = _cacheService.GetScanRoot(root);
		var allNodes = _cacheService.GetNodesUnderRoot(root).ToList();

		var totalBytes = rootMeta?.TotalBytes ?? allNodes.Sum(n => n.OwnBytes);
		var totalFiles = rootMeta?.TotalFiles ?? allNodes.Sum(n => n.Files.Count);
		var scannedAt = rootMeta?.ScannedAt ?? DateTimeOffset.UtcNow;
		var exportedAt = DateTimeOffset.UtcNow;
		var displayRoot = Redact(root, redactPaths);

		// Aggregate file types for donut chart
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

		var svgChartHtml = GenerateSvgDonutChart(categoryTotals, totalBytes);

		await writer.WriteLineAsync($$"""
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>GS System Analyzer — Scan Report [{{displayRoot}}]</title>
<style>
  :root {
    --bg-dark: #0a0e17;
    --bg-panel: #121824;
    --bg-card: #182234;
    --accent-cyan: #00f0ff;
    --accent-green: #00ff9d;
    --accent-amber: #ffb800;
    --accent-red: #ff3864;
    --text-primary: #e2e8f0;
    --text-dim: #94a3b8;
    --border-color: #1e293b;
    --font-mono: 'Consolas', 'Courier New', monospace;
    --font-sans: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
  }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    background-color: var(--bg-dark);
    color: var(--text-primary);
    font-family: var(--font-sans);
    padding: 24px;
    line-height: 1.5;
  }
  header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    border-bottom: 2px solid var(--border-color);
    padding-bottom: 16px;
    margin-bottom: 24px;
  }
  .title-group h1 {
    color: var(--accent-cyan);
    font-size: 24px;
    letter-spacing: 1.5px;
    font-family: var(--font-mono);
  }
  .title-group p {
    color: var(--text-dim);
    font-size: 13px;
    margin-top: 4px;
  }
  .badge {
    background-color: var(--bg-card);
    border: 1px solid var(--accent-cyan);
    color: var(--accent-cyan);
    padding: 6px 12px;
    border-radius: 4px;
    font-family: var(--font-mono);
    font-size: 12px;
    font-weight: bold;
  }
  .grid-summary {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
    gap: 16px;
    margin-bottom: 24px;
  }
  .card {
    background-color: var(--bg-panel);
    border: 1px solid var(--border-color);
    border-radius: 6px;
    padding: 16px;
  }
  .card-label {
    color: var(--text-dim);
    font-size: 11px;
    letter-spacing: 1px;
    text-transform: uppercase;
    font-family: var(--font-mono);
  }
  .card-value {
    color: var(--accent-cyan);
    font-size: 22px;
    font-weight: bold;
    font-family: var(--font-mono);
    margin-top: 6px;
  }
  .section-title {
    color: var(--text-primary);
    font-size: 16px;
    letter-spacing: 1px;
    font-family: var(--font-mono);
    margin-bottom: 12px;
    border-left: 3px solid var(--accent-cyan);
    padding-left: 8px;
  }
  .chart-layout {
    display: flex;
    flex-wrap: wrap;
    gap: 24px;
    align-items: center;
    margin-bottom: 24px;
  }
  .chart-container {
    flex: 1;
    min-width: 280px;
    max-width: 380px;
    display: flex;
    justify-content: center;
  }
  .chart-legend {
    flex: 2;
    min-width: 320px;
  }
  table {
    width: 100%;
    border-collapse: collapse;
    font-size: 13px;
    font-family: var(--font-mono);
  }
  th {
    background-color: var(--bg-card);
    color: var(--accent-cyan);
    text-align: left;
    padding: 10px;
    border-bottom: 1px solid var(--border-color);
  }
  td {
    padding: 8px 10px;
    border-bottom: 1px solid var(--border-color);
  }
  tr:hover td {
    background-color: rgba(0, 240, 255, 0.03);
  }
  .text-right { text-align: right; }
  .dot {
    display: inline-block;
    width: 10px;
    height: 10px;
    border-radius: 50%;
    margin-right: 8px;
  }
  footer {
    margin-top: 32px;
    padding-top: 16px;
    border-top: 1px solid var(--border-color);
    color: var(--text-dim);
    font-size: 11px;
    text-align: center;
    font-family: var(--font-mono);
  }
</style>
</head>
<body>
<header>
  <div class="title-group">
    <h1>SCAN_REPORT // {{displayRoot}}</h1>
    <p>GS System Analyzer v2.0 • Scanned: {{scannedAt:yyyy-MM-dd HH:mm:ss}} UTC • Exported: {{exportedAt:yyyy-MM-dd HH:mm:ss}} UTC</p>
  </div>
  <div class="badge">CYBER-HUD OFFLINE REPORT</div>
</header>

<div class="grid-summary">
  <div class="card">
    <div class="card-label">ROOT TARGET</div>
    <div class="card-value">{{displayRoot}}</div>
  </div>
  <div class="card">
    <div class="card-label">TOTAL SIZE</div>
    <div class="card-value">{{FormatBytes(totalBytes)}}</div>
  </div>
  <div class="card">
    <div class="card-label">TOTAL FILES</div>
    <div class="card-value">{{totalFiles:N0}}</div>
  </div>
  <div class="card">
    <div class="card-label">DIRECTORY NODES</div>
    <div class="card-value">{{allNodes.Count:N0}}</div>
  </div>
</div>

<div class="card" style="margin-bottom: 24px;">
  <div class="section-title">FILE TYPE ANALYTICS</div>
  <div class="chart-layout">
    <div class="chart-container">
      {{svgChartHtml}}
    </div>
    <div class="chart-legend">
      <table>
        <thead>
          <tr>
            <th>CATEGORY</th>
            <th class="text-right">FILES</th>
            <th class="text-right">SIZE</th>
            <th class="text-right">% TOTAL</th>
          </tr>
        </thead>
        <tbody>
""");

		var colors = new Dictionary<string, string>
		{
			["media"] = "#00f0ff",
			["documents"] = "#00ff9d",
			["code"] = "#a78bfa",
			["executables"] = "#ff3864",
			["archives"] = "#ffb800",
			["system"] = "#38bdf8",
			["other"] = "#64748b"
		};

		foreach (var kvp in categoryTotals.OrderByDescending(c => c.Value.bytes))
		{
			if (kvp.Value.count == 0 && kvp.Value.bytes == 0) continue;
			var pct = totalBytes > 0 ? (double)kvp.Value.bytes / totalBytes * 100.0 : 0.0;
			var col = colors.TryGetValue(kvp.Key, out var c) ? c : "#64748b";

			await writer.WriteLineAsync($$"""
          <tr>
            <td><span class="dot" style="background-color: {{col}};"></span>{{kvp.Key.ToUpperInvariant()}}</td>
            <td class="text-right">{{kvp.Value.count:N0}}</td>
            <td class="text-right">{{FormatBytes(kvp.Value.bytes)}}</td>
            <td class="text-right">{{pct:F1}}%</td>
          </tr>
""");
		}

		await writer.WriteLineAsync("""
        </tbody>
      </table>
    </div>
  </div>
</div>

<div class="card">
  <div class="section-title">TOP DIRECTORIES</div>
  <table>
    <thead>
      <tr>
        <th>PATH</th>
        <th class="text-right">FILES</th>
        <th class="text-right">OWN SIZE</th>
        <th class="text-right">RECURSIVE SIZE</th>
      </tr>
    </thead>
    <tbody>
""");

		foreach (var node in allNodes.OrderByDescending(n => n.RecursiveBytes).Take(100))
		{
			var p = Redact(node.Path, redactPaths);
			await writer.WriteLineAsync($$"""
      <tr>
        <td>{{HtmlEscape(p)}}</td>
        <td class="text-right">{{node.Files.Count:N0}}</td>
        <td class="text-right">{{FormatBytes(node.OwnBytes)}}</td>
        <td class="text-right">{{FormatBytes(node.RecursiveBytes)}}</td>
      </tr>
""");
		}

		await writer.WriteLineAsync($$"""
    </tbody>
  </table>
</div>

<footer>
  GS System Analyzer • Non-intrusive local telemetry & disk diagnostics • Report generated fully offline with zero network egress.
</footer>
</body>
</html>
""");

		await writer.FlushAsync(ct);
	}

	private static string GenerateSvgDonutChart(Dictionary<string, (long bytes, int count)> categories, long totalBytes)
	{
		var colors = new Dictionary<string, string>
		{
			["media"] = "#00f0ff",
			["documents"] = "#00ff9d",
			["code"] = "#a78bfa",
			["executables"] = "#ff3864",
			["archives"] = "#ffb800",
			["system"] = "#38bdf8",
			["other"] = "#64748b"
		};

		if (totalBytes <= 0)
		{
			return """
<svg width="240" height="240" viewBox="0 0 240 240">
  <circle cx="120" cy="120" r="90" fill="none" stroke="#1e293b" stroke-width="30"/>
  <text x="120" y="125" text-anchor="middle" fill="#94a3b8" font-family="monospace" font-size="12">NO DATA</text>
</svg>
""";
		}

		var cx = 120.0;
		var cy = 120.0;
		var r = 85.0;
		var strokeWidth = 30.0;
		var circumference = 2.0 * Math.PI * r;

		var sb = new StringBuilder();
		sb.AppendLine("""<svg width="240" height="240" viewBox="0 0 240 240">""");
		sb.AppendLine($"""  <circle cx="{cx}" cy="{cy}" r="{r}" fill="none" stroke="#121824" stroke-width="{strokeWidth}"/>""");

		var currentOffset = 0.0;
		foreach (var kvp in categories.OrderByDescending(c => c.Value.bytes))
		{
			if (kvp.Value.bytes <= 0) continue;
			var fraction = (double)kvp.Value.bytes / totalBytes;
			var dashLength = fraction * circumference;
			var col = colors.TryGetValue(kvp.Key, out var c) ? c : "#64748b";

			// SVG stroke-dasharray="dash, circumference" and stroke-dashoffset="-currentOffset"
			// Rotated -90 degrees so 0 starts at top
			sb.AppendLine(
				string.Format(CultureInfo.InvariantCulture,
					@"  <circle cx=""{0}"" cy=""{1}"" r=""{2}"" fill=""none"" stroke=""{3}"" stroke-width=""{4}"" stroke-dasharray=""{5:F2} {6:F2}"" stroke-dashoffset=""{7:F2}"" transform=""rotate(-90 {0} {1})""/>",
					cx, cy, r, col, strokeWidth, dashLength, circumference, -currentOffset));

			currentOffset += dashLength;
		}

		sb.AppendLine($"""  <text x="{cx}" y="{cy - 5}" text-anchor="middle" fill="#00f0ff" font-family="monospace" font-size="14" font-weight="bold">TOTAL</text>""");
		sb.AppendLine($"""  <text x="{cx}" y="{cy + 15}" text-anchor="middle" fill="#e2e8f0" font-family="monospace" font-size="11">{FormatBytes(totalBytes)}</text>""");
		sb.AppendLine("</svg>");

		return sb.ToString();
	}

	private static string HtmlEscape(string input)
	{
		return input
			.Replace("&", "&amp;")
			.Replace("<", "&lt;")
			.Replace(">", "&gt;")
			.Replace("\"", "&quot;")
			.Replace("'", "&#39;");
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
