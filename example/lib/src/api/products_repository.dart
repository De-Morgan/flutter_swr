import '../models/product.dart';
import 'store_api_client.dart';

/// Write operations for products. Kept separate from [StoreFetcher]: these
/// are one-off mutations (`DELETE`/`PUT`), not `useSwr` keys — the caller
/// feeds the result into the cache afterward, via `mutate(...)` or
/// `useSwrMutation`'s `populateCache`.
class ProductsRepository {
  ProductsRepository(this._client);

  final StoreApiClient _client;

  Future<void> deleteProduct(int id) => _client.delete('/products/$id');

  /// `PUT`s the whole [product] and returns the server's copy. The Fake
  /// Store API echoes the body back but doesn't persist it: a later `GET`
  /// still returns the seed data.
  Future<Product> updateProduct(Product product) async {
    final json = await _client.put('/products/${product.id}', product.toJson());
    return Product.fromJson(json as Map<String, dynamic>);
  }
}
