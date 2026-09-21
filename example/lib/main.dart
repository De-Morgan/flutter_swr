import 'package:flutter/material.dart';
import 'package:flutter_swr_example/src/cache/sqflite_swr_cache.dart';
import 'package:flutter_swr_example/src/cache/swr_model.dart';

import 'src/app.dart';
import 'src/models/product.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final cache = await SqfliteSwrCache.open(
    fromJson: {...swrModel<Product>(Product.fromJson)},
  );

  runApp(StoreApp(cache: cache));
}
