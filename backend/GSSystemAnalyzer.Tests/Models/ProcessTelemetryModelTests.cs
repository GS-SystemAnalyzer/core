using GSSystemAnalyzer.Models;
using Microsoft.AspNetCore.SignalR.Protocol;
using System.Text;
using System.Text.Json;
using Xunit;

namespace GSSystemAnalyzer.Tests.Models;

public class ProcessTelemetryModelTests
{
	[Fact]
	public void SignalRPayload_PreservesDistinctByteCountersAndExplicitZero()
	{
		var process = new ProcessTelemetry
		{
			ProcessId = 42, WorkingSetBytes = 104857600, PrivateWorkingSetBytes = 0, CommitBytes = 209715200
		};
		var protocol = new JsonHubProtocol();
		var message = protocol.GetMessageBytes(new InvocationMessage("RamUpdate", new object[]
		{
			new { Processes = new[] { process } }
		}));
		using var json = JsonDocument.Parse(Encoding.UTF8.GetString(message.Span).TrimEnd('\u001e'));
		var row = json.RootElement.GetProperty("arguments")[0].GetProperty("processes")[0];
		Assert.Equal(104857600, row.GetProperty("workingSetBytes").GetInt64());
		Assert.Equal(0, row.GetProperty("privateWorkingSetBytes").GetInt64());
		Assert.Equal(209715200, row.GetProperty("commitBytes").GetInt64());
		Assert.Equal(100, row.GetProperty("ramMb").GetDouble());
	}

	[Fact]
	public void UnmeasuredNewCounters_AreNull_NotWorkingSetAliases()
	{
		var process = new ProcessTelemetry { WorkingSetBytes = 104857600 };
		Assert.Null(process.PrivateWorkingSetBytes);
		Assert.Null(process.CommitBytes);
		Assert.Equal(100, process.RamMb);
	}

	[Fact]
	public void RamMb_ConvertsWorkingSetBytesCorrectly()
	{
		var p = new ProcessTelemetry { WorkingSetBytes = 104_857_600 }; // 100 MB
		Assert.Equal(100.0, p.RamMb);
	}

	[Fact]
	public void RamMb_IsRoundedToTwoDecimalPlaces()
	{
		var p = new ProcessTelemetry { WorkingSetBytes = 1_500_000 }; // 1.43 MB
		Assert.Equal(Math.Round(1_500_000 / 1024.0 / 1024.0, 2), p.RamMb);
	}

	[Fact]
	public void RamMb_IsZeroWhenWorkingSetIsZero()
	{
		var p = new ProcessTelemetry { WorkingSetBytes = 0 };
		Assert.Equal(0.0, p.RamMb);
	}

	[Fact]
	public void DefaultUser_IsSYSTEM()
	{
		var p = new ProcessTelemetry();
		Assert.Equal("SYSTEM", p.User);
	}

	[Fact]
	public void DefaultStatus_IsRUNNING()
	{
		var p = new ProcessTelemetry();
		Assert.Equal("RUNNING", p.Status);
	}

	[Theory]
	[InlineData(0)]
	[InlineData(-1)]
	[InlineData(int.MinValue)]
	public void RamMb_NeverGoesNegative(long bytes)
	{
		var p = new ProcessTelemetry { WorkingSetBytes = bytes };
		Assert.True(p.RamMb <= 0);
	}

	[Fact]
	public void AllPropertiesAssignableAndReadBack()
	{
		var p = new ProcessTelemetry
		{
			ProcessId = 1234,
			Name = "devenv",
			WorkingSetBytes = 52_428_800,
			CpuPercent = 12.5,
			Status = "SLEEPING",
			User = "G00dS0ul"
		};

		Assert.Equal(1234, p.ProcessId);
		Assert.Equal("devenv", p.Name);
		Assert.Equal(12.5, p.CpuPercent);
		Assert.Equal("SLEEPING", p.Status);
		Assert.Equal("G00dS0ul", p.User);
		Assert.Equal(50.0, p.RamMb); // 50 MB
	}
}
