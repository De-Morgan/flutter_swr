# flutter_swr example — Fake Store

A small product-browsing app built on [flutter_swr](../) and the
[Fake Store API](https://fakestoreapi.com), showing what the package looks
like wired up to a real network backend rather than an in-memory fake.

## What it demonstrates

- **`useSwr` as the only data-fetching call site.** Every screen just does
  `useSwr<T>('/some/path')` — the fetching, caching, deduping, retrying, and
  background revalidation are all handled by the package. See
  [`lib/src/features/products/product_list_screen.dart`](lib/src/features/products/product_list_screen.dart)
  and
  [`lib/src/features/products/product_detail_screen.dart`](lib/src/features/products/product_detail_screen.dart).
- **A single keyed fetcher.** [`lib/src/api/store_fetcher.dart`](lib/src/api/store_fetcher.dart)
  is the app's one `SwrConfig.fetcher`: given a `useSwr` key (a REST path
  like `/products` or `/products/1`), it does the `http` GET and decodes the
  JSON into the exact typed shape (`List<Product>` or `Product`) that call
  site expects — which is what lets screens use a plain string key with no
  per-call `fetcher:` override.
- **Two `SwrProvider`s.** The root one (in
  [`lib/src/app.dart`](lib/src/app.dart)) sets the fetcher and a 30s
  `dedupingInterval` for the catalog; the product detail screen wraps itself
  in a second, nested `SwrProvider` with a shorter 5s interval, since a
  single product's page should feel fresher on repeat visits than the grid
  does. Nested providers merge field-by-field, so the detail screen still
  inherits the same fetcher and retry policy from the root.
- **A reusable retry widget.** [`lib/src/widgets/swr_view.dart`](lib/src/widgets/swr_view.dart)
  wraps any `SwrResponse<T>` and renders a spinner while loading, a "Retry"
  button wired to the bound `mutate()` on error, or the data. Both screens
  use it instead of hand-rolled loading/error branches.
- **A revalidating indicator.** [`lib/src/widgets/swr_status_bar.dart`](lib/src/widgets/swr_status_bar.dart)
  shows a small "Refreshing…" row whenever `SwrResponse.isValidating` is
  true — visible proof of the stale-while-revalidate behavior, e.g. when
  pulling to refresh or when the app regains focus.
- **Deleting a product with `mutate()`.** The detail screen's delete action
  (in `product_detail_screen.dart`) calls the Fake Store API's `DELETE
  /products/:id` via [`lib/src/api/products_repository.dart`](lib/src/api/products_repository.dart),
  then patches the list's cache directly with the top-level
  `mutate<List<Product>>('/products', data: ..., revalidate: false)` —
  `revalidate: false` matters here because Fake Store API doesn't actually
  persist writes, so a real refetch would just bring the deleted item right
  back.
- **Cached images.** [`lib/src/widgets/store_network_image.dart`](lib/src/widgets/store_network_image.dart)
  wraps `cached_network_image` with a loading placeholder and a
  broken-image fallback for every product photo.

## Project layout

```
lib/
  main.dart                                  # runApp(const StoreApp())
  src/
    api/
      store_api_client.dart                  # http.Client wrapper, StoreApiException
      store_fetcher.dart                     # the SwrConfig.fetcher (GET + decode by key)
      products_repository.dart               # deleteProduct (DELETE), used outside useSwr
      api.dart                               # app-wide singletons for the above
    models/
      product.dart                           # Product, Rating
    widgets/
      swr_view.dart                          # retry-on-error wrapper around SwrResponse
      swr_status_bar.dart                    # "Refreshing…" indicator (isValidating)
      store_network_image.dart               # CachedNetworkImage wrapper
    features/products/
      product_list_screen.dart               # grid of products, pull-to-refresh
      product_detail_screen.dart             # single product + delete
      widgets/product_card.dart
    app.dart                                 # root SwrProvider + MaterialApp
```

## Running it

```
flutter pub get
flutter run
```

This app talks to the live `https://fakestoreapi.com` — no backend to run
and no API key needed, but you do need network access.

## Getting Started (Flutter)

A few resources if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
