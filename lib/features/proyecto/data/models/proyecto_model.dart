import '../../domain/entities/proyecto_entity.dart';

/// Models for the Project domain, adding JSON serialization logic.

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
        fechaEmision: d['fechaEmision'] != null
            ? DateTime.tryParse(d['fechaEmision'])
            : null,
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
      fechaReclamo: d['fechaReclamo'] != null ? DateTime.tryParse(d['fechaReclamo']) : null,
      documentos: docs,
      estado: d['estado']?.toString() ?? 'Pendiente',
      fechaRespuesta: d['fechaRespuesta'] != null ? DateTime.tryParse(d['fechaRespuesta']) : null,
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

    return ProyectoModel(
      id: d['id']?.toString() ?? '',
      institucion: d['institucion'] ?? '',
      productos: d['productos'] ?? '',
      modalidadCompra: d['modalidadCompra'] ?? '',
      valorMensual: (d['valorMensual'] as num?)?.toDouble(),
      fechaInicio: d['fechaInicio'] != null ? DateTime.tryParse(d['fechaInicio']) : null,
      fechaTermino: d['fechaTermino'] != null ? DateTime.tryParse(d['fechaTermino']) : null,
      idLicitacion: d['idLicitacion'],
      idCotizacion: d['idCotizacion'],
      urlConvenioMarco: d['urlConvenioMarco'],
      idsOrdenesCompra: ids,
      documentos: docs,
      certificados: certs,
      reclamos: reclamos,
      notas: d['notas'],
      fechaCreacion: d['fechaCreacion'] != null ? DateTime.tryParse(d['fechaCreacion']) : null,
      completado: d['completado'] ?? false,
      estadoManual: d['estadoManual'],
      fechaInicioRuta: d['fechaInicioRuta'] != null ? DateTime.tryParse(d['fechaInicioRuta']) : null,
      fechaTerminoRuta: d['fechaTerminoRuta'] != null ? DateTime.tryParse(d['fechaTerminoRuta']) : null,
      fechaPublicacion: d['fechaPublicacion'] != null ? DateTime.tryParse(d['fechaPublicacion']) : null,
      fechaCierre: d['fechaCierre'] != null ? DateTime.tryParse(d['fechaCierre']) : null,
      fechaConsultasInicio: d['fechaConsultasInicio'] != null ? DateTime.tryParse(d['fechaConsultasInicio']) : null,
      fechaConsultas: d['fechaConsultas'] != null ? DateTime.tryParse(d['fechaConsultas']) : null,
      fechaAdjudicacion: d['fechaAdjudicacion'] != null ? DateTime.tryParse(d['fechaAdjudicacion']) : null,
      fechaAdjudicacionFin: d['fechaAdjudicacionFin'] != null ? DateTime.tryParse(d['fechaAdjudicacionFin']) : null,
      montoTotalOC: (d['montoTotalOC'] as num?)?.toDouble(),
      proyectoContinuacionIds: d['proyectoContinuacionIds'] is List ? List<String>.from(d['proyectoContinuacionIds']) : [],
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
      };
}
