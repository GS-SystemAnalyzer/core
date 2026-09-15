namespace GSSystemAnalyzer.Models;

/// <summary>
/// Authoritative dictionary mapping file extensions to broad categories
/// (media, documents, executables, archives, code, system, other).
/// Centralized single source of truth for FileTypeScanner, ScanExportService, and analytics.
/// </summary>
public static class FileCategoryDictionary
{
	public const string Media = "media";
	public const string Documents = "documents";
	public const string Executables = "executables";
	public const string Archives = "archives";
	public const string Code = "code";
	public const string System = "system";
	public const string Other = "other";

	public static readonly IReadOnlyList<string> AllCategories = new[]
	{
		Media, Documents, Executables, Archives, Code, System, Other
	};

	public static readonly IReadOnlyDictionary<string, string> ExtensionMap = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
	{
		// Media (Video, Audio, Images)
		[".mp4"] = Media,
		[".mkv"] = Media,
		[".avi"] = Media,
		[".mov"] = Media,
		[".wmv"] = Media,
		[".flv"] = Media,
		[".webm"] = Media,
		[".m4v"] = Media,
		[".3gp"] = Media,
		[".mp3"] = Media,
		[".flac"] = Media,
		[".wav"] = Media,
		[".aac"] = Media,
		[".ogg"] = Media,
		[".wma"] = Media,
		[".m4a"] = Media,
		[".opus"] = Media,
		[".jpg"] = Media,
		[".jpeg"] = Media,
		[".png"] = Media,
		[".gif"] = Media,
		[".bmp"] = Media,
		[".svg"] = Media,
		[".webp"] = Media,
		[".heic"] = Media,
		[".raw"] = Media,
		[".ico"] = Media,
		[".tiff"] = Media,
		[".tif"] = Media,

		// Documents
		[".pdf"] = Documents,
		[".doc"] = Documents,
		[".docx"] = Documents,
		[".xls"] = Documents,
		[".xlsx"] = Documents,
		[".ppt"] = Documents,
		[".pptx"] = Documents,
		[".txt"] = Documents,
		[".md"] = Documents,
		[".csv"] = Documents,
		[".odt"] = Documents,
		[".rtf"] = Documents,
		[".tex"] = Documents,
		[".epub"] = Documents,
		[".pages"] = Documents,
		[".numbers"] = Documents,
		[".key"] = Documents,

		// Executables
		[".exe"] = Executables,
		[".dll"] = Executables,
		[".msi"] = Executables,
		[".bat"] = Executables,
		[".cmd"] = Executables,
		[".sh"] = Executables,
		[".bin"] = Executables,
		[".app"] = Executables,
		[".deb"] = Executables,
		[".rpm"] = Executables,
		[".ps1"] = Executables,
		[".vbs"] = Executables,
		[".com"] = Executables,
		[".scr"] = Executables,

		// Archives
		[".zip"] = Archives,
		[".rar"] = Archives,
		[".7z"] = Archives,
		[".tar"] = Archives,
		[".gz"] = Archives,
		[".bz2"] = Archives,
		[".xz"] = Archives,
		[".iso"] = Archives,
		[".img"] = Archives,
		[".cab"] = Archives,
		[".tgz"] = Archives,
		[".dmg"] = Archives,
		[".pkg"] = Archives,

		// Code
		[".cs"] = Code,
		[".js"] = Code,
		[".ts"] = Code,
		[".jsx"] = Code,
		[".tsx"] = Code,
		[".py"] = Code,
		[".dart"] = Code,
		[".java"] = Code,
		[".cpp"] = Code,
		[".c"] = Code,
		[".h"] = Code,
		[".hpp"] = Code,
		[".go"] = Code,
		[".rs"] = Code,
		[".json"] = Code,
		[".xml"] = Code,
		[".yaml"] = Code,
		[".yml"] = Code,
		[".toml"] = Code,
		[".html"] = Code,
		[".htm"] = Code,
		[".css"] = Code,
		[".scss"] = Code,
		[".sass"] = Code,
		[".sql"] = Code,
		[".php"] = Code,
		[".rb"] = Code,
		[".swift"] = Code,
		[".kt"] = Code,
		[".kts"] = Code,
		[".lua"] = Code,
		[".r"] = Code,

		// System
		[".sys"] = System,
		[".ini"] = System,
		[".cfg"] = System,
		[".conf"] = System,
		[".log"] = System,
		[".tmp"] = System,
		[".dat"] = System,
		[".db"] = System,
		[".sqlite"] = System,
		[".lnk"] = System,
		[".bak"] = System,
		[".dmp"] = System,
	};

	/// <summary>
	/// Resolves an extension (e.g. ".mp4", "mp4", "") to its category.
	/// Defaults to "other" if unknown or empty.
	/// </summary>
	public static string GetCategory(string? extension)
	{
		if (string.IsNullOrWhiteSpace(extension)) return Other;
		var ext = extension.StartsWith('.') ? extension.ToLowerInvariant() : "." + extension.ToLowerInvariant();
		return ExtensionMap.TryGetValue(ext, out var cat) ? cat : Other;
	}
}
