# Implementation Plan

This plan turns [PRODUCT_DETAILS.md](PRODUCT_DETAILS.md) into a sequenced, buildable implementation for the `flutter_swr` package. It covers package structure, module design, build order, and testing/acceptance criteria for each phase. It does not restate the product rationale — see PRODUCT_DETAILS.md for the "why" behind every decision referenced here.

Scope boundary: this plan implements the **MVP** (PRODUCT_DETAILS.md §16) end-to-end, then lays out the Post-MVP phases in the same level of detail so they can be picked up later without re-deriving the architecture. One deviation from PRODUCT_DETAILS.md as written: **polling (`refreshInterval`) has been pulled forward into MVP scope** (Phase 10 below) rather than left Post-MVP — PRODUCT_DETAILS.md §6/§16/§17 should be updated to match if this plan is treated as the source of truth going forward.

## 1. Package Structure

Single package (`flutter_swr`), no `swr_core`/`flutter_swr` split for v1 — deferred per Open Question in PRODUCT_DETAILS.md §21; revisit only if a non-Flutter Dart consumer materializes.

```
lib/
  flutter_swr.dart              # public export barrel
  src/
    cache/
      swr_cache.dart            # SwrCache interface (get/set/delete/keys)
      in_memory_cache.dart      # default in-memory implementation
      cache_entry.dart          # CacheEntry<T>: value, timestamp, error, isValidating
      key_normalizer.dart       # normalizes Object keys to stable identity
    core/
      dedup_manager.dart        # in-flight Future tracking per normalized key
      retry_policy.dart         # SwrRetryPolicy + exponential backoff executor
      revalidation_scheduler.dart # timers (polling) + lifecycle hooks -> revalidate
      swr_controller.dart       # glues cache + dedup + retry + scheduler per key
    mutation/
      mutate.dart               # SwrMutate<T> typedef + bound-mutate implementation
      global_mutate.dart        # top-level mutate<T>(key, ...) function
    config/
      swr_config.dart           # SwrConfig data class (fetcher, intervals, retry, callbacks, cache)
      swr_provider.dart         # InheritedWidget scoping SwrConfig, with ancestor merge
    hooks/
      use_swr.dart              # useSwr<T> hook
      swr_response.dart         # SwrResponse<T> (data/error/isLoading/isValidating + when/maybeWhen/map)
    lifecycle/
      app_lifecycle_listener.dart # WidgetsBindingObserver wrapper feeding the scheduler
test/
  cache/
  core/
  mutation/
  hooks/
  lifecycle/
example/
  lib/main.dart                 # runnable demo app (§20 of PRODUCT_DETAILS.md)
```

**New dependency**: add `flutter_hooks` to `pubspec.yaml` (`dependencies:`); it is the foundation the whole hook layer sits on and is currently absent. Add `connectivity_plus` only in the separate Post-MVP adapter, never as a core dependency (per PRODUCT_DETAILS.md §12).

## 2. Build Order and Rationale

Modules are built bottom-up: each phase only depends on modules already implemented and tested in a prior phase, so every phase ends with something independently verifiable (no phase depends on the hook layer existing yet, since that's the riskiest/most integration-heavy piece and comes last).

```
Phase 1: Cache primitives
Phase 2: Key normalization
Phase 3: Dedup manager
Phase 4: Retry policy
Phase 5: SwrController (glues 1-4 into one per-key state machine)
Phase 6: Config + Provider
Phase 7: Hook layer (useSwr, SwrResponse)
Phase 8: Bound + global mutate, cascade invalidation
Phase 9: App-lifecycle revalidation
Phase 10: Polling (refreshInterval)
Phase 11: Conditional/dependent fetching support
Phase 12: Example app + integration pass
Phase 13+: Post-MVP features (below)
```

---

## Phase 1 — Cache Primitives

**Files**: `src/cache/cache_entry.dart`, `src/cache/swr_cache.dart`, `src/cache/in_memory_cache.dart`

- `CacheEntry<T>`: immutable value holder — `T? data`, `Object? error`, `DateTime? fetchedAt`, `bool isValidating`. Provide a `copyWith`.
- `SwrCache` abstract interface: `CacheEntry<T>? get<T>(Object key)`, `void set<T>(Object key, CacheEntry<T> entry)`, `void delete(Object key)`, `Iterable<Object> keys()`, plus a way to subscribe to changes for a key (a `Stream<CacheEntry<T>>` or `ValueListenable<CacheEntry<T>?>` per key) — this subscription mechanism is what the hook layer (Phase 7) will listen to.
- `InMemoryCache implements SwrCache`: backed by a `Map<Object, CacheEntry>` plus a `Map<Object, ChangeNotifier or StreamController>` per key for change notification. Lazily creates the notifier for a key on first subscription; disposes it when no listeners remain.
- Staleness is **not** stored as a boolean on the entry — compute it at read time from `fetchedAt` + a caller-supplied freshness window, so the same entry can be "stale" under one caller's config and "fresh" under another's (matches PRODUCT_DETAILS.md §10: "staleness is a separate, time-based flag, not deletion").

**Acceptance criteria**:

- Unit tests: set/get/delete round-trip; get on unset key returns `null`; setting a key notifies subscribers; deleting a key notifies subscribers with `null`.
- No dependency on `flutter_hooks`, `flutter`, or any widget code — this module must be pure Dart so it's trivially unit-testable without `flutter_test`.

## Phase 2 — Key Normalization

**Files**: `src/cache/key_normalizer.dart`

- Function `Object normalizeKey(Object key)`. For `String`/primitives, return as-is (they already have correct `==`/`hashCode`). For `List`, wrap in an internal `_ListKey` class implementing deep `==`/`hashCode` (Dart `List` does not have value equality by default — this is the concrete fix for PRODUCT_DETAILS.md §5's "equality/hashing rules are defined explicitly"). Dart 3 `Record`s already have structural equality, so pass them through unchanged.
- `null` is a valid key input meaning "don't fetch" — normalization is skipped entirely upstream in the hook (Phase 7/10), not handled here.

**Acceptance criteria**:

- Unit tests: two distinct `List` instances with equal contents normalize to equal (`==`) keys and equal hash codes; a `Record` key works out of the box; a `String` key is returned unchanged (identity-preserving, not just value-equal, to avoid unnecessary allocation).

## Phase 3 — Request Deduplication Manager

**Files**: `src/core/dedup_manager.dart`

- `DedupManager`: `Future<T> run<T>(Object normalizedKey, Future<T> Function() fetcher, {required Duration dedupingInterval})`.
- Internally tracks `Map<Object, _InFlight>` where `_InFlight` holds the shared `Future` and the `DateTime` it started. A new call for the same key:
  - If an in-flight `Future` exists for that key, return it directly (true dedup — no second fetcher invocation).
  - Else if the last completed fetch for that key finished within `dedupingInterval`, still start a genuinely new fetch (dedup only collapses _concurrent_ calls, not sequential ones after completion — matches SWR's model of collapsing simultaneous requests, not rate-limiting).
  - Else start a new fetch, register it as in-flight, and clear the in-flight entry on completion (success or failure) via `whenComplete`.

**Acceptance criteria**:

- Unit tests: two calls issued synchronously (before either resolves) for the same key result in exactly one fetcher invocation and both callers receive the same resolved value; two calls issued after the first has resolved each invoke the fetcher; two calls for _different_ keys never collapse.

## Phase 4 — Retry Policy

**Files**: `src/core/retry_policy.dart`

- `SwrRetryPolicy`: `int maxAttempts`, `Duration Function(int attempt) backoff` (default exponential: `min(2^attempt * baseDelay, maxDelay)`), optional `bool Function(Object error, int attempt)? shouldRetry` (defaults to "always retry until maxAttempts").
- `Future<T> executeWithRetry<T>(Future<T> Function() fetcher, SwrRetryPolicy policy, {void Function(Object error, int attempt)? onAttemptFailed})`: loops, catching failures, awaiting `backoff(attempt)` between attempts, rethrowing the last error once `maxAttempts` is exhausted or `shouldRetry` returns `false`.

**Acceptance criteria**:

- Unit tests (using `FakeAsync`/`fake_async` package or injected clock to avoid real delays): fetcher failing N times then succeeding resolves successfully with exactly N+1 invocations; fetcher failing beyond `maxAttempts` rethrows the final error with exactly `maxAttempts` invocations; `shouldRetry` returning `false` stops immediately regardless of `maxAttempts`.

## Phase 5 — SwrController (per-key state machine)

**Files**: `src/core/swr_controller.dart`

This is the module where Phases 1–4 compose into the actual stale-while-revalidate behavior, independent of any widget/hook concerns.

- `SwrController<T>`: owns one normalized key, a reference to the shared `SwrCache`, `DedupManager`, and `SwrRetryPolicy`.
- `CacheEntry<T>? get currentEntry` — synchronous read from the cache (used for the "return cached data instantly" half of stale-while-revalidate).
- `Future<void> revalidate({required Future<T> Function() fetcher})`:
  1. Mark the cache entry's `isValidating = true` (preserving existing `data`/`error`) and notify subscribers immediately.
  2. Run `fetcher` through `DedupManager.run` wrapped in `RetryPolicy.executeWithRetry`.
  3. On success: write a fresh `CacheEntry(data: result, error: null, fetchedAt: now, isValidating: false)`.
  4. On failure: write `CacheEntry(data: <preserve existing data>, error: e, fetchedAt: <preserve>, isValidating: false)` — never discard last-good `data` on a failed revalidation (PRODUCT_DETAILS.md §9 transition rules).
- `bool isStale(Duration freshnessWindow)` — computed from `currentEntry.fetchedAt`.

**Acceptance criteria**:

- Unit tests (pure Dart, fake fetcher functions, no widgets): initial revalidate with no prior entry produces `isLoading`-equivalent state (no data, isValidating true) then resolves to populated data; revalidate with existing data keeps that data visible with `isValidating: true` throughout, then updates; failed revalidate preserves prior `data`, sets `error`; concurrent `revalidate()` calls for the same controller dedup through `DedupManager` correctly.

## Phase 6 — Configuration and Provider

**Files**: `src/config/swr_config.dart`, `src/config/swr_provider.dart`

- `SwrConfig`: immutable data class — `Future<T> Function()? fetcher` (generic per-call, so stored as a nullable resolver typedef, not a concrete `Future<T> Function()` at the config level — see note below), `Duration dedupingInterval`, `Duration? refreshInterval`, `SwrRetryPolicy retry`, `void Function(Object error, Object key)? onError`, `void Function(Object? data, Object key)? onSuccess`, `SwrCache? cache`.
  - _Design note_: since `SwrConfig` is not generic but individual `useSwr<T>` calls are, the "default fetcher" concept at the config level is necessarily a keyed resolver (`Future<dynamic> Function(Object key)?`) that the hook casts/uses per its own `T`, rather than a literal `Future<T> Function()`. Document this clearly in doc comments so it's not mistaken for a type-safety hole — it's an intentional boundary between the generic hook and the non-generic global config, exactly the same boundary SWR's `fetcher` option in `<SWRConfig>` has in a dynamically-typed language, made explicit here.
- `SwrProvider extends InheritedWidget`: holds a resolved `SwrConfig` that **merges** with the nearest ancestor `SwrProvider`'s config field-by-field (non-null fields on the child override the parent; unset fields fall through) — implements the "nested providers merge" rule from PRODUCT_DETAILS.md §14.
- Static `SwrProvider.of(BuildContext context)` returning the merged `SwrConfig`, falling back to a package-level default `SwrConfig` (in-memory cache, no default fetcher, standard retry policy) when no provider is present in the tree — this is what makes `useSwr` work with zero setup (per the Open Question in §21, defaulting to "works with zero setup," revisit if that decision changes).

**Acceptance criteria**:

- Widget tests: a `useSwr` call inside a nested `SwrProvider` observes the merged config (child's explicit `retry` overrides parent's, but child's unset `dedupingInterval` inherits the parent's); no `SwrProvider` in the tree still resolves to sane defaults, not a null-check crash.

## Phase 7 — Hook Layer: `useSwr` and `SwrResponse`

**Files**: `src/hooks/swr_response.dart`, `src/hooks/use_swr.dart`

- `SwrResponse<T>`: immutable class with `data`, `error`, `isLoading`, `isValidating`, and `when`/`maybeWhen`/`map` methods implemented as straightforward conditionals over the core fields (no need for a sealed-class hierarchy — a single concrete class computing these fields is simpler and matches the "not more abstraction than needed" instruction, since there's no meaningfully different _shape_ of data per state the way a sealed class would buy you, just different field values).
- `useSwr<T>(Object? key, {Future<T> Function()? fetcher, SwrOptions<T>? options})`:
  1. Resolve merged config via `SwrProvider.of(context)` (needs `useContext()` from `flutter_hooks`).
  2. If `key == null`, return a "never fetched, no error, not loading" `SwrResponse` immediately and skip all controller/subscription setup — this is the conditional-fetching short-circuit (Phase 10 covers the "key throws" variant).
  3. `useMemoized`/`Hook.use` to obtain (or create, cached by normalized key) a `SwrController<T>` scoped to the resolved `SwrCache`.
  4. Subscribe to the controller's cache-entry changes via a `useState`/`useValueListenable`-style hook primitive so the widget rebuilds on change; unsubscribe `useEffect`-cleanup on dispose or key change.
  5. `useEffect` with `[normalizedKey]` as keys: on first mount (or key change), if there's no entry or the entry is stale, call `controller.revalidate(fetcher: fetcher ?? config.fetcher-for-this-key)`.
  6. Build and return the `SwrResponse<T>` from the current cache entry, and the bound `SwrMutate<T>` (Phase 8) as the second record element: `(response, mutate)`.

**Acceptance criteria**:

- Widget tests: first mount with a fresh key shows `isLoading: true` then resolves to `data`; two widgets mounting the same key simultaneously trigger exactly one fetcher call (dedup verified at the hook level, not just the unit level); changing the `key` passed to `useSwr` between rebuilds correctly unsubscribes the old key and subscribes/fetches the new one; disposing the widget unsubscribes (verified via no lingering listeners on the cache).

## Phase 8 — Mutation: Bound and Global

**Files**: `src/mutation/mutate.dart`, `src/mutation/global_mutate.dart`

- `SwrMutate<T>` (bound, returned from `useSwr`): implements the record-callable shape from PRODUCT_DETAILS.md §7:

  ```dart
  Future<void> call([T? data, T Function(T?)? updater, {List<Object> invalidate = const []}]);
  ```

  (Dart doesn't allow optional-positional + named mixed exactly like this in one signature ergonomically — finalize as either two named parameters `data`/`updater` with no positional data, or a small sealed `MutationInput<T>` argument; resolve during implementation, but the three call shapes from §7 (`mutate(newUser)`, `mutate(updaterFn)`, `mutate(invalidate: [...])`) must all type-check cleanly.)- Own-key path: if `data`/`updater` provided, write directly to the cache via the controller (bypassing dedup — a direct write is not a fetch) and notify subscribers, then trigger `controller.revalidate()` unless the call opts out.
  - No-data path (`mutate()`): just calls `controller.revalidate()`.
  - `invalidate: [...]` path: for each key in the list, look up (or lazily create) that key's controller from the **shared cache/registry** (see design note below) and call `.revalidate()` on it if it has active subscribers; never write data for those keys.

- **Design note — controller registry**: `SwrController` instances must live in a registry keyed by normalized key, scoped to the `SwrCache` instance (so `SwrProvider`-scoped caches get independent registries). This registry is what both `useSwr` (Phase 7, to find/create its own controller) and `mutate`'s cascade-invalidation path (to reach _other_ keys' controllers) use. Implement this registry as part of Phase 5's `SwrController` module (a `SwrControllerRegistry` alongside it) rather than bolting it on in Phase 8 — flag this dependency now so Phase 5 isn't revisited later.
- `global_mutate.dart`: top-level `Future<void> mutate<T>(Object key, {T? data, bool revalidate = true})` reaching every `SwrCache` known to have registered a controller for `key` — the **default/global** `SwrCache` (the one `SwrProvider.of` falls back to when no provider is present) plus any `SwrProvider`-scoped cache that has already fetched that key. This is a deliberate divergence from SWR's per-provider `useSWRConfig().mutate` scoping (which only reaches one scope at a time), chosen so a single call can invalidate a key across independently-scoped subtrees.

**Acceptance criteria**:

- Unit/widget tests: `mutate(newData)` updates the subscribed widget synchronously before the subsequent revalidation resolves; `mutate()` with no args triggers exactly one revalidation and no cache write; `mutate(invalidate: [otherKey])` triggers a revalidation on `otherKey`'s controller (verified via a second mounted `useSwr(otherKey)` widget updating) and does **not** alter `otherKey`'s `data` field before that revalidation completes; invalidating a key with zero mounted subscribers is a safe no-op (no crash, optionally lazily marks it stale for next mount — decide during implementation and document the choice).

## Phase 9 — App-Lifecycle Revalidation

**Files**: `src/lifecycle/app_lifecycle_listener.dart`

- A single package-wide `WidgetsBindingObserver` (installed lazily on first `useSwr` call, torn down when zero `useSwr` hooks remain mounted — or simpler: installed once per `SwrCache` instance's lifetime) that on `didChangeAppLifecycleState(AppLifecycleState.resumed)`:
  - Iterates all controllers in the registry that currently have mounted subscribers.
  - Revalidates each, subject to a `focusThrottleInterval`-equivalent (skip if the last revalidation for that key happened within the throttle window) to avoid a revalidation storm on rapid resume/pause cycling.
- On `AppLifecycleState.paused`, pause any active polling timers — this observer is shared with Phase 10's polling work rather than each creating its own, so implement the pause/resume hook here even though nothing pauses yet until Phase 10 lands.

**Acceptance criteria**:

- Widget tests: simulating `AppLifecycleState.resumed` via `TestWidgetsFlutterBinding` triggers revalidation for all mounted keys exactly once each; a second resume within the throttle window is a no-op; keys with no mounted subscriber are not revalidated (avoids waking up controllers nobody is watching).

## Phase 10 — Polling (`refreshInterval`)

**Files**: extends `src/core/revalidation_scheduler.dart`

`Timer.periodic` per key with an active `useSwr` subscriber, started when the first subscriber mounts and cancelled when the last one unmounts. Wires into the same `AppLifecycleState` observer from Phase 9 to pause while backgrounded (per PRODUCT_DETAILS.md §12). Moved into MVP scope (originally scoped Post-MVP in PRODUCT_DETAILS.md §16) — implement here rather than deferring.

**Acceptance criteria**: timer fires at the configured interval only while ≥1 subscriber is mounted; pauses on background, resumes (with an immediate revalidation) on foreground.

## Phase 11 — Conditional / Dependent Fetching

**Files**: touches `src/hooks/use_swr.dart` only (no new files)

- Extend the key parameter handling from Phase 7 step 2: accept `Object? Function()? keyBuilder` as an alternate way to pass a key (or simply require callers to pass a pre-evaluated nullable key expression, e.g. `useSwr(ready ? key : null)`, and additionally catch synchronous exceptions if a **key expression itself** is passed as a closure). Decide the exact call-site ergonomics here against the two forms shown in PRODUCT_DETAILS.md §6/§8 (`useSwr(condition ? key : null)` is the primary documented form; a throwing-closure form is secondary and only needed if plain conditional expressions prove insufficient in practice) — default to shipping only the `Object?`-key form for MVP simplicity, since it already covers every example in PRODUCT_DETAILS.md §8, and revisit the closure form only if real usage demands it.
- Ensure a transition from `null` → non-null key (e.g., once a dependency resolves) correctly starts fetching on the next rebuild, and non-null → `null` correctly unsubscribes without deleting the cache entry (so it's still there if the key becomes non-null again later).

**Acceptance criteria**:

- Widget tests: `useSwr(null)` never invokes any fetcher and returns an immediately-idle response; a widget rebuilding with `key` flipping from `null` to a real value starts fetching on that rebuild; flipping back to `null` unsubscribes but does not evict the cache entry.

## Phase 12 — Example App and Integration Pass

**Files**: `example/lib/main.dart` (+ supporting files as needed)

- Build the runnable example demonstrating: basic fetch (user profile), loading/error/data branching, two widgets sharing a cache key, manual `mutate()` refresh button, conditional fetching (profile depends on session) — i.e., every MVP example from PRODUCT_DETAILS.md §8.
- Use a fake/in-memory "API" (no real network dependency) so the example runs offline and in CI if ever wired into automated screenshot/integration tests.
- Manual verification pass (per the "test in a browser/app before reporting done" standard for UI-facing work): run the example app, confirm stale-while-revalidate visually (cached data shows instantly on hot-restart-simulated remount, "refreshing" state is visible), confirm dedup (two widgets, one network call, verified via a counter in the fake API), confirm app-resume revalidation (trigger via lifecycle simulation or backgrounding on a real device/simulator).

**Acceptance criteria**: example app runs, all five documented interaction patterns are visibly demonstrable, and the manual verification pass above is actually performed (not just claimed) before Phase 12 is marked done.

---

## Post-MVP Phases (build after Phase 12, same rigor)

### Phase 15 — Reconnect Adapter (separate package or optional import)

**Files**: new package `flutter_swr_connectivity` (or `lib/src/lifecycle/connectivity_adapter.dart` behind a documented optional dependency — finalize per the Open Question in §21) depending on `connectivity_plus`.

Listens for offline→online transitions and calls the same revalidation path used by Phase 9's resume handler, so both triggers converge on one "revalidate all mounted keys, throttled" implementation rather than duplicating logic.

**Acceptance criteria**: revalidation fires only on an offline→online transition, never on online→offline or repeated online events; core package has zero new dependencies from this phase (fully isolated in the adapter).

### Phase 16 — Pluggable/Persisted Cache Providers

**Files**: documentation + at least one reference non-default `SwrCache` implementation (in `/example` or a docs snippet, not shipped as a first-party persisted provider per PRODUCT_DETAILS.md §3's explicit non-goal).

**Acceptance criteria**: the `SwrCache` interface from Phase 1 requires zero changes to support a custom implementation — this phase should be pure validation that the interface designed in Phase 1 was sufficient, not new production code.

### Phase 17 — `useSwrInfinite`

**Files**: `src/hooks/use_swr_infinite.dart`

Lowest priority per PRODUCT_DETAILS.md §13/§16. Implements `getKey(pageIndex, previousPageData)`, `size`/`setSize`, sequential default with `parallel: true` opt-in, `revalidateFirstPage`/`persistSize` options. Each page is backed by its own `SwrController` (reusing Phase 5 unchanged), composed into one aggregate `SwrResponse<List<T>>`-shaped result by the hook layer.

**Acceptance criteria**: `getKey` returning `null` stops further page fetches; `setSize(n)` fetches exactly the newly-added pages (not re-fetching already-loaded ones, unless individually stale); parallel mode fetches all current pages concurrently with `previousPageData` unavailable, matching the documented tradeoff.

---

## 3. Cross-Cutting Testing Strategy

- **Pure-Dart unit tests** (Phases 1–4, most of 5, 8's non-widget logic): run under plain `test`, no `flutter_test`, so they're fast and can run in any Dart environment.
- **Widget/hook tests** (Phases 6, 7, 8's widget-facing parts, 9, 10, 11): `flutter_test` + `flutter_hooks_test` (or manual `HookBuilder` harnesses) for verifying rebuild behavior and subscription lifecycle.
- **Fake time control**: use an injectable clock/`Timer` abstraction (or the `fake_async` package) everywhere retry backoff, polling (Phase 10), or dedup windows are tested, so the suite never sleeps in real time.
- **No live network** anywhere in the test suite — every test supplies a fake `Future<T> Function()` fetcher with controllable timing/success/failure.
- Each phase's "Acceptance criteria" above doubles as its test checklist — a phase is not complete until its listed tests exist and pass.

## 4. Milestones

| Milestone             | Phases | Definition of Done                                                                                                                                                                                             |
| --------------------- | ------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| M1 — Core engine      | 1–5    | `SwrController` correctly implements stale-while-revalidate, dedup, and retry in pure Dart, fully unit-tested, with zero Flutter/widget dependency.                                                            |
| M2 — MVP hook surface | 6–11   | `useSwr` + bound/global `mutate` + app-resume revalidation + polling + conditional fetching all work in a real widget tree; this is the first point where the package is genuinely usable.                     |
| M3 — MVP ships        | 12     | Example app demonstrates every MVP pattern from PRODUCT_DETAILS.md §8; manual verification pass completed; README updated from its current TODO-template state to real usage docs (§20 of PRODUCT_DETAILS.md). |
| M4 — Post-MVP phase   | 15–17  | Reconnect adapter, pluggable/persisted cache-provider validation, and `useSwrInfinite` all land — the full Post-MVP surface from PRODUCT_DETAILS.md §16 is complete.                                          |

## 5. Risks / Watch Items

- **Records-in-return-type ergonomics**: `(SwrResponse<T>, SwrMutate<T>)` requires Dart 3 pattern-matching destructuring at every call site; confirm the SDK constraint in `pubspec.yaml` (`environment.sdk`) is raised accordingly before Phase 7 — the current `sdk: ^3.11.0` already satisfies this, so no action needed, just noting the dependency explicitly.
- **Controller registry lifecycle**: because Phase 8's cascade-invalidation needs to reach controllers for keys with no currently-mounted `useSwr` widget, decide early (during Phase 5) whether uncontrolled growth of the registry (controllers for keys nobody currently watches) is acceptable or needs eviction — flagged here so it isn't discovered late as a memory-leak surprise.
- **`SwrConfig`'s non-generic default fetcher**: the type-erasure boundary noted in Phase 6 is easy to implement sloppily (silent `as T` casts). Write an explicit test that a mismatched default-fetcher return type throws a clear, typed error rather than a confusing cast failure.
