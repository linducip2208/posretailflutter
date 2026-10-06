import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import 'secure_token_storage.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  /// Dipanggil sekali saat menerima 401 (token kedaluwarsa/dicabut).
  /// Di-wire di main.dart ke logout + navigasi login.
  static void Function()? onUnauthorized;

  String? _token;

  Future<String?> get token async {
    if (_token != null) return _token;
    _token = await SecureTokenStorage().readToken();
    return _token;
  }

  Future<void> setToken(String token) async {
    _token = token;
    await SecureTokenStorage().writeToken(token);
  }

  Future<void> clearToken() async {
    _token = null;
    await SecureTokenStorage().clearToken();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_name');
    await prefs.remove('user_email');
    await prefs.remove('user_role');
    await prefs.remove('current_outlet_id');
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
    dynamic body;
    try {
      body = response.body.isNotEmpty ? jsonDecode(response.body) : {};
    } catch (_) {
      body = {};
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body;
    }
    if (response.statusCode == 401) {
      _token = null;
      onUnauthorized?.call();
    }
    throw ApiException(
      statusCode: response.statusCode,
      message: (body is Map ? body['message'] : null) ?? _humanMessage(response.statusCode),
      errors: body is Map ? body['errors'] : null,
    );
  }

  /// Pesan manusiawi (Bahasa Indonesia) per status HTTP.
  static String _humanMessage(int status) {
    switch (status) {
      case 400:
        return 'Permintaan tidak valid.';
      case 401:
        return 'Sesi berakhir, silakan login kembali.';
      case 403:
        return 'Anda tidak memiliki akses.';
      case 404:
        return 'Data tidak ditemukan.';
      case 409:
        return 'Data bentrok, coba lagi.';
      case 422:
        return 'Data tidak valid, periksa isian.';
      case 429:
        return 'Terlalu banyak percobaan, tunggu sebentar.';
      case 500:
        return 'Server bermasalah, coba lagi.';
      case 502:
      case 503:
        return 'Server sibuk, coba lagi.';
      default:
        if (status >= 500) return 'Server bermasalah, coba lagi.';
        return 'Request gagal.';
    }
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
