using System.Collections.Generic;
using System.Threading.Tasks;
using GSSystemAnalyzer.Models;

namespace GSSystemAnalyzer.Interfaces
{
	public interface IDiskIoReader
	{
		Task<IReadOnlyList<DiskIoRawSample>> ReadSamplesAsync();
	}
}
