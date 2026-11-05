using GSSystemAnalyzer.Interfaces;
using System.Diagnostics;
using GSSystemAnalyzer.Models;

namespace GSSystemAnalyzer.Services
{
	public class WindowsCpuProvider : ICpuMetricsProvider
	{
#if WINDOWS
		private readonly List<PerformanceCounter> _coreCounters = new();
		private double _previousAverage = 0;
		private readonly PerformanceCounter? _baseFreqCounter;
		private readonly PerformanceCounter? _perfRatioCounter;
		private readonly PerformanceCounter? _systemProcesses;
		private readonly PerformanceCounter? _systemThreads;
		private readonly PerformanceCounter? _systemHandles;


		public WindowsCpuProvider()
		{
			for (int i = 0; i < Environment.ProcessorCount; i++)
			{
				var pc = new PerformanceCounter("Processor", "% Processor Time", i.ToString());
				pc.NextValue();
				_coreCounters.Add(pc);
			}

			try
			{
				_baseFreqCounter = new PerformanceCounter("Processor Information", "Processor Frequency", "_Total");
				_perfRatioCounter =
					new PerformanceCounter("Processor Information", "% Processor Performance", "_Total");
				_baseFreqCounter.NextValue();
				_perfRatioCounter.NextValue();
			}
			catch
			{
				_baseFreqCounter = null;
				_perfRatioCounter = null;
			}

			_systemProcesses = new PerformanceCounter("System", "Processes");
			_systemThreads = new PerformanceCounter("System", "Threads");
			_systemHandles = new PerformanceCounter("Process", "Handle Count", "_Total");
		}
#else
        public WindowsCpuProvider() =>
            throw new PlatformNotSupportedException("WindowsCpuProvider is only supported on Windows.");
#endif

		public async Task<CpuTelemetryDto> GetNextSampleAsync()
		{
#if WINDOWS
			var loads = _coreCounters.Select(c => Math.Round(c.NextValue(), 1)).ToList();
			double? baseMhz = null, perfRatio = null;
			try
			{
				if (_baseFreqCounter != null && _perfRatioCounter != null)
				{
					baseMhz = _baseFreqCounter.NextValue();
					perfRatio = _perfRatioCounter.NextValue();
				}
			}
			catch
			{
			}

			var dto = Project(loads, _previousAverage, baseMhz, perfRatio,
				(int)_systemProcesses.NextValue(), (int)_systemThreads.NextValue(), (int)_systemHandles.NextValue());
			_previousAverage = dto.AverageLoad;
			return await Task.FromResult(dto);
#else

            return await Task.FromException<CpuTelemetryDto>(new PlatformNotSupportedException());
#endif
		}

		internal static CpuTelemetryDto Project(IEnumerable<double> samples, double previousAverage,
			double? baseMhz, double? perfRatio, int processes, int threads, int handles)
		{
			var loads = samples.Select(value => Math.Round(value, 1)).ToList();
			var average = Math.Round(loads.Average(), 1);
			var dto = new CpuTelemetryDto
			{
				AverageLoad = average,
				Delta = Math.Round(average - previousAverage, 1),
				CurrentFrequencyGhz = baseMhz.HasValue && perfRatio.HasValue
					? Math.Round(baseMhz.Value * (perfRatio.Value / 100.0) / 1000.0, 2) : 0.0,
				TotalProcesses = processes, TotalThreads = threads, TotalHandles = handles,
				L1Cache = "256 KB", L2Cache = "1.0 MB", L3Cache = "8.0 MB"
			};
			for (int i = 0; i < loads.Count; i += 4)
				dto.CoreGroups.Add($"CORE {i}-{Math.Min(i + 3, loads.Count - 1)}", loads.Skip(i).Take(4).ToList());
			return dto;
		}
	}
}
