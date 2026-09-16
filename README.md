# flutter_swr

**Flutter Hooks for data fetching** — a Dart port of [SWR](https://swr.vercel.app), Vercel's React
data-fetching library, built on top of [`flutter_hooks`](https://pub.dev/packages/flutter_hooks).

`useSwr` gives you a cache-then-revalidate hook for remote data: call it with a key and a fetcher,
and every widget that asks for the same key gets instant cached data, a background refetch,
request deduplication, and a simple way to mutate the cache — all without wiring up your own
cache map or adopting a full state-management framework.

## Why does this exist?

Flutter doesn't have an equivalent to SWR (or React Query). The idiomatic pattern today is a
`FutureBuilder` wired to manual `setState`, or reaching for a `Bloc` / Riverpod `FutureProvider` —
each of which either re-fetches on every rebuild, requires you to hand-roll caching, or requires
adopting an entire state-management architecture just to get "cache this GET request and share it
across widgets."

`flutter_swr` fills the specific gap SWR fills in React: a small, focused hook for remote data that
gives you the stale-while-revalidate strategy ([RFC 5861](https://www.rfc-editor.org/rfc/rfc5861))
— show cached data immediately, then quietly refetch in the background — plus deduplication and
mutation, without asking you to restructure how the rest of your app manages state.

**What it isn't:**

- A general state-management framework — it doesn't replace Bloc/Riverpod/Provider for app state.
- An HTTP client — the fetcher is a plain `Future<T> Function()` you supply.
- A middleware system — if you need cross-cutting behavior like logging, wrap the fetcher you
  already pass in.

## Get started

Add the package to your `pubspec.yaml` (not yet published to pub.dev — depend on it via path or
git for now):

```yaml
dependencies:
  flutter_hooks: latest
  flutter_swr: latest
```

The smallest possible usage — a `HookWidget`, a key, and a fetcher:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_swr/flutter_swr.dart';

class ProfileScreen extends HookWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final (response, mutate) = useSwr<String>(
      'user/profile',
      fetcher: () => fetchProfileName(),
    );

    return response.when(
      loading: () => const CircularProgressIndicator(),
      error: (error, stackTrace) => Text('Failed: $error'),
      data: (name) => Text('Hello, $name'),
    );
  }
}
```

That's it — no provider setup required. The first call fetches and caches under the key
`'user/profile'`; any other widget that calls `useSwr('user/profile')` anywhere in the tree
instantly gets the cached value and shares the same in-flight request.

## Deep dive

### Core concepts

| Concept                    | In flutter_swr                                                                                                                                |
| -------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| **Stale-while-revalidate** | The hook returns whatever's cached for a key on the first frame, then kicks off a background fetch and rebuilds subscribers when it resolves. |
| **Cache key**              | Any hashable`Object` — typically a `String` (`'/api/user/$id'`), but a `List` or a Dart 3 `Record` works too.                                 |
| **Global cache**           | A singleton`SwrCache` shared by every `useSwr` call by default. Scope a different instance to a subtree with `SwrProvider`.                   |
| **Deduplication**          | Concurrent`useSwr` calls for the same key share a single in-flight fetch rather than issuing parallel requests.                               |

### `useSwr`

```dart
(SwrResponse<T>, SwrMutate<T>) useSwr<T>(
  Object? key, {
  Future<T> Function()? fetcher,
  SwrConfig? config,
})
```

- **`key`** — the cache key. Pass `null` to skip fetching entirely (see [Conditional fetching](#conditional--dependent-fetching)).
- **`fetcher`** — overrides the ambient config's fetcher for this call. If you set a `fetcher` on
  a `SwrProvider` (see below), you can omit this per call.
- **`config`** — a per-call `SwrConfig` merged on top of the nearest `SwrProvider`'s config; any
  field you don't set falls through to the ambient value. This is where `dedupingInterval`,
  `refreshInterval`, `retry`, `revalidateOnFocus`, and `onError`/`onSuccess` are set per call.

It returns a record: a `SwrResponse<T>` snapshot, and a `SwrMutate<T>` function bound to this call's key.

### `SwrResponse<T>`

```dart
class SwrResponse<T> {
  final T? data;
  final Object? error;
  final StackTrace? stackTrace;
  final bool isLoading;    // true only until the *first ever* fetch for this key resolves
  final bool isValidating; // true whenever a fetch (initial or background) is in flight
}
```

Read it directly, or pattern-match it the way you'd match a Riverpod `AsyncValue`:

```dart
// when: every branch required, exhaustive
response.when(
  loading: () => const CircularProgressIndicator(),
  error: (error, stackTrace) => Text('Error: $error'),
  data: (products) => ProductGrid(products),
);

// maybeWhen: handle what you care about, fall back for the rest
response.maybeWhen(
  data: (products) => ProductGrid(products),
  orElse: () => const SizedBox.shrink(),
);

// map / maybeMap: same idea, but callbacks receive the full SwrResponse
// (useful when you also want isValidating alongside data/error/loading)
response.map(
  data: (r) => ProductGrid(r.data!, isRefreshing: r.isValidating),
  error: (r) => ErrorView(r.error!),
  loading: (r) => const CircularProgressIndicator(),
);
```

`isLoading` and `isValidating` are independent: `isLoading` is only true before the very first
fetch for a key resolves, while `isValidating` is true for _any_ fetch in flight — including a
silent background refresh of data you're already showing. Use `isValidating` to show a subtle
"refreshing" indicator without hiding the data you already have.

### Mutation

Every `useSwr` call returns a bound `mutate` alongside its response:

```dart
final (response, mutate) = useSwr<List<Product>>('/products');

// Revalidate: refetch and update the cache
await mutate();

// Write directly, then still revalidate in the background
await mutate(data: updatedList);

// Write via an updater function
await mutate(updater: (current) => [...?current, newProduct]);

// Cascade: also revalidate other keys that currently have active subscribers
await mutate(invalidate: ['/products/summary']);
```

For mutating a key from outside the widget that owns it (e.g. after a delete elsewhere in the
app), use the top-level `mutate`, which operates on the shared default cache:

```dart
import 'package:flutter_swr/flutter_swr.dart' as swr;

await deleteProduct(productId);
await swr.mutate<List<Product>>(
  '/products',
  data: currentList.where((p) => p.id != productId).toList(),
  revalidate: false, // we already know the correct end state; skip the refetch
);
```

### Configuration: `SwrProvider` and `SwrConfig`

Scope defaults to a subtree with `SwrProvider`, so individual `useSwr` calls don't need to repeat
a `fetcher` or intervals:

```dart
SwrProvider(
  config: SwrConfig(
    fetcher: (key) => apiClient.get(key as String),
    dedupingInterval: const Duration(seconds: 30),
    revalidateOnFocus: true,
  ),
  child: const MaterialApp(home: HomeScreen()),
);
```

Nested `SwrProvider`s merge: a child's non-null fields override its ancestor's, and unset fields
fall through — same as a per-call `config:` merges over the nearest provider.

| Field                   | Type                                    | Default                                   | Purpose                                                                                |
| ----------------------- | --------------------------------------- | ----------------------------------------- | -------------------------------------------------------------------------------------- |
| `fetcher`               | `Future<dynamic> Function(Object key)?` | none                                      | Default fetcher, resolved by key, used when a`useSwr` call omits its own `fetcher`.    |
| `dedupingInterval`      | `Duration?`                             | 2s                                        | How long a cached result is considered fresh enough to skip an automatic revalidation. |
| `refreshInterval`       | `Duration?`                             | none (no polling)                         | Poll this key on a fixed interval while it has an active subscriber.                   |
| `retry`                 | `SwrRetryPolicy?`                       | 5 attempts, exponential backoff up to 30s | Retry behavior on fetcher failure.                                                     |
| `revalidateOnFocus`     | `bool?`                                 | `true`                                    | Whether resuming the app from the background revalidates this key.                     |
| `onError` / `onSuccess` | callbacks                               | none                                      | Side-effect hooks fired on fetch failure/success.                                      |
| `cache`                 | `SwrCache?`                             | shared`InMemoryCache`                     | Swap in a custom cache implementation (see below).                                     |

### Conditional / dependent fetching

Pass `null` as the key to skip fetching — useful when a request depends on data that isn't ready yet:

```dart
final (userResponse, _) = useSwr<User>('/user');
final (postsResponse, _) = useSwr<List<Post>>(
  userResponse.data == null ? null : '/user/${userResponse.data!.id}/posts',
);
```

Flipping from `null` to a real key starts fetching immediately on that rebuild. Flipping back to
`null` unsubscribes (cancels any polling) but leaves the cached data in place for next time.

### Automatic revalidation

Two triggers are wired up for you with no extra setup:

- **On app resume** — when the app returns to the foreground, every currently-mounted key with
  `revalidateOnFocus: true` (the default) revalidates, throttled to once per 5 seconds per key so
  rapid background/foreground cycling doesn't cause a revalidation storm.
- **Polling** — set `refreshInterval` (globally via `SwrConfig`, or per call via `useSwr`'s
  `config:`) to refetch on a fixed timer. Polling is ref-counted per key (only runs while at least
  one widget is subscribed) and automatically pauses while the app is backgrounded, resuming with
  an immediate revalidation when it comes back.

### Caching and deduplication

By default, every `useSwr` call in your app shares one in-memory cache (`InMemoryCache`). Keys are
normalized so that equal `String`s, Dart 3 `Record`s, and deeply-equal `List`s all map to the same
cache entry. Concurrent calls for the same key within the dedup window share a single in-flight
fetch — issuing the request once no matter how many widgets ask for it at the same moment.

You can supply your own cache (e.g. a persisted one) by implementing `SwrCache` and passing it via
`SwrConfig(cache: myCache)`:

```dart
abstract class SwrCache {
  CacheEntry<T>? get<T>(Object key);
  void set<T>(Object key, CacheEntry<T> entry);
  void delete(Object key);
  Iterable<Object> keys();
  Stream<CacheEntry<T>?> watch<T>(Object key);
  bool hasWatchers(Object key);
}
```

### Error handling and retry

Fetcher failures are retried automatically with exponential backoff (5 attempts by default, capped
at 30s between attempts) before the error surfaces in `SwrResponse.error`. Customize or disable
this via `SwrRetryPolicy`:

```dart
SwrConfig(
  retry: const SwrRetryPolicy(maxAttempts: 3),
);
```

### A fuller example

The [`example/`](example) app is a small product catalog against the public
[Fake Store API](https://fakestoreapi.com), showing the patterns above in a real widget tree: a
root `SwrProvider` with a shared fetcher, list/detail screens sharing a cache key, pull-to-refresh
via bound `mutate`, and an optimistic delete via the global `mutate`. Run it with:

```sh
cd example
flutter run
```

## flutter_swr vs. React SWR

| React SWR                                 | flutter_swr                                                        |
| ----------------------------------------- | ------------------------------------------------------------------ |
| `useSWR(key, fetcher)`                    | `useSwr<T>(key, fetcher: fetcher)`                                 |
| `<SWRConfig value={...}>`                 | `SwrProvider(config: SwrConfig(...))`                              |
| `mutate` from `useSWRConfig()`            | top-level`mutate<T>(key, ...)`                                     |
| `revalidateOnFocus` (tab refocus)         | `revalidateOnFocus` (app resume)                                   |
| `revalidateOnReconnect`                   | planned — see Roadmap                                              |
| `data`/`error`/`isLoading`/`isValidating` | same fields on`SwrResponse<T>`, plus `when`/`map` pattern matching |

## Roadmap

The core hook, caching, dedup, retry, mutation, app-resume revalidation, polling, and conditional
fetching are all implemented. Not yet shipped:

- Revalidate-on-reconnect (network connectivity adapter)
- Pluggable/persisted cache providers (interface exists; not yet validated beyond `InMemoryCache`)
- `useSwrInfinite` for pagination
- `keepPreviousData`
- Optimistic updates with automatic rollback
- `useSwrMutation` (imperative, trigger-based mutations)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for project layout, local setup, and test conventions.

## License

MIT — see [LICENSE](LICENSE).
