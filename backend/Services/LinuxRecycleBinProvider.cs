using System;
using System.IO;
using GSSystemAnalyzer.Interfaces;

namespace GSSystemAnalyzer.Services
{
	public class LinuxRecycleBinProvider : IRecycleBinProvider
	{
		private readonly string _trashFilesDir;
		private readonly string _trashInfoDir;

		public LinuxRecycleBinProvider()
		{
			var homeDir = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
			var xdgDataHome = Environment.GetEnvironmentVariable("XDG_DATA_HOME");
			var trashBase = !string.IsNullOrEmpty(xdgDataHome)
				? Path.Combine(xdgDataHome, "Trash")
				: Path.Combine(homeDir, ".local", "share", "Trash");

			_trashFilesDir = Path.Combine(trashBase, "files");
			_trashInfoDir = Path.Combine(trashBase, "info");
		}

		public void SendFileToRecycleBin(string path)
		{
			MoveToTrash(path, isDirectory: false);
		}

		public void SendDirectoryToRecycleBin(string path)
		{
			MoveToTrash(path, isDirectory: true);
		}

		public bool TryRestore(string originalPath)
		{
			if (!Directory.Exists(_trashInfoDir) || !Directory.Exists(_trashFilesDir))
				return false;

			var fullPath = Path.GetFullPath(originalPath);
			var escapedPath = Uri.EscapeDataString(fullPath);

			foreach (var infoFile in Directory.EnumerateFiles(_trashInfoDir, "*.trashinfo"))
			{
				try
				{
					var lines = File.ReadAllLines(infoFile);
					bool matches = false;
					foreach (var line in lines)
					{
						if (line.StartsWith("Path=", StringComparison.OrdinalIgnoreCase))
						{
							var val = line.Substring(5).Trim();
							if (val.Equals(fullPath, StringComparison.OrdinalIgnoreCase) ||
								val.Equals(escapedPath, StringComparison.OrdinalIgnoreCase))
							{
								matches = true;
								break;
							}
						}
					}

					if (matches)
					{
						var baseName = Path.GetFileNameWithoutExtension(infoFile);
						var trashedFilePath = Path.Combine(_trashFilesDir, baseName);
						if (File.Exists(trashedFilePath))
						{
							var parentDir = Path.GetDirectoryName(originalPath);
							if (!string.IsNullOrEmpty(parentDir) && !Directory.Exists(parentDir))
								Directory.CreateDirectory(parentDir);

							File.Move(trashedFilePath, originalPath);
							File.Delete(infoFile);
							return true;
						}
						else if (Directory.Exists(trashedFilePath))
						{
							var parentDir = Path.GetDirectoryName(originalPath);
							if (!string.IsNullOrEmpty(parentDir) && !Directory.Exists(parentDir))
								Directory.CreateDirectory(parentDir);

							Directory.Move(trashedFilePath, originalPath);
							File.Delete(infoFile);
							return true;
						}
					}
				}
				catch
				{
					// Ignore access exceptions while reading trashinfo
				}
			}

			return false;
		}

		private void MoveToTrash(string path, bool isDirectory)
		{
			Directory.CreateDirectory(_trashFilesDir);
			Directory.CreateDirectory(_trashInfoDir);

			var fileName = Path.GetFileName(path.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar));
			var destFilePath = Path.Combine(_trashFilesDir, fileName);
			var infoFilePath = Path.Combine(_trashInfoDir, fileName + ".trashinfo");

			int suffix = 1;
			while (File.Exists(destFilePath) || Directory.Exists(destFilePath) || File.Exists(infoFilePath))
			{
				var uniqueName = $"{fileName}.{suffix}";
				destFilePath = Path.Combine(_trashFilesDir, uniqueName);
				infoFilePath = Path.Combine(_trashInfoDir, uniqueName + ".trashinfo");
				suffix++;
			}

			var fullPath = Path.GetFullPath(path);
			var deletionDate = DateTime.Now.ToString("yyyy-MM-ddTHH:mm:ss");
			var trashInfoContent = $"[Trash Info]\nPath={Uri.EscapeDataString(fullPath)}\nDeletionDate={deletionDate}\n";

			File.WriteAllText(infoFilePath, trashInfoContent);

			if (isDirectory)
			{
				Directory.Move(path, destFilePath);
			}
			else
			{
				File.Move(path, destFilePath);
			}
		}
	}
}
