namespace GSSystemAnalyzer.Services;

/// <summary>
/// Reusable threshold-alert state machine with:
///   • N-consecutive-sample debounce (configurable, default 1)
///   • Hysteresis band to prevent flapping on recovery
///   • Cooldown interval + progression re-fire while alerting
///
/// Callers can qualify elapsed pressure before requesting a threshold transition.
/// Thread-safety is the caller's responsibility — the tracker itself is single-threaded.
/// </summary>
public class ThresholdAlertTracker
{
	// ── Configuration (immutable after construction) ──────────────────
	private readonly int _requiredConsecutive;
	private readonly double _hysteresisBand;
	private readonly double _reAlertIncrease;
	private readonly TimeSpan _cooldownInterval;

	// ── Mutable state ────────────────────────────────────────────────
	public bool IsAlerting { get; private set; }
	public DateTimeOffset? LastAlertedAt { get; private set; }
	public double LastAlertedValue { get; private set; }
	public DateTimeOffset? FirstDetectedAt { get; private set; }
	public int ConsecutiveCount { get; private set; }

	public ThresholdAlertTracker(
		int requiredConsecutive = 1,
		double hysteresisBand = 5.0,
		double reAlertIncrease = 5.0,
		TimeSpan? cooldownInterval = null)
	{
		_requiredConsecutive = Math.Max(1, requiredConsecutive);
		_hysteresisBand = hysteresisBand;
		_reAlertIncrease = reAlertIncrease;
		_cooldownInterval = cooldownInterval ?? TimeSpan.FromMinutes(60);
	}

	/// <summary>
	/// Evaluates a single sample against the given threshold.
	/// <paramref name="isAboveThreshold"/> should be true when ALL trigger conditions are met
	/// (this lets the caller own the threshold logic — percentage-only for disk, dual-condition for RAM).
	/// <paramref name="currentValue"/> is the raw metric value used for hysteresis/re-fire tracking (e.g. usedPercent).
	/// </summary>
	public AlertEvaluation Evaluate(
		bool isAboveThreshold,
		double currentValue,
		double threshold,
		DateTimeOffset now)
	{
		if (!IsAlerting)
		{
			//  Normal - Alerting path
			if (isAboveThreshold)
			{
				ConsecutiveCount++;
				FirstDetectedAt ??= now;

				if (ConsecutiveCount >= _requiredConsecutive)
				{
					return new AlertEvaluation(AlertAction.Fire, currentValue, FirstDetectedAt.Value);
				}

				return AlertEvaluation.None;
			}
			else
			{
				// Below threshold — reset the consecutive counter
				ConsecutiveCount = 0;
				FirstDetectedAt = null;
				return AlertEvaluation.None;
			}
		}
		else
		{
			//  Alerting - Recovery path 
			if (currentValue <= (threshold - _hysteresisBand))
			{
				return new AlertEvaluation(AlertAction.Clear, currentValue, null);
			}

			//  Still alerting: check cooldown + progression re-fire 
			bool cooldownElapsed = LastAlertedAt.HasValue &&
				(now - LastAlertedAt.Value) >= _cooldownInterval;
			bool valueClimbed = currentValue >= (LastAlertedValue + _reAlertIncrease);

			if (cooldownElapsed && valueClimbed)
			{
				return new AlertEvaluation(AlertAction.Fire, currentValue, FirstDetectedAt ?? now);
			}

			return AlertEvaluation.None;
		}
	}

	/// <summary>
	/// Called by the owner after successfully emitting an alert.
	/// Updates internal state to reflect the fired alert.
	/// </summary>
	public void RecordAlertFired(double value, DateTimeOffset now)
	{
		IsAlerting = true;
		LastAlertedAt = now;
		LastAlertedValue = value;
		// ConsecutiveCount stays — no need to reset mid-alert
	}

	/// <summary>
	/// Called by the owner after emitting a "cleared" event.
	/// Resets all state back to Normal.
	/// </summary>
	public void RecordCleared()
	{
		IsAlerting = false;
		LastAlertedAt = null;
		LastAlertedValue = 0;
		FirstDetectedAt = null;
		ConsecutiveCount = 0;
	}
}

public enum AlertAction
{
	None,
	Fire,
	Clear
}

public record AlertEvaluation(
	AlertAction Action,
	double CurrentValue,
	DateTimeOffset? FirstDetectedAt)
{
	public static readonly AlertEvaluation None = new(AlertAction.None, 0, null);
}
