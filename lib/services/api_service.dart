import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  String? _token;

  Future<String?> get token async {
    if (_token != null) return _token;
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('auth_token');
    return _token;
  }

  Future<void> setToken(String token) async {
    _token = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
  }

  Future<void> clearToken() async {
    _token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('user_name');
    await prefs.remove('user_email');
    await prefs.remove('user_role');
  }

  Map<String, String> _headers({bool auth = true}) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (auth && _token != null) {
      headers['Authorization'] = 'Bearer $_token';
    }
    return headers;
  }

  Future<dynamic> get(String path, {bool auth = true}) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}$path');
    final response = await http.get(uri, headers: _headers(auth: auth))
        .timeout(ApiConfig.connectTimeout);
    return _handleResponse(response);
  }

  Future<dynamic> post(String path, {Map<String, dynamic>? body, bool auth = true}) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}$path');
    final response = await http.post(
      uri,
      headers: _headers(auth: auth),
      body: body != null ? jsonEncode(body) : null,
    ).timeout(ApiConfig.connectTimeout);
    return _handleResponse(response);
  }

  dynamic _handleResponse(http.Response response) {
    final body = jsonDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body;
    }
    throw ApiException(
      statusCode: response.statusCode,
      message: body['message'] ?? 'Request failed',
      errors: body['errors'],
    );
  }
}

class ApiException implements Exception {
  final int statusCode;
  final String message;
  final dynamic errors;

  ApiException({required this.statusCode, required this.message, this.errors});

  @override
  String toString() => message;
}
