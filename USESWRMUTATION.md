# `useSwrMutation` Implementation Plan

This plan adds `useSwrMutation`, a Dart port of React SWR's
[`useSWRMutation`](https://swr.vercel.app/docs/mutation#useswrmutation), to `flutter_swr`. It is the
Post-MVP item listed in [PRODUCT_DETAILS.md](PRODUCT_DETAILS.md) §6 ("`useSwrMutation` (imperative
mutation)"), §16 (Post-MVP #2) and §17. The plan works out the API shape (§7 of PRODUCT_DETAILS only
sketched it), the changes it needs in `core/`, the tests, and the docs to update.

Status: **implemented** (0.3.0). Build log: [USESWRMUTATION_IMPLEMENTATION.md](USESWRMUTATION_IMPLEMENTATION.md).

---

## 1. What React SWR's `useSWRMutation` does

```tsx
const { data, error, trigger, reset, isMutating } = useSWRMutation(key, fetcher, options?)
// fetcher: (key, { arg }) => Promise<Data>
```

| Behavior | Detail |
| --- | --- |
| **Not triggered automatically** | Nothing runs on mount. The request starts only when `trigger(arg)` is called. |
| **Local, unshared state** | `data` / `error` / `isMutating` belong to that hook instance only. Two `useSWRMutation`s on the same key do **not** share state, and a `useSWR` on the key doesn't see mutation state either. |
| **Shares the cache** | It writes to the same cache as `useSWR` (through `optimisticData` / `populateCache`) and revalidates the key's `useSWR` readers after it finishes. |
| **Options** (hook-level, overridable per `trigger`) | `optimisticData` (value or `current => next`), `revalidate = true`, `populateCache = false` (bool or `(result, current) => next`), `rollbackOnError = true`, `throwOnError = true`, `onSuccess(data, key, config)`, `onError(err, key, config)`. |
| **Returns** | `trigger(arg, options?)`: runs the mutation and resolves to its result. `reset()`: clears `data`/`error`/`isMutating`. `isMutating`, `data`, `error`. |
| **Race protection** | A `useSWR` fetch that is in flight when a mutation starts has its result thrown away, and the key is revalidated after the mutation. Stale pre-mutation data never overwrites what the mutation wrote. |
| **Latest trigger wins** | If `trigger` is called again before an earlier call resolves, only the latest call updates hook state and fires `onSuccess`/`onError`. |
| **Missing key** | `trigger` throws if the key is falsy. |

---

## 2. Proposed Dart API

### 2.1 Hook signature

```dart
(SwrMutationState<T>, SwrTrigger<T, Arg>) useSwrMutation<T, Arg>(
  Future<T> Function(Arg arg) fetcher, {
  Object? key,
  SwrMutationOptions<T, Arg>? options,
});
```

```dart
// Bound to a key: T is also the cached type for '/api/user'.
final (updateState, updateUser) = useSwrMutation<User, String>(
  (newName) => api.updateUserName(newName),
  key: '/api/user',
  options: SwrMutationOptions(
    optimisticData: (current, newName) => current?.copyWith(name: newName),
    populateCache: true,
    revalidate: false,
  ),
);

ElevatedButton(
  onPressed: updateState.isMutating ? null : () async {
    try {
      await updateUser('Ada');
    } catch (e) {
      showSnackBar('$e');
    }
  },
  child: const Text('Rename'),
);
```

Why this shape:

- **Record return, like `useSwr`.** `useSwr` returns `(SwrResponse<T>, SwrMutate<T>)`, and this hook
  follows the same pattern: `(state, trigger)`, the two-element record sketched in PRODUCT_DETAILS
  §7. Upstream's `reset` is a method on the trigger, `trigger.reset()` (§2.2), rather than a third
  record element. Adding an element to a record later would break every call site that
  destructures it, but adding methods to `SwrTrigger` never breaks anything. This keeps the record
  stable for future additions.
- **`fetcher` takes only `Arg`, not `(key, {arg})`.** `useSwr`'s fetcher is `Future<T> Function()` and
  closes over the key at the call site. The mutation fetcher does the same, so the key is not passed
  in. `fetcher` is **required**: the ambient `SwrConfig.fetcher` is a keyed read (GET) resolver, and
  reusing it for writes would be wrong.
- **Two type parameters, `T` and `Arg`.** `T` is the fetcher's result type. `Arg` is what `trigger`
  takes. For "no argument" use `Arg = void`. See Q2 for how `trigger` is called in that case.
- **`key` is optional and named** (decided, see Q1). This changes what the hook is:
  - **With `key`:** the mutation is bound to that cache entry, and `T` **must** be the key's cached
    type. The cache is read and written as `cache.get<T>(key)`/`set<T>`. `optimisticData`,
    `populateCache`, `rollbackOnError` and `revalidate` all act on `key`. If the key already caches
    a different type (for example `List<Todo>` with `T = Todo`), `trigger` throws a `StateError`
    that names the key and points to unbound mode, instead of the raw `TypeError` that
    `cache.get<T>` would throw.
  - **Without `key`:** the hook only tracks async state for a remote call (`isMutating`/`data`/
    `error`, trigger, reset, latest-trigger-wins), and `T` can be anything. It never touches the
    cache. If readers need updating, call top-level `mutate`/`invalidate` from `onSuccess`. Example:
    a POST that returns one `Todo` while `/todos` caches `List<Todo>`.
  - Setting a cache-only option **without** a key (`optimisticData`, `populateCache: true`,
    `populateCacheWith`) is a programming error, reported with an `assert` after the options are
    merged. In debug builds and under `flutter test`, where asserts are enabled, `trigger` throws
    an `AssertionError` that names the offending options, whatever `throwOnError` is set to. In
    release builds the assert is compiled out and those options are **ignored**: the mutation runs
    in unbound mode as if they were never set. `revalidate` and `rollbackOnError` default to
    `true`, so without a key they are silently ignored in every build mode and never assert.
  - This differs from upstream, where a falsy key makes `trigger` throw. Here a `null` key means
    "not bound to the cache", not "disabled". A caller who wants the hook disabled while some
    condition is false should gate the call to `trigger` on it.

### 2.2 `SwrTrigger<T, Arg>`

```dart
/// Callable: `trigger()` / `trigger(arg)`.
abstract class SwrTrigger<T, Arg> {
  Future<T?> call([Arg? data]);

  /// Resets this hook's [SwrMutationState] to idle (no data, no error,
  /// not mutating), and makes any trigger still in flight finish without
  /// updating state or calling onSuccess/onError. The cache is not touched:
  /// optimistic/populated writes and rollback still apply.
  void reset();
}
```

- `reset()` increments the same latest-trigger counter that step 10 of §3 checks, then sets
  the state to idle. It does nothing after unmount. The in-flight trigger's own `Future` still
  completes or throws as usual for whoever is awaiting it. Only hook state and callbacks are
  suppressed.
- `trigger` increments that counter **only after** its argument checks pass (the missing-`data`
  `ArgumentError` and the unbound-mode `AssertionError`). A call rejected by those checks must not
  make the real in-flight trigger non-latest. If it did, that trigger's settle would be suppressed
  and `isMutating` would stay `true` for good.

- **`data` is optional for every `Arg` (decided, see Q2).** `trigger()` is valid for `Arg = void` or
  any nullable `Arg`. If `data` is omitted (or `null`) and `Arg` is non-nullable, `trigger` throws
  `ArgumentError('useSwrMutation<$T, $Arg>: trigger() requires `data`')` before doing anything else.
  It doesn't call the fetcher, update state, write to the cache or fire callbacks, and it throws even
  with `throwOnError: false`, because this is a programming error rather than a mutation failure.
  The check is `data == null && null is! Arg`: `null is Arg` is true for `void`, `dynamic`,
  `Object?` and `String?`, and false for `String` (checked with Dart 3). After the check, `data` is
  passed to the fetcher as `data as Arg`.
- The return type is `Future<T?>`. It completes with the result on success. On failure it throws when
  `throwOnError` is true (the default) and completes with `null` when it is false.
- The object's **identity is stable across rebuilds** (`useMemoized`), so it can be passed to child
  widgets without causing rebuilds. It reads the latest `fetcher`/`options` through a `useRef` that
  is updated on every build, so it never calls a stale closure (React SWR does the same with
  `useLatestRef`).
- The **key is captured when `trigger` is called**. If `key` changes while a mutation is in flight,
  that mutation still finishes against the key it started with.

### 2.3 `SwrMutationOptions<T, Arg>`

```dart
class SwrMutationOptions<T, Arg> {
  const SwrMutationOptions({
    this.optimisticData,
    this.revalidate,        // default true
    this.populateCache,     // no default: effective value is populateCache ?? (populateCacheWith != null)
    this.populateCacheWith,
    this.rollbackOnError,   // default true
    this.throwOnError,      // default true
    this.onSuccess,
    this.onError,
  });

  final T? Function(T? current, Arg arg)? optimisticData;
  final bool? revalidate;
  final bool? populateCache;
  final T Function(T result, T? current)? populateCacheWith;
  final bool? rollbackOnError;
  final bool? throwOnError;
  final void Function(T data, Object? key, Arg arg)? onSuccess;
  final void Function(Object error, StackTrace stackTrace, Object? key, Arg arg)? onError;

  /// `populateCache ?? (populateCacheWith != null)`: an explicit `false` always wins.
  bool get effectivePopulateCache;

  /// Field-by-field, `other`'s non-null values win — same rule as SwrConfig.merge.
  SwrMutationOptions<T, Arg> merge(SwrMutationOptions<T, Arg>? other);

  /// Merges [other] over this, then fills `revalidate`/`rollbackOnError`/`throwOnError`
  /// with `true` where still unset. This is what the engine runs with.
  SwrMutationOptions<T, Arg> resolve(SwrMutationOptions<T, Arg>? other);
}
```

Where this differs from upstream, and why:

- **`optimisticData` is function-only and also receives `arg`.** Upstream takes a value or
  `current => next`. In practice the optimistic value almost always depends on the trigger argument,
  for example `(user, newName) => user.copyWith(name: newName)`. Passing `arg` lets the optimistic
  logic sit in hook-level options instead of being repeated at every `trigger` call. A constant is
  just `(_, _) => value`. Having one field also avoids the "value vs. function, both set" ambiguity.
  If `optimisticData` returns `null`, that trigger makes **no** optimistic write, and there is
  nothing to roll back. Writing `CacheEntry(data: null)` would put every `useSwr` reader of the key
  back into `isLoading`.
- **`populateCache` (bool) and `populateCacheWith` (function) are separate fields.** Dart has no
  `bool | Function` union. `populateCache` has **no** built-in default. The effective value is
  `populateCache ?? (populateCacheWith != null)`, so setting `populateCacheWith` implies `true`, and
  an explicit `populateCache: false` always wins. With no default, the rule still holds if
  per-call options are added later (Q5): a per-call `false` could override a hook-level
  `populateCacheWith`. A `false` default merged in first would make that impossible.
- **Callbacks get `arg`, and `onError` gets the `StackTrace`.** This follows the repo's convention of
  carrying stack traces (`CacheEntry.stackTrace`, `SwrResponse.stackTrace`). Upstream's third
  parameter, `config`, has no equivalent here.
- **The callbacks' `key` is `Object?`, and it is the raw key.** In unbound mode there is no key, so
  the callbacks get `null`. In bound mode they get the key exactly as the caller passed it, not the
  normalized one: a normalized `List` key is the private `_ListKey` wrapper.
- **Exceptions thrown by `onSuccess`/`onError` propagate out of `trigger` unchanged.**
- **The global `SwrConfig.onSuccess`/`onError` are not called for mutations.** Those callbacks are
  scoped to reads, and a mutation failure is not a read failure (PRODUCT_DETAILS §9). Note that they
  aren't wired up for reads yet either (they are declared in `swr_config.dart` and nothing calls
  them). That gap is separate from this work.
- **Merge order:** built-in defaults, then hook-level `options` (`hookOptions.resolve(null)`).
  There are no per-`trigger` options (Q5). `resolve(other)` still takes an override so they can be
  added later without changing `SwrMutationOptions`. Callback fields aren't type-covariant, so the
  defaults can't be a shared `SwrMutationOptions<Never, Never>` constant. `resolve` fills them in
  afterwards instead.

### 2.4 `SwrMutationState<T>`

```dart
class SwrMutationState<T> {
  const SwrMutationState({this.data, this.error, this.stackTrace, this.isMutating = false});
  final T? data;
  final Object? error;
  final StackTrace? stackTrace;
  final bool isMutating;
}
```

Transitions (these follow upstream exactly):

| Event | `isMutating` | `data` | `error` |
| --- | --- | --- | --- |
| Initial / after `reset()` | `false` | `null` | `null` |
| `trigger` starts | `true` | unchanged | unchanged |
| Latest trigger succeeds | `false` | result | cleared |
| Latest trigger fails | `false` | unchanged | set |
| A superseded (non-latest) trigger settles | no state change, no callbacks | | |

`when`/`maybeWhen` helpers are deliberately left out of v1. Mutation state is usually read as fields
(`isMutating` to disable a button, `error` for a snackbar). They can be added later without breaking
anything.

---

## 3. `trigger` algorithm

This lives in a pure-Dart engine, `runSwrMutation` (see §5), so it can be tested under `package:test`.
Given the normalized `key`, the resolved `cache` and its `registry`, `arg`, and the merged `options`:

0. **Validate `data`:** if `data == null && null is! Arg`, throw `ArgumentError` (§2.2). This runs
   before anything else.
1. **Guard / unbound mode:** if `key` is `null`: `assert` that no cache-only option is set (§2.1).
   This throws `AssertionError` in debug and is compiled out in release. Build the list of
   offending option names inside the assert's message, so the list is only built when the assert
   fails. Once both checks pass, call `onStart`: the hook uses it to take the latest-trigger id and
   set `isMutating` (§2.2). In unbound mode, then run the fetcher and skip steps 2–4 and 6–9: no
   cache access, no tracker, no revalidation. Steps 10–11 still apply. Because unbound mode skips
   every cache step regardless of the options, cache-only options are ignored in release without
   any separate "strip options" code.
2. **Begin:** `token = registry.beginMutation(key)` (see §4). From this point, any read fetch for
   `key` that completes has its result discarded. Steps 3–7 run inside a `try`/`finally` that owns
   the token. A throwing `optimisticData`, a throwing `populateCacheWith` or the step-3 type error
   still ends the mutation, and each goes down the error path. If an optimistic write already
   happened, rollback applies.
3. **Snapshot:** `snapshot = cache.get<T>(key)`. If that throws a `TypeError` (the key caches a
   different type), rethrow it as a `StateError` naming the key (§2.1).
4. **Optimistic write** (if `optimisticData` is set): `next = optimisticData(snapshot?.data, arg)`.
   If `next` is non-null, write `CacheEntry<T>(data: next, fetchedAt: snapshot?.fetchedAt)` and
   remember `next` as `optimistic`. If it is `null`, skip the write and have nothing to roll back
   (§2.3).
5. **Run the fetcher:** `result = await fetcher(arg)`. There is **no retry and no dedup**. Mutations
   are not idempotent, so retrying a POST or collapsing two separate triggers into one would be a bug.
   This is the main way a mutation's execution differs from `SwrController.revalidate`.
6. **On success:** if `effectivePopulateCache` is true, write
   `CacheEntry<T>(data: populateCacheWith?.call(result, cache.get<T>(key)?.data) ?? result, fetchedAt: now)`.
   If it isn't set, the optimistic value (if any) stays until revalidation replaces it.
7. **On error:** if `rollbackOnError` is set, an optimistic write happened, **and** the cache still
   holds `identical(cache.get(key)?.data, optimistic)`, restore `snapshot.copyWith(isValidating: false)`
   (or `cache.delete(key)` if there was no snapshot). The identity check stops a rollback from
   overwriting a newer write made by someone else in the meantime (upstream does the same
   comparison). `isValidating` is forced to `false` because the snapshot may have been taken while
   a read fetch was in flight. That fetch is discarded (§4.2). With `revalidate: false`, restoring
   the snapshot verbatim would leave `isValidating: true` in the cache with nothing to clear it.
8. **End:** `registry.endMutation(token)`, which ends the token and calls
   `dedupManager.forget(key)` (§4.3). This runs in a `finally` so the key can't get stuck in the
   mutating state.
9. **Revalidate** (if `revalidate` is set), on both the success and error paths, as upstream does. It
   reconciles with the server after a rollback too. Revalidate only if `registry[key]` exists,
   `controller.hasFetcher` is true **and** `cache.hasWatchers(key)` is true. If so, call
   `controller.revalidate()` using its remembered fetcher. The `hasFetcher` check is the same one
   `app_lifecycle_listener.dart` uses. A controller can exist before its first fetcher is attached
   (the cold-start race fixed in 0.2.0). Revalidating it then would write a "no fetcher" error into
   the cache. The call is **not awaited** (`unawaited`): `trigger` resolves with the mutation
   result, and readers see the refetch through `useSwr`.
10. **Hook state and callbacks:** only if this trigger is still the hook's latest (a `_latestTriggerId`
    counter, which `reset()` also increments) and the hook is still mounted (`context.mounted`):
    update `SwrMutationState`, then call `onSuccess`/`onError`. The engine takes this check as an
    `isCurrent()` callback.
11. **Return / throw:** return `result`, or rethrow when `throwOnError` is set, otherwise return `null`.

**Cache scope:** the hook uses the cache from `SwrProvider.of(context)`, like a bound `useSwr` mutate.
It does **not** walk `allRegistries()` the way top-level `mutate` does. A mutation hook mounted under
a provider acts on that provider's data.

---

## 4. Core changes: race protection

The upstream guarantee is: "after the mutation, `useSWR` ditches the ongoing request and revalidates,
so stale data is never displayed". It needs two small additions to `core/`, and both stay pure Dart.

### 4.1 `MutationTracker` (new, `lib/src/core/mutation_tracker.dart`)

Each `SwrControllerRegistry` owns one, the same way it owns its `DedupManager`, and injects it into
every controller it creates.

```dart
class MutationTracker {
  int _epoch = 0;                            // bumped on every begin AND every end
  final Map<Object, int> _inFlight = {};     // key -> count of active mutations
  final Map<Object, int> _lastBoundary = {}; // key -> epoch of latest begin or end

  MutationToken begin(Object key);
  void end(MutationToken token);             // ending a token twice is a no-op

  /// Epoch to capture when a read fetch starts.
  int get epoch;

  bool isMutating(Object key);

  /// Whether a read fetch for [key] that started at [fetchEpoch] must be discarded:
  /// a mutation on [key] is in flight, or any mutation on [key] began *or ended*
  /// after the fetch started.
  bool shouldDiscard(Object key, int fetchEpoch) =>
      isMutating(key) || (_lastBoundary[key] ?? -1) > fetchEpoch;
}
```

Why the epoch moves on `end` as well as `begin`: take a fetch that starts **during** a mutation.
That happens when a `useSwr` mounts mid-mutation, on a polling tick, or on app resume. The fetch
captures the epoch *after* `begin`. If only `begin` moved the epoch, the check would say "keep" once
the mutation ended, and that fetch can carry pre-mutation server data. Because `end` moves the
epoch too, the fetch sees a boundary after its start and is discarded. A fetch that starts after
`end` captures the epoch `end` produced and is kept.

It is tracked **per registry and per key, not per controller**. `useSwrMutation` can fire before any
`useSwr` has created a controller for the key. If a `useSwr` then mounts mid-mutation, its first fetch
still has to be discarded. `_lastBoundary` keeps one `int` for every key ever mutated, which is
bounded by key count, the same as the registry's controller map.

The tracker is pure bookkeeping and doesn't know about `DedupManager`. The registry exposes the entry
points the mutation engine calls:

```dart
MutationToken beginMutation(Object normalizedKey) => mutations.begin(normalizedKey);

void endMutation(MutationToken token) {
  mutations.end(token);
  _dedupManager.forget(token.key);
}
```

### 4.2 `SwrController.revalidate` change

- Capture `fetchEpoch = mutations.epoch` before starting the fetch.
- When it resolves (success or failure), if `mutations.shouldDiscard(key, fetchEpoch)` is true, skip
  the data/error write and only clear `isValidating`, as long as no newer revalidation owns that flag.
  That needs a per-controller `_revalidationSeq`; confirm this against the existing
  `isValidating` tests.
- The tracker is an optional constructor parameter (default `MutationTracker()`), so tests that
  construct `SwrController` directly still compile.

### 4.3 `DedupManager.forget(key)`

This drops the in-flight entry for `key` without cancelling the underlying future. Without it, the
post-mutation `revalidate()` in step 9 would **join** the pre-mutation in-flight fetch through dedup,
get the same (discarded) result, and the key would never be refreshed. `registry.endMutation()`
calls `forget` right after `tracker.end()`, before the revalidation starts (§4.1).

### 4.4 Side benefit (out of scope)

The same tracker could protect bound `mutate(data: …)` and global `mutate(key, data: …)` from the
same race: an older in-flight fetch overwriting a direct write. Wiring them to it is a one-line
change each, but it changes existing public behavior. Leave it for a follow-up and record it in
IMPLEMENTATION_PLAN.md.

---

## 5. Files

| File | Change |
| --- | --- |
| `lib/src/core/mutation_tracker.dart` | **New.** `MutationTracker`, `MutationToken`. Pure Dart. |
| `lib/src/core/dedup_manager.dart` | Add `forget(key)`. |
| `lib/src/core/swr_controller.dart` | Registry owns a `MutationTracker`, passes it to controllers, and exposes `beginMutation`/`endMutation`. `revalidate` captures an epoch and discards stale results. |
| `lib/src/mutation/swr_mutation_options.dart` | **New.** `SwrMutationOptions<T, Arg>` + `merge`/`resolve`/`effectivePopulateCache`. Pure Dart. |
| `lib/src/mutation/swr_mutation.dart` | **New.** `runSwrMutation<T, Arg>(...)`, the §3 algorithm with no hook concerns. It reports state changes through callbacks (`onStart`, `onSettled`) so the hook layer can gate them on the latest trigger and on mount. Pure Dart. |
| `lib/src/hooks/swr_mutation_state.dart` | **New.** `SwrMutationState<T>`. |
| `lib/src/hooks/use_swr_mutation.dart` | **New.** The hook: resolve config/cache/registry, `useState` for state, `useRef` for latest fetcher/options, `useMemoized` stable `SwrTrigger` (including `reset()`), mounted guard via `useContext()` + `context.mounted` (`useIsMounted` is deprecated in flutter_hooks 0.21). |
| `lib/flutter_swr.dart` | Export `swr_mutation_options.dart`, `swr_mutation_state.dart`, `use_swr_mutation.dart`. **Do not** export `swr_mutation.dart` or `mutation_tracker.dart`; they are internal. |

The layering rule from CLAUDE.md still holds: `core/` and `mutation/` import no Flutter code, and the
only Flutter code is in `hooks/`.

---

## 6. Test plan

The suite mirrors `lib/src/` one-to-one. There is no real network and no real delays: fetchers are
fakes backed by `Completer`s, and timing uses `fake_async`.

**`test/core/mutation_tracker_test.dart`** (new)
- `shouldDiscard` returns true while a mutation is in flight, and true for a fetch that started
  before a mutation began, even after the mutation has ended.
- It returns true for a fetch that started **during** a mutation, both while the mutation is in
  flight and after it ends.
- It returns false for a fetch that started after the last mutation ended.
- Overlapping mutations on one key: the key is not "clear" until both have ended.
- Ending the same token twice is a no-op.
- Keys are independent.

**`test/core/dedup_manager_test.dart`** (extend)
- After `forget(key)`, the next `run` starts a fresh fetch, and the original future still completes
  for callers already waiting on it.

**`test/core/swr_controller_test.dart`** (extend)
- A fetch in flight when a mutation begins resolves → cache data is unchanged and `isValidating`
  is cleared.
- A failed fetch in the same situation also leaves the error unrecorded.
- A fetch that starts during the mutation and resolves after it ends is discarded.
- A fetch that starts after the mutation ends writes as normal.
- A discarded older fetch doesn't clear a newer revalidation's `isValidating: true`.
- After `registry.endMutation`, `revalidate()` starts a new fetch instead of joining the
  pre-mutation one.

**`test/mutation/swr_mutation_test.dart`** (new, pure Dart, against `InMemoryCache` + registry)
- The fetcher receives `arg` and is called exactly once, with no retry on failure.
- Two concurrent triggers each call the fetcher, with no dedup.
- `optimisticData` is visible in the cache synchronously, before the fetcher resolves.
- `rollbackOnError` restores the exact snapshot, or deletes the entry when there was no snapshot.
- Rollback is skipped when another write replaced the optimistic value in the meantime.
- `rollbackOnError: false` leaves the optimistic value in place.
- `populateCache` writes the result, and `populateCacheWith` receives `(result, current)`. With the
  default `false`, the result is not written.
- `revalidate` fires only when a controller exists and has watchers, runs on both success and error,
  and `revalidate: false` suppresses it.
- `throwOnError: false` resolves to `null`, and the default rethrows.
- No key: the fetcher runs, the result is returned, and the cache and tracker are untouched (the
  cache has no writes and no watchers are notified). A result type unrelated to any cached type
  works.
- No key plus `optimisticData`/`populateCache`/`populateCacheWith` throws `AssertionError`
  (`throwsA(isA<AssertionError>())`) even with `throwOnError: false`, and the fetcher is not
  called. The release-mode "ignored" path can't be tested directly because tests run with asserts
  enabled. It's covered structurally instead: the no-key test above proves unbound mode never
  touches the cache, and that is the only path a key-less trigger can take.
- Missing `data` for a non-nullable `Arg` (`String`) throws `ArgumentError`, even with
  `throwOnError: false`. The fetcher isn't called, the cache and tracker are untouched, and no
  callbacks fire.
- Missing `data` is fine for `void` and for nullable `Arg` (`String?`): the fetcher receives `null`.
- `resolve(override)` merges field by field over the hook-level options. This is the path per-call
  options would use (Q5).
- `optimisticData` returning `null`: no write, and a failure neither rolls back nor deletes.
- A snapshot taken while `isValidating: true` is restored with `isValidating: false`.
- A controller that has watchers but no fetcher is not revalidated, and no error is written.
- Bound mode with a mismatched `T` throws `StateError`, and the key isn't left mutating.
- A read fetch in flight when the mutation starts, resolving before the mutation does, never lands
  in the cache.
- `isCurrent()` returning false suppresses `onSettled`/`onSuccess`/`onError`, but the returned
  future still completes or throws.
- `onStart` is never called when the `ArgumentError` or `AssertionError` check fires.

**`test/mutation/swr_mutation_options_test.dart`** (new)
- `merge`: per field, the child's non-null value wins.
- `resolve` defaults to `revalidate: true`, `rollbackOnError: true`, `throwOnError: true`.
- `effectivePopulateCache`: unset → false; `populateCacheWith` alone → true; explicit `false` +
  `populateCacheWith` → false.

**`test/hooks/swr_mutation_state_test.dart`** (new): idle defaults, and `copyWith`.

**`test/hooks/use_swr_mutation_test.dart`** (new, `flutter_test` + `HookBuilder`)
- Mounting never calls the fetcher, and the initial state is idle.
- `trigger` → `isMutating` true, then on success `data` is set, `error` is cleared and `isMutating`
  is false.
- Failure → `error`/`stackTrace` are set, `data` is kept, and `trigger`'s future throws.
- `trigger.reset()` returns to idle. An in-flight trigger settling after `reset` does not change
  state or call `onSuccess`/`onError`, but its `Future` still completes or throws for the caller.
- `trigger.reset()` after unmount is a no-op and doesn't throw.
- Latest trigger wins: the first of two triggers settling last doesn't overwrite state, and its
  `onSuccess` isn't called.
- Two `useSwrMutation` hooks on the same key don't share state.
- Unmounting mid-flight → the trigger still completes, and there are no set-state-after-dispose
  errors.
- The trigger's identity is stable across rebuilds, and it uses the latest `fetcher` passed in.
- **Integration with `useSwr`:** a mounted `useSwr(key)` shows the optimistic data right away, then
  the populated data. A `useSwr` fetch that was in flight when the trigger started never shows its
  stale result. The reader refetches after the mutation.
- It uses the `SwrProvider`-scoped cache and does not touch the default cache.
- A rejected `trigger()` call (missing `data`) while another trigger is in flight doesn't stop that
  trigger from settling state.
- Changing `key` mid-flight: the in-flight mutation still finishes against its original key.

`flutter analyze` must be clean and `flutter test` must pass before this is done.

---

## 7. Docs and example

- **README.md**: add a `useSwrMutation` section (basic, optimistic + rollback, `populateCache`,
  deferred loading). Update the React SWR comparison table: `useSWRMutation` → `useSwrMutation`,
  with the divergences from §2.3 (`optimisticData` gets `arg`, the `populateCacheWith` split,
  `trigger(arg)` / bare `trigger()` with its runtime check for non-nullable `Arg`, no per-call
  options (Q5), the
  two-element record return, `reset` living on the trigger as
  `trigger.reset()`).
- **PRODUCT_DETAILS.md**: replace the §7 sketch with the final signature. Update §11 (the
  optimistic/rollback convenience now exists, through `useSwrMutation`). Resolve the §21 open question
  on the optimistic-update API shape. Mark §16 Post-MVP #1 and #2 as delivered.
- **IMPLEMENTATION_PLAN.md**: add a "Phase 18: `useSwrMutation`" entry that points to this document,
  and record the §4.4 follow-up.
- **CHANGELOG.md**: add an entry under the next minor version (new public API).
- **example/**: add a mutation to the Fake Store demo, for example editing a product title with
  `PUT /products/:id` using `optimisticData` + `populateCache`, with a `useSwr` detail view mounted
  on the same key to show the race protection in practice. Check it manually in the running app.
  The Fake Store API doesn't persist writes (a `GET` after a `PUT` returns the seed data), so the
  example sets `revalidate: false`, with a comment saying why. Otherwise the refetch would visibly
  undo the edit.

---

## 8. Build order

1. `MutationTracker` + tests.
2. `DedupManager.forget` + tests.
3. Wire the tracker into `SwrControllerRegistry`/`SwrController.revalidate` + tests, and confirm the
   existing controller/hook suites are still green.
4. `SwrMutationOptions` + `runSwrMutation` + pure-Dart tests.
5. `SwrMutationState` + `useSwrMutation` hook + widget tests.
6. Barrel exports, then `flutter analyze` and `flutter test`.
7. Example app screen and the manual check.
8. README, PRODUCT_DETAILS, IMPLEMENTATION_PLAN, CHANGELOG.

Steps 1–3 are useful on their own and can land as a separate PR first.

---

## 9. Open questions

- **Q1: Separate cache type from result type? DECIDED.** `key` is optional. With a key, `T` must be
  the key's cached type. Without one, `T` is unconstrained and the hook does not touch the cache.
  See §2.1. This covers the "POST returns one `Todo`, the key caches `List<Todo>`" case without a
  third type parameter.
- **Q2: `void` argument ergonomics. DECIDED: option (b), positional.** The API is
  `trigger([Arg? data])`, so both `trigger()` and `trigger(arg)` compile, and leaving out `data` for a non-nullable `Arg` throws
  `ArgumentError` at runtime (§2.2). This gives up a compile-time check in exchange for simpler call
  sites. Findings that led here, checked with `dart analyze` against Dart 3:
  - **Named vs. positional makes no difference; only required vs. optional does.**
  - `call({required Arg data})`: `trigger()` is a compile error even for `void`, so you have to
    write `trigger(data: null)`.
  - `call({Arg? data})` (or `[Arg? arg]`): `trigger()` compiles for **every** `Arg`. Forgetting the
    argument when `Arg = String` is then a runtime `TypeError` (`type 'Null' is not a subtype of
    type 'String'`), not a compile error.
  - Separate extensions, `call()` on `SwrTrigger<T, void>` and `call(Arg)` on
    `SwrTrigger<T, Arg extends Object>`: this gives compile-safe `trigger()` for `void` and
    `trigger(x)` for non-null `Arg`. It breaks for nullable `Arg` (`String?`): the unbounded or
    nullable variant is ambiguous with the `void` extension (`ambiguous_extension_member_access`),
    and with the bounded one a `String?` trigger can't pass a value. Extensions also dispatch on
    static type only, so generic code can't call it. Rejected.
  - Options: **(a)** required argument, `trigger(null)` / `trigger(data: null)` for `void`, fully
    type-safe. **(b)** optional `{Arg? data}`, where `trigger()` always compiles and omitting a
    non-nullable argument fails at runtime with a clear `ArgumentError`. This matches JS, where
    `arg` is optional.
- **Q5: Per-call options on `trigger`? DECIDED: no, for now.** Upstream has `trigger(arg, options)`.
  Dart can't mix optional positional and named parameters (`call([Arg? data], {options})` is a parse
  error), so keeping named `options` would have forced `trigger(data: arg)`. Most of what per-call
  options do is already covered:
  - a per-call `onSuccess`/`onError` → `await trigger(arg)` plus `try`/`catch`;
  - a per-call `throwOnError` → `try`/`catch`;
  - a per-call `optimisticData` → the hook-level function already receives `arg`.

  Only a one-off `revalidate`/`populateCache` override has nothing to replace it, and that's rare.
  Adding an optional second positional parameter later, `call([Arg? data, SwrMutationOptions? options])`,
  is non-breaking. Removing one after release wouldn't be.
- **Q3: Should an optimistic write mark the entry `isValidating: true`?** Upstream doesn't. Leaving
  it unset means `useSwr` readers see settled data during the mutation. Recommendation: leave it
  unset.
- **Q4: Should the post-mutation revalidation be awaited?** The plan says no, which matches upstream.
  Bound `mutate` does await its revalidation, so the two differ. That's acceptable because `trigger`
  returns the mutation result, while `mutate` has nothing else to return. Record the difference in
  the README.
