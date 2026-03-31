/// Pure entities for the Project domain.
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
  });

  // Business logic (derived properties)
  bool get isExpired {
    if (fechaTermino == null) return false;
    return fechaTermino!.isBefore(DateTime.now());
  }

  String get calculatedStatus {
    if (estadoManual != null && estadoManual!.isNotEmpty) return estadoManual!;
    if (fechaTermino == null) return 'Sin fecha';
    final now = DateTime.now();
    if (fechaTermino!.isBefore(now)) return 'Finalizado';
    if (fechaTermino!.isBefore(now.add(const Duration(days: 30)))) return 'X Vencer';
    return 'Vigente';
  }
}
