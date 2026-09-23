## 0.2.0 - 2026-09-21

- Added `skipError`, `skipLoadingOnReload`, and `skipLoadingOnRefresh` parameters to
  `SwrResponse.when`/`maybeWhen`/`map`/`maybeMap`, mirroring Riverpod's `AsyncValue.when`.
  `skipError` (default `false`) routes a failed background revalidation to the `data` branch
  instead of `error` when stale data is still available, so a transient fetch failure doesn't
  hide already-cached data.
- Fixed a "key has no fetcher" error thrown by app-resume revalidation when a controller for a
  key exists (e.g. from a persisted cache) before its fetcher is attached on first mount.

## 0.1.0 - 2026-09-17

Initial release.

- `useSwr` hook: stale-while-revalidate data fetching with request deduplication and
  automatic revalidation.
- `SwrProvider` for scoping a cache to a subtree, with a shared global cache by default.
- `mutate` for optimistic/manual cache updates, including a top-level `mutate` that reaches
  every registered `SwrCache` (not just the default).
- Conditional fetching (skip the fetch by passing a `null` key).
- `revalidateOnFocus` support via `SwrConfig`.
