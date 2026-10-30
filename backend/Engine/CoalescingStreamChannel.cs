using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Channels;
using System.Threading.Tasks;

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

			_consumerTask = Task.Run(ConsumerLoopAsync);
		}

		public bool TryWrite(T item)
		{
			if (_cts.IsCancellationRequested) return false;
			return _channel.Writer.TryWrite(item);
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
					}

					if (batch.Count >= _maxBatchSize)
					{
						await _flushAction(batch.ToArray());
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
						await _flushAction(batch.ToArray());
						batch.Clear();
					}
				}

				// Flush remaining items after completion
				while (reader.TryRead(out var item))
				{
					batch.Add(item);
					if (batch.Count >= _maxBatchSize)
					{
						await _flushAction(batch.ToArray());
						batch.Clear();
					}
				}

				if (batch.Count > 0)
				{
					await _flushAction(batch.ToArray());
					batch.Clear();
				}
			}
			catch (OperationCanceledException)
			{
				// Clean shutdown on cancellation
			}
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
				_cts.Dispose();
			}
		}
	}
}
