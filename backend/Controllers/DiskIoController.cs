using GSSystemAnalyzer.Interfaces;
using GSSystemAnalyzer.Models;
using Microsoft.AspNetCore.Mvc;

namespace GSSystemAnalyzer.Controllers
{
	[ApiController]
	[Route("api/[controller]")]
	public class DiskIoController : ControllerBase
	{
		private readonly IDiskIoEngine _diskIoEngine;

		public DiskIoController(IDiskIoEngine diskIoEngine)
		{
			_diskIoEngine = diskIoEngine;
		}

		/// <summary>
		/// GET /api/diskio
		/// Returns the current DiskIoSnapshotCollection with per-physical-disk throughput, queue length, and session totals.
		/// </summary>
		[HttpGet]
		public IActionResult GetDiskIo()
		{
			var snapshot = _diskIoEngine.GetCurrentSnapshot();
			return Ok(snapshot);
		}
	}
}
