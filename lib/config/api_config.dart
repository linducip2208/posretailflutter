class ApiConfig {
  /// Alamat API produksi adalah default; dapat dioverride saat build
  /// untuk staging/lokal tanpa mengubah kode:
  /// `flutter build apk --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1`
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://posretail.whitelabel.co.id/api/v1',
  );

  /// Batas tunggu total per request HTTP (connect + baca respons).
  static const Duration requestTimeout = Duration(seconds: 15);
}
