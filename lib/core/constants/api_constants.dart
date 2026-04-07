class ApiConstants {
  static const String baseUrl = 'https://us-central1-licitaciones-prod.cloudfunctions.net';

  // Proyectos CRUD
  static const String obtenerProyectos    = '$baseUrl/obtenerProyectos';
  static const String crearProyecto       = '$baseUrl/crearProyecto';
  static const String actualizarProyecto  = '$baseUrl/actualizarProyecto';
  static const String eliminarProyecto    = '$baseUrl/eliminarProyecto';

  // Licitaciones / OCDS
  static const String buscarLicitacion    = '$baseUrl/buscarLicitacionPorId';
  static const String buscarOrdenCompra   = '$baseUrl/buscarOrdenCompra';
  static const String convenioMarco       = '$baseUrl/obtenerDetalleConvenioMarco';

  // Cache externo
  static const String obtenerCache        = '$baseUrl/obtenerCacheExterno';
  static const String guardarCache        = '$baseUrl/guardarCacheExterno';

  // Foro
  static const String fetchForo           = '$baseUrl/fetchForoLicitacion';
  static const String generarResumenForo  = '$baseUrl/generarResumenForo';

  // BigQuery / Análisis
  static const String getAnalisisBq             = '$baseUrl/getAnalisisBq';
  static const String queryBigQuery             = '$baseUrl/queryBigQuery';
  static const String competidoresLicitacion    = '$baseUrl/obtenerCompetidoresLicitacion';
  static const String ganadorLicitacion         = '$baseUrl/obtenerGanadorLicitacion';
  static const String historialGanador          = '$baseUrl/obtenerHistorialGanador';
  static const String prediccionOrganismo       = '$baseUrl/obtenerPrediccionOrganismo';
  static const String fichaOrganismo            = '$baseUrl/obtenerFichaOrganismo';
  static const String fichaProveedor            = '$baseUrl/obtenerFichaProveedor';
  static const String radarOportunidades        = '$baseUrl/obtenerRadarOportunidades';
  static const String analizarClientesMeetcard  = '$baseUrl/analizarClientesMeetcard';
  static const String analizarMesesPublicadoOC  = '$baseUrl/analizarMesesPublicadoOC';

  // Configuración
  static const String obtenerConfiguracion  = '$baseUrl/obtenerConfiguracion';
  static const String guardarConfiguracion  = '$baseUrl/guardarConfiguracion';
  static const String obtenerTiposDocumento = '$baseUrl/obtenerTiposDocumento';
  static const String guardarTipoDocumento  = '$baseUrl/guardarTipoDocumento';
  static const String eliminarTipoDocumento = '$baseUrl/eliminarTipoDocumento';
  static const String contarUsoModalidades  = '$baseUrl/contarUsoModalidades';

  // IA / Búsqueda
  static const String buscarLicitacionesAI      = '$baseUrl/buscarLicitacionesAI';
  static const String obtenerInteligencia       = '$baseUrl/obtenerInteligenciaLicitacion';
  static const String obtenerResumen            = '$baseUrl/obtenerResumen';
  static const String calcularEstadisticas      = '$baseUrl/calcularEstadisticas';
  static const String dispararIngestaOCDS       = '$baseUrl/dispararIngestaOCDS';
  static const String obtenerHistorialApi       = '$baseUrl/obtenerHistorialApi';
  static const String obtenerLicitacionesCategoria = '$baseUrl/obtenerLicitacionesPorCategoria';
}
