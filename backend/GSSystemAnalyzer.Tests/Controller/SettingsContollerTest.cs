using GSSystemAnalyzer.Controllers;
using GSSystemAnalyzer.Interfaces;
using GSSystemAnalyzer.Models.SettingDtos;
using Microsoft.AspNetCore.Mvc;
using Moq;

namespace GSSystemAnalyzer.Tests.Controller
{
	public class SettingsControllerTests
	{
		private static SettingsController MakeController(
			Mock<ISettingService> mockService,
			Mock<IDiskScannerEngine>? mockScanner = null)
		{
			var scanner = mockScanner ?? new Mock<IDiskScannerEngine>();
			return new SettingsController(mockService.Object, scanner.Object);
		}

		[Fact]
		public async Task SaveSettings_WhenValidationFails_ReturnsBadRequestAndDoesNotSave()
		{
			var mockService = new Mock<ISettingService>();
			var controller = MakeController(mockService);

			var badSettings = AppSettingDto.GetFactoryDefaults();
			badSettings.Advanced.BackendPort = 10;

			var result = await controller.SaveSettings(badSettings);

			Assert.IsType<BadRequestObjectResult>(result);
			mockService.Verify(s => s.SaveAsync(It.IsAny<AppSettingDto>()), Times.Never);
		}

		[Fact]
		public async Task SaveSettings_WhenValidationPasses_ReturnsOkAndCallsSave()
		{
			var mockService = new Mock<ISettingService>();
			var validSettings = AppSettingDto.GetFactoryDefaults();
			mockService.Setup(s => s.Current).Returns(validSettings);

			var controller = MakeController(mockService);

			var result = await controller.SaveSettings(validSettings);

			Assert.IsType<OkObjectResult>(result);
			mockService.Verify(s => s.SaveAsync(It.Is<AppSettingDto>(s =>
				s.Monitoring.RamPollIntervalMs == validSettings.Monitoring.RamPollIntervalMs && !ReferenceEquals(s, validSettings))), Times.Once);
		}

		[Theory]
		[InlineData(199, false)]
		[InlineData(200, true)]
		[InlineData(1000, true)]
		[InlineData(5000, true)]
		[InlineData(5001, false)]
		public async Task RamPollingBoundary_ReturnsTheExpectedStatus(int period, bool accepted)
		{
			var service = new Mock<ISettingService>();
			service.Setup(s => s.SaveAsync(It.IsAny<AppSettingDto>())).Returns(Task.CompletedTask);
			var request = AppSettingDto.GetFactoryDefaults();
			request.Monitoring.RamPollIntervalMs = period;
			var result = await MakeController(service).SaveSettings(request);
			Assert.Equal(accepted, result is OkObjectResult);
			service.Verify(s => s.SaveAsync(It.IsAny<AppSettingDto>()), accepted ? Times.Once() : Times.Never());
		}

		[Fact]
		public async Task InterleavedSaves_AcknowledgeTheirOwnDetachedRequests()
		{
			var service = new Mock<ISettingService>();
			var current = AppSettingDto.GetFactoryDefaults();
			var releaseFirst = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
			service.SetupGet(s => s.Current).Returns(() => current);
			service.Setup(s => s.SaveAsync(It.IsAny<AppSettingDto>())).Returns<AppSettingDto>(snapshot =>
			{
				current = snapshot;
				return snapshot.Monitoring.RamPollIntervalMs == 1500 ? releaseFirst.Task : Task.CompletedTask;
			});
			var controller = MakeController(service);
			var firstRequest = AppSettingDto.GetFactoryDefaults();
			firstRequest.Monitoring.RamPollIntervalMs = 1500;
			var secondRequest = AppSettingDto.GetFactoryDefaults();
			secondRequest.Monitoring.RamPollIntervalMs = 200;
			var firstSave = controller.SaveSettings(firstRequest);
			firstRequest.Monitoring.RamPollIntervalMs = 1000;
			try
			{
				var second = Assert.IsType<OkObjectResult>(await controller.SaveSettings(secondRequest));
				var data = (AppSettingDto)second.Value!.GetType().GetProperty("data")!.GetValue(second.Value)!;
				Assert.Equal(200, data.Monitoring.RamPollIntervalMs);
			}
			finally
			{
				releaseFirst.TrySetResult();
				await firstSave;
			}
			var first = Assert.IsType<OkObjectResult>(await firstSave);
			var firstData = (AppSettingDto)first.Value!.GetType().GetProperty("data")!.GetValue(first.Value)!;
			Assert.Equal(1500, firstData.Monitoring.RamPollIntervalMs);
		}

		[Fact]
		public async Task ResetSettings_Always_OverwritesWithFactoryDefaults()
		{
			var mockService = new Mock<ISettingService>();
			var controller = MakeController(mockService);

			var result = await controller.ResetSettings();

			Assert.IsType<OkObjectResult>(result);
			mockService.Verify(s => s.SaveAsync(It.IsAny<AppSettingDto>()), Times.Once);
		}
	}
}
