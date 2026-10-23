using System;
using System.IO;
using System.Runtime.Versioning;
using System.Threading;
using GSSystemAnalyzer.Interfaces;
using Microsoft.VisualBasic.FileIO;

namespace GSSystemAnalyzer.Services
{
	[SupportedOSPlatform("windows")]
	public class WindowsRecycleBinProvider : IRecycleBinProvider
	{
		public void SendFileToRecycleBin(string path)
		{
			if (!OperatingSystem.IsWindows())
			{
				throw new PlatformNotSupportedException("Windows Recycle Bin is only supported on Windows.");
			}

			var attributes = File.GetAttributes(path);
			if ((attributes & FileAttributes.ReadOnly) != 0)
			{
				File.SetAttributes(path, attributes & ~FileAttributes.ReadOnly);
			}

			FileSystem.DeleteFile(path, UIOption.OnlyErrorDialogs, RecycleOption.SendToRecycleBin, UICancelOption.ThrowException);
		}

		public void SendDirectoryToRecycleBin(string path)
		{
			if (!OperatingSystem.IsWindows())
			{
				throw new PlatformNotSupportedException("Windows Recycle Bin is only supported on Windows.");
			}

			var dir = new DirectoryInfo(path);
			foreach (var info in dir.GetFileSystemInfos("*", System.IO.SearchOption.AllDirectories))
			{
				if ((info.Attributes & FileAttributes.ReadOnly) != 0)
				{
					info.Attributes &= ~FileAttributes.ReadOnly;
				}
			}
			if ((dir.Attributes & FileAttributes.ReadOnly) != 0)
			{
				dir.Attributes &= ~FileAttributes.ReadOnly;
			}

			FileSystem.DeleteDirectory(path, UIOption.OnlyErrorDialogs, RecycleOption.SendToRecycleBin, UICancelOption.ThrowException);
		}

		public bool TryRestore(string originalPath)
		{
			if (!OperatingSystem.IsWindows()) return false;

			bool restored = false;
			var thread = new Thread(() =>
			{
				try
				{
					Type? shellType = Type.GetTypeFromProgID("Shell.Application");
					if (shellType == null) return;

					dynamic? shell = Activator.CreateInstance(shellType);
					if (shell == null) return;

					dynamic? bin = shell.NameSpace(10); // ssfBITBUCKET
					if (bin == null) return;

					var targetName = Path.GetFileName(originalPath);
					var targetNameWithoutExt = Path.GetFileNameWithoutExtension(originalPath);

					foreach (dynamic item in bin.Items())
					{
						string itemName = item.Name;
						string itemPath = item.Path;

						if (itemName.Equals(targetName, StringComparison.OrdinalIgnoreCase) ||
							itemName.Equals(targetNameWithoutExt, StringComparison.OrdinalIgnoreCase) ||
							itemPath.Equals(originalPath, StringComparison.OrdinalIgnoreCase))
						{
							foreach (dynamic verb in item.Verbs())
							{
								string verbName = verb.Name;
								var cleaned = verbName.Replace("&", "");
								if (cleaned.Equals("Restore", StringComparison.OrdinalIgnoreCase) ||
									cleaned.Equals("Undelete", StringComparison.OrdinalIgnoreCase) ||
									cleaned.Equals("Restaurer", StringComparison.OrdinalIgnoreCase) ||
									cleaned.Equals("Wiederherstellen", StringComparison.OrdinalIgnoreCase))
								{
									verb.DoIt();
									restored = true;
									return;
								}
							}
						}
					}
				}
				catch
				{
					// Ignore COM errors
				}
			});

			thread.SetApartmentState(ApartmentState.STA);
			thread.Start();
			thread.Join(3000);

			return restored;
		}
	}
}
