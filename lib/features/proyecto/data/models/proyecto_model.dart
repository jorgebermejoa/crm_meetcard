import '../../domain/entities/proyecto_entity.dart';

DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  try {
    return (value as dynamic).toDate();
  } catch (_) {
    try {
      return DateTime.parse(value.toString());
    } catch (_) {}
  }
  return null;
}


/// Models for the Project domain, adding JSON serialization logic.

class AumentoModel extends AumentoEntity {
  AumentoModel({
    required super.id,
    required super.tipo,
    required super.fechaTermino,
    super.valorMensual,
    super.documentos = const [],
    required super.fechaRegistro,
    super.descripcion,
  });

  factory AumentoModel.fromJson(Map<String, dynamic> d) {
    List<DocumentoModel> docs = d['documentos'] is List
        ? (d['documentos'] as List)
            .map((e) => DocumentoModel.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : [];
    return AumentoModel(
      id: d['id']?.toString() ?? '',
      tipo: d['tipo']?.toString() ?? 'aumento_plazo',
      fechaTermino: _parseDate(d['fechaTermino']) ?? DateTime.now(),
      valorMensual: (d['valorMensual'] as num?)?.toDouble(),
      documentos: docs,
      fechaRegistro: _parseDate(d['fechaRegistro']) ?? DateTime.now(),
      descripcion: d['descripcion']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'tipo': tipo,
        'fechaTermino': fechaTermino.toIso8601String(),
        'valorMensual': valorMensual,
        'documentos': documentos.map((d) => (d as DocumentoModel).toJson()).toList(),
        'fechaRegistro': fechaRegistro.toIso8601String(),
        'descripcion': descripcion,
      };
}

class CertificadoModel extends CertificadoEntity {
  CertificadoModel({
    required super.id,
    required super.descripcion,
    super.fechaEmision,
    super.url,
  });

  factory CertificadoModel.fromJson(Map<String, dynamic> d) =>
      CertificadoModel(
        id: d['id']?.toString() ?? '',
        descripcion: d['descripcion']?.toString() ?? '',
        fechaEmision: _parseDate(d['fechaEmision']),
        url: d['url']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'descripcion': descripcion,
        'fechaEmision': fechaEmision?.toIso8601String(),
        'url': url,
      };
}

class DocumentoModel extends DocumentoEntity {
  DocumentoModel({
    required super.tipo,
    required super.url,
    super.nombre,
  });

  factory DocumentoModel.fromJson(Map<String, dynamic> d) => DocumentoModel(
        tipo: d['tipo'] as String? ?? '',
        url: d['url'] as String? ?? '',
        nombre: d['nombre'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'tipo': tipo,
        'url': url,
        if (nombre != null) 'nombre': nombre,
      };
}

class ReclamoModel extends ReclamoEntity {
  ReclamoModel({
    required super.id,
    required super.descripcion,
    super.fechaReclamo,
    super.documentos = const [],
    super.estado = 'Pendiente',
    super.fechaRespuesta,
    super.descripcionRespuesta,
    super.documentosRespuesta = const [],
    super.urlFicha,
  });

  factory ReclamoModel.fromJson(Map<String, dynamic> d) {
    List<DocumentoModel> docs;
    if (d['documentos'] is List) {
      docs = (d['documentos'] as List)
          .map((e) => DocumentoModel.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } else {
      docs = [];
    }
    
    List<DocumentoModel> docsResp;
    if (d['documentosRespuesta'] is List) {
      docsResp = (d['documentosRespuesta'] as List)
          .map((e) => DocumentoModel.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } else {
      docsResp = [];
    }
    
    return ReclamoModel(
      id: d['id']?.toString() ?? '',
      descripcion: d['descripcion']?.toString() ?? '',
      fechaReclamo: _parseDate(d['fechaReclamo']),
      documentos: docs,
      estado: d['estado']?.toString() ?? 'Pendiente',
      fechaRespuesta: _parseDate(d['fechaRespuesta']),
      descripcionRespuesta: d['descripcionRespuesta']?.toString(),
      documentosRespuesta: docsResp,
      urlFicha: d['urlFicha']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'descripcion': descripcion,
        'fechaReclamo': fechaReclamo?.toIso8601String(),
        'documentos': documentos.map((d) => (d as DocumentoModel).toJson()).toList(),
        'estado': estado,
        'fechaRespuesta': fechaRespuesta?.toIso8601String(),
        'descripcionRespuesta': descripcionRespuesta,
        'documentosRespuesta': documentosRespuesta.map((d) => (d as DocumentoModel).toJson()).toList(),
        'urlFicha': urlFicha,
      };
}

class ProyectoModel extends ProyectoEntity {
  ProyectoModel({
    required super.id,
    required super.institucion,
    required super.productos,
    required super.modalidadCompra,
    super.valorMensual,
    super.fechaInicio,
    super.fechaTermino,
    super.idLicitacion,
    super.idCotizacion,
    super.urlConvenioMarco,
    super.idsOrdenesCompra = const [],
    super.documentos = const [],
    super.certificados = const [],
    super.reclamos = const [],
    super.notas,
    super.fechaCreacion,
    super.completado = false,
    super.estadoManual,
    super.fechaInicioRuta,
    super.fechaTerminoRuta,
    super.fechaPublicacion,
    super.fechaCierre,
    super.fechaConsultasInicio,
    super.fechaConsultas,
    super.fechaAdjudicacion,
    super.fechaAdjudicacionFin,
    super.montoTotalOC,
    super.proyectoContinuacionIds = const [],
    super.aumentos = const [],
    super.origenFechas,
    super.urlFicha,
    super.hasSugerenciasPendientes = false,
    super.fromSugerencia = false,
  });

  factory ProyectoModel.fromJson(Map<String, dynamic> d) {
    List<String> ids = d['idsOrdenesCompra'] is List ? List<String>.from(d['idsOrdenesCompra']) : [];

    List<DocumentoModel> docs = d['documentos'] is List
        ? (d['documentos'] as List).map((e) => DocumentoModel.fromJson(Map<String, dynamic>.from(e))).toList()
        : [];

    List<CertificadoModel> certs = d['certificados'] is List
        ? (d['certificados'] as List).map((e) => CertificadoModel.fromJson(Map<String, dynamic>.from(e))).toList()
        : [];

    List<ReclamoModel> reclamos = d['reclamos'] is List
        ? (d['reclamos'] as List).map((e) => ReclamoModel.fromJson(Map<String, dynamic>.from(e))).toList()
        : [];

    List<AumentoModel> aumentos = d['aumentos'] is List
        ? (d['aumentos'] as List).map((e) => AumentoModel.fromJson(Map<String, dynamic>.from(e))).toList()
        : [];

    return ProyectoModel(
      id: d['id']?.toString() ?? '',
      institucion: d['institucion'] ?? '',
      productos: d['productos'] ?? '',
      modalidadCompra: d['modalidadCompra'] ?? '',
      valorMensual: (d['valorMensual'] as num?)?.toDouble(),
      fechaInicio: _parseDate(d['fechaInicio']),
      fechaTermino: _parseDate(d['fechaTermino']),
      idLicitacion: d['idLicitacion'],
      idCotizacion: d['idCotizacion'],
      urlConvenioMarco: d['urlConvenioMarco'],
      idsOrdenesCompra: ids,
      documentos: docs,
      certificados: certs,
      reclamos: reclamos,
      notas: d['notas'],
      fechaCreacion: _parseDate(d['fechaCreacion']),
      completado: d['completado'] ?? false,
      estadoManual: d['estadoManual'],
      fechaInicioRuta: _parseDate(d['fechaInicioRuta']),
      fechaTerminoRuta: _parseDate(d['fechaTerminoRuta']),
      fechaPublicacion: _parseDate(d['fechaPublicacion']),
      fechaCierre: _parseDate(d['fechaCierre']),
      fechaConsultasInicio: _parseDate(d['fechaConsultasInicio']),
      fechaConsultas: _parseDate(d['fechaConsultas']),
      fechaAdjudicacion: _parseDate(d['fechaAdjudicacion']),
      fechaAdjudicacionFin: _parseDate(d['fechaAdjudicacionFin']),
      montoTotalOC: (d['montoTotalOC'] as num?)?.toDouble(),
      proyectoContinuacionIds: d['proyectoContinuacionIds'] is List ? List<String>.from(d['proyectoContinuacionIds']) : [],
      aumentos: aumentos,
      origenFechas: d['origenFechas']?.toString(),
      urlFicha: d['urlFicha']?.toString(),
      hasSugerenciasPendientes: d['hasSugerenciasPendientes'] == true,
      fromSugerencia: d['fromSugerencia'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'institucion': institucion,
        'productos': productos,
        'modalidadCompra': modalidadCompra,
        'valorMensual': valorMensual,
        'fechaInicio': fechaInicio?.toIso8601String(),
        'fechaTermino': fechaTermino?.toIso8601String(),
        'idLicitacion': idLicitacion,
        'idCotizacion': idCotizacion,
        'urlConvenioMarco': urlConvenioMarco,
        'idsOrdenesCompra': idsOrdenesCompra,
        'documentos': documentos.map((e) => (e as DocumentoModel).toJson()).toList(),
        'certificados': certificados.map((e) => (e as CertificadoModel).toJson()).toList(),
        'reclamos': reclamos.map((e) => (e as ReclamoModel).toJson()).toList(),
        'notas': notas,
        'fechaCreacion': fechaCreacion?.toIso8601String(),
        'completado': completado,
        'estadoManual': estadoManual,
        'fechaInicioRuta': fechaInicioRuta?.toIso8601String(),
        'fechaTerminoRuta': fechaTerminoRuta?.toIso8601String(),
        'fechaPublicacion': fechaPublicacion?.toIso8601String(),
        'fechaCierre': fechaCierre?.toIso8601String(),
        'fechaConsultasInicio': fechaConsultasInicio?.toIso8601String(),
        'fechaConsultas': fechaConsultas?.toIso8601String(),
        'fechaAdjudicacion': fechaAdjudicacion?.toIso8601String(),
        'fechaAdjudicacionFin': fechaAdjudicacionFin?.toIso8601String(),
        'montoTotalOC': montoTotalOC,
        'proyectoContinuacionIds': proyectoContinuacionIds,
        'aumentos': aumentos.map((a) => (a as AumentoModel).toJson()).toList(),
        'origenFechas': origenFechas,
        'urlFicha': urlFicha,
      };
}
