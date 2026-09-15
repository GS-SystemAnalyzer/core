using System.Collections.Generic;
using System.Threading.Tasks;
using GSSystemAnalyzer.Models;

namespace GSSystemAnalyzer.Interfaces;

public interface IAutomationAuditService
{
	Task AppendEntryAsync(AutomationAuditEntry entry);
	Task<List<AutomationAuditEntry>> GetEntriesAsync(int days = 30);
	Task PruneOldEntriesAsync(int retentionDays = 90);
}
