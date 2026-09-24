import 'dart:convert';

import 'package:http/http.dart' as http;

/// Thrown for a non-2xx response or an unparsable body, with a message
/// that's safe to show directly in the UI.
class StoreApiException implements Exception {
  StoreApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Thin HTTP wrapper around the Fake Store API: owns the base URL and the
/// `http.Client`, and turns network/decode failures into [StoreApiException].
class StoreApiClient {
  StoreApiClient({http.Client? client}) : _client = client ?? http.Client();

  static const String baseUrl = 'https://fakestoreapi.com';

  final http.Client _client;

  Future<dynamic> get(String path) => _send(() => _client.get(_uri(path)));

  Future<dynamic> delete(String path) =>
      _send(() => _client.delete(_uri(path)));

  Future<dynamic> put(String path, Object body) => _send(
    () => _client.put(
      _uri(path),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    ),
  );

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Future<dynamic> _send(Future<http.Response> Function() request) async {
    final http.Response response;
    try {
      response = await request();
    } on http.ClientException {
      throw StoreApiException('No internet connection. Please try again.');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StoreApiException(
        'Request failed (${response.statusCode}). Please try again.',
      );
    }

    try {
      return jsonDecode(response.body);
    } on FormatException {
      throw StoreApiException('Received an unexpected response.');
    }
  }
}
