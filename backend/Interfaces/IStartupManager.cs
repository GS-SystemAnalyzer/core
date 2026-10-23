using GSSystemAnalyzer.Models;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace GSSystemAnalyzer.Interfaces
{
    public interface IStartupManager
    {
        Task<IEnumerable<StartupProgramDto>> GetStartupEntriesAsync();
        Task ToggleStartupEntryAsync(string id, bool enable, string? scope = null);
        Task DeleteStartupEntryAsync(string id);
    }
}
