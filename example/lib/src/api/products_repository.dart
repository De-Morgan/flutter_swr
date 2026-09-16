import 'store_api_client.dart';

/// Write operations for products. Kept separate from [StoreFetcher]: this
/// is a one-off mutation (`DELETE`), not a `useSwr` key — the caller feeds
/// the result into the cache afterward via `mutate(...)`, not through it.
class ProductsRepository {
  ProductsRepository(this._client);

  final StoreApiClient _client;

  Future<void> deleteProduct(int id) => _client.delete('/products/$id');
}
