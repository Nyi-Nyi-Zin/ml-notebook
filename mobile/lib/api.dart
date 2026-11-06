import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final int status;
  final String message;
  const ApiException(this.status, this.message);
  @override
  String toString() => message;
}

class ApiClient {
  final http.Client client;
  String baseUrl;
  String? token;
  ApiClient({this.baseUrl = '', http.Client? client})
    : client = client ?? http.Client();
  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    bool auth = true,
  }) async {
    if (baseUrl.isEmpty) {
      throw const ApiException(
        0,
        'Set your Rust API URL in Settings to connect.',
      );
    }
    final request = http.Request(method, Uri.parse('$baseUrl$path'));
    request.headers['Content-Type'] = 'application/json';
    if (auth && token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    if (body != null) request.body = jsonEncode(body);
    try {
      final streamed = await client
          .send(request)
          .timeout(const Duration(seconds: 20));
      final response = await http.Response.fromStream(
        streamed,
      ).timeout(const Duration(seconds: 20));
      dynamic result;
      if (response.bodyBytes.isNotEmpty) {
        try {
          result = jsonDecode(utf8.decode(response.bodyBytes));
        } on FormatException {
          throw const ApiException(
            502,
            'The server returned an invalid response. Check your API URL.',
          );
        }
      }
      if (response.statusCode >= 400) {
        throw ApiException(
          response.statusCode,
          result is Map
              ? (result['error']?.toString() ??
                    'Request failed (${response.statusCode}).')
              : 'Request failed (${response.statusCode}).',
        );
      }
      return result;
    } on TimeoutException {
      throw const ApiException(
        0,
        'The API did not respond in time. A free server may be starting; retry shortly.',
      );
    } on http.ClientException {
      throw const ApiException(
        0,
        'Cannot reach the API. Check the URL, internet connection and server CORS settings.',
      );
    }
  }

  void close() => client.close();
}
