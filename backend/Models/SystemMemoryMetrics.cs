using System.Runtime.InteropServices;

namespace GSSystemAnalyzer.Models
{
	public class SystemMemoryMetrics
	{
		[StructLayout(LayoutKind.Sequential)]
		public struct MEMORYSTATUSEX
		{
			public uint dwLength;
			public uint dwMemoryLoad;
			public ulong ullTotalPhys;
			public ulong ullAvailPhys;
			public ulong ulTotalPagePhys;
			public ulong ulAvailPagePhys;
			public ulong ullTotalVirtual;
			public ulong ulAvailVirtual;
			public ulong ullAvailExtendedVirtual;
		}

		public class GlobalMemoryMetrics
		{
			public double ActiveGb { get; set; }
			public double CacheGb { get; set; }
			public double SwapGb { get; set; }
			public double TotalSwapGb { get; set; }
			public double TotalGb { get; set; }
			public long? PhysicalTotalBytes { get; set; }
			internal long? AvailablePhysicalBytes { get; set; }
		}

		[DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
		public static extern bool GlobalMemoryStatusEx(ref MEMORYSTATUSEX lpBuffer);

		public static GlobalMemoryMetrics? GetLiveMetrics()
		{
			if (!OperatingSystem.IsWindows()) return null;
			var memStatus = new MEMORYSTATUSEX();
			memStatus.dwLength = (uint)Marshal.SizeOf(typeof(MEMORYSTATUSEX));
			return GlobalMemoryStatusEx(ref memStatus) ? FromNativeStatus(memStatus) : null;
		}

		internal static GlobalMemoryMetrics? FromNativeStatus(MEMORYSTATUSEX memStatus)
		{
			if (memStatus.ullTotalPhys > 0 && memStatus.ullTotalPhys <= long.MaxValue &&
				memStatus.ullAvailPhys <= memStatus.ullTotalPhys && memStatus.ulAvailPagePhys <= memStatus.ulTotalPagePhys)
			{
				double totalRamGb = memStatus.ullTotalPhys / (1024.0 * 1024.0 * 1024.0);
				double availRamGb = memStatus.ullAvailPhys / (1024.0 * 1024.0 * 1024.0);
				double activeRamGb = totalRamGb - availRamGb;

				double totalCommitLimitGb = memStatus.ulTotalPagePhys / (1024.0 * 1024.0 * 1024.0);
				double availCommitLimitGb = memStatus.ulAvailPagePhys / (1024.0 * 1024.0 * 1024.0);

				double commitChargeGb = totalCommitLimitGb - availCommitLimitGb;

				// In Windows, Swap/Pagefile usage is most accurately represented to users as the System Commit Charge
				// TotalSwapGb represents the absolute Commit Limit (Physical RAM + Pagefile bounds)
				double totalSwapGb = totalCommitLimitGb;
				double swapGb = commitChargeGb;

				return new GlobalMemoryMetrics
				{
					ActiveGb = Math.Round(activeRamGb, 2),
					CacheGb = Math.Round(availRamGb, 2),
					SwapGb = Math.Round(swapGb, 2),
					TotalSwapGb = Math.Round(totalSwapGb, 2),
					TotalGb = Math.Round(totalRamGb, 2),
					PhysicalTotalBytes = (long)memStatus.ullTotalPhys,
					AvailablePhysicalBytes = (long)memStatus.ullAvailPhys
				};
			}

			return null;
		}
	}
}
