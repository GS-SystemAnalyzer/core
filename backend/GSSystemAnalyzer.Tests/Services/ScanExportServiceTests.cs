using System.Text;
using System.Text.Json;
using GSSystemAnalyzer.Interfaces;
using GSSystemAnalyzer.Models;
using GSSystemAnalyzer.Models.SettingDtos;
using GSSystemAnalyzer.Services;
using Moq;
using Xunit;

namespace GSSystemAnalyzer.Tests.Services;

public class ScanExportServiceTests
{
	private readonly Mock<IScanCacheService> _mockCache;
	private readonly Mock<ISettingService> _mockSettings;
	private readonly ScanExportService _exportService;

	public ScanExportServiceTests()
	{
		_mockCache = new Mock<IScanCacheService>();
		_mockSettings = new Mock<ISettingService>();
		_mockSettings.Setup(s => s.Current).Returns(new AppSettingDto());
		_exportService = new ScanExportService(_mockCache.Object, _mockSettings.Object);
	}

	[Theory]
	[InlineData("=cmd|'/c calc'!A1.txt", "'=cmd|'/c calc'!A1.txt")]
	[InlineData("+calc.exe", "'+calc.exe")]
	[InlineData("-test.log", "'-test.log")]
	[InlineData("@macro.xlsm", "'@macro.xlsm")]
	[InlineData("\tleadingtab.txt", "'\tleadingtab.txt")]
	[InlineData("\rleadingcr.txt", "\"'\rleadingcr.txt\"")]
	[InlineData("normal_file.txt", "normal_file.txt")]
	public void EscapeCsvField_NeutralizesFormulaInjectionPrefixes(string input, string expected)
	{
		var result = ScanExportService.EscapeCsvField(input);
		Assert.Equal(expected, result);
	}

	[Fact]
	public void EscapeCsvField_QuotesAndDoublesQuotesOnCommasAndQuotes()
	{
		var input = "report, \"Q3\" 2026.csv";
		var result = ScanExportService.EscapeCsvField(input);

		// Must be wrapped in quotes and internal quotes doubled
		Assert.Equal("\"report, \"\"Q3\"\" 2026.csv\"", result);
	}

	[Fact]
	public void EscapeCsvField_HandlesFormulaWithCommaAndQuote()
	{
		var input = "=cmd|'/c calc',A1.txt";
		var result = ScanExportService.EscapeCsvField(input);

		// Prefixed with ' and wrapped in quotes because it contains a comma
		Assert.Equal("\"'=cmd|'/c calc',A1.txt\"", result);
	}

	[Fact]
	public async Task ExportCsvAsync_IncludesHeader_AndDepthColumn_AndRows()
	{
		var root = @"C:\Data";
		var rootMeta = new ScanRootMeta(root, 3, DateTimeOffset.UtcNow, 2048, 2, root);
		_mockCache.Setup(c => c.GetScanRoot(root, null)).Returns(rootMeta);
		_mockCache.Setup(c => c.HasScanRoot(root)).Returns(true);

		var file1 = new CachedFileEntry("normal.txt", ".txt", 1024, DateTime.UtcNow);
		var file2 = new CachedFileEntry("=dangerous.exe", ".exe", 1024, DateTime.UtcNow);

		var dir1 = new CachedDirNode(root, new[] { @"C:\Data\Sub" }, new[] { file1, file2 }, 2048, 2048, DateTimeOffset.UtcNow, false);
		var dir2 = new CachedDirNode(@"C:\Data\Sub", Array.Empty<string>(), Array.Empty<CachedFileEntry>(), 0, 0, DateTimeOffset.UtcNow, false);

		_mockCache.Setup(c => c.GetNodesUnderRoot(root)).Returns(new[] { dir1, dir2 });

		using var ms = new MemoryStream();
		await _exportService.ExportAsync(root, "csv", false, ms);

		var csv = Encoding.UTF8.GetString(ms.ToArray());
		var lines = csv.Split(new[] { "\r\n", "\n" }, StringSplitOptions.RemoveEmptyEntries);

		Assert.True(lines.Length >= 4);
		Assert.Equal("path,name,isDirectory,sizeBytes,sizeFormatted,extension,category,lastModified,depth", lines[0]);

		// Check depth
		// dir1 depth: 0
		Assert.Contains(",0", lines[1]);
		// file rows depth: 1
		Assert.Contains(",1", lines[2]);
		// dir2 depth: 1
		Assert.Contains(@"C:\Data\Sub", csv);

		// Formula injection prevented in file row
		Assert.Contains("=dangerous.exe", csv);
		Assert.Contains("'=dangerous.exe", csv);
	}

	[Fact]
	public async Task ExportJsonAsync_ContainsEnvelope_AndPreservesTreeNesting()
	{
		var root = @"C:\Data";
		var rootMeta = new ScanRootMeta(root, 2, DateTimeOffset.UtcNow, 5000, 1, root);
		_mockCache.Setup(c => c.GetScanRoot(root, null)).Returns(rootMeta);
		_mockCache.Setup(c => c.HasScanRoot(root)).Returns(true);

		var file = new CachedFileEntry("sample.cs", ".cs", 5000, DateTime.UtcNow);
		var subNode = new CachedDirNode(@"C:\Data\Sub", Array.Empty<string>(), new[] { file }, 5000, 5000, DateTimeOffset.UtcNow, false);
		var rootNode = new CachedDirNode(root, new[] { @"C:\Data\Sub" }, Array.Empty<CachedFileEntry>(), 0, 5000, DateTimeOffset.UtcNow, false);

		_mockCache.Setup(c => c.GetNodesUnderRoot(root)).Returns(new[] { rootNode, subNode });

		using var ms = new MemoryStream();
		await _exportService.ExportAsync(root, "json", false, ms);

		var json = Encoding.UTF8.GetString(ms.ToArray());
		using var doc = JsonDocument.Parse(json);
		var rootElem = doc.RootElement;

		Assert.Equal(root, rootElem.GetProperty("root").GetString());
		Assert.Equal("2.0.0", rootElem.GetProperty("appVersion").GetString());
		Assert.Equal(5000, rootElem.GetProperty("totalBytes").GetInt64());
		Assert.True(rootElem.TryGetProperty("scannedAt", out _));
		Assert.True(rootElem.TryGetProperty("exportedAt", out _));

		var tree = rootElem.GetProperty("tree");
		Assert.Equal(root, tree.GetProperty("path").GetString());
		var directories = tree.GetProperty("directories");
		Assert.Equal(1, directories.GetArrayLength());

		var subDir = directories[0];
		Assert.Equal(@"C:\Data\Sub", subDir.GetProperty("path").GetString());
		var files = subDir.GetProperty("files");
		Assert.Equal(1, files.GetArrayLength());
		Assert.Equal("sample.cs", files[0].GetProperty("name").GetString());
		Assert.Equal("code", files[0].GetProperty("category").GetString());
	}

	[Fact]
	public async Task ExportHtmlAsync_IsOfflineSelfContained_WithInlineSvgAndCyberHudTheme()
	{
		var root = @"C:\Data";
		var rootMeta = new ScanRootMeta(root, 2, DateTimeOffset.UtcNow, 10240, 2, root);
		_mockCache.Setup(c => c.GetScanRoot(root, null)).Returns(rootMeta);
		_mockCache.Setup(c => c.HasScanRoot(root)).Returns(true);

		var file1 = new CachedFileEntry("song.mp3", ".mp3", 6000, DateTime.UtcNow);
		var file2 = new CachedFileEntry("doc.pdf", ".pdf", 4240, DateTime.UtcNow);
		var dir = new CachedDirNode(root, Array.Empty<string>(), new[] { file1, file2 }, 10240, 10240, DateTimeOffset.UtcNow, false);
		_mockCache.Setup(c => c.GetNodesUnderRoot(root)).Returns(new[] { dir });

		using var ms = new MemoryStream();
		await _exportService.ExportAsync(root, "html", false, ms);

		var html = Encoding.UTF8.GetString(ms.ToArray());

		// Self contained checks
		Assert.Contains("<!DOCTYPE html>", html);
		Assert.Contains("<svg width=\"240\" height=\"240\"", html);
		Assert.Contains("CYBER-HUD OFFLINE REPORT", html);
		Assert.Contains("--accent-cyan: #00f0ff", html);
		Assert.Contains("MEDIA", html);
		Assert.Contains("DOCUMENTS", html);

		// Verify zero external network references
		Assert.DoesNotContain("http://", html);
		Assert.DoesNotContain("https://", html);
	}

	[Fact]
	public async Task ExportAsync_WithRedactPathsTrue_ReplacesUserProfileWithTilde()
	{
		var userProfile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
		var root = userProfile;
		var rootMeta = new ScanRootMeta(root, 1, DateTimeOffset.UtcNow, 100, 1, root);
		_mockCache.Setup(c => c.GetScanRoot(root, null)).Returns(rootMeta);
		_mockCache.Setup(c => c.HasScanRoot(root)).Returns(true);

		var file = new CachedFileEntry("test.txt", ".txt", 100, DateTime.UtcNow);
		var dir = new CachedDirNode(root, Array.Empty<string>(), new[] { file }, 100, 100, DateTimeOffset.UtcNow, false);
		_mockCache.Setup(c => c.GetNodesUnderRoot(root)).Returns(new[] { dir });

		using var ms = new MemoryStream();
		await _exportService.ExportAsync(root, "json", redactPaths: true, ms);

		var json = Encoding.UTF8.GetString(ms.ToArray());
		using var doc = JsonDocument.Parse(json);
		var rootElem = doc.RootElement;

		Assert.Equal("~", rootElem.GetProperty("root").GetString());
		var tree = rootElem.GetProperty("tree");
		Assert.Equal("~", tree.GetProperty("path").GetString());
		var files = tree.GetProperty("files");
		var filePath = files[0].GetProperty("path").GetString();
		Assert.StartsWith("~", filePath!);
		Assert.DoesNotContain(userProfile, filePath);
	}

	[Fact]
	public async Task ExportJsonAsync_SynthesizesRootNode_WhenRootNodeAbsentFromCache()
	{
		var root = @"C:\Data";
		var rootMeta = new ScanRootMeta(root, 2, DateTimeOffset.UtcNow, 8000, 2, root);
		_mockCache.Setup(c => c.GetScanRoot(root, null)).Returns(rootMeta);
		_mockCache.Setup(c => c.HasScanRoot(root)).Returns(true);

		// Only subnodes exist in cache — root "C:\Data" node itself was not cached
		var subNode1 = new CachedDirNode(@"C:\Data\Sub1", Array.Empty<string>(), Array.Empty<CachedFileEntry>(), 4000, 4000, DateTimeOffset.UtcNow, false);
		var subNode2 = new CachedDirNode(@"C:\Data\Sub2", Array.Empty<string>(), Array.Empty<CachedFileEntry>(), 4000, 4000, DateTimeOffset.UtcNow, false);
		_mockCache.Setup(c => c.GetNodesUnderRoot(root)).Returns(new[] { subNode1, subNode2 });

		using var ms = new MemoryStream();
		await _exportService.ExportAsync(root, "json", false, ms);

		var json = Encoding.UTF8.GetString(ms.ToArray());
		using var doc = JsonDocument.Parse(json);
		var rootElem = doc.RootElement;

		// Verify tree is rooted at C:\Data, not defaulting to C:\Data\Sub1
		var tree = rootElem.GetProperty("tree");
		Assert.Equal(root, tree.GetProperty("path").GetString());
		var directories = tree.GetProperty("directories");
		Assert.Equal(2, directories.GetArrayLength());
	}
}
