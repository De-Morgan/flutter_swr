/// Collapses concurrent fetches for the same key into a single in-flight
/// [Future], so multiple simultaneous callers share one fetcher invocation
/// and one resolved value.
///
/// Dedup only collapses *concurrent* calls. Once a fetch for a key
/// completes, the next call for that key always starts a fresh fetch; SWR's
/// model is "collapse simultaneous requests," not "throttle requests."
/// Interval-based staleness is handled separately (see
/// `SwrController.isStale`).
class DedupManager {
  final Map<Object, Future<Object?>> _inFlight = {};

  /// Runs [fetcher] for [normalizedKey], or returns the already-in-flight
  /// [Future] for that key if one exists.
  Future<T> run<T>(Object normalizedKey, Future<T> Function() fetcher) {
    final existing = _inFlight[normalizedKey];
    if (existing != null) {
      return existing.then((value) => value as T);
    }

    final future = fetcher();
    _inFlight[normalizedKey] = future;
    future
        .whenComplete(() {
          if (identical(_inFlight[normalizedKey], future)) {
            _inFlight.remove(normalizedKey);
          }
        })
        // The cleanup future's own error (mirroring `future`'s) is handled
        // by callers awaiting `future`/`existing` directly; ignore it here
        // so a failed fetch doesn't also surface as an unhandled exception
        // from this untracked cleanup future.
        .ignore();
    return future;
  }
}
