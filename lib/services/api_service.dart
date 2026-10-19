import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import 'secure_token_storage.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  /// HTTP client — dapat diganti di test (mis. MockClient dari http/testing).
  static http.Client client = http.Client();

  /// Dipanggil saat menerima 401 (token kedaluwarsa/dicabut).
  /// Di-wire di main.dart ke logout + navigasi login.
  static void Function()? onUnauthorized;

  /// Debounce 401 beruntun (beberapa request paralel) → satu navigasi saja.
  static DateTime? _lastUnauthorizedAt;

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

  /// Bangun URI + query parameter yang di-encode aman.
  /// Nilai null/kosong diabaikan agar tidak mengirim `?search=`.
  Uri _uri(String path, Map<String, String?>? query) {
    final base = Uri.parse('${ApiConfig.baseUrl}$path');
    if (query == null || query.isEmpty) return base;
    final cleaned = <String, String>{};
    query.forEach((key, value) {
      if (value != null && value.isNotEmpty) cleaned[key] = value;
    });
    if (cleaned.isEmpty) return base;
    return base.replace(queryParameters: {...base.queryParameters, ...cleaned});
  }

  Future<dynamic> get(
    String path, {
    bool auth = true,
    Map<String, String?>? query,
  }) async {
    final uri = _uri(path, query);
    final response = await _send(
      () => client.get(uri, headers: _headers(auth: auth)),
    );
    return _handleResponse(response);
  }

  Future<dynamic> post(
    String path, {
    Map<String, dynamic>? body,
    bool auth = true,
    Map<String, String?>? query,
  }) async {
    final uri = _uri(path, query);
    final response = await _send(
      () => client.post(
        uri,
        headers: _headers(auth: auth),
        body: body != null ? jsonEncode(body) : null,
      ),
    );
    return _handleResponse(response);
  }

  /// Eksekusi request + timeout + normalisasi kegagalan jaringan.
  Future<http.Response> _send(Future<http.Response> Function() request) async {
    try {
      return await request().timeout(ApiConfig.requestTimeout);
    } on TimeoutException {
      throw ApiNetworkException(
        'Koneksi ke server timeout. Periksa jaringan lalu coba lagi.',
      );
    } on SocketException {
      throw ApiNetworkException(
        'Tidak dapat terhubung ke server. Periksa jaringan Anda.',
      );
    } on http.ClientException {
      throw ApiNetworkException(
        'Koneksi ke server gagal. Periksa jaringan Anda.',
      );
    }
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
      // Bersihkan juga token tersimpan — jangan hanya di memori.
      unawaited(() async {
        try {
          await clearToken();
        } catch (_) {
          // Storage tidak tersedia (mis. unit test) — abaikan.
        }
      }());
      final now = DateTime.now();
      if (_lastUnauthorizedAt == null ||
          now.difference(_lastUnauthorizedAt!) > const Duration(seconds: 3)) {
        _lastUnauthorizedAt = now;
        onUnauthorized?.call();
      }
    }
    throw ApiException(
      statusCode: response.statusCode,
      message:
          (body is Map ? body['message'] : null) ??
          _humanMessage(response.statusCode),
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

/// Kegagalan jaringan (timeout / tidak dapat terhubung ke server).
/// Dibedakan dari error HTTP agar pemanggil bisa fallback ke antrean offline.
/// [statusCode] = 0 karena tidak ada respons HTTP.
class ApiNetworkException extends ApiException {
  ApiNetworkException(String message) : super(statusCode: 0, message: message);
}
