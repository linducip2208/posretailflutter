import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'lang_provider.dart';
import 'strings_en.dart';

/// Akses string terlokalisasi: S.t(context, 'Bayar').
/// Fallback = kunci Bahasa Indonesia bila terjemahan belum ada.
/// S.e tanpa context untuk dipakai setelah async gap (tangkap dulu
/// `context.read<LangProvider>().isEnglish` sebelum await).
class S {
  static String e(bool isEnglish, String id, [Map<String, String>? params]) {
    var out = id;
    if (isEnglish && stringsEn.containsKey(id)) out = stringsEn[id]!;
    params?.forEach((k, v) => out = out.replaceAll('{$k}', v));
    return out;
  }

  static String t(BuildContext context, String id, [Map<String, String>? params]) {
    final lang = context.watch<LangProvider>();
    return e(lang.isEnglish, id, params);
  }

  static String tn(BuildContext context, String id, [Map<String, String>? params]) {
    final lang = context.read<LangProvider>();
    return e(lang.isEnglish, id, params);
  }
}
