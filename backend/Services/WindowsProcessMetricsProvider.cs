using System.Buffers.Binary;
using System.ComponentModel;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Text;
using GSSystemAnalyzer.Models;

namespace GSSystemAnalyzer.Services;

public sealed class WindowsProcessMetricsProvider
{
	internal delegate int SystemInformationQuery(int informationClass, IntPtr buffer, int length, out int returnedLength);

	private const int ProcessInformationClass = 5;
	private const int LengthMismatch = unchecked((int)0xC0000004);
	private const int BufferTooSmall = unchecked((int)0xC0000023);
	private readonly SystemInformationQuery _query;
	private readonly int _initialCapacity;
	private readonly int _maximumCapacity;

	public WindowsProcessMetricsProvider() : this(NtQuerySystemInformation) { }

	internal WindowsProcessMetricsProvider(SystemInformationQuery query, int initialCapacity = 131072, int maximumCapacity = 67108864)
	{
		ArgumentNullException.ThrowIfNull(query);
		if (initialCapacity < 1 || maximumCapacity < initialCapacity)
			throw new ArgumentOutOfRangeException(nameof(initialCapacity));
		_query = query;
		_initialCapacity = initialCapacity;
		_maximumCapacity = maximumCapacity;
	}

	internal IReadOnlyList<ProcessMemorySample> ReadSnapshot()
	{
		var capacity = _initialCapacity;
		for (var attempt = 0; attempt < 8; attempt++)
		{
			var buffer = Marshal.AllocHGlobal(capacity);
			try
			{
				var status = _query(ProcessInformationClass, buffer, capacity, out var returnedLength);
				if (status == LengthMismatch || status == BufferTooSmall)
				{
					var next = Math.Max((long)returnedLength, (long)capacity * 2);
					if (next > _maximumCapacity) throw new InvalidDataException("Process snapshot exceeds its bounded buffer.");
					capacity = (int)next;
					continue;
				}
				if (status < 0) throw new Win32Exception(status, $"Native process query failed (0x{unchecked((uint)status):X8}).");
				if (returnedLength <= 0 || returnedLength > capacity)
					throw new InvalidDataException("Native process query returned an invalid length.");

				var data = new byte[returnedLength];
				Marshal.Copy(buffer, data, 0, data.Length);
				return ParseSnapshot(data, unchecked((ulong)buffer.ToInt64()), IntPtr.Size);
			}
			finally
			{
				Marshal.FreeHGlobal(buffer);
			}
		}
		throw new InvalidDataException("Native process snapshot did not stabilize within the retry bound.");
	}

	internal static List<ProcessMemorySample> ParseSnapshot(ReadOnlySpan<byte> data, ulong baseAddress, int pointerSize)
	{
		if (pointerSize is not (4 or 8)) throw new ArgumentOutOfRangeException(nameof(pointerSize));
		var headerSize = pointerSize == 8 ? 256 : 184;
		var namePointerOffset = pointerSize == 8 ? 64 : 60;
		var pidOffset = pointerSize == 8 ? 80 : 68;
		var workingSetOffset = pointerSize == 8 ? 144 : 104;
		var commitOffset = pointerSize == 8 ? 200 : 132;
		var result = new List<ProcessMemorySample>();
		var offset = 0;

		while (offset < data.Length)
		{
			if (data.Length - offset < headerSize) throw new InvalidDataException("Truncated native process header.");
			var record = data[offset..];
			var next = BinaryPrimitives.ReadUInt32LittleEndian(record);
			if (next != 0 && (next < headerSize || next > data.Length - offset - headerSize || next % pointerSize != 0))
				throw new InvalidDataException("Invalid native process record offset.");

			var pidValue = ReadPointer(record[pidOffset..], pointerSize);
			if (pidValue > int.MaxValue) throw new InvalidDataException("Native process identifier is out of range.");
			var pid = (int)pidValue;
			var nameLength = BinaryPrimitives.ReadUInt16LittleEndian(record[56..]);
			var maximumNameLength = BinaryPrimitives.ReadUInt16LittleEndian(record[58..]);
			if ((nameLength & 1) != 0 || (maximumNameLength & 1) != 0 || nameLength > maximumNameLength)
				throw new InvalidDataException("Invalid native process name length.");

			var name = string.Empty;
			if (nameLength != 0)
			{
				var pointer = ReadPointer(record[namePointerOffset..], pointerSize);
				if (pointer < baseAddress || pointer - baseAddress > (ulong)data.Length ||
					(ulong)nameLength > (ulong)data.Length - (pointer - baseAddress))
					throw new InvalidDataException("Native process name points outside its snapshot.");
				name = Encoding.Unicode.GetString(data.Slice((int)(pointer - baseAddress), nameLength));
			}

			var workingSet = ReadPointer(record[workingSetOffset..], pointerSize);
			if (workingSet > long.MaxValue) throw new InvalidDataException("Invalid native working-set counter.");
			var privateWorkingSet = BinaryPrimitives.ReadUInt64LittleEndian(record[8..]);
			var commit = ReadPointer(record[commitOffset..], pointerSize);
			var creation = BinaryPrimitives.ReadInt64LittleEndian(record[32..]);
			var user = BinaryPrimitives.ReadInt64LittleEndian(record[40..]);
			var kernel = BinaryPrimitives.ReadInt64LittleEndian(record[48..]);
			if (creation < 0 || user < 0 || kernel < 0 || user > long.MaxValue - kernel)
				throw new InvalidDataException("Invalid native process time counter.");

			result.Add(new ProcessMemorySample(pid, NormalizeName(name, pid), creation, user + kernel,
				(long)workingSet, privateWorkingSet <= long.MaxValue ? (long)privateWorkingSet : null,
				commit <= long.MaxValue ? (long)commit : null));
			if (next == 0) break;
			offset += (int)next;
		}
		return result;
	}

	private static ulong ReadPointer(ReadOnlySpan<byte> data, int pointerSize) =>
		pointerSize == 8 ? BinaryPrimitives.ReadUInt64LittleEndian(data) : BinaryPrimitives.ReadUInt32LittleEndian(data);

	private static string NormalizeName(string name, int pid)
	{
		if (name.Length == 0) return pid switch { 0 => "Idle", 4 => "System", _ => pid.ToString(CultureInfo.InvariantCulture) };
		var separator = Math.Max(name.LastIndexOf('\\'), name.LastIndexOf('/'));
		if (separator >= 0) name = name[(separator + 1)..];
		return name.EndsWith(".exe", StringComparison.OrdinalIgnoreCase) ? name[..^4] : name;
	}

	[DllImport("ntdll.dll")]
	private static extern int NtQuerySystemInformation(int informationClass, IntPtr buffer, int length, out int returnedLength);
}
