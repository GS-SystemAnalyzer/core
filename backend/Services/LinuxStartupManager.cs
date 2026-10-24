using System;
using System.Collections.Generic;
using System.IO;
using System.Threading.Tasks;
using GSSystemAnalyzer.Models;
using GSSystemAnalyzer.Interfaces;

namespace GSSystemAnalyzer.Services
{
    public class LinuxStartupManager : IStartupManager
    {
        private readonly string _autostartDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".config", "autostart");

        public async Task<IEnumerable<StartupProgramDto>> GetStartupEntriesAsync()
        {
            var entries = new List<StartupProgramDto>();

            if (!Directory.Exists(_autostartDir))
            {
                return entries;
            }

            var files = Directory.GetFiles(_autostartDir, "*.desktop");
            foreach (var file in files)
            {
                var lines = await File.ReadAllLinesAsync(file);

                string name = Path.GetFileNameWithoutExtension(file);
                string exec = string.Empty;
                bool isHidden = false;

                foreach (var line in lines)
                {
                    if (line.StartsWith("Name=")) name = line.Substring(5).Trim();
                    else if (line.StartsWith("Exec=")) exec = line.Substring(5).Trim();
                    else if (line.StartsWith("Hidden=")) isHidden = line.Equals("Hidden=true", StringComparison.OrdinalIgnoreCase);
                }

                string execPath = exec;
                string args = string.Empty;

                if (exec.StartsWith("\""))
                {
                    int closingQuoteIndex = exec.IndexOf('"', 1);
                    if (closingQuoteIndex > 0)
                    {
                        execPath = exec.Substring(1, closingQuoteIndex - 1);
                        args = exec.Substring(closingQuoteIndex + 1).Trim();
                    }
                }
                else
                {
                    int spaceIndex = exec.IndexOf(' ');
                    if (spaceIndex > 0)
                    {
                        execPath = exec.Substring(0, spaceIndex);
                        args = exec.Substring(spaceIndex + 1).Trim();
                    }
                }

                entries.Add(new StartupProgramDto
                {
                    Id = Path.GetFileName(file),
                    Name = name,
                    ExecutablePath = execPath,
                    Arguments = args,
                    IsEnabled = !isHidden,
                    Scope = "user",
                    Platform = "linux"
                });
            }

            return entries;
        }

        public async Task ToggleStartupEntryAsync(string id, bool enable, string? scope = null)
        {
            var filePath = Path.Combine(_autostartDir, id);
            if (!File.Exists(filePath)) return;

            var lines = new List<string>(await File.ReadAllLinesAsync(filePath));
            bool hiddenFound = false;

            for (int i = 0; i < lines.Count; i++)
            {
                if (lines[i].StartsWith("Hidden="))
                {
                    lines[i] = enable ? "Hidden=false" : "Hidden=true";
                    hiddenFound = true;
                    break;
                }
            }

            if (!hiddenFound && !enable)
            {
                lines.Add("Hidden=true");
            }
            else if (!hiddenFound && enable)
            {
                lines.Add("Hidden=false");
            }

            await File.WriteAllLinesAsync(filePath, lines);

        }

        public Task DeleteStartupEntryAsync(string id)
        {
            var filePath = Path.Combine(_autostartDir, id);
            if (File.Exists(filePath))
            {
                File.Delete(filePath);
            }
            return Task.CompletedTask;
        }
    }
}