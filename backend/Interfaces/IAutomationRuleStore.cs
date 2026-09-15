using System.Collections.Generic;
using GSSystemAnalyzer.Models;

namespace GSSystemAnalyzer.Interfaces;

public interface IAutomationRuleStore
{
	List<AutomationRule> LoadAll();
	void SaveAll(List<AutomationRule> rules);
}
