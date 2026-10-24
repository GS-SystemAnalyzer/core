using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using System.Text.Json;
using Moq;
using Xunit;
using GSSystemAnalyzer.Controllers;
using GSSystemAnalyzer.Interfaces;
using GSSystemAnalyzer.Models;

namespace GSSystemAnalyzer.Tests.Controllers
{
    public class StartupControllerTests
    {
        private readonly Mock<IStartupManager> _mockManager;
        private readonly StartupController _controller;

        public StartupControllerTests()
        {
            _mockManager = new Mock<IStartupManager>();
            _controller = new StartupController(_mockManager.Object);
        }

        [Fact]
        public async Task GetAll_ReturnsOk_WithData()
        {
            var fakeEntries = new List<StartupProgramDto>
            {
                new StartupProgramDto { Id = "App1", Name = "App1", ExecutablePath = "path1", Scope = "user", Platform = "windows" }
            };
            _mockManager.Setup(m => m.GetStartupEntriesAsync()).ReturnsAsync(fakeEntries);

            var result = await _controller.GetAll();

            var okResult = Assert.IsType<OkObjectResult>(result);
            var returnedData = Assert.IsAssignableFrom<IEnumerable<StartupProgramDto>>(okResult.Value);
            Assert.Single(returnedData);
        }

        [Fact]
        public async Task DisableStartup_WhenSuccessful_ReturnsOk()
        {
            _mockManager.Setup(m => m.ToggleStartupEntryAsync("Discord", false))
                        .Returns(Task.CompletedTask);

            var result = await _controller.DisableStartup("Discord");

            var okResult = Assert.IsType<OkObjectResult>(result);
            Assert.NotNull(okResult.Value);
        }

        [Fact]
        public async Task DeleteStartup_WhenMissingAdminRights_Returns403Forbidden()
        {
            _mockManager.Setup(m => m.DeleteStartupEntryAsync("SystemApp"))
                        .Throws(new UnauthorizedAccessException("Admin privileges required"));

            var result = await _controller.DeleteStartup("SystemApp");

            var objectResult = Assert.IsType<ObjectResult>(result);
            Assert.Equal(403, objectResult.StatusCode);
            
            var jsonResponse = JsonSerializer.Serialize(objectResult.Value);
            Assert.Contains("Admin privileges required", jsonResponse);
        }

        [Fact]
        public async Task EnableStartup_WhenSecurityExceptionOccurs_Returns403Forbidden()
        {
            _mockManager.Setup(m => m.ToggleStartupEntryAsync("SystemApp", true))
                        .Throws(new System.Security.SecurityException("Requested registry access is not allowed."));

            var result = await _controller.EnableStartup("SystemApp");

            var objectResult = Assert.IsType<ObjectResult>(result);
            Assert.Equal(403, objectResult.StatusCode);
            var jsonResponse = JsonSerializer.Serialize(objectResult.Value);
            Assert.Contains("Requested registry access is not allowed.", jsonResponse);
        }

        [Fact]
        public async Task DisableStartup_WhenSecurityExceptionOccurs_Returns403Forbidden()
        {
            _mockManager.Setup(m => m.ToggleStartupEntryAsync("SystemApp", false))
                        .Throws(new System.Security.SecurityException("Requested registry access is not allowed."));

            var result = await _controller.DisableStartup("SystemApp");

            var objectResult = Assert.IsType<ObjectResult>(result);
            Assert.Equal(403, objectResult.StatusCode);
            var jsonResponse = JsonSerializer.Serialize(objectResult.Value);
            Assert.Contains("Requested registry access is not allowed.", jsonResponse);
        }

        [Fact]
        public async Task DeleteStartup_WhenSecurityExceptionOccurs_Returns403Forbidden()
        {
            _mockManager.Setup(m => m.DeleteStartupEntryAsync("SystemApp"))
                        .Throws(new System.Security.SecurityException("Requested registry access is not allowed."));

            var result = await _controller.DeleteStartup("SystemApp");

            var objectResult = Assert.IsType<ObjectResult>(result);
            Assert.Equal(403, objectResult.StatusCode);
            var jsonResponse = JsonSerializer.Serialize(objectResult.Value);
            Assert.Contains("Requested registry access is not allowed.", jsonResponse);
        }

        [Fact]
        public async Task EnableStartup_WhenRandomExceptionOccurs_Returns500InternalServerError()
        {
            _mockManager.Setup(m => m.ToggleStartupEntryAsync("BrokenApp", true))
                        .Throws(new Exception("Disk failure"));

            var result = await _controller.EnableStartup("BrokenApp");

            var objectResult = Assert.IsType<ObjectResult>(result);
            Assert.Equal(500, objectResult.StatusCode);
        }
    }
}
