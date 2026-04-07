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
}
