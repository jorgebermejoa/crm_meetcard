import '../features/proyecto/domain/entities/proyecto_entity.dart';

class AumentoContrato {
  final String id;
  final String tipo; // 'aumento_plazo' | 'aumento_contrato'
  final DateTime fechaTermino;
  final double? valorMensual;
  final List<DocumentoProyecto> documentos;
  final DateTime fechaRegistro;
  final String? descripcion;

  AumentoContrato({
    required this.id,
    required this.tipo,
    required this.fechaTermino,
    this.valorMensual,
    this.documentos = const [],
    required this.fechaRegistro,
    this.descripcion,
  });

  AumentoEntity toEntity() => AumentoEntity(
        id: id,
        tipo: tipo,
        fechaTermino: fechaTermino,
        valorMensual: valorMensual,
        documentos: documentos.map((d) => d.toEntity()).toList(),
        fechaRegistro: fechaRegistro,
        descripcion: descripcion,
      );

  factory AumentoContrato.fromJson(Map<String, dynamic> d) {
    List<DocumentoProyecto> docs;
    if (d['documentos'] is List) {
      docs = (d['documentos'] as List)
          .map((e) => DocumentoProyecto.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } else {
      docs = [];
    }
    return AumentoContrato(
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
        'documentos': documentos.map((d) => d.toJson()).toList(),
        'fechaRegistro': fechaRegistro.toIso8601String(),
        'descripcion': descripcion,
      };
}

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


class CertificadoExperiencia {
  final String id;
  final String descripcion;
  final DateTime? fechaEmision;
  final String? url;

  CertificadoExperiencia({
    required this.id,
    required this.descripcion,
    this.fechaEmision,
    this.url,
  });

  CertificadoEntity toEntity() => CertificadoEntity(
        id: id,
        descripcion: descripcion,
        fechaEmision: fechaEmision,
        url: url,
      );

  factory CertificadoExperiencia.fromJson(Map<String, dynamic> d) =>
      CertificadoExperiencia(
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

class Reclamo {
  final String id;
  final String descripcion;
  final DateTime? fechaReclamo;
  final List<DocumentoProyecto> documentos;
  final String estado; // 'Pendiente', 'Respondido'
  final DateTime? fechaRespuesta;
  final String? descripcionRespuesta;
  final List<DocumentoProyecto> documentosRespuesta;
  final String? urlFicha;

  Reclamo({
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

  ReclamoEntity toEntity() => ReclamoEntity(
        id: id,
        descripcion: descripcion,
        fechaReclamo: fechaReclamo,
        documentos: documentos.map((d) => d.toEntity()).toList(),
        estado: estado,
        fechaRespuesta: fechaRespuesta,
        descripcionRespuesta: descripcionRespuesta,
        documentosRespuesta: documentosRespuesta.map((d) => d.toEntity()).toList(),
        urlFicha: urlFicha,
      );

  factory Reclamo.fromJson(Map<String, dynamic> d) {
    // documentos: nueva lista, o backward-compat con campo url
    List<DocumentoProyecto> docs;
    if (d['documentos'] is List) {
      docs = (d['documentos'] as List)
          .map((e) => DocumentoProyecto.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } else if (d['url'] is String && (d['url'] as String).isNotEmpty) {
      docs = [DocumentoProyecto(tipo: 'Documento', url: d['url'] as String)];
    } else {
      docs = [];
    }
    // documentosRespuesta: nueva lista, o backward-compat con urlRespuesta
    List<DocumentoProyecto> docsResp;
    if (d['documentosRespuesta'] is List) {
      docsResp = (d['documentosRespuesta'] as List)
          .map((e) => DocumentoProyecto.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } else if (d['urlRespuesta'] is String && (d['urlRespuesta'] as String).isNotEmpty) {
      docsResp = [DocumentoProyecto(tipo: 'Documento', url: d['urlRespuesta'] as String)];
    } else {
      docsResp = [];
    }
    return Reclamo(
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
        'documentos': documentos.map((d) => d.toJson()).toList(),
        'estado': estado,
        'fechaRespuesta': fechaRespuesta?.toIso8601String(),
        'descripcionRespuesta': descripcionRespuesta,
        'documentosRespuesta': documentosRespuesta.map((d) => d.toJson()).toList(),
        'urlFicha': urlFicha,
      };
}

class DocumentoProyecto {
  final String tipo;
  final String url;
  final String? nombre;

  DocumentoProyecto({required this.tipo, required this.url, this.nombre});

  DocumentoEntity toEntity() => DocumentoEntity(
        tipo: tipo,
        url: url,
        nombre: nombre,
      );

  factory DocumentoProyecto.fromJson(Map<String, dynamic> d) => DocumentoProyecto(
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

/// Constantes de estado de proyecto — usar estas en lugar de strings literales
/// para evitar errores de tipeo y facilitar refactoring.
class EstadoProyecto {
  static const vigente      = 'Vigente';
  static const xVencer      = 'X Vencer';
  static const finalizado   = 'Finalizado';
  static const sinFecha     = 'Sin fecha';
  static const enEvaluacion = 'En Evaluación';
}

class Proyecto {
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
  final List<DocumentoProyecto> documentos;
  final List<CertificadoExperiencia> certificados;
  final List<Reclamo> reclamos;
  final String? notas;
  final DateTime? fechaCreacion;
  final bool completado;
  final String? estadoManual;
  final DateTime? fechaInicioRuta;
  final DateTime? fechaTerminoRuta;
  // Postulación / licitación timeline
  final DateTime? fechaPublicacion;
  final DateTime? fechaCierre;
  final DateTime? fechaConsultasInicio;
  final DateTime? fechaConsultas;       // enquiryPeriod.endDate
  final DateTime? fechaAdjudicacion;    // awardPeriod.startDate
  final DateTime? fechaAdjudicacionFin;
  final double? montoTotalOC; // Suma total OC en CLP (UF ya convertido)
  final List<String> proyectoContinuacionIds; // IDs de proyectos que continúan este contrato
  final List<AumentoContrato> aumentos;
  /// 'ocds' | 'mp' | null (manual)
  final String? origenFechas;
  final String? urlFicha;
  /// true cuando el cron semanal encontró sugerencias de encadenamiento pendientes.
  final bool hasSugerenciasPendientes;
  /// true si este proyecto fue encadenado a través de una sugerencia de IA.
  final bool fromSugerencia;

  /// Backward-compat: primer sucesor (o null si no hay ninguno)
  String? get proyectoContinuacionId =>
      proyectoContinuacionIds.isNotEmpty ? proyectoContinuacionIds.first : null;

  Proyecto({
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

  ProyectoEntity toEntity() => ProyectoEntity(
        id: id,
        institucion: institucion,
        productos: productos,
        modalidadCompra: modalidadCompra,
        valorMensual: valorMensual,
        fechaInicio: fechaInicio,
        fechaTermino: fechaTermino,
        idLicitacion: idLicitacion,
        idCotizacion: idCotizacion,
        urlConvenioMarco: urlConvenioMarco,
        idsOrdenesCompra: idsOrdenesCompra,
        documentos: documentos.map((d) => d.toEntity()).toList(),
        certificados: certificados.map((c) => c.toEntity()).toList(),
        reclamos: reclamos.map((r) => r.toEntity()).toList(),
        notas: notas,
        fechaCreacion: fechaCreacion,
        completado: completado,
        estadoManual: estadoManual,
        fechaInicioRuta: fechaInicioRuta,
        fechaTerminoRuta: fechaTerminoRuta,
        fechaPublicacion: fechaPublicacion,
        fechaCierre: fechaCierre,
        fechaConsultasInicio: fechaConsultasInicio,
        fechaConsultas: fechaConsultas,
        fechaAdjudicacion: fechaAdjudicacion,
        fechaAdjudicacionFin: fechaAdjudicacionFin,
        montoTotalOC: montoTotalOC,
        proyectoContinuacionIds: proyectoContinuacionIds,
        aumentos: aumentos.map((a) => a.toEntity()).toList(),
        origenFechas: origenFechas,
        urlFicha: urlFicha,
        hasSugerenciasPendientes: hasSugerenciasPendientes,
        fromSugerencia: fromSugerencia,
      );

  Proyecto _copyBase({
    double? montoTotalOC,
    List<String>? proyectoContinuacionIds,
  }) => Proyecto(
    id: id, institucion: institucion, productos: productos,
    modalidadCompra: modalidadCompra, valorMensual: valorMensual,
    fechaInicio: fechaInicio, fechaTermino: fechaTermino,
    idLicitacion: idLicitacion, idCotizacion: idCotizacion,
    urlConvenioMarco: urlConvenioMarco, idsOrdenesCompra: idsOrdenesCompra,
    documentos: documentos, certificados: certificados, reclamos: reclamos,
    notas: notas, fechaCreacion: fechaCreacion, completado: completado,
    estadoManual: estadoManual, fechaInicioRuta: fechaInicioRuta,
    fechaTerminoRuta: fechaTerminoRuta, fechaPublicacion: fechaPublicacion,
    fechaCierre: fechaCierre, fechaConsultasInicio: fechaConsultasInicio,
    fechaConsultas: fechaConsultas, fechaAdjudicacion: fechaAdjudicacion,
    fechaAdjudicacionFin: fechaAdjudicacionFin,
    montoTotalOC: montoTotalOC ?? this.montoTotalOC,
    proyectoContinuacionIds: proyectoContinuacionIds ?? this.proyectoContinuacionIds,
    aumentos: aumentos,
    origenFechas: origenFechas,
    urlFicha: urlFicha,
    hasSugerenciasPendientes: hasSugerenciasPendientes,
    fromSugerencia: fromSugerencia,
  );

  Proyecto copyWithMontoTotalOC(double monto) =>
      _copyBase(montoTotalOC: monto);

  /// Backward-compat: reemplaza toda la lista con un solo ID (o vacía si null)
  Proyecto copyWithContinuacion(String? continuacionId) =>
      _copyBase(proyectoContinuacionIds: continuacionId != null ? [continuacionId] : []);

  /// Agrega un sucesor a la lista (sin duplicados)
  Proyecto copyWithAddContinuacion(String id) {
    if (proyectoContinuacionIds.contains(id)) return this;
    return _copyBase(proyectoContinuacionIds: [...proyectoContinuacionIds, id]);
  }

  /// Elimina un sucesor específico de la lista
  Proyecto copyWithRemoveContinuacion(String id) =>
      _copyBase(proyectoContinuacionIds: proyectoContinuacionIds.where((e) => e != id).toList());

  /// Elimina todos los sucesores
  Proyecto copyWithClearContinuaciones() =>
      _copyBase(proyectoContinuacionIds: []);

  // Backward compat: first OC in list
  String? get idOrdenCompra =>
      idsOrdenesCompra.isNotEmpty ? idsOrdenesCompra.first : null;

  /// Computes estado relative to [now]. Prefer this method in tight loops
  /// (sorting/filtering) to avoid calling DateTime.now() on every comparison.
  String estadoAt(DateTime now) {
    if (estadoManual != null && estadoManual!.isNotEmpty) return estadoManual!;
    if (fechaTermino == null) return EstadoProyecto.sinFecha;
    if (fechaTermino!.isBefore(now)) return EstadoProyecto.finalizado;
    if (fechaTermino!.isBefore(now.add(const Duration(days: 30)))) return EstadoProyecto.xVencer;
    return EstadoProyecto.vigente;
  }

  /// Convenience getter — calls [estadoAt] with DateTime.now().
  /// Use [estadoAt] directly when computing estado for many projects in a loop.
  String get estado => estadoAt(DateTime.now());

  factory Proyecto.fromJson(Map<String, dynamic> d) {
    // Support both new list field and legacy single field for OCs
    List<String> ids;
    if (d['idsOrdenesCompra'] is List) {
      ids = List<String>.from(d['idsOrdenesCompra']);
    } else if (d['idOrdenCompra'] is String &&
        (d['idOrdenCompra'] as String).isNotEmpty) {
      ids = [d['idOrdenCompra'] as String];
    } else {
      ids = [];
    }

    // Support new documentos list and backward compat with legacy documentoUrl
    List<DocumentoProyecto> docs;
    if (d['documentos'] is List) {
      docs = (d['documentos'] as List)
          .map((e) => DocumentoProyecto.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } else if (d['documentoUrl'] is String && (d['documentoUrl'] as String).isNotEmpty) {
      docs = [DocumentoProyecto(tipo: 'Documento', url: d['documentoUrl'] as String)];
    } else {
      docs = [];
    }

    return Proyecto(
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
      certificados: d['certificados'] is List
          ? (d['certificados'] as List)
              .map((e) => CertificadoExperiencia.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : [],
      reclamos: d['reclamos'] is List
          ? (d['reclamos'] as List)
              .map((e) => Reclamo.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : [],
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
      aumentos: d['aumentos'] is List
          ? (d['aumentos'] as List)
              .map((e) => AumentoContrato.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : [],
      proyectoContinuacionIds: () {
        if (d['proyectoContinuacionIds'] is List) {
          return List<String>.from(
              (d['proyectoContinuacionIds'] as List).where((e) => e != null && e.toString().isNotEmpty));
        }
        final single = d['proyectoContinuacionId']?.toString();
        return single != null && single.isNotEmpty ? [single] : <String>[];
      }(),
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
        'documentos': documentos.map((e) => e.toJson()).toList(),
        'certificados': certificados.map((e) => e.toJson()).toList(),
        'reclamos': reclamos.map((e) => e.toJson()).toList(),
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
        'aumentos': aumentos.map((a) => a.toJson()).toList(),
        'origenFechas': origenFechas,
        'urlFicha': urlFicha,
      };
}
