import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:printing/printing.dart';


class ApiClient {
  ApiClient(this.baseUrl, {this.token});
  final String baseUrl;
  final String? token;

  Map<String, String> get _headers => {
        'Accept': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<Map<String, dynamic>> login(String email, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {'username': email, 'password': password},
    );
    final body = _decode(response);
    return Map<String, dynamic>.from(body as Map);
  }

  Future<dynamic> get(String path) async {
    final response = await http.get(Uri.parse('$baseUrl$path'), headers: _headers);
    return _decode(response);
  }

  /// Exhausts an offset-paginated list endpoint. Do not use for unpaged routes.
  /// A failed page fails the whole load rather than returning partial search data.
  Future<List<Map<String, dynamic>>> getAll(String path) async {
    final uri = Uri.parse(path);
    final records = <Map<String, dynamic>>[];
    final seen = <Object>{};
    var offset = 0;
    while (true) {
      final page = await get(
        uri
            .replace(
              queryParameters: {
                ...uri.queryParameters,
                'limit': '200',
                'offset': '$offset',
              },
            )
            .toString(),
      );
      if (page is! List) throw const FormatException('Se esperaba una lista');
      if (page.isEmpty) return records;
      var added = 0;
      for (final row in page) {
        if (row is! Map || row['id'] == null) {
          throw const FormatException('Registro sin identificador');
        }
        if (seen.add(row['id'] as Object)) {
          records.add(Map<String, dynamic>.from(row));
          added++;
        }
      }
      if (added == 0) {
        throw const FormatException('La API no avanzó a la siguiente página');
      }
      offset += page.length;
    }
  }

  Future<Uint8List> getBytes(String path) async {
    final response = await http.get(Uri.parse('$baseUrl$path'), headers: _headers);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _decode(response);
      throw Exception('Error HTTP ${response.statusCode}');
    }
    return response.bodyBytes;
  }

  Future<dynamic> post(String path) async {
    final response = await http.post(Uri.parse('$baseUrl$path'), headers: _headers);
    return _decode(response);
  }

  Future<dynamic> postJson(String path, Map<String, dynamic> data) async {
    final response = await http.post(
      Uri.parse('$baseUrl$path'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode(data),
    );
    return _decode(response);
  }

  Future<dynamic> patchJson(String path, Map<String, dynamic> data) async {
    final response = await http.patch(
      Uri.parse('$baseUrl$path'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode(data),
    );
    return _decode(response);
  }

  Future<dynamic> putJson(String path, Map<String, dynamic> data) async {
    final response = await http.put(
      Uri.parse('$baseUrl$path'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode(data),
    );
    return _decode(response);
  }

  Future<dynamic> delete(String path) async {
    final response = await http.delete(Uri.parse('$baseUrl$path'), headers: _headers);
    return _decode(response);
  }

  Future<dynamic> uploadBytes(String path, List<int> bytes, String filename, {String? contentType}) async {
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl$path'));
    request.headers.addAll(_headers);
    request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    return _decode(response);
  }

  dynamic _decode(http.Response response) {
    final body = response.body.isEmpty ? null : jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = body is Map ? body['detail'] : null;
      throw Exception(message?.toString() ?? 'Error HTTP ${response.statusCode}');
    }
    return body;
  }
}

Future<void> openGudexPdf(ApiClient api, String path, String filename) async {
  final bytes = await api.getBytes(path);
  if (kIsWeb) {
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  } else {
    await Printing.sharePdf(bytes: bytes, filename: filename);
  }
}
