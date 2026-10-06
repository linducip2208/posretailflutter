import 'package:shared_preferences/shared_preferences.dart';
import '../models/outlet.dart';
import '../models/user.dart';
import 'api_service.dart';

class AuthService {
  final ApiService _api = ApiService();
  static const _outletKey = 'current_outlet_id';

  Future<User> login(String email, String password) async {
    final response = await _api.post('/login', body: {
      'email': email,
      'password': password,
    }, auth: false);

    final token = response is Map ? response['token'] : null;
    if (token is! String || token.isEmpty) {
      throw ApiException(statusCode: 500, message: 'Login gagal, coba lagi.');
    }
    await _api.setToken(token);

    final userData = response['user'];
    if (userData is! Map<String, dynamic>) {
      await _api.clearToken();
      throw ApiException(statusCode: 500, message: 'Login gagal, coba lagi.');
    }
    return User.fromJson(userData);
  }

  Future<User> getCurrentUser() async {
    final response = await _api.get('/user');
    if (response is! Map<String, dynamic>) {
      throw ApiException(statusCode: 500, message: 'Gagal memuat profil.');
    }
    return User.fromJson(response);
  }

  Future<List<Outlet>> getOutlets() async {
    final response = await _api.get('/outlets');
    final data = response is Map ? response['data'] : response;
    if (data is! List) return [];
    return data.whereType<Map<String, dynamic>>().map(Outlet.fromJson).toList();
  }

  Future<void> logout() async {
    try {
      await _api.post('/logout');
    } catch (_) {}
    await _api.clearToken();
  }

  Future<bool> isLoggedIn() async {
    final token = await _api.token;
    return token != null && token.isNotEmpty;
  }

  Future<int?> readCurrentOutletId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_outletKey);
  }

  Future<void> saveCurrentOutletId(int id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_outletKey, id);
  }

  Future<void> clearCurrentOutletId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_outletKey);
  }
}
