using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;

namespace GSSystemAnalyzer.Models;

/// <summary>
/// Central registry of discoverable temporary and cache directories.
/// Single source of truth for TempFolderCleanerService and related diagnostics.
/// </summary>
public static class TempFolderDictionary
{
	public static List<CleanTarget> ResolveCleanTargets()
	{
		var raw = new List<CleanTarget>();

		void Add(string label, CleanCategory cat, params string[] parts)
		{
			if (parts.Any(string.IsNullOrWhiteSpace)) return;
			raw.Add(new CleanTarget(Path.Combine(parts), label, cat));
		}

		if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
		{
			var local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
			var roaming = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
			var profile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
			var programData = Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData);
			var winDir = Environment.GetEnvironmentVariable("SystemRoot") ?? @"C:\Windows";

			// ---- Standard & System Temp ----
			raw.Add(new CleanTarget(Path.GetTempPath(), "User temp", CleanCategory.Temp));
			Add("User temp (Local)", CleanCategory.Temp, local, "Temp");
			Add("System temp", CleanCategory.Temp, winDir, "Temp");
			Add("Legacy temp", CleanCategory.Temp, @"C:\Temp");
			Add("OneDrive temp", CleanCategory.Temp, profile, "OneDriveTemp");

			// ---- Crash Dumps & Error Reporting ----
			Add("Crash Dumps", CleanCategory.Temp, local, "CrashDumps");
			Add("WER Report Archive", CleanCategory.Temp, programData, "Microsoft", "Windows", "WER", "ReportArchive");
			Add("WER Report Queue", CleanCategory.Temp, programData, "Microsoft", "Windows", "WER", "ReportQueue");
			Add("WER Temp", CleanCategory.Temp, programData, "Microsoft", "Windows", "WER", "Temp");

			// ---- Developer & Package Manager Caches (safe: regenerated on demand) ----
			Add("npm cache", CleanCategory.Cache, local, "npm-cache");
			Add("npm cache", CleanCategory.Cache, roaming, "npm-cache");
			Add("Yarn cache", CleanCategory.Cache, local, "Yarn", "Cache");
			Add("pip cache", CleanCategory.Cache, local, "pip", "Cache");
			Add("NuGet HTTP cache", CleanCategory.Cache, local, "NuGet", "v3-cache");
			Add("Gradle cache", CleanCategory.Cache, profile, ".gradle", "caches");
			Add("Gradle cache (Android)", CleanCategory.Cache, @"C:\Android\.gradle\caches");
			Add("Pub cache", CleanCategory.Cache, local, "Pub", "Cache");
			Add("Pub cache (Android)", CleanCategory.Cache, @"C:\Android\.pub-cache");
			Add("Dart analysis cache", CleanCategory.Cache, local, ".dartServer", ".analysis-driver");
			Add("Roslyn compiler cache", CleanCategory.Cache, local, "Microsoft", "VisualStudio", "Roslyn", "Cache");

			// ---- Engine & Build Caches ----
			Add("Unity Bee cache", CleanCategory.Cache, local, "Unity", "Caches", "bee");
			Add("Unity package cache", CleanCategory.Cache, local, "Unity", "cache", "packages");

			// ---- Graphics & System Component Caches ----
			Add("Direct3D shader cache", CleanCategory.Cache, local, "D3DSCache");
			Add("Windows INetCache", CleanCategory.Cache, local, "Microsoft", "Windows", "INetCache");

			// ---- Browser Caches (locked while browser runs -> skipped safely) ----
			Add("Chrome cache", CleanCategory.Cache, local, "Google", "Chrome", "User Data", "Default", "Cache");
			Add("Edge cache", CleanCategory.Cache, local, "Microsoft", "Edge", "User Data", "Default", "Cache");

			// Firefox keeps one cache2 folder per profile — expand dynamically.
			var ffProfiles = Path.Combine(local, "Mozilla", "Firefox", "Profiles");
			if (Directory.Exists(ffProfiles))
			{
				foreach (var p in Directory.GetDirectories(ffProfiles))
				{
					Add($"Firefox cache ({Path.GetFileName(p)})", CleanCategory.Cache, p, "cache2");
				}
			}
		}
		else
		{
			// Linux / macOS
			var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
			raw.Add(new CleanTarget(Path.GetTempPath(), "User temp", CleanCategory.Temp));
			Add("XDG cache", CleanCategory.Cache, home, ".cache");
			Add("npm cache", CleanCategory.Cache, home, ".npm", "_cacache");
			raw.Add(new CleanTarget("/tmp", "System temp", CleanCategory.Temp));
			raw.Add(new CleanTarget("/var/tmp", "System temp", CleanCategory.Temp));
		}

		var comparer = RuntimeInformation.IsOSPlatform(OSPlatform.Windows)
			? StringComparer.OrdinalIgnoreCase : StringComparer.Ordinal;

		// Normalize -> keep existing only -> de-dupe by path (first label wins).
		var seen = new HashSet<string>(comparer);
		var result = new List<CleanTarget>();
		foreach (var t in raw)
		{
			string full;
			try { full = Path.GetFullPath(t.Path).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar); } catch { continue; }
			if (!seen.Add(full)) continue;
			if (!Directory.Exists(full)) continue;
			result.Add(t with { Path = full });
		}
		return result;
	}

	/// <summary>Back-compat whitelist shim: returns string paths only.</summary>
	public static List<string> ResolveTempPaths() =>
		ResolveCleanTargets().Select(t => t.Path).ToList();
}
