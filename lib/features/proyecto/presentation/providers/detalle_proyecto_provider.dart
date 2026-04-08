import 'package:flutter/material.dart';
import '../../domain/entities/proyecto_entity.dart';
import '../../domain/repositories/proyecto_repository.dart';
import '../../../../models/configuracion.dart';
import '../../../../services/config_service.dart';
import 'mixins/proyecto_edit_mixin.dart';
import 'mixins/proyecto_analisis_mixin.dart';
import 'mixins/proyecto_foro_mixin.dart';
import 'mixins/proyecto_external_data_mixin.dart';
import 'mixins/proyecto_chain_mixin.dart';
import 'mixins/proyecto_aumentos_mixin.dart';

class DetalleProyectoProvider extends ChangeNotifier
    with ProyectoEditMixin, ProyectoAnalisisMixin, ProyectoForoMixin, ProyectoExternalDataMixin, ProyectoChainMixin, ProyectoAumentosMixin {

  // ── Core state ─────────────────────────────────────────────────────────────
  @override
  final ProyectoRepository repository;

  ProyectoEntity _proyecto;

  @override
  ProyectoEntity get proyecto => _proyecto;

  @override
  set proyectoInternal(ProyectoEntity value) => _proyecto = value;

  String activeTab = 'Detalle';
  bool isLoading = false;

  @override
  String? errorMessage;

  // Cache para detalles de Convenio Marco
  Map<String, dynamic>? convenioMarcoDetalles;

  List<EstadoItem> cfgEstados = [
    EstadoItem(nombre: 'Vigente',       color: '10B981'),
    EstadoItem(nombre: 'X Vencer',      color: 'F59E0B'),
    EstadoItem(nombre: 'En Evaluación', color: '6366F1'),
    EstadoItem(nombre: 'Finalizado',    color: '64748B'),
    EstadoItem(nombre: 'Sin fecha',     color: 'EF4444'),
  ];

  // ── Constructor ────────────────────────────────────────────────────────────
  DetalleProyectoProvider({
    required this.repository,
    required ProyectoEntity proyecto,
    String? initialTabName,
  }) : _proyecto = proyecto {
    if (initialTabName != null) activeTab = initialTabName;
  }

  // ── Init ───────────────────────────────────────────────────────────────────
  bool _disposed = false;

  void init() {
    // Limpiar estado del foro para este nuevo proyecto
    foroEnquiries = [];
    foroResumen = null;
    cargandoForo = false;
    cargandoResumen = false;
    isForoFromLocalFile = false;
    foroQuery = '';
    foroFechaCache = null;
    
    // Limpiar estado de análisis para este nuevo proyecto
    analisisCargando = false;
    analisisError = null;
    competidores = [];
    ganadorOcs = [];
    predicciones = [];
    nombreGanador = null;
    rutGanador = null;
    permanenciaGanador = null;
    rutOrganismo = null;
    historialGanador = [];
    
    cargarAnalisisBq();
    cargarCadena();
    ConfigService.instance.load().then((cfg) {
      if (_disposed) return;
      if (cfg.estados.isNotEmpty) cfgEstados = cfg.estados;
      notifyListeners();
    }).catchError((_) {
      // cfgEstados keeps its default values on failure
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  // ── Navigation ─────────────────────────────────────────────────────────────
  void setActiveTab(String tab) {
    activeTab = tab;
    notifyListeners();
  }

  Future<void> updateEstadoManual(String? newEstado) async {
    await editField('estadoManual', newEstado, 'Estado');
  }

  /// Deletes an aumento from any project in the chain (not necessarily the current one).
  Future<void> deleteAumentoFromChain(String projectId, String aumentoId) async {
    try {
      await repository.deleteAumento(projectId, aumentoId);
      proyectoInternal = await repository.getProyecto(proyecto.id);
      onMutated?.call();
      await cargarCadena();
      notifyListeners();
    } catch (e) {
      errorMessage = e.toString();
      notifyListeners();
    }
  }

  // ── Utilities ──────────────────────────────────────────────────────────────
  String fmt(dynamic value) {
    if (value == null) return '—';
    if (value is num) {
      return value.toStringAsFixed(0).replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
        (m) => '${m[1]}.',
      );
    }
    return value.toString();
  }

  String cleanName(String? name) {
    if (name == null) return '—';
    return name.replaceAll(RegExp(r'^\d+\s*-\s*'), '').trim();
  }

  String fmtDateStr(String? date) {
    if (date == null) return '—';
    try {
      final dt = DateTime.parse(date);
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return date;
    }
  }

  /// Actualiza las fechas de publicación y cierre desde Convenio Marco
  void actualizarFechasConvenioMarco(DateTime? fechaPublicacion, DateTime? fechaCierre) {
    try {
      // Crear nueva instancia con fechas actualizadas
      final newProyecto = ProyectoEntity(
        id: _proyecto.id,
        institucion: _proyecto.institucion,
        productos: _proyecto.productos,
        modalidadCompra: _proyecto.modalidadCompra,
        valorMensual: _proyecto.valorMensual,
        fechaInicio: _proyecto.fechaInicio,
        fechaTermino: _proyecto.fechaTermino,
        idLicitacion: _proyecto.idLicitacion,
        idCotizacion: _proyecto.idCotizacion,
        urlConvenioMarco: _proyecto.urlConvenioMarco,
        idsOrdenesCompra: _proyecto.idsOrdenesCompra,
        documentos: _proyecto.documentos,
        certificados: _proyecto.certificados,
        reclamos: _proyecto.reclamos,
        notas: _proyecto.notas,
        fechaCreacion: _proyecto.fechaCreacion,
        completado: _proyecto.completado,
        estadoManual: _proyecto.estadoManual,
        fechaInicioRuta: _proyecto.fechaInicioRuta,
        fechaTerminoRuta: _proyecto.fechaTerminoRuta,
        fechaPublicacion: fechaPublicacion ?? _proyecto.fechaPublicacion,
        fechaCierre: fechaCierre ?? _proyecto.fechaCierre,
        fechaConsultasInicio: _proyecto.fechaConsultasInicio,
        fechaConsultas: _proyecto.fechaConsultas,
        fechaAdjudicacion: _proyecto.fechaAdjudicacion,
        fechaAdjudicacionFin: _proyecto.fechaAdjudicacionFin,
        montoTotalOC: _proyecto.montoTotalOC,
        proyectoContinuacionIds: _proyecto.proyectoContinuacionIds,
        aumentos: _proyecto.aumentos,
        origenFechas: _proyecto.origenFechas,
        urlFicha: _proyecto.urlFicha,
        hasSugerenciasPendientes: _proyecto.hasSugerenciasPendientes,
        fromSugerencia: _proyecto.fromSugerencia,
      );
      _proyecto = newProyecto;
      notifyListeners();
      debugPrint('[DetalleProyectoProvider] Fechas actualizadas: pub=$fechaPublicacion, cierre=$fechaCierre');
    } catch (e) {
      debugPrint('[DetalleProyectoProvider] Error actualizando fechas: $e');
    }
  }

  /// Guarda los detalles del Convenio Marco en el caché
  void guardarConvenioMarcoDetalles(Map<String, dynamic> detalles) {
    convenioMarcoDetalles = detalles;
    debugPrint('[DetalleProyectoProvider] Detalles Convenio Marco guardados en caché');
  }

  /// Obtiene los detalles del Convenio Marco del caché
  Map<String, dynamic>? obtenerConvenioMarcoDetalles() {
    return convenioMarcoDetalles;
  }
}
