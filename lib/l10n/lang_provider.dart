import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Bahasa aplikasi: Indonesia (default) atau English.
/// Semua string UI memakai Bahasa Indonesia sebagai kunci-and-fallback,
/// sehingga string baru otomatis tampil (ID) walau belum diterjemahkan.
class LangProvider extends ChangeNotifier {
  static const _key = 'lang';
  String _code = 'id';

  String get code => _code;
  bool get isEnglish => _code == 'en';
  Locale get locale => Locale(_code);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _code = prefs.getString(_key) ?? 'id';
    if (_code != 'en') _code = 'id';
    notifyListeners();
  }

  Future<void> setCode(String code) async {
    if (code != 'id' && code != 'en') return;
    _code = code;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, code);
    notifyListeners();
  }
}
