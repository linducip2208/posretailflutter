import '../models/user.dart';
import 'api_service.dart';

class AuthService {
  final ApiService _api = ApiService();

  Future<User> login(String email, String password) async {
    final response = await _api.post('/login', body: {
      'email': email,
      'password': password,
    }, auth: false);

    final token = response['token'];
    await _api.setToken(token);

    final userData = response['user'];

    return User.fromJson(userData);
  }

  Future<User> getCurrentUser() async {
    final response = await _api.get('/user');
    return User.fromJson(response);
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
}
