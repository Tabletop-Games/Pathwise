import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// How a request failed. Players only ever see friendly text derived from this.
enum ApiFailure {
  none,
  noInternet,
  backendUnavailable,
  unauthorized,
  updateRequired,
  rejected,
}

final class ApiResponse {
  const ApiResponse(this.status, this.body, {this.failure = ApiFailure.none});

  /// A status of 0 means the request never produced an HTTP response.
  final int status;
  final Map<String, dynamic> body;
  final ApiFailure failure;

  bool get ok => status >= 200 && status < 300;
  bool get transportFailure => status == 0;
  bool get retryable =>
      transportFailure || status == 429 || (status >= 500 && status < 600);
  String? get error => body['error'] is String ? body['error'] as String : null;
}

abstract class HttpTransport {
  Future<ApiResponse> send(
    String method,
    Uri url, {
    required Map<String, String> headers,
    String? body,
    required Duration timeout,
  });
}

/// dart:io transport. TLS validation stays at the platform default.
class IoTransport implements HttpTransport {
  IoTransport() : _client = HttpClient() {
    _client.connectionTimeout = const Duration(seconds: 6);
    _client.idleTimeout = const Duration(seconds: 20);
  }

  final HttpClient _client;

  @override
  Future<ApiResponse> send(
    String method,
    Uri url, {
    required Map<String, String> headers,
    String? body,
    required Duration timeout,
  }) async {
    try {
      final request = await _client.openUrl(method, url).timeout(timeout);
      for (final entry in headers.entries) {
        request.headers.set(entry.key, entry.value);
      }
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.add(utf8.encode(body));
      }
      final response = await request.close().timeout(timeout);
      final text = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);
      Map<String, dynamic> decoded = const {};
      if (text.isNotEmpty) {
        try {
          final value = jsonDecode(text);
          if (value is Map<String, dynamic>) decoded = value;
        } on FormatException {
          decoded = const {};
        }
      }
      return ApiResponse(response.statusCode, decoded);
    } on SocketException {
      return const ApiResponse(0, {}, failure: ApiFailure.noInternet);
    } on TimeoutException {
      return const ApiResponse(0, {}, failure: ApiFailure.backendUnavailable);
    } on HttpException {
      return const ApiResponse(0, {}, failure: ApiFailure.backendUnavailable);
    } on HandshakeException {
      return const ApiResponse(0, {}, failure: ApiFailure.backendUnavailable);
    } on TlsException {
      return const ApiResponse(0, {}, failure: ApiFailure.backendUnavailable);
    }
  }
}

/// Thin JSON client. It adds the build header and classifies failures.
class ApiClient {
  ApiClient({
    required this.baseUrl,
    required this.transport,
    required this.build,
    this.timeout = const Duration(seconds: 10),
  });

  final String baseUrl;
  final HttpTransport transport;
  final int build;
  final Duration timeout;

  bool get configured => Uri.tryParse(baseUrl)?.hasAuthority ?? false;

  Future<ApiResponse> request(
    String method,
    String path, {
    Object? body,
    String? token,
  }) async {
    final response = await transport.send(
      method,
      Uri.parse('$baseUrl$path'),
      headers: {
        'accept': 'application/json',
        'x-pathwise-build': '$build',
        if (token != null) 'authorization': 'Bearer $token',
      },
      body: body == null ? null : jsonEncode(body),
      timeout: timeout,
    );
    if (response.transportFailure) return response;
    final failure = switch (response.status) {
      426 => ApiFailure.updateRequired,
      401 => ApiFailure.unauthorized,
      >= 500 => ApiFailure.backendUnavailable,
      >= 400 => ApiFailure.rejected,
      _ => ApiFailure.none,
    };
    if (failure == ApiFailure.none) return response;
    return ApiResponse(response.status, response.body, failure: failure);
  }
}
