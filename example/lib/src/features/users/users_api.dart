import 'dart:convert';

import 'package:http/http.dart' as http;

/// One user from the reqres.in demo API.
class User {
  const User({
    required this.id,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.avatar,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'] as int,
    email: json['email'] as String,
    firstName: json['first_name'] as String,
    lastName: json['last_name'] as String,
    avatar: json['avatar'] as String,
  );

  final int id;
  final String email;
  final String firstName;
  final String lastName;
  final String avatar;

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'first_name': firstName,
    'last_name': lastName,
    'avatar': avatar,
  };

  String get name => '$firstName $lastName';
}

/// One page of `GET /api/users`: the page type `useSwrInfinite` works with.
class UsersPage {
  const UsersPage({
    required this.page,
    required this.totalPages,
    required this.users,
  });

  factory UsersPage.fromJson(Map<String, dynamic> json) => UsersPage(
    page: json['page'] as int,
    totalPages: json['total_pages'] as int,
    users: [
      for (final user in json['data'] as List)
        User.fromJson(user as Map<String, dynamic>),
    ],
  );

  /// 1-based, as reqres numbers them.
  final int page;
  final int totalPages;
  final List<User> users;

  Map<String, dynamic> toJson() => {
    'page': page,
    'total_pages': totalPages,
    'data': [for (final user in users) user.toJson()],
  };

  bool get isLast => page >= totalPages;
}

/// Thin client for reqres.in, a separate API from the store's, because it
/// has real page-based pagination
/// (`/api/users?page=N&per_page=M` → `{page, total_pages, data}`).
class UsersApi {
  UsersApi({http.Client? client}) : _client = client ?? http.Client();

  static const String baseUrl = 'https://reqres.in';
  static const int perPage = 10;

  final http.Client _client;

  /// The key for the page after [previous] (the first page when [previous]
  /// is `null`), or `null` once [previous] was the last page.
  static String? pageKey(int pageIndex, UsersPage? previous) {
    if (previous != null && previous.isLast) return null;
    return '/api/users?page=${pageIndex + 1}&per_page=$perPage';
  }

  /// Fetches the page at [key], a path from [pageKey].
  Future<UsersPage> fetchPage(Object key) async {
    final http.Response response;
    try {
      response = await _client.get(Uri.parse('$baseUrl$key'));
    } on http.ClientException {
      throw Exception('No internet connection. Please try again.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Request failed (${response.statusCode}). Please try again.',
      );
    }
    return UsersPage.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }
}

final UsersApi usersApi = UsersApi();
