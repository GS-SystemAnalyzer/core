using System;
using System.Threading;
using System.Threading.Tasks;
using GSSystemAnalyzer.Engine;
using GSSystemAnalyzer.Hubs;
using GSSystemAnalyzer.Interfaces;
using GSSystemAnalyzer.Models.SettingDtos;
using GSSystemAnalyzer.Tests.Services;
using Microsoft.AspNetCore.SignalR;
using Microsoft.Extensions.Logging;
using Moq;
using Xunit;

namespace GSSystemAnalyzer.Tests.Engine
{
	public class DiskScannerEngineTokenTests : IDisposable
	{
		private readonly DiskScannerEngine _engine;
		private readonly ScannerCacheTestScope _cacheScope = new();
		private readonly List<Guid> _sessions = new();

		public DiskScannerEngineTokenTests()
		{
			var hubMock = new Mock<IHubContext<SystemHub>>();
			var settingsMock = new Mock<ISettingService>();
			settingsMock.SetupGet(s => s.Current).Returns(AppSettingDto.GetFactoryDefaults());
			var loggerMock = new Mock<ILogger<DiskScannerEngine>>();

			_engine = new DiskScannerEngine(hubMock.Object, settingsMock.Object, loggerMock.Object,
				cacheFilePath: _cacheScope.CreateCachePath());
		}

		private Guid BeginSession()
		{
			var id = _engine.BeginScanSession();
			_sessions.Add(id);
			return id;
		}

		public void Dispose()
		{
			foreach (var id in _sessions) _engine.EndScanSession(id);
			_engine.Dispose();
			_cacheScope.Dispose();
		}

		[Fact]
		public void BeginScanSession_ReturnsLiveToken()
		{
			var id = BeginSession();
			var token = _engine.GetScanToken(id);
			Assert.False(token.IsCancellationRequested);
		}

		[Fact]
		public void TriggerScanAbort_SpecificId_CancelsOnlyThatToken()
		{
			var id1 = BeginSession();
			var id2 = BeginSession();

			var token1 = _engine.GetScanToken(id1);
			var token2 = _engine.GetScanToken(id2);

			_engine.TriggerScanAbort(id1);

			Assert.True(token1.IsCancellationRequested);
			Assert.False(token2.IsCancellationRequested);
		}

		[Fact]
		public void TriggerScanAbort_NullId_CancelsAllTokens()
		{
			var id1 = BeginSession();
			var id2 = BeginSession();

			var token1 = _engine.GetScanToken(id1);
			var token2 = _engine.GetScanToken(id2);

			_engine.TriggerScanAbort(null);

			Assert.True(token1.IsCancellationRequested);
			Assert.True(token2.IsCancellationRequested);
		}
	}
}
