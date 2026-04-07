/// Pure entities for the Project domain.

class AumentoEntity {
  final String id;
  /// 'aumento_plazo' = solo extiende plazo
  /// 'aumento_contrato' = extiende plazo Y cambia monto
  final String tipo;
  final DateTime fechaTermino;
  final double? valorMensual; // null → mantiene el valor original
  final List<DocumentoEntity> documentos;
  final DateTime fechaRegistro;
  final String? descripcion;

  AumentoEntity({
    required this.id,
    required this.tipo,
    required this.fechaTermino,
    this.valorMensual,
    this.documentos = const [],
    required this.fechaRegistro,
    this.descripcion,
  });

  String get badgeLabel => tipo == 'aumento_contrato' ? 'Aumento de Contrato' : 'Aumento de Plazo';
}

class CertificadoEntity {
  final String id;
  final String descripcion;
  final DateTime? fechaEmision;
  final String? url;

  CertificadoEntity({
    required this.id,
    required this.descripcion,
    this.fechaEmision,
    this.url,
  });
}

class DocumentoEntity {
  final String tipo;
  final String url;
  final String? nombre;

  DocumentoEntity({
    required this.tipo,
    required this.url,
    this.nombre,
  });
}

class ReclamoEntity {
  final String id;
  final String descripcion;
  final DateTime? fechaReclamo;
  final List<DocumentoEntity> documentos;
  final String estado;
  final DateTime? fechaRespuesta;
  final String? descripcionRespuesta;
  final List<DocumentoEntity> documentosRespuesta;
  final String? urlFicha;

  ReclamoEntity({
    required this.id,
    required this.descripcion,
    this.fechaReclamo,
    this.documentos = const [],
    this.estado = 'Pendiente',
    this.fechaRespuesta,
    this.descripcionRespuesta,
    this.documentosRespuesta = const [],
    this.urlFicha,
  });
}

class ProyectoEntity {
  final String id;
  final String institucion;
  final String productos;
  final String modalidadCompra;
  final double? valorMensual;
  final DateTime? fechaInicio;
  final DateTime? fechaTermino;
  final String? idLicitacion;
  final String? idCotizacion;
  final String? urlConvenioMarco;
  final List<String> idsOrdenesCompra;
  final List<DocumentoEntity> documentos;
  final List<CertificadoEntity> certificados;
  final List<ReclamoEntity> reclamos;
  final String? notas;
  final DateTime? fechaCreacion;
  final bool completado;
  final String? estadoManual;
  final DateTime? fechaInicioRuta;
  final DateTime? fechaTerminoRuta;
  final DateTime? fechaPublicacion;
  final DateTime? fechaCierre;
  final DateTime? fechaConsultasInicio;
  final DateTime? fechaConsultas;
  final DateTime? fechaAdjudicacion;
  final DateTime? fechaAdjudicacionFin;
  final double? montoTotalOC;
  final List<String> proyectoContinuacionIds;
  final List<AumentoEntity> aumentos;
  /// 'ocds' | 'mp' | null (manual)
  final String? origenFechas;
  final String? urlFicha;
  final bool hasSugerenciasPendientes;
  /// true si este proyecto fue encadenado a través de una sugerencia de IA.
  final bool fromSugerencia;

  ProyectoEntity({
    required this.id,
    required this.institucion,
    required this.productos,
    required this.modalidadCompra,
    this.valorMensual,
    this.fechaInicio,
    this.fechaTermino,
    this.idLicitacion,
    this.idCotizacion,
    this.urlConvenioMarco,
    this.idsOrdenesCompra = const [],
    this.documentos = const [],
    this.certificados = const [],
    this.reclamos = const [],
    this.notas,
    this.fechaCreacion,
    this.completado = false,
    this.estadoManual,
    this.fechaInicioRuta,
    this.fechaTerminoRuta,
    this.fechaPublicacion,
    this.fechaCierre,
    this.fechaConsultasInicio,
    this.fechaConsultas,
    this.fechaAdjudicacion,
    this.fechaAdjudicacionFin,
    this.montoTotalOC,
    this.proyectoContinuacionIds = const [],
    this.aumentos = const [],
    this.origenFechas,
    this.urlFicha,
    this.hasSugerenciasPendientes = false,
    this.fromSugerencia = false,
  });

  // Business logic (derived properties)

  /// Fecha de término real, considerando el último aumento si existe.
  DateTime? get fechaTerminoEfectiva {
    if (aumentos.isEmpty) return fechaTermino;
    final sortedEnds = aumentos.map((a) => a.fechaTermino).toList()
      ..sort((a, b) => a.compareTo(b));
    final latest = sortedEnds.last;
    if (fechaTermino == null) return latest;
    return latest.isAfter(fechaTermino!) ? latest : fechaTermino;
  }

  /// Valor mensual vigente: último aumento que lo modifica, o el original.
  double? get valorMensualEfectivo {
    if (aumentos.isEmpty) return valorMensual;
    final sorted = [...aumentos]
      ..sort((a, b) => a.fechaTermino.compareTo(b.fechaTermino));
    for (final a in sorted.reversed) {
      if (a.valorMensual != null) return a.valorMensual;
    }
    return valorMensual;
  }

  bool get isExpired {
    final termino = fechaTerminoEfectiva;
    if (termino == null) return false;
    return termino.isBefore(DateTime.now());
  }

  String get calculatedStatus {
    if (estadoManual != null && estadoManual!.isNotEmpty) return estadoManual!;
    final termino = fechaTerminoEfectiva;
    if (termino == null) return 'Sin fecha';
    final now = DateTime.now();
    if (termino.isBefore(now)) return 'Finalizado';
    if (termino.isBefore(now.add(const Duration(days: 30)))) return 'X Vencer';
    return 'Vigente';
  }
}
