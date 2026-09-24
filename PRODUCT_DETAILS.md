# Product Details

## 1. Product Overview

**flutter_swr** is a Flutter/Dart port of [Vercel's SWR](https://vercel.app/oss/swr) — a React data-fetching library built around the **stale-while-revalidate** HTTP caching strategy (RFC 5861). SWR's pitch, straight from its [getting-started guide](https://swr.vercel.app/docs/getting-started), is that "your code is more declarative: you just need to specify what data is used by the component" — the library handles caching, deduplication, revalidation, and cache sharing across every component that asks for the same key.

Flutter has no equivalent today. The idiomatic pattern is `FutureBuilder`/`StreamBuilder` wired to manual `setState`, a `Bloc`, or a Riverpod `FutureProvider` — each of which either re-fetches on every rebuild, requires hand-written caching, or requires adopting an entire state-management architecture just to get "cache this GET request and share it across widgets." flutter_swr fills the specific gap SWR fills in React: a **small, focused, drop-in hook** for remote data that gives you instant cached data, background revalidation, request deduplication, and simple mutation — without requiring you to restructure your app's state management.

flutter_swr is built on top of [`flutter_hooks`](https://pub.dev/packages/flutter_hooks) so it can offer a hook-shaped API (`useSwr`) that composes naturally inside `HookWidget`/`HookBuilder`, the same way `useSWR` composes inside a React function component.

**Who it's for**: Flutter developers who already use `flutter_hooks` (or are willing to adopt it for this), and who want SWR's specific data-fetching ergonomics — instant-cache-then-revalidate UX, dedup, and simple mutation — without committing to a general-purpose state-management framework for that concern alone.

## 2. Product Goals

1. Provide a `useSwr` hook with the same conceptual shape as `useSWR(key, fetcher)` — call it, get reactive data/error/loading state back.
2. Implement true stale-while-revalidate semantics: return cached data instantly on remount, revalidate in the background, and push the fresh result to all subscribers.
3. Deduplicate concurrent requests for the same key ([SWR: "Built-in cache and request deduplication"](https://github.com/vercel/swr)).
4. Support automatic revalidation triggers that make sense in Flutter: on mount-if-stale, on app resume (focus-equivalent), optionally on network reconnect, and on a polling interval.
5. Provide a mutation API that can update the local cache immediately (optimistic updates), roll back on failure, and revalidate afterward — mirroring [SWR's mutation model](https://swr.vercel.app/docs/mutation).
6. Offer a global, app-scoped configuration point (`SwrProvider`/`SwrConfig`) for defaults (fetcher, intervals, retry policy, callbacks), overridable per call.
7. Be fully type-safe: generic `useSwr<T>`, no `dynamic`/`any` in the public API.
8. Keep the dependency surface small and the cache transport-agnostic — flutter_swr does not assume REST/HTTP; the fetcher is just `Future<T> Function()`.
9. Make cross-widget cache sharing automatic: two widgets calling `useSwr` with the same key see the same data and the same in-flight request.
10. Give the DX a familiar shape to two audiences at once: React/SWR developers moving to Flutter, and Flutter developers already comfortable with Riverpod's `AsyncValue`-style pattern matching.
11. Ship a genuinely small MVP first (see §16) rather than attempting all of SWR's surface area immediately.

## 3. Non-Goals

- **Not a general state-management framework.** flutter_swr does not replace Bloc, Riverpod, or Provider for app-wide state; it is scoped to remote-data fetching/caching, the same niche SWR occupies relative to Redux/MobX in React.
- **No SSR/SSG/RSC equivalents.** Flutter has no server-rendering model, so SWR's Next.js-specific features — `preload()`, RSC cache hydration, `getStaticProps`/`getServerSideProps` prefetching, `unstable_serialize` for server components (see [SWR with Next.js](https://swr.vercel.app/docs/with-nextjs)) — have no target to port to and are excluded outright, not adapted.
- **No React Suspense equivalent.** Flutter's build model has no Suspense-style boundary that pauses subtree rendering while a promise resolves; `isLoading` branching (already part of the state model) is the Flutter-native substitute, so a distinct "suspense mode" is not part of this package.
- **No middleware/extension-point system.** SWR supports composable middleware ([SWR: Middleware](https://swr.vercel.app/docs/middleware)) for cross-cutting concerns like logging or key serialization. This is explicitly excluded from flutter_swr — a developer who needs to wrap a fetcher for logging can simply wrap the `Future<T> Function()` they already pass in; a dedicated middleware chain is unnecessary indirection for this package's scope.
- **Not an HTTP client.** flutter_swr does not ship a REST/GraphQL client; the fetcher is caller-supplied.
- **No built-in persistence layer in the MVP.** flutter_swr will support pluggable cache providers (mirroring [SWR's Map-like cache interface](https://swr.vercel.app/docs/advanced/cache)), but shipping a first-party persisted (disk/SQLite) provider is out of scope for the initial release.
- **No built-in connectivity detection in the core package.** Unlike a browser, Flutter/Dart has no built-in "online/offline" API; reconnect-triggered revalidation requires an optional adapter (see §12), not a core dependency.

## 4. Target Users

- Flutter developers already using `flutter_hooks` in their app who want SWR-style remote-data ergonomics without adopting Bloc/Riverpod for this concern.
- Teams porting a React + SWR web app's data-fetching conventions to a Flutter client and wanting the mental model (and ideally similar naming) to transfer directly.
- Developers who currently hand-roll `FutureBuilder` + manual cache maps + `setState` and want that collapsed into one hook call.
- Riverpod users who like `AsyncValue.when/maybeWhen/map` pattern matching and want a similarly-shaped return type for one specific feature (remote fetch/cache) without pulling in all of Riverpod.

## 5. Core Concepts

| SWR Concept | Flutter/Dart Translation |
| --- | --- |
| **Stale-while-revalidate** ([getting-started](https://swr.vercel.app/docs/getting-started)) — return cached data immediately, then fetch fresh data in the background | Same strategy; the hook synchronously returns whatever is in the cache for that key on the first frame, then kicks off a background fetch and rebuilds subscribers when it resolves. |
| **Cache key** (string, or array-like key for compound requests) | `Object` — commonly a `String` (URL-shaped, e.g. `'/api/user/$id'`), but any hashable value (a `List`, a Dart `Record`) works, since Dart doesn't have JS's implicit array-to-string key coercion; equality/hashing rules are defined explicitly (see §10). |
| **Global cache** ([advanced/cache](https://swr.vercel.app/docs/advanced/cache)) — a Map-like store shared by default across all `useSWR` calls, scoped by `<SWRConfig>` | A singleton `SwrCache` by default, with an optional `SwrProvider` (`InheritedWidget`) to scope a different cache instance to a subtree — same role as `<SWRConfig value={{ provider }}>`. |
| **`useSWR` hook** | `useSwr<T>()`, a `flutter_hooks` custom hook, composable inside `HookWidget`/`HookBuilder`. |
| **Revalidate on focus** (tab/window refocus) | Revalidate on **app resume** — `AppLifecycleState.resumed`, observed via `WidgetsBindingObserver`. This is the closest Flutter-native analogue to "user came back to this screen/app." |
| **Revalidate on reconnect** (browser `online` event) | No Dart/Flutter core equivalent exists (unlike the browser, there's no OS-agnostic "online" event in the SDK). Modeled as an **optional adapter** on top of `connectivity_plus`, not a core dependency (see §12). |
| **Request deduplication** ([GitHub feature list](https://github.com/vercel/swr)) | Same concept: concurrent `useSwr` calls (or remounts) for the same key within the dedup window share one in-flight `Future` rather than issuing parallel requests. |
| **Mutation** (`mutate`) ([mutation docs](https://swr.vercel.app/docs/mutation)) | Same concept, adapted to a bound value returned alongside the hook's state (see §7, §11) rather than a field on the response object. |
| **Middleware** | **Excluded** — see §3. |
| **Suspense mode** | **Excluded** — see §3; `isLoading` state serves this purpose in Flutter. |

## 6. Core Features

### Fetch + Cache
**Description**: Calling `useSwr(key)` fetches data via the supplied (or provider-default) fetcher and stores the result in the shared cache keyed by `key`.
**Expected behavior**: First call for a never-seen key starts in a loading state with no data; subsequent calls (same key, any widget) return cached data instantly.
**Priority**: MVP

### Request Deduplication
**Description**: Multiple simultaneous `useSwr` calls (or a remount within the dedup window) for the same key share a single in-flight request.
**Expected behavior**: Only one network/fetcher call happens; all callers resolve from that one `Future`.
**Priority**: MVP

### Revalidate-on-mount-if-stale
**Description**: When a widget mounts and cached data for its key already exists but is considered stale, a background revalidation starts automatically ([revalidateIfStale](https://swr.vercel.app/docs/revalidation), default `true`).
**Expected behavior**: UI shows cached data immediately with `isValidating: true`, then updates in place when the revalidation resolves.
**Priority**: MVP

### Revalidate-on-app-resume
**Description**: Flutter-native analogue of SWR's `revalidateOnFocus`.
**Expected behavior**: When the app transitions to `AppLifecycleState.resumed`, all currently-mounted `useSwr` keys revalidate (subject to a throttle interval, mirroring `focusThrottleInterval`).
**Priority**: MVP

### Revalidate-on-reconnect (optional adapter)
**Description**: Flutter-native analogue of SWR's `revalidateOnReconnect`, using `connectivity_plus`.
**Expected behavior**: When connectivity transitions from offline to online, mounted keys revalidate. Ships as an opt-in adapter, not a hard dependency.
**Priority**: Post-MVP

### Polling
**Description**: Analogue of `refreshInterval` — periodic background refetch while a key is in active use.
**Expected behavior**: Configurable interval per call or globally; paused when no widget is subscribed to the key (mirrors SWR's "only refetches when the component is visible").
**Priority**: Post-MVP

### Manual Mutate (own key)
**Description**: The bound `mutate` returned alongside `useSwr`'s state writes data or triggers revalidation for that hook's own key.
**Expected behavior**: `mutate(newData)` writes synchronously and notifies subscribers; `mutate()` with no arguments just revalidates.
**Priority**: MVP

### Cascade Invalidation (other keys)
**Description**: The same bound `mutate` can mark **other** cache keys as stale and trigger their revalidation, without writing data into them.
**Expected behavior**: `mutate(otherKey1, otherKey2)` schedules revalidation for those keys' currently-mounted subscribers; it never writes arbitrary data into a key it doesn't own.
**Priority**: MVP (minimal form); richer selector/predicate invalidation is Post-MVP.

### Optimistic Updates + Rollback
**Description**: Write a predicted value to the cache immediately on mutation, then reconcile with the real response or roll back on error ([mutation docs — optimisticData/rollbackOnError](https://swr.vercel.app/docs/mutation)).
**Expected behavior**: UI reflects the optimistic value instantly; on fetcher/mutation failure, the cache reverts to its pre-mutation value and the error surfaces.
**Priority**: Post-MVP — **delivered** through `useSwrMutation`'s `optimisticData`/`rollbackOnError` (see [USESWRMUTATION.md](USESWRMUTATION.md)).

### `useSwrMutation` (imperative mutation)
**Description**: A separate hook for mutations that should not run automatically on mount, mirroring [`useSWRMutation`](https://swr.vercel.app/docs/mutation#useswrmutation).
**Expected behavior**: Returns an idle state plus a `trigger()` function; calling `trigger()` runs the mutation and updates `isMutating`/`data`/`error`.
**Priority**: Post-MVP — **delivered** (0.3.0). Design and rationale: [USESWRMUTATION.md](USESWRMUTATION.md).

### Conditional / Dependent Fetching
**Description**: Skip fetching when the key is `null`, or derive a key from another hook's data and skip while that data isn't ready yet ([conditional-fetching docs](https://swr.vercel.app/docs/conditional-fetching)).
**Expected behavior**: `useSwr(condition ? key : null)` never fetches while the key is `null`; a key-producing closure that throws (e.g. accessing a field on not-yet-loaded data) is treated the same as `null` — the request simply waits.
**Priority**: MVP

### Error Retry
**Description**: Exponential backoff retry on fetcher failure ([error-handling docs](https://swr.vercel.app/docs/error-handling)).
**Expected behavior**: Default backoff with a max retry count; configurable or fully disabled per call (`shouldRetryOnError: false`-equivalent) and globally.
**Priority**: MVP (basic backoff); custom per-error retry predicate is Post-MVP.

### Pagination / Infinite Loading
**Description**: `useSwrInfinite`-equivalent for cursor- or index-based paginated lists ([pagination docs](https://swr.vercel.app/docs/pagination)).
**Expected behavior**: A `getKey(pageIndex, previousPageData)` function drives per-page keys; `size`/`setSize` control how many pages are loaded; returning `null` from `getKey` signals the end of the list.
**Priority**: **Post-MVP — lowest priority.** This is the most complex feature in the surface area and the least essential to delivering SWR's core value (instant-cache-then-revalidate for a single resource); it should land after everything else in §16's Post-MVP list.

### Global Configuration Provider
**Description**: `SwrProvider`/`SwrConfig` scoping default fetcher, intervals, retry policy, and callbacks to a subtree.
**Expected behavior**: Per-call options override provider defaults; nested providers merge with the nearest ancestor, mirroring [SWR's nested `<SWRConfig>` merge behavior](https://swr.vercel.app/docs/advanced/cache).
**Priority**: MVP

### `keepPreviousData`
**Description**: When the key changes, keep showing the previous key's data (marked as "previous") instead of flashing to a loading state, until new data arrives.
**Expected behavior**: `dataAsync.data` is the fresh data once available; a separate `previousData` field/flag is exposed while a new key is in flight.
**Priority**: Post-MVP

## 7. API Design

The hook signature intentionally departs from a literal `const { data, error, isLoading } = useSWR(...)` port. Dart doesn't have JS object destructuring, and cramming every field (including the mutate function) into one big object makes the common "I just want to call mutate" call site noisy. Instead:

```dart
T Function(...)? -> Future<T> Function()  // fetcher shape used throughout

// Hook signature — fetcher and options are both optional, resolved from
// the nearest SwrProvider when omitted.
(SwrResponse<T>, SwrMutate<T>) useSwr<T>(
  Object? key, {
  Future<T> Function()? fetcher,
  SwrOptions<T>? options,
});
```

Call sites destructure the returned **Dart record** so the data/async state and the mutate function are visibly separate values:

```dart
final (dataAsync, mutate) = useSwr<User>('/api/user/$id');
```

`dataAsync` is an `SwrResponse<T>`, modeled on Riverpod's `AsyncValue<T>` DX — familiar to Flutter developers — but extended with the `isValidating` dimension that plain `AsyncValue` doesn't have, since SWR's defining trait is that **data and an in-flight background revalidation coexist**:

```dart
class SwrResponse<T> {
  T? get data;
  Object? get error;
  bool get isLoading;     // true only when there is no data yet at all
  bool get isValidating;  // true whenever a fetch is in flight, with or without data
  T? get previousData;    // Post-MVP: keepPreviousData

  R when<R>({
    required R Function(T data, {required bool isValidating}) data,
    required R Function(Object error) error,
    required R Function() loading,
  });
  R? maybeWhen<R>({ /* ...with orElse */ });
  R map<R>({ /* ...analogous to AsyncValue.map */ });
}
```

Both styles are first-class — simple screens read fields directly, more complex ones pattern-match:

```dart
// Field access
if (dataAsync.isLoading) return const CircularProgressIndicator();
if (dataAsync.error != null) return ErrorView(dataAsync.error!);
return UserView(dataAsync.data!);

// Pattern matching
dataAsync.when(
  data: (user, {required isValidating}) => UserView(user, refreshing: isValidating),
  error: (e) => ErrorView(e),
  loading: () => const CircularProgressIndicator(),
);
```

`mutate` is a small callable value, not a method buried on `dataAsync`:

```dart
typedef SwrMutate<T> = Future<void> Function(
  [T? data, Object? updaterOrNothing]
) Function({List<Object> invalidate});
```

Concretely, it supports:

```dart
mutate(newUser);                 // write this hook's own key, revalidate after
mutate((current) => current!.copyWith(name: 'X')); // functional update
mutate();                        // no data — just revalidate this key
mutate(invalidate: [postsListKey, otherKey]); // cascade-invalidate OTHER keys
                                               // (never writes data into them)
```

This mirrors SWR's global `mutate(key)`-with-no-data call, which "marks data as expired and refetches" rather than writing a value — so one hook's `mutate` can write its own key's data **and** cascade-invalidate related read keys (e.g., after creating a post: write `/api/post/$id`, invalidate `/api/posts`) without reaching for the separate global `mutate` in the common case. Writing arbitrary data into a key this hook doesn't own is out of scope for the bound `mutate` — that remains the job of the global, top-level `mutate`.

Supporting pieces:

```dart
// Global mutate — for mutating/invalidating from outside any hook's scope
Future<void> mutate<T>(Object key, {T? data, bool revalidate = true});

// Imperative mutation hook. Key optional: bound to the cache entry when given,
// pure async-state tracking when omitted. See USESWRMUTATION.md §2.
(SwrMutationState<T>, SwrTrigger<T, Arg>) useSwrMutation<T, Arg>(
  Future<T> Function(Arg arg) fetcher, {
  Object? key,
  SwrMutationOptions<T, Arg>? options,
});

abstract class SwrTrigger<T, Arg> {
  Future<T?> call([Arg? data]); // trigger() / trigger(arg)
  void reset();
}

// Global/app-scoped configuration
class SwrProvider extends StatelessWidget {
  const SwrProvider({
    required this.child,
    this.fetcher,
    this.dedupingInterval = const Duration(milliseconds: 2000),
    this.refreshInterval,
    this.retry = const SwrRetryPolicy(),
    this.onError,
    this.onSuccess,
    this.cache, // pluggable Map-like provider
  });
}
```

Design principles applied throughout:
- **Type-safe**: `useSwr<T>` and `SwrResponse<T>` are generic; no `dynamic` in the public surface.
- **Predictable**: `mutate`'s own-key-write vs. other-keys-invalidate-only split is a hard rule, not a convention — this avoids the "did that just silently overwrite unrelated cache data" footgun.
- **Reactive**: rebuilding is driven by `flutter_hooks`' `useState`/`ValueListenable` machinery internally; consumers never manually call `setState`.
- **Flutter-friendly**: works inside any `HookWidget`/`HookBuilder`, requires no `BuildContext`-based provider lookup for the common case (only `SwrProvider` overrides need one).
- **No middleware extension point** (per §3/§6).

## 8. Example Usage

### Basic data fetching

```dart
class UserProfile extends HookWidget {
  const UserProfile({required this.id});
  final String id;

  @override
  Widget build(BuildContext context) {
    final (dataAsync, mutate) = useSwr<User>(
      '/api/user/$id',
      fetcher: () => api.fetchUser(id),
    );

    return dataAsync.when(
      data: (user, {required isValidating}) => UserCard(user, refreshing: isValidating),
      error: (e) => ErrorBanner(e),
      loading: () => const CircularProgressIndicator(),
    );
  }
}
```

### Loading / error / data via direct fields

```dart
final (dataAsync, _) = useSwr<List<Post>>('/api/posts');

if (dataAsync.isLoading) return const LoadingSpinner();
if (dataAsync.error != null) return ErrorBanner(dataAsync.error!);
return PostList(dataAsync.data!);
```

### Caching across widgets

```dart
// Widget A and Widget B both call this with the same key.
// Only one fetch happens; both rebuild from the same cache entry.
final (dataAsync, _) = useSwr<User>('/api/user/$id');
```

### Manual revalidation

```dart
final (dataAsync, mutate) = useSwr<List<Post>>('/api/posts');

IconButton(
  icon: const Icon(Icons.refresh),
  onPressed: () => mutate(), // no data -> just revalidate
);
```

### Mutation with optimistic update

With `useSwrMutation` (delivered), optimistic write, rollback and reconciliation are options:

```dart
final (renameState, rename) = useSwrMutation<User, String>(
  (newName) => api.updateUser(id, name: newName),
  key: '/api/user/$id',
  options: SwrMutationOptions(
    optimisticData: (current, newName) => current?.copyWith(name: newName),
    populateCache: true,     // reconcile with server response
    // rollbackOnError: true is the default
  ),
);
await rename('Ada');
```

The manual pattern below, using the bound `mutate`, still works:

```dart
final (dataAsync, mutate) = useSwr<User>('/api/user/$id');

Future<void> updateName(String newName) async {
  final previous = dataAsync.data;
  await mutate(
    previous?.copyWith(name: newName),        // optimisticData-equivalent
  );
  try {
    final saved = await api.updateUser(id, name: newName);
    await mutate(saved);                       // reconcile with server response
  } catch (e) {
    await mutate(previous);                    // rollback
    rethrow;
  }
}
```

### Pagination / infinite loading (Post-MVP)

```dart
final (pages, setSize, size) = useSwrInfinite<List<Post>>(
  getKey: (pageIndex, previousPageData) {
    if (previousPageData != null && previousPageData.isEmpty) return null; // end
    return '/api/posts?page=$pageIndex';
  },
  fetcher: (key) => api.fetchPosts(key),
);

ListView.builder(
  itemCount: pages.data?.expand((p) => p).length ?? 0,
  // ...
);

TextButton(
  onPressed: () => setSize(size + 1),
  child: const Text('Load more'),
);
```

### Conditional / dependent fetching

```dart
final (sessionAsync, _) = useSwr<Session>('/api/session');

// Only fetch the profile once we have a session with a userId.
final (profileAsync, _) = useSwr<Profile>(
  sessionAsync.data?.userId != null ? '/api/profile/${sessionAsync.data!.userId}' : null,
);
```

## 9. State Model

| State | Meaning | Notes |
| --- | --- | --- |
| `data` | Last known-good value for the key, from cache or a completed fetch. | Can be present while `error` is also present (a background revalidation failed but the last good data is retained) — mirrors SWR's "data and error can exist at the same time." |
| `error` | The error from the most recent failed fetch/revalidation. | Cleared on the next successful fetch. |
| `isLoading` | `true` only when there is **no data yet at all** and a fetch is in flight. | Distinct from `isValidating` — this is the "first load" signal. |
| `isValidating` | `true` whenever any fetch (initial or background) is in flight, regardless of whether `data` is already populated. | This is what lets the UI show cached data with a subtle "refreshing" indicator instead of a full loading state. |
| `previousData` | The data held for the *previous* key, retained while a new key's fetch is in flight. | Post-MVP (`keepPreviousData`); avoids UI flicker when a key changes (e.g. paging between user IDs). |
| Mutation state (`isMutating`, mutation `data`/`error`) | Local state for `useSwrMutation`'s imperative trigger. | Separate from the read-hook's state; a mutation's own success/failure doesn't overwrite the read hook's `error` unless the mutation also writes/invalidates that key. |

**Transition rules**:
- Mount with no cache entry → `isLoading: true`, `isValidating: true`, `data: null`.
- Mount with a cache entry → `isLoading: false`, `data` populated immediately; `isValidating: true` if the entry is stale (triggers background revalidation), else `false`.
- Fetch success → `data` updated, `error` cleared, `isValidating: false`.
- Fetch failure → `error` set, `data` untouched (stale-but-present data is preserved), `isValidating: false`, retry scheduled per policy.
- `mutate(newData)` → `data` updated synchronously, then a revalidation runs (unless disabled) to reconcile with the source of truth.

## 10. Caching & Revalidation

- **Cache keys**: any hashable `Object` (`==`/`hashCode` contract). Strings are the common case (URL-shaped); `List`/`Record` keys are supported for compound requests, with equality defined by deep value equality, not identity — this is the explicit Dart-side answer to JS's array-key behavior in SWR.
- **Cache storage**: a Map-like interface (`get`/`set`/`delete`/`keys`, mirroring [SWR's cache provider interface](https://swr.vercel.app/docs/advanced/cache)) so the default in-memory implementation can be swapped for a custom provider. Never mutated directly by consumers — all writes go through `mutate`.
- **Cache lifetime**: entries live for the process lifetime by default (no automatic expiry); "staleness" is a separate, time-based flag (see below), not deletion.
- **Stale data**: an entry is considered stale once older than a configurable freshness window (or immediately, if no such window is configured) — stale data is still served instantly, but triggers a background revalidation on next access.
- **Revalidation triggers**: mount-if-stale (default on), app-resume (default on), reconnect (optional adapter), polling interval (opt-in), manual `mutate()`.
- **Deduplication**: concurrent requests for the same key within a `dedupingInterval` window (default mirrors SWR's ~2s) share one in-flight `Future` rather than issuing separate fetcher calls.
- **Cache invalidation**: via `mutate(key)` with no data (own key) or `mutate(invalidate: [...])` (other keys) — see §7/§11. A broader "invalidate by predicate over keys" is Post-MVP.
- **Manual refresh**: `mutate()` with no arguments on the bound value.
- **Automatic refresh**: polling (`refreshInterval`) and lifecycle-triggered revalidation (app resume / reconnect), both Post-MVP for reconnect, MVP for app-resume.

## 11. Mutation

- **Own-key write**: `mutate(newData)` or `mutate(updaterFn)` on the bound value writes the cache for that hook's key and notifies all subscribers synchronously.
- **Optimistic updates**: write a predicted value before the network call resolves, so the UI updates instantly; reconcile with the real response afterward. Delivered as `useSwrMutation`'s `optimisticData` + `populateCache`/`populateCacheWith`.
- **Rollback**: if the underlying mutation throws, the cache is restored to its pre-mutation value. `useSwrMutation` does this automatically (`rollbackOnError`, default `true`), skipping the rollback if someone else wrote the key in the meantime; with the bound `mutate`, the caller still captures/passes the "previous" value manually, as shown in §8.
- **Race protection**: while a `useSwrMutation` on a key is in flight, any read fetch for that key that overlapped it has its result discarded, and the key is revalidated after the mutation — stale pre-mutation data never overwrites what the mutation wrote. The bound and global `mutate` are not (yet) covered by this.
- **Global callbacks**: `SwrConfig.onSuccess`/`onError` are scoped to reads and are not called for `useSwrMutation`; use its own `onSuccess`/`onError` options.
- **Revalidation after mutation**: by default, a successful `mutate` triggers a background revalidation to reconcile the cache with the source of truth, mirroring SWR's default `mutate` behavior; this can be disabled per call.
- **Mutation errors**: surfaced via the returned `Future` from `mutate`/`trigger` (so callers can `try/catch`), and also reflected in `useSwrMutation`'s `error` state for the imperative-mutation hook.
- **Cascade invalidation**: `mutate(invalidate: [...])` marks other keys stale and triggers their revalidation for any currently-mounted subscriber — it never writes data into a key it doesn't own (see §7 for the rationale).

## 12. Network & App Lifecycle

| Concern | Core package or Flutter-specific integration? |
| --- | --- |
| **App resume** (focus-equivalent) | **Core.** `WidgetsBindingObserver`/`AppLifecycleState.resumed` is pure Flutter SDK — no extra dependency needed. |
| **Network reconnect** | **Optional adapter**, not core. Flutter/Dart has no built-in "online" event (unlike the browser SWR runs in); a `flutter_swr_connectivity` (or similar) package built on `connectivity_plus` plugs into the same revalidation hook that app-resume uses. Kept separate so the core package has zero platform-channel dependencies. |
| **Polling** | **Core.** Plain `Timer.periodic`, paused when a key has no mounted subscribers. |
| **Failed requests / retries** | **Core.** Exponential backoff by default (mirroring [SWR's error-handling](https://swr.vercel.app/docs/error-handling)), with a configurable max retry count and interval; can be disabled per call or globally. |
| **Background/foreground transitions beyond resume** (e.g., pausing polling while backgrounded) | **Core**, via the same `WidgetsBindingObserver` — polling timers pause on `AppLifecycleState.paused` and resume (with an immediate revalidation) on `AppLifecycleState.resumed`. |

## 13. Pagination & Infinite Loading

**Explicitly Post-MVP / not in the initial release** (per product decision — see §16), and the lowest-priority Post-MVP item given its complexity relative to its necessity for delivering SWR's core value.

Proposed shape, mirroring [`useSWRInfinite`](https://swr.vercel.app/docs/pagination):

- `useSwrInfinite<T>({ required Object? Function(int pageIndex, T? previousPageData) getKey, required Future<T> Function(Object key) fetcher })`.
- `getKey` returns `null` to signal the end of the list — same convention as SWR.
- Returns pages as a `SwrResponse<List<T>>`-shaped value (a list of per-page results) plus `size`/`setSize` for "load more" control.
- Sequential fetching (each page depends on the previous) is the default, matching cursor-based APIs; a `parallel: true` opt-in fetches all pages independently for index-based APIs, with the tradeoff that `previousPageData` is unavailable in that mode (same tradeoff SWR documents).
- `revalidateFirstPage`-equivalent option to always refresh page 0 on mount, `persistSize`-equivalent to keep the loaded page count stable across key changes.

## 14. Configuration

**Global** (`SwrProvider` at or near the app root):
- `fetcher`: default `Future<T> Function()` resolver used when a call site omits its own.
- `dedupingInterval`: window within which duplicate requests for the same key are merged.
- `refreshInterval`: default polling interval (Post-MVP; `null`/off by default).
- `retry`: retry policy (max attempts, backoff shape, optional per-error predicate).
- `onError` / `onSuccess`: global callbacks for cross-cutting concerns like logging or toast notifications, without requiring per-hook boilerplate.
- `cache`: pluggable cache provider (defaults to an in-memory `Map`-backed store).

**Per-call** (`useSwr(..., options: SwrOptions(...))`):
- Overrides any of the above for that specific key/hook instance.
- Additional per-call-only options: whether to revalidate on mount, whether this key participates in app-resume revalidation, `keepPreviousData` (Post-MVP).

Nested `SwrProvider`s merge with their nearest ancestor's config rather than replacing it wholesale — mirroring how [nested `<SWRConfig>` extends the parent config](https://swr.vercel.app/docs/advanced/cache) in SWR.

## 15. Architecture Overview

- **Cache Store**: the Map-like key→value store (`get`/`set`/`delete`/`keys`) plus per-entry metadata (last-fetched timestamp, staleness). Default implementation is in-memory; pluggable via `SwrProvider`.
- **Key Normalizer**: converts a caller-supplied `Object` key into a stable, hashable identity used for cache lookup and equality (handles `List`/`Record` keys consistently).
- **Fetcher / Request Dedup Manager**: tracks in-flight `Future`s per normalized key; new requests for a key already in flight attach to the existing `Future` instead of starting a new one, and this component enforces the `dedupingInterval` window.
- **Revalidation Scheduler**: owns the timers (polling) and lifecycle listeners (`WidgetsBindingObserver` for app-resume; the optional connectivity adapter plugs in here too) that decide when a key should be revalidated in the background.
- **Mutation Manager**: applies own-key writes, handles the optimistic-write/rollback sequence (Post-MVP), and performs cascade invalidation of other keys, then hands off to the Revalidation Scheduler to trigger the post-mutation refetch.
- **Retry Policy Executor**: wraps fetcher calls with the configured backoff/retry behavior and reports terminal failures to the Cache Store as the entry's `error`.
- **Hook Layer**: the `flutter_hooks` integration (`useSwr`, `useSwrMutation`, `useSwrInfinite`) — subscribes a widget to a cache key's changes (via an internal `ValueListenable`/`ChangeNotifier`-style mechanism) and triggers a rebuild when that key's entry changes; unsubscribes on widget disposal.
- **Config/Provider**: the `SwrProvider` `InheritedWidget` that scopes a `SwrConfig` (defaults + cache instance) to a subtree, with merge-over-ancestor semantics.

No middleware chain module exists in this architecture (per §3/§6).

## 16. MVP Scope

### MVP
- `useSwr<T>` core: fetch, cache, dedup, `data`/`error`/`isLoading`/`isValidating`.
- Bound `mutate`: own-key write, own-key revalidate-only call, cascade-invalidate other keys.
- Revalidate-on-mount-if-stale.
- Revalidate-on-app-resume.
- Basic exponential-backoff retry with a configurable max count.
- Global `SwrProvider` configuration (default fetcher, dedupingInterval, retry policy, onError/onSuccess).
- Conditional/dependent fetching (`null` key skips the fetch).

### Post-MVP
Roughly in priority order:
1. ~~Optimistic updates + rollback convenience API.~~ Delivered via `useSwrMutation` (0.3.0).
2. ~~`useSwrMutation` (imperative mutation hook).~~ Delivered (0.3.0).
3. Polling (`refreshInterval`).
4. Reconnect-triggered revalidation (`connectivity_plus` adapter package).
5. `keepPreviousData` / `previousData`.
6. Pluggable/persisted cache providers beyond the default in-memory store.
7. Pagination / infinite loading (`useSwrInfinite`) — lowest priority given its complexity relative to how essential it is to SWR's core value proposition.

Middleware is not on either list — it is out of scope for this package entirely (see §3).

## 17. Feature Mapping: SWR → Flutter

| SWR Feature | Flutter Equivalent | MVP? | Notes |
| --- | --- | --- | --- |
| `useSWR(key, fetcher)` | `useSwr<T>(key, {fetcher, options})` | Yes | Returns a `(SwrResponse<T>, SwrMutate<T>)` record instead of a destructured object. |
| `data` | `SwrResponse.data` | Yes | |
| `error` | `SwrResponse.error` | Yes | Coexists with stale `data`. |
| `isLoading` | `SwrResponse.isLoading` | Yes | True only with no data yet. |
| `isValidating` | `SwrResponse.isValidating` | Yes | True for any in-flight fetch, with or without data. |
| Bound `mutate` | `SwrMutate<T>` record element | Yes | Own-key write; other-key invalidation via `invalidate: [...]`. |
| Global `mutate` (`useSWRConfig`) | Top-level `mutate<T>(key, {data, revalidate})` function | Yes (minimal) | For mutating/invalidating outside a hook's scope. Reaches every cache the key is registered in — default or `SwrProvider`-scoped — a deliberate divergence from `useSWRConfig().mutate`'s single-scope reach. |
| `revalidateOnFocus` | Revalidate on `AppLifecycleState.resumed` | Yes | Closest Flutter-native analogue to browser focus. |
| `revalidateOnReconnect` | Optional `connectivity_plus`-based adapter | No | No core "online" event in Dart/Flutter; kept out of core deps. |
| `revalidateIfStale` | Revalidate-on-mount-if-stale | Yes | |
| `refreshInterval` (polling) | `Timer.periodic`-based polling option | No | |
| Request deduplication | In-flight `Future` sharing per key | Yes | |
| `dedupingInterval` | `SwrOptions.dedupingInterval` | Yes | |
| `optimisticData` / `rollbackOnError` | `SwrMutationOptions.optimisticData` / `rollbackOnError` on `useSwrMutation` | Post-MVP (delivered 0.3.0) | `optimisticData` is function-only and also receives the trigger argument. Not on the bound `mutate`; the manual pattern (§8) still works there. |
| `populateCache` | Implicit in own-key `mutate` write | Yes | No separate flag needed at MVP scope. |
| `useSWRMutation` | `useSwrMutation<T, Arg>(fetcher, {key, options})` | Post-MVP (delivered 0.3.0) | Returns `(SwrMutationState<T>, SwrTrigger<T, Arg>)`; `reset` lives on the trigger. Optional `key` means "unbound", not "disabled". `populateCache` is split into a bool + `populateCacheWith`. See USESWRMUTATION.md. |
| `useSWRInfinite` | `useSwrInfinite<T>` | No | Lowest-priority Post-MVP item. |
| Conditional fetching (`null` key) | `useSwr(null)` skips the fetch | Yes | |
| Dependent fetching (key derived from another hook, throws/returns falsy until ready) | Same pattern — key expression returns `null` until the dependency is ready | Yes | |
| Cache provider interface (Map-like) | `SwrCache` interface, pluggable via `SwrProvider` | Yes (in-memory default); pluggable persisted providers Post-MVP | |
| `<SWRConfig>` | `SwrProvider` `InheritedWidget` | Yes | Nested providers merge with ancestor config. |
| `onErrorRetry` / retry backoff | Built-in exponential backoff, configurable count/interval | Yes (basic); custom per-error predicate Post-MVP | |
| `onError` / `onSuccess` (global) | `SwrProvider.onError` / `onSuccess` | Yes | |
| Middleware | **Excluded entirely** | N/A | Wrap your own fetcher instead; no dedicated extension point. |
| React Suspense integration | **Excluded** | N/A | `isLoading` branching is the substitute; Flutter has no Suspense-equivalent boundary. |
| Next.js RSC `preload()` / SSR cache hydration / `getStaticProps` prefetch | **Excluded** | N/A | No server-rendering model in Flutter to port these onto. |
| Scroll position recovery | **Excluded** (not part of this spec) | N/A | Flutter has its own scroll-restoration primitives (`PageStorage`) unrelated to data fetching; not part of flutter_swr's scope. |

## 18. Developer Experience

A developer who knows SWR should recognize the shape immediately: a hook named `useSwr`, called with a key and fetcher, returning `data`/`error`/`isLoading`/`isValidating`, with a `mutate` for local cache updates and automatic revalidation on app resume/reconnect. The naming and the return-value fields intentionally track SWR's vocabulary.

At the same time, the API should feel native to a Flutter developer who has never touched React: it composes as a `flutter_hooks` hook (not a special widget or provider-lookup-by-context for the common case), it returns a typed generic response object rather than `dynamic`, and its pattern-matching surface (`when`/`maybeWhen`/`map`) deliberately echoes Riverpod's `AsyncValue`, so the "read this response" half of the API requires zero new mental model for anyone who has used Riverpod. The one deliberate divergence from `AsyncValue` — exposing `isValidating` as an orthogonal flag rather than folding "loading" into a single state — is the one concept a Riverpod user has to learn, and it's the entire point of SWR, so it earns its place.

## 19. Testing Requirements

- **Cache behavior**: get/set/delete correctness, key equality for non-`String` keys (`List`/`Record`), staleness computation over time.
- **Request deduplication**: concurrent `useSwr` calls (or remounts) for the same key within the dedup window issue exactly one fetcher call; calls outside the window issue a new one.
- **Revalidation**: mount-if-stale triggers exactly one background fetch; app-resume triggers revalidation for all mounted keys (via a fake `WidgetsBindingObserver`/lifecycle injection); polling timers fire at the configured interval and pause when unsubscribed (Post-MVP).
- **Retries**: backoff timing/sequence on repeated fetcher failure; retry stops at the configured max count; `error` reflects the final failure.
- **Mutations**: own-key write updates the cache and notifies subscribers synchronously; cascade `invalidate` marks other keys stale and triggers their revalidation without writing data into them; post-mutation revalidation fires by default and can be disabled.
- **Optimistic updates** (Post-MVP): optimistic value is visible immediately; rollback restores the exact pre-mutation value on failure.
- **Error handling**: fetcher throwing surfaces via `error` while retaining last-good `data`; global `onError` callback fires.
- **Pagination** (Post-MVP): `getKey` sequencing (index/cursor), `null` return stops fetching further pages, `size`/`setSize` correctness, parallel-mode independence from `previousPageData`.
- **Lifecycle/network behavior**: simulated `AppLifecycleState` transitions trigger/pause revalidation and polling correctly; the optional connectivity adapter triggers revalidation only on offline→online transitions.
- **Concurrent requests**: two widgets mounting the same key simultaneously share one fetch and both receive the resolved data; a key change mid-flight cancels/ignores the now-irrelevant in-flight result rather than writing stale data into the new key's slot.

## 20. Documentation Requirements

- **Getting Started guide**: install, wrap the app in `SwrProvider` (optional for defaults), first `useSwr` call.
- **API reference**: every public hook/class/option, generated from doc comments.
- **Migration notes for React SWR users**: a side-by-side table of `useSWR`/`mutate`/`useSWRInfinite` vs. their flutter_swr equivalents, explicitly calling out the excluded features (middleware, Suspense, SSR/RSC) and why.
- **Cookbook**: worked examples for optimistic updates, auth-conditional fetching, pagination, and app-lifecycle-aware revalidation.
- **Example app**: a runnable Flutter app in `/example` demonstrating the MVP feature set end-to-end.

## 21. Open Questions & Decisions

- **Naming**: `useSwr` vs. `useSWR` (casing) — does the public API mirror JS casing exactly or follow Dart's `lowerCamelCase` convention throughout (e.g. `useSwrMutation` vs. `useSWRMutation`)?
- **Default cache scope**: implicit process-wide singleton cache with `SwrProvider` as purely optional, vs. requiring an explicit `SwrProvider` at the app root before any `useSwr` call works. Affects testability (isolated caches per test) and the "it just works with zero setup" goal.
- **Key type strictness**: keep the key parameter as `Object?` (maximally flexible, matching SWR's permissiveness), or narrow it to a sealed `SwrKey` type for better compile-time safety at the cost of extra ceremony at call sites?
- **Connectivity adapter packaging**: ship as `flutter_swr_connectivity` (separate pub package) vs. an optional import path within the same package gated behind a dependency the user must add themselves?
- **`keepPreviousData` default**: off by default (matches SWR) or on by default for Flutter's typically more "list navigation"-heavy UI patterns?
- **Error typing**: keep `error` as `Object?` (matches SWR/JS's untyped catch), or introduce a typed `SwrError` wrapper carrying the underlying exception plus retry-count metadata?
- **Minimum Dart/Flutter SDK**: the record-based `(SwrResponse<T>, SwrMutate<T>)` return type requires Dart 3's records/patterns — confirm the minimum supported SDK version reflects this.
- **Package structure**: single `flutter_swr` package, or split a platform-agnostic `swr_core` (cache, dedup, retry logic) from a `flutter_swr` package that adds the `flutter_hooks` integration and lifecycle wiring — the latter would ease a future non-Flutter Dart consumer but adds release/versioning overhead now.
- **Cascade-invalidation ergonomics**: is `mutate(invalidate: [...])` (§7) the final shape, or should there be a separate top-level helper (e.g. `invalidateKeys([...])`) so the "own key" and "other keys" operations aren't both hanging off the same bound function signature?
- ~~**Optimistic-update convenience API shape**~~ — **Decided:** it lives on `useSwrMutation` as `SwrMutationOptions.optimisticData`/`rollbackOnError`/`populateCache(With)` (closer to literal SWR's `useSWRMutation`); the bound `mutate` stays manual, as shown in §8. See USESWRMUTATION.md §2.3.
