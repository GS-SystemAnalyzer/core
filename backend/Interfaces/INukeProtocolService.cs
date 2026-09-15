using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using GSSystemAnalyzer.Models;

namespace GSSystemAnalyzer.Interfaces
{
	public interface INukeProtocolService
	{
		Task<NukePreviewResponse> PreviewNukeAsync(List<string> paths, CancellationToken cancellationToken = default);
		Task<NukeResultDto> ObliterateNodeAsync(List<string> paths, string planToken, bool useRecycleBin = false, CancellationToken cancellationToken = default);
		void TriggerNukeAbort();
		bool IsNuking { get; }

		// Undo stack operations
		NukeOperation? PeekUndo();
		NukeResultDto? UndoNuke(string? operationId = null);
		List<NukeOperation> GetUndoHistory();
		void ClearUndoStack();
	}
}
