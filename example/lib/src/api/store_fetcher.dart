import '../models/product.dart';
import 'store_api_client.dart';

/// The app's single [SwrConfig.fetcher]: given a `useSwr` key (a REST path,
/// e.g. `/products` or `/products/1`), performs the `GET` and decodes the
/// JSON into the exact typed shape `useSwr`'s type parameter expects for
/// that key.
///
/// The ambient fetcher isn't generic (it resolves by key and returns
/// `dynamic`), so this routing/decoding step is what lets call sites simply
/// do `useSwr('/products')`, typed as a list of products, with no per-call
/// `fetcher:` override.
class StoreFetcher {
  StoreFetcher(this._client);

  final StoreApiClient _client;

  static final RegExp _productIdPath = RegExp(r'^/products/\d+$');

  Future<dynamic> fetch(Object key) async {
    final path = key as String;
    final decoded = await _client.get(path);

    if (path == '/products') {
      return (decoded as List)
          .map((e) => Product.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    if (_productIdPath.hasMatch(path)) {
      return Product.fromJson(decoded as Map<String, dynamic>);
    }

    throw StateError('StoreFetcher has no route for key "$path".');
  }
}
