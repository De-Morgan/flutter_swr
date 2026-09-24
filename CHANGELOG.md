## Unreleased

- Added `useSwrInfinite<T>(getKey, {fetcher, options, config})`, a port of React SWR's
  `useSWRInfinite` for paginated lists. It returns `(SwrResponse<List<T>>, SwrInfinite<T>)`.
  `SwrInfinite` has `size`, `setSize(n)` (completes with the new response), a bound `mutate` that
  refetches every page, and `isLoadingMore`/`isReachingEnd`. `SwrInfiniteOptions` has
  `initialSize`, `revalidateAll`, `revalidateFirstPage`, `persistSize` and `parallel`, with React's
  defaults. The list is cached as one entry, so dedup, retry, polling, app-resume revalidation,
  `onSuccess`/`onError` and `useSwrMutation` race protection all apply to it. Each page is also
  cached under its own key.
- Added `swrInfiniteKey(getKey)`, the key a `useSwrInfinite` list is cached under, for the
  top-level `mutate` and `useSwrMutation` (React's `unstable_serialize`).
- Example app: a Users screen that demonstrates `useSwrInfinite` with `pull_to_refresh` against
  reqres.in.

## 0.3.0 - 2026-09-24

- Added `useSwrMutation<T, Arg>(fetcher, {key, options})`, a port of React SWR's `useSWRMutation`
  for writes that run only when triggered. It returns `(SwrMutationState<T>, SwrTrigger<T, Arg>)`.
  With a `key` it supports `optimisticData`, `populateCache`/`populateCacheWith` and
  `rollbackOnError`, and it revalidates the key's mounted `useSwr` readers afterwards. Without a key
  it only tracks the call's state. Call it as `trigger(arg)`, or `trigger()` for no argument.
  Options are set on the hook. If `trigger` is called again before the first call finishes, only
  the latest call updates state. `trigger.reset()` returns the state to idle.
- New public types: `SwrTrigger`, `SwrMutationOptions`, `SwrMutationState`.
- Behavior change: `useSwr` now discards the result of a fetch that overlaps a `useSwrMutation` on
  the same key, success or error, and clears only `isValidating`. The key is then revalidated after
  the mutation. This only applies while a `useSwrMutation` is running on the key. `mutate` is
  unchanged.
- Example app: products can be renamed from the detail screen, which demonstrates optimistic
  update, rollback and race protection.
- Fixed `SwrConfig.onSuccess`/`onError` never being called. They now fire after each `useSwr`
  fetch whose result is written to the cache, with `(data or error, key)`. This includes polling,
  app-resume, and `mutate` revalidations. Each fetch fires once, even when several hooks share it
  through dedup. A fetch whose result is discarded because a `useSwrMutation` overlapped it fires
  neither callback. An exception thrown by a callback is not recorded as a fetch error.

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
