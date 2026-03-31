class ApiConstants {
  static const String baseUrl = 'https://us-central1-licitaciones-prod.cloudfunctions.net';
  
  static const String findLicitacionById = '$baseUrl/buscarLicitacionPorId';
  static const String getExternalCache = '$baseUrl/obtenerCacheExterno';
  static const String saveExternalCache = '$baseUrl/guardarCacheExterno';
  static const String fetchForo = '$baseUrl/fetchForoLicitacion';
  static const String generateForoSummary = '$baseUrl/generarResumenForo';
}
