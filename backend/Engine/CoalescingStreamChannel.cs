using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Channels;
using System.Threading.Tasks;
using GSSystemAnalyzer.Services;

namespace GSSystemAnalyzer.Engine
{
	public sealed class CoalescingStreamChannel<T> : IAsyncDisposable
	{
		private readonly Channel<T> _channel;
		private readonly TimeSpan _flushInterval;
		private readonly int _maxBatchSize;
		private readonly Func<IReadOnlyList<T>, Task> _flushAction;
		private readonly CancellationTokenSource _cts;
		private readonly Task _consumerTask;
		private readonly BenchmarkTrace? _trace;
		private readonly BenchmarkTrace.Observation? _consumer;
		private long _accepted, _rejected, _drained, _delivered;

		public CoalescingStreamChannel(
			Func<IReadOnlyList<T>, Task> flushAction,
			TimeSpan? flushInterval = null,
			int maxBatchSize = 100,
			CancellationToken cancellationToken = default)
		{
			_flushAction = flushAction ?? throw new ArgumentNullException(nameof(flushAction));
			_flushInterval = flushInterval ?? TimeSpan.FromMilliseconds(100);
			_maxBatchSize = maxBatchSize > 0 ? maxBatchSize : 100;
			_cts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);

			_channel = Channel.CreateUnbounded<T>(new UnboundedChannelOptions
			{
				SingleReader = true,
				SingleWriter = false
			});

			_trace = BenchmarkTrace.Current;
			_consumer = _trace?.Begin("coalescer.consumer");
			_consumerTask = Task.Run(ConsumerLoopAsync);
		}

		public bool TryWrite(T item)
		{
			if (_cts.IsCancellationRequested)
			{
				if (_trace != null) Interlocked.Increment(ref _rejected);
				return false;
			}
			if (_trace != null) Interlocked.Increment(ref _accepted);
			var accepted = _channel.Writer.TryWrite(item);
			if (!accepted && _trace != null)
			{
				Interlocked.Decrement(ref _accepted);
				Interlocked.Increment(ref _rejected);
			}
			return accepted;
		}

		public void Complete()
		{
			_channel.Writer.TryComplete();
		}

		public void Fault(Exception ex)
		{
			_channel.Writer.TryComplete(ex);
		}

		private async Task ConsumerLoopAsync()
		{
			var token = _cts.Token;
			var reader = _channel.Reader;
			var batch = new List<T>(_maxBatchSize);

			try
			{
				while (await reader.WaitToReadAsync(token))
				{
					var deadline = DateTime.UtcNow + _flushInterval;

					while (batch.Count < _maxBatchSize && reader.TryRead(out var item))
					{
						batch.Add(item);
						if (_trace != null) Interlocked.Increment(ref _drained);
					}

					if (batch.Count >= _maxBatchSize)
					{
						await FlushAsync(batch);
						batch.Clear();
						continue;
					}

					while (batch.Count > 0 && DateTime.UtcNow < deadline)
					{
						var remaining = deadline - DateTime.UtcNow;
						if (remaining <= TimeSpan.Zero) break;

						using var delayCts = new CancellationTokenSource(remaining);
						using var linkedCts = CancellationTokenSource.CreateLinkedTokenSource(token, delayCts.Token);

						try
						{
							if (await reader.WaitToReadAsync(linkedCts.Token))
							{
								while (batch.Count < _maxBatchSize && reader.TryRead(out var item))
								{
									batch.Add(item);
									if (_trace != null) Interlocked.Increment(ref _drained);
								}

								if (batch.Count >= _maxBatchSize) break;
							}
							else
							{
								// Reader completed!
								break;
							}
						}
						catch (OperationCanceledException) when (delayCts.IsCancellationRequested)
						{
							break;
						}
					}

					if (batch.Count > 0)
					{
						await FlushAsync(batch);
						batch.Clear();
					}
				}

				// Flush remaining items after completion
				while (reader.TryRead(out var item))
				{
					batch.Add(item);
					if (_trace != null) Interlocked.Increment(ref _drained);
					if (batch.Count >= _maxBatchSize)
					{
						await FlushAsync(batch);
						batch.Clear();
					}
				}

				if (batch.Count > 0)
				{
					await FlushAsync(batch);
					batch.Clear();
				}
			}
			catch (OperationCanceledException)
			{
				if (_consumer != null) _consumer.Outcome = "cancelled";
				// Clean shutdown on cancellation
			}
			catch (Exception ex) { _consumer?.Fail(ex); throw; }
			finally { _consumer?.Dispose(); }
		}

		private Task FlushAsync(List<T> batch) => _trace == null ? _flushAction(batch.ToArray()) : TraceFlushAsync(batch);

		private async Task TraceFlushAsync(List<T> batch)
		{
			using var flush = _trace?.Begin("coalescer.flush", _consumer?.Metadata.StreamId);
			try
			{
				await _flushAction(batch.ToArray());
				if (_trace != null) Interlocked.Add(ref _delivered, batch.Count);
				if (flush != null)
				{
					flush.Outcome = "succeeded";
					flush.Counts = new Dictionary<string, long> { ["delivered"] = batch.Count };
				}
			}
			catch (Exception ex) { flush?.Fail(ex); throw; }
		}

		public async ValueTask DisposeAsync()
		{
			_channel.Writer.TryComplete();
			try
			{
				await _consumerTask;
			}
			catch (Exception)
			{
				// Ignore cancellation or task faults during disposal
			}
			finally
			{
				_trace?.Emit("coalescer.summary", metadata: _consumer?.Metadata,
					counts: new Dictionary<string, long> { ["accepted"] = _accepted, ["rejected"] = _rejected,
						["drained"] = _drained, ["delivered"] = _delivered, ["abandoned"] = _accepted - _delivered });
				_cts.Dispose();
			}
		}
	}
}
