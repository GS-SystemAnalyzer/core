using System.Buffers.Binary;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using GSSystemAnalyzer.Services;

namespace GSSystemAnalyzer.Tests.Services;

public class WindowsProcessMetricsProviderTests
{
	[Theory]
	[InlineData(4)]
	[InlineData(8)]
	public void IndependentNativeFixture_MapsCountersTimesAndShortName(int pointerSize)
	{
		const ulong baseAddress = 0x100000;
		var data = Fixture(pointerSize, baseAddress, 42, @"C:\Apps\sample.exe");
		var sample = Assert.Single(WindowsProcessMetricsProvider.ParseSnapshot(data, baseAddress, pointerSize));
		Assert.Equal(42, sample.ProcessId);
		Assert.Equal("sample", sample.Name);
		Assert.Equal(123456, sample.CreationTimeTicks);
		Assert.Equal(500, sample.CpuTimeTicks);
		Assert.Equal(0x123456789L, sample.PrivateWorkingSetBytes);
		Assert.Equal(pointerSize == 8 ? 9000000000L : 3000000000L, sample.WorkingSetBytes);
		Assert.Equal(pointerSize == 8 ? 12000000000L : 4000000000L, sample.CommitBytes);
	}

	[Fact]
	public void VariableLengthChain_VisitsFinalRecordAndRetainsItsValues()
	{
		const ulong baseAddress = 0x100000;
		var first = Fixture(8, baseAddress, 42, "first.exe");
		var second = Fixture(8, baseAddress + (ulong)first.Length, 43, "second.exe");
		var data = new byte[first.Length + second.Length];
		first.CopyTo(data, 0);
		second.CopyTo(data, first.Length);
		BinaryPrimitives.WriteUInt32LittleEndian(data, (uint)first.Length);
		var samples = WindowsProcessMetricsProvider.ParseSnapshot(data, baseAddress, 8);
		Assert.Equal(new[] { "first", "second" }, samples.Select(p => p.Name));
		Assert.Equal(new[] { 42, 43 }, samples.Select(p => p.ProcessId));
	}

	[Theory]
	[InlineData(0, "Idle")]
	[InlineData(4, "System")]
	[InlineData(42, "42")]
	public void EmptyNativeName_UsesTheDefinedIdentity(int pid, string expected)
	{
		var sample = Assert.Single(WindowsProcessMetricsProvider.ParseSnapshot(Fixture(8, 0x100000, pid, ""), 0x100000, 8));
		Assert.Equal(expected, sample.Name);
	}

	[Fact]
	public void GenuineZeroCounters_RemainMeasuredZeros()
	{
		var data = Fixture(8, 0x100000, 42, "zero.exe");
		BinaryPrimitives.WriteUInt64LittleEndian(data.AsSpan(8), 0);
		BinaryPrimitives.WriteUInt64LittleEndian(data.AsSpan(144), 0);
		BinaryPrimitives.WriteUInt64LittleEndian(data.AsSpan(200), 0);
		var sample = Assert.Single(WindowsProcessMetricsProvider.ParseSnapshot(data, 0x100000, 8));
		Assert.Equal(0, sample.WorkingSetBytes);
		Assert.Equal(0, sample.PrivateWorkingSetBytes);
		Assert.Equal(0, sample.CommitBytes);
	}

	[Theory]
	[InlineData("header")]
	[InlineData("offset")]
	[InlineData("terminal")]
	[InlineData("name-length")]
	[InlineData("name-pointer")]
	[InlineData("pid")]
	[InlineData("working-set")]
	[InlineData("cpu")]
	public void MalformedBatch_IsRejectedInsteadOfPublishingPlausibleValues(string defect)
	{
		var data = Fixture(8, 0x100000, 42, "sample.exe");
		switch (defect)
		{
			case "header": data = data[..200]; break;
			case "offset": BinaryPrimitives.WriteUInt32LittleEndian(data, 16); break;
			case "terminal": BinaryPrimitives.WriteUInt32LittleEndian(data, (uint)data.Length); break;
			case "name-length": BinaryPrimitives.WriteUInt16LittleEndian(data.AsSpan(56), 3); break;
			case "name-pointer": BinaryPrimitives.WriteUInt64LittleEndian(data.AsSpan(64), 0x100000 + (ulong)data.Length); break;
			case "pid": BinaryPrimitives.WriteUInt64LittleEndian(data.AsSpan(80), ulong.MaxValue); break;
			case "working-set": BinaryPrimitives.WriteUInt64LittleEndian(data.AsSpan(144), ulong.MaxValue); break;
			case "cpu": BinaryPrimitives.WriteInt64LittleEndian(data.AsSpan(40), -1); break;
		}
		Assert.Throws<InvalidDataException>(() => WindowsProcessMetricsProvider.ParseSnapshot(data, 0x100000, 8));
	}

	[Fact]
	public void QueryGrowth_RetriesWithinBoundsAndCopiesNativeNamesBeforeFreeing()
	{
		var calls = 0;
		var provider = new WindowsProcessMetricsProvider((int informationClass, IntPtr buffer, int length, out int returnedLength) =>
		{
			Assert.Equal(5, informationClass);
			calls++;
			var data = Fixture(IntPtr.Size, unchecked((ulong)buffer.ToInt64()), 42, "grown.exe");
			returnedLength = data.Length;
			if (length < data.Length) return unchecked((int)0xC0000004);
			Marshal.Copy(data, 0, buffer, data.Length);
			return 0;
		}, initialCapacity: 64);
		var sample = Assert.Single(provider.ReadSnapshot());
		Assert.Equal(2, calls);
		Assert.Equal("grown", sample.Name);
		Assert.Equal(42, sample.ProcessId);
	}

	[Fact]
	public void QueryFailure_ThrowsAndDoesNotBecomeAnEmptySuccessfulBatch()
	{
		var provider = new WindowsProcessMetricsProvider((int _, IntPtr _, int _, out int returnedLength) =>
		{
			returnedLength = 0;
			return unchecked((int)0xC0000022);
		});
		Assert.Throws<Win32Exception>(() => provider.ReadSnapshot());
	}

	[Fact]
	public void UnboundedGrowth_IsRejected()
	{
		var provider = new WindowsProcessMetricsProvider((int _, IntPtr _, int _, out int returnedLength) =>
		{
			returnedLength = 2048;
			return unchecked((int)0xC0000004);
		}, initialCapacity: 64, maximumCapacity: 1024);
		Assert.Throws<InvalidDataException>(() => provider.ReadSnapshot());
	}

	[Fact]
	public void LiveWindowsSnapshot_ContainsTheCurrentProcessAndItsThreeCounters()
	{
		if (!OperatingSystem.IsWindows()) return;
		var provider = new WindowsProcessMetricsProvider();
		var current = Assert.Single(provider.ReadSnapshot(), p => p.ProcessId == Environment.ProcessId);
		Assert.True(current.WorkingSetBytes > 0);
		Assert.True(current.PrivateWorkingSetBytes > 0);
		Assert.True(current.CommitBytes > 0);
		Assert.NotEmpty(current.Name);
	}

	private static byte[] Fixture(int pointerSize, ulong baseAddress, int pid, string name)
	{
		var header = pointerSize == 8 ? 256 : 184;
		var text = Encoding.Unicode.GetBytes(name);
		var data = new byte[(header + text.Length + 7) / 8 * 8];
		BinaryPrimitives.WriteUInt64LittleEndian(data.AsSpan(8), 0x123456789);
		BinaryPrimitives.WriteInt64LittleEndian(data.AsSpan(32), 123456);
		BinaryPrimitives.WriteInt64LittleEndian(data.AsSpan(40), 200);
		BinaryPrimitives.WriteInt64LittleEndian(data.AsSpan(48), 300);
		BinaryPrimitives.WriteUInt16LittleEndian(data.AsSpan(56), (ushort)text.Length);
		BinaryPrimitives.WriteUInt16LittleEndian(data.AsSpan(58), (ushort)text.Length);
		if (pointerSize == 8)
		{
			BinaryPrimitives.WriteUInt64LittleEndian(data.AsSpan(64), baseAddress + (ulong)header);
			BinaryPrimitives.WriteUInt64LittleEndian(data.AsSpan(80), (ulong)pid);
			BinaryPrimitives.WriteUInt64LittleEndian(data.AsSpan(144), 9000000000);
			BinaryPrimitives.WriteUInt64LittleEndian(data.AsSpan(200), 12000000000);
		}
		else
		{
			BinaryPrimitives.WriteUInt32LittleEndian(data.AsSpan(60), (uint)(baseAddress + (ulong)header));
			BinaryPrimitives.WriteUInt32LittleEndian(data.AsSpan(68), (uint)pid);
			BinaryPrimitives.WriteUInt32LittleEndian(data.AsSpan(104), 3000000000);
			BinaryPrimitives.WriteUInt32LittleEndian(data.AsSpan(132), 4000000000);
		}
		text.CopyTo(data, header);
		return data;
	}
}
