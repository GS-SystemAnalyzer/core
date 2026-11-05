using System.Diagnostics;
using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading.Channels;
using Microsoft.AspNetCore.SignalR;

namespace GSSystemAnalyzer.Services;

public sealed record BenchmarkMetadata(int SchemaVersion, string RunId, string StreamId,
	string ProducerEpoch, string Sequence, string ClockId, string FrequencyHz,
	[property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] string? AcquisitionStartTicks = null,
	[property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] string? AcquisitionEndTicks = null);

public sealed record BenchmarkEvent(string EventId, int ProcessId, BenchmarkMetadata BenchmarkTrace,
	string Stage, string LocalTicks, string Outcome, string? OperationId = null,
	IReadOnlyDictionary<string, long>? Counts = null, string? Key = null);

public sealed class BenchmarkTrace : IAsyncDisposable
{
	private sealed record Context(BenchmarkTrace? Trace, string Stream);
	private static readonly AsyncLocal<Context?> Ambient = new();
	internal static BenchmarkTrace? ProcessTrace { get; set; }
	public static BenchmarkTrace? Current => Ambient.Value is { } context ? context.Trace : ProcessTrace;
	internal static string Stream => Ambient.Value?.Stream ?? "system";
	internal static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);
	private readonly Channel<BenchmarkEvent> _events;
	private readonly TextWriter _writer;
	private readonly Action? _finalizeOutput;
	private readonly Task _writerTask;
	private readonly Dictionary<string, long> _sequences = new(StringComparer.Ordinal);
	private sealed class ObservedTask(Task source) { public Task Source { get; } = source; public Task Completion { get; set; } = Task.CompletedTask; }
	private readonly Dictionary<string, ObservedTask> _sends = new(StringComparer.Ordinal);
	private long _eventId, _operationId, _dropped, _written, _outstanding;
	private int _closed, _writeFailed, _evictionQueueUnknown;
	public string RunId { get; }
	public string Epoch { get; } = Guid.NewGuid().ToString("N");
	public bool Rich { get; }
	public long Dropped => Interlocked.Read(ref _dropped);
	public long Outstanding => Interlocked.Read(ref _outstanding);
	public bool WriteFailed => Volatile.Read(ref _writeFailed) != 0;
	public bool IsOpen => Volatile.Read(ref _closed) == 0;
	public static long Ticks => Stopwatch.GetTimestamp();
	private static string Number(long value) => value.ToString(CultureInfo.InvariantCulture);

	internal BenchmarkTrace(string runId, TextWriter writer, int capacity = 4096, bool rich = false, Action? finalizeOutput = null)
	{
		if (!Guid.TryParseExact(runId, "N", out _) || capacity < 1) throw new ArgumentException("Invalid trace ownership or capacity.");
		RunId = runId;
		Rich = rich;
		_writer = writer;
		_finalizeOutput = finalizeOutput;
		_events = Channel.CreateBounded<BenchmarkEvent>(new BoundedChannelOptions(capacity)
			{ SingleReader = true, FullMode = BoundedChannelFullMode.Wait });
		_writerTask = Task.Run(WriteAsync);
		Emit("trace.start", counts: new Dictionary<string, long> { ["rich"] = rich ? 1 : 0 });
	}

	public static BenchmarkTrace? FromEnvironment()
	{
		var runId = Environment.GetEnvironmentVariable("GS_BENCHMARK_RUN_ID");
		var output = Environment.GetEnvironmentVariable("GS_BENCHMARK_OUTPUT");
		if (runId == null && output == null) return null;
		return CreateOwned(runId, output);
	}

	internal static BenchmarkTrace CreateOwned(string? runId, string? output)
	{
		if (!Guid.TryParseExact(runId, "N", out _) || string.IsNullOrWhiteSpace(output))
			throw new InvalidDataException("Both benchmark ownership variables are required.");
		var root = Path.GetFullPath(output);
		using var owner = JsonDocument.Parse(File.ReadAllText(Path.Combine(root, "owner.json")));
		if (owner.RootElement.GetProperty("runId").GetString() != runId ||
			owner.RootElement.GetProperty("schemaVersion").GetInt32() != 1)
			throw new InvalidDataException("Benchmark output ownership mismatch.");
		var detail = owner.RootElement.GetProperty("detail").GetString();
		if (detail is not ("minimal" or "rich")) throw new InvalidDataException("Unknown trace detail.");
		var finalPath = Path.Combine(root, $"backend-{Guid.NewGuid():N}.jsonl");
		var partialPath = finalPath + ".partial";
		var file = new FileStream(partialPath, FileMode.CreateNew, FileAccess.Write, FileShare.Read);
		return new BenchmarkTrace(runId!, new StreamWriter(file, new UTF8Encoding(false)), rich: detail == "rich",
			finalizeOutput: () => File.Move(partialPath, finalPath));
	}

	internal void MarkEvictionQueueUnknown()
	{
		if (Interlocked.Exchange(ref _evictionQueueUnknown, 1) == 0) Emit("cache.eviction_queue", "unknown");
	}

	internal static IDisposable Use(BenchmarkTrace? trace, string stream = "system")
	{
		var old = Ambient.Value;
		Ambient.Value = new(trace, stream);
		return new Restore(() => Ambient.Value = old);
	}

	public static IDisposable? Enter(string stream) => Current is { } trace ? Use(trace, stream) : null;
	private sealed class Restore(Action restore) : IDisposable { public void Dispose() => restore(); }

	public BenchmarkMetadata Metadata(string? stream = null, long? acquisitionStart = null, long? acquisitionEnd = null)
	{
		stream ??= Stream;
		long sequence;
		lock (_sequences)
		{
			if (!_sequences.ContainsKey(stream) && _sequences.Count >= 1024)
			{
				Interlocked.Increment(ref _dropped);
				stream = "overflow";
			}
			_sequences.TryGetValue(stream, out sequence);
			_sequences[stream] = ++sequence;
		}
		return new(1, RunId, stream, Epoch, Number(sequence), "dotnet-" + Epoch, Number(Stopwatch.Frequency),
			acquisitionStart.HasValue ? Number(acquisitionStart.Value) : null,
			acquisitionEnd.HasValue ? Number(acquisitionEnd.Value) : null);
	}

	public string Key(string value) => Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(Epoch + "\n" + value)));

	public void Emit(string stage, string outcome = "observed", BenchmarkMetadata? metadata = null,
		string? operationId = null, IReadOnlyDictionary<string, long>? counts = null, string? key = null)
	{
		var record = Record(stage, outcome, metadata, operationId, counts, key);
		if (!_events.Writer.TryWrite(record)) Interlocked.Increment(ref _dropped);
	}

	private BenchmarkEvent Record(string stage, string outcome, BenchmarkMetadata? metadata,
		string? operationId, IReadOnlyDictionary<string, long>? counts, string? key) =>
		new(Number(Interlocked.Increment(ref _eventId)), Environment.ProcessId, metadata ?? Metadata(),
			stage, Number(Ticks), outcome, operationId, counts, key);

	public Observation Begin(string stage, string? stream = null, BenchmarkMetadata? metadata = null) => new(this, stage, metadata ?? Metadata(stream));

	public sealed class Observation : IDisposable
	{
		private readonly BenchmarkTrace _trace;
		private readonly string _stage;
		private int _ended;
		public BenchmarkMetadata Metadata { get; }
		public string Id { get; }
		public string Outcome { get; set; } = "settled";
		public IReadOnlyDictionary<string, long>? Counts { get; set; }
		internal Observation(BenchmarkTrace trace, string stage, BenchmarkMetadata metadata)
		{
			_trace = trace; _stage = stage; Metadata = metadata;
			Id = Number(Interlocked.Increment(ref trace._operationId));
			Interlocked.Increment(ref trace._outstanding);
			trace.Emit(stage + ".start", "started", metadata, Id);
		}
		public void Fail(Exception error) => Outcome = error is OperationCanceledException ? "cancelled" : "failed";
		public void Dispose()
		{
			if (Interlocked.Exchange(ref _ended, 1) != 0) return;
			_trace.Emit(_stage + ".end", Outcome, Metadata, Id, Counts);
			Interlocked.Decrement(ref _trace._outstanding);
		}
	}

	public Task Observe(Task task, Observation observation)
	{
		lock (_sends)
		{
			if (_sends.Count >= 4096)
			{
				Interlocked.Increment(ref _dropped);
				observation.Outcome = "unobserved";
				observation.Dispose();
				return task;
			}
			var tracked = new ObservedTask(task);
			_sends.Add(observation.Id, tracked);
			tracked.Completion = task.ContinueWith(completed =>
			{
				lock (_sends)
				{
					observation.Outcome = completed.IsCanceled ? "cancelled" : completed.IsFaulted ? "failed" : "succeeded";
					observation.Dispose();
					_sends.Remove(observation.Id);
				}
			}, CancellationToken.None, TaskContinuationOptions.ExecuteSynchronously, TaskScheduler.Default);
		}
		return task;
	}

	public static Task Send(IClientProxy client, string method, object payload, CancellationToken token = default,
		BenchmarkMetadata? metadata = null)
	{
		var trace = Current;
		if (trace == null) return client.SendAsync(method, payload, cancellationToken: token);
		var observation = trace.Begin("send." + method, metadata: metadata);
		try
		{
			return trace.Observe(client.SendAsync(method, Enrich(payload, metadata ?? observation.Metadata), cancellationToken: token), observation);
		}
		catch (Exception ex) { observation.Fail(ex); observation.Dispose(); throw; }
	}

	internal static object Enrich(object payload, BenchmarkMetadata? metadata)
	{
		if (metadata == null) return payload;
		var fields = payload.GetType().GetProperties().ToDictionary(
			p => JsonNamingPolicy.CamelCase.ConvertName(p.Name), p => p.GetValue(payload));
		fields.Add("benchmarkTrace", metadata);
		return fields;
	}

	private async Task WriteAsync()
	{
		try
		{
			await foreach (var record in _events.Reader.ReadAllAsync())
			{
				await _writer.WriteLineAsync(JsonSerializer.Serialize(record, Json));
				Interlocked.Increment(ref _written);
			}
			var footer = Record("trace.end", Dropped == 0 && Outstanding == 0 ? "drained" : "incomplete", null, null,
				new Dictionary<string, long> { ["dropped"] = Dropped, ["written"] = _written, ["outstanding"] = Outstanding,
					["eviction_queue_unknown"] = Volatile.Read(ref _evictionQueueUnknown) }, null);
			await _writer.WriteLineAsync(JsonSerializer.Serialize(footer, Json));
			await _writer.FlushAsync();
		}
		catch { Interlocked.Exchange(ref _writeFailed, 1); }
		finally
		{
			try { await _writer.DisposeAsync(); }
			catch { Interlocked.Exchange(ref _writeFailed, 1); }
		}
		if (!WriteFailed)
		{
			try { _finalizeOutput?.Invoke(); }
			catch { Interlocked.Exchange(ref _writeFailed, 1); }
		}
	}

	public async ValueTask DisposeAsync()
	{
		if (Interlocked.Exchange(ref _closed, 1) == 0)
		{
			Task[] completed;
			lock (_sends) completed = _sends.Values.Where(s => s.Source.IsCompleted).Select(s => s.Completion).ToArray();
			await Task.WhenAll(completed).ConfigureAwait(false);
			_events.Writer.TryComplete();
		}
		await _writerTask.ConfigureAwait(false);
	}
}
