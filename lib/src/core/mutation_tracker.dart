/// Handle returned by [MutationTracker.begin]; pass it back to
/// [MutationTracker.end]. Ending the same token twice is a no-op.
class MutationToken {
  MutationToken._(this.key);

  /// The normalized key this mutation is running against.
  final Object key;
  bool _ended = false;
}

/// Records, per normalized key, whether a mutation is in flight and the
/// epoch of the most recent mutation boundary (begin *or* end).
///
/// A read fetch captures [epoch] when it starts; [shouldDiscard] then says
/// whether a mutation overlapped it, in which case its result may predate
/// the mutation and must not be written. The epoch moves on `end` as well
/// as `begin` so that a fetch which *starts* mid-mutation (a `useSwr`
/// mounting, a polling tick, an app resume) is still discarded once the
/// mutation ends — it may carry pre-mutation server data.
///
/// Tracked per registry and per key, not per controller: a mutation can
/// begin before any `useSwr` has created a controller for its key.
/// [_lastBoundary] keeps one `int` per key ever mutated — bounded by key
/// count, the same as the registry's controller map.
class MutationTracker {
  int _epoch = 0;
  final Map<Object, int> _inFlight = {};
  final Map<Object, int> _lastBoundary = {};

  /// The epoch to capture when a read fetch starts.
  int get epoch => _epoch;

  /// Whether at least one mutation on [key] is currently in flight.
  bool isMutating(Object key) => _inFlight.containsKey(key);

  /// Marks the start of a mutation on [key].
  MutationToken begin(Object key) {
    _epoch++;
    _inFlight[key] = (_inFlight[key] ?? 0) + 1;
    _lastBoundary[key] = _epoch;
    return MutationToken._(key);
  }

  /// Marks the end of the mutation [token] was returned for.
  void end(MutationToken token) {
    if (token._ended) return;
    token._ended = true;
    _epoch++;
    final remaining = (_inFlight[token.key] ?? 1) - 1;
    if (remaining <= 0) {
      _inFlight.remove(token.key);
    } else {
      _inFlight[token.key] = remaining;
    }
    _lastBoundary[token.key] = _epoch;
  }

  /// Whether a read fetch for [key] that started at [fetchEpoch] must be
  /// discarded: a mutation on [key] is in flight, or any mutation on [key]
  /// began or ended after the fetch started.
  bool shouldDiscard(Object key, int fetchEpoch) =>
      isMutating(key) || (_lastBoundary[key] ?? -1) > fetchEpoch;
}
