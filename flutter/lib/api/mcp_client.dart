import 'dart:convert';

import 'package:http/http.dart' as http;

enum McpFailure { unauthorized, forbidden, network, server, tool }

class McpException implements Exception {
  const McpException(this.failure, this.message);

  final McpFailure failure;
  final String message;

  @override
  String toString() => 'McpException(${failure.name}): $message';
}

/// One JSON-RPC `tools/call` against the Reqall MCP endpoint, the same
/// request the desktop app and omarchy widget make. The server answers as
/// plain JSON or as a one-event SSE stream; both are handled. Returns the
/// tool's `data` object.
class McpClient {
  McpClient({required this.endpoint, required this.token, http.Client? httpClient, this.timeout = const Duration(seconds: 20)})
      : _http = httpClient ?? http.Client(),
        _ownsHttp = httpClient == null;

  /// Full URL of the MCP endpoint, e.g. https://www.reqall.net/mcp.
  final Uri endpoint;

  /// Reads the current bearer token on every call, so a refreshed token
  /// takes effect without rebuilding the client.
  final String Function() token;
  final Duration timeout;
  final http.Client _http;
  final bool _ownsHttp;
  int _id = 0;

  Future<Map<String, dynamic>> call(String name, [Map<String, dynamic> args = const {}]) async {
    final body = jsonEncode({
      'jsonrpc': '2.0',
      'id': ++_id,
      'method': 'tools/call',
      'params': {'name': name, 'arguments': args},
    });
    http.Response res;
    try {
      res = await _http
          .post(endpoint,
              headers: {
                'Authorization': 'Bearer ${token()}',
                'Content-Type': 'application/json',
                'Accept': 'application/json, text/event-stream',
              },
              body: body)
          .timeout(timeout);
    } catch (_) {
      throw McpException(McpFailure.network, 'Could not reach ${endpoint.host}');
    }

    var text = utf8.decode(res.bodyBytes);
    String jsonMessage(String fallback) {
      try {
        final j = jsonDecode(text);
        if (j is Map) return (j['message'] ?? j['error_description'] ?? j['error'] ?? fallback).toString();
      } catch (_) {}
      return fallback;
    }

    if (res.statusCode == 401) throw McpException(McpFailure.unauthorized, jsonMessage('Unauthorized'));
    if (res.statusCode == 403) throw McpException(McpFailure.forbidden, jsonMessage('Forbidden'));
    if (res.statusCode != 200) throw McpException(McpFailure.server, 'Server returned HTTP ${res.statusCode}');

    if (RegExp(r'^(event|data):').hasMatch(text)) {
      final line = const LineSplitter().convert(text).where((l) => l.startsWith('data:')).firstOrNull;
      text = line == null ? '' : line.substring(5).trimLeft();
    }

    Object? payload;
    try {
      payload = jsonDecode(text);
    } catch (_) {
      throw const McpException(McpFailure.server, 'Unexpected response');
    }
    if (payload is! Map) throw const McpException(McpFailure.server, 'Unexpected response');

    final error = payload['error'];
    if (error is Map) throw McpException(McpFailure.tool, (error['message'] ?? 'Request failed').toString());

    final result = payload['result'];
    final structured = result is Map ? result['structuredContent'] : null;
    if (structured is Map) {
      if (structured['ok'] == false || result['isError'] == true) {
        throw McpException(McpFailure.tool, (structured['error'] ?? structured['message'] ?? 'Request failed').toString());
      }
      final data = structured['data'];
      return data is Map<String, dynamic> ? data : Map<String, dynamic>.from(structured);
    }
    // Errors from the tool layer arrive as text content with isError set.
    final content = result is Map ? result['content'] : null;
    final first = content is List && content.isNotEmpty ? content.first : null;
    final message = first is Map ? first['text']?.toString() : null;
    throw McpException(McpFailure.tool, message ?? 'Unexpected response');
  }

  void close() {
    if (_ownsHttp) _http.close();
  }
}
