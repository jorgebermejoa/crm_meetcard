/// Strips "|" suffix and "Unidad de compra:" prefix from institution name.
String cleanInst(String raw) {
  var s = raw.split('|').first.trim();
  if (s.toLowerCase().startsWith('unidad de compra:')) {
    s = s.substring('unidad de compra:'.length).trim();
  }
  return s;
}

/// Extracts the contract ID to use in URLs from a ProyectoEntity.
/// Priority: idLicitacion → idCotizacion (stripped of "CM: ") → CM from urlConvenioMarco → firestoreId
String contractIdForUrl(String firestoreId, {String? idLicitacion, String? idCotizacion, String? urlConvenioMarco}) {
  if (idLicitacion != null && idLicitacion.isNotEmpty) return idLicitacion;
  if (idCotizacion != null && idCotizacion.isNotEmpty) {
    final clean = idCotizacion.startsWith('CM: ') ? idCotizacion.substring(4) : idCotizacion;
    if (clean.isNotEmpty) return clean;
  }
  if (urlConvenioMarco != null && urlConvenioMarco.isNotEmpty) {
    final match = RegExp(r'/id/([^/\?#]+)').firstMatch(urlConvenioMarco);
    final seg = match?.group(1);
    if (seg != null && seg.isNotEmpty) return seg;
  }
  return firestoreId;
}

/// Converts a modalidad string to a URL-safe slug.
/// e.g. "Licitación Pública" → "licitacion_publica"
String modalidadSlug(String modalidad) {
  var s = modalidad.toLowerCase();
  // Remove accents
  const from = 'áéíóúüñ';
  const to   = 'aeiouun';
  for (var i = 0; i < from.length; i++) {
    s = s.replaceAll(from[i], to[i]);
  }
  // Replace spaces and special chars with underscore
  s = s.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  // Trim leading/trailing underscores
  s = s.replaceAll(RegExp(r'^_+|_+$'), '');
  return s.isEmpty ? 'sin_modalidad' : s;
}
