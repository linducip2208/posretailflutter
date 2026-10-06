import 'package:flutter/material.dart';
import '../models/outlet.dart';
import '../models/user.dart';
import '../services/auth_service.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();
  User? _user;
  List<Outlet> _outlets = [];
  Outlet? _currentOutlet;
  bool _isLoading = false;
  String? _error;

  User? get user => _user;
  bool get isLoading => _isLoading;
  bool get isLoggedIn => _user != null;
  String? get error => _error;
  String? get role => _user?.role;
  List<Outlet> get outlets => List.unmodifiable(_outlets);
  Outlet? get currentOutlet => _currentOutlet;
  int? get currentOutletId => _currentOutlet?.id;

  Future<bool> login(String email, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _user = await _authService.login(email, password);
      await _resolveOutlets(autoPersistSingle: true);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    await _authService.logout();
    await _authService.clearCurrentOutletId();
    _user = null;
    _outlets = [];
    _currentOutlet = null;
    notifyListeners();
  }

  Future<bool> tryAutoLogin() async {
    final hasToken = await _authService.isLoggedIn();
    if (!hasToken) return false;
    try {
      _user = await _authService.getCurrentUser();
      await _resolveOutlets(autoPersistSingle: false);
      notifyListeners();
      return true;
    } catch (_) {
      await _authService.logout();
      return false;
    }
  }

  /// Muat daftar outlet + pulihkan pilihan tersimpan.
  /// 1 outlet → otomatis dipilih. >1 → butuh pilihan eksplisit user.
  Future<void> _resolveOutlets({required bool autoPersistSingle}) async {
    List<Outlet> list = _user?.outlets ?? [];
    if (list.isEmpty) {
      try {
        list = await _authService.getOutlets();
      } catch (_) {
        list = [];
      }
    }
    _outlets = list;

    final savedId = await _authService.readCurrentOutletId();
    Outlet? saved;
    if (savedId != null) {
      for (final o in _outlets) {
        if (o.id == savedId) saved = o;
      }
    }
    if (saved != null) {
      _currentOutlet = saved;
    } else if (_outlets.length == 1) {
      _currentOutlet = _outlets.first;
      if (autoPersistSingle) {
        await _authService.saveCurrentOutletId(_currentOutlet!.id);
      }
    } else {
      _currentOutlet = null;
    }
  }

  /// True jika outlet aktif sudah pasti (tidak perlu layar seleksi).
  bool get hasOutlet => _currentOutlet != null;

  Future<void> selectOutlet(Outlet outlet) async {
    _currentOutlet = outlet;
    await _authService.saveCurrentOutletId(outlet.id);
    notifyListeners();
  }
}
