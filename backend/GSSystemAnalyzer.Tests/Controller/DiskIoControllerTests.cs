using System;
using System.Collections.Generic;
using GSSystemAnalyzer.Controllers;
using GSSystemAnalyzer.Interfaces;
using GSSystemAnalyzer.Models;
using Microsoft.AspNetCore.Mvc;
using Moq;
using Xunit;

namespace GSSystemAnalyzer.Tests.Controller
{
	public class DiskIoControllerTests
	{
		[Fact]
		public void GetDiskIo_ReturnsOkWithSnapshot()
		{
			var mockEngine = new Mock<IDiskIoEngine>();
			var snapshot = new DiskIoSnapshotCollection(
				DateTimeOffset.UtcNow,
				new List<DiskIoSnapshot>
				{
					new DiskIoSnapshot(
						"0",
						"Samsung 980",
						new[] { "C:" },
						1000000.0,
						500000.0,
						15.0,
						0.4,
						1000000,
						500000)
				});

			mockEngine.Setup(e => e.GetCurrentSnapshot()).Returns(snapshot);

			var controller = new DiskIoController(mockEngine.Object);
			var result = controller.GetDiskIo() as OkObjectResult;

			Assert.NotNull(result);
			Assert.Equal(200, result.StatusCode);
			Assert.Equal(snapshot, result.Value);
		}
	}
}
