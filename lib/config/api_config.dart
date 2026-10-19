class ApiConfig {
  static const String baseUrl = 'https://posretail.whitelabel.co.id/api/v1';

  /// Batas tunggu total per request HTTP (connect + baca respons).
  static const Duration requestTimeout = Duration(seconds: 15);
}
