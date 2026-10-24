namespace GSSystemAnalyzer.Tests.Infrastructure;

using System;
using GSSystemAnalyzer.Interfaces;
using GSSystemAnalyzer.Services;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using Xunit;

public class DependencyInjectionValidationTests
{
	[Fact]
	public void LargeFileHunterService_CanBeResolvedFromServiceProvider_WithoutConstructorAmbiguity()
	{
		var services = new ServiceCollection();
		var mockSettings = new Mock<ISettingService>();
		var mockIndexer = new Mock<IFileSystemIndexer>();

		services.AddSingleton(mockSettings.Object);
		services.AddSingleton(mockIndexer.Object);
		services.AddSingleton(typeof(ILogger<>), typeof(NullLogger<>));
		services.AddSingleton<ILargeFileHunterService, LargeFileHunterService>();

		var provider = services.BuildServiceProvider(new ServiceProviderOptions
		{
			ValidateOnBuild = true,
			ValidateScopes = true
		});

		var hunter = provider.GetRequiredService<ILargeFileHunterService>();
		Assert.NotNull(hunter);
	}
}
