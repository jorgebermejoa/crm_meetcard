import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/utils/chain_utils.dart';
import '../../../../core/utils/string_utils.dart';
import '../../../../models/configuracion.dart';
import '../../../../models/proyecto.dart';
import '../../data/proyectos_constants.dart';
import '../../domain/entities/doc_item.dart';
import '../../domain/repositories/proyectos_repository.dart';

class ProyectosProvider extends ChangeNotifier {
  final ProyectosRepository _proyectosRepository;

  ProyectosProvider({required ProyectosRepository proyectosRepository})
      : _proyectosRepository = proyectosRepository;

  // STATE
  List<Proyecto> _proyectos = [];
  bool _cargando = true;
  bool _fetching = false; // true mientras hay un Future.wait activo
  String? _error;
  ConfiguracionData _config = ConfiguracionData.defaults();
  List<Map<String, dynamic>> _radarOportunidades = [];
  bool _radarCargando = false;
  String? _radarError;

  // Gantt state
  String _ganttMode = 'postulacion';
  final Set<String> _ganttExpandedRows = {};
  DateTime? _ganttWindowStart;
  DateTime? _ganttWindowEnd;

  // Filters — Proyectos tab
  String? _filterInstitucion;
  Set<String> _filterProductos = {};
  String? _filterModalidad;
  String? _filterEstado;
  String? _filterReclamo;
  String? _filterVencer;
  int? _filterQuarterYear;
  int? _filterQuarterQ;
  bool _filterQuarterOnlyWithOC = false;
  bool _filterQuarterIsChurn = false;
  bool _filterQuarterOnlyIngresos = false;
  bool? _filterEncadenado;
  bool _filterSugerencia = false;

  // Pagination — Proyectos tab
  int _currentPage = 0;

  // Filters — Documentación tab
  String? _docFilterInstitucion;
  Set<String> _docFilterProductos = {};
  String? _docFilterModalidad;
  String? _docFilterEstado;
  Set<String> _docFilterTipos = {};
  int _docCurrentPage = 0;
  bool _docSortAscending = false;

  // Sorting
  int? _sortColumn;
  bool _sortAscending = true;
  bool _estadoSortAsc = true;

  // GETTERS
  bool get cargando => _cargando;
  String? get error => _error;
  List<Proyecto> get proyectos => _proyectos;
  ConfiguracionData get config => _config;
  List<Map<String, dynamic>> get radarOportunidades => _radarOportunidades;
  bool get radarCargando => _radarCargando;
  String? get radarError => _radarError;

  // Gantt getters
  String get ganttMode => _ganttMode;
  Set<String> get ganttExpandedRows => _ganttExpandedRows;
  DateTime? get ganttWindowStart => _ganttWindowStart;
  DateTime? get ganttWindowEnd => _ganttWindowEnd;

  // Filter getters
  String? get filterInstitucion => _filterInstitucion;
  Set<String> get filterProductos => _filterProductos;
  String? get filterModalidad => _filterModalidad;
  String? get filterEstado => _filterEstado;
  String? get filterReclamo => _filterReclamo;
  String? get filterVencer => _filterVencer;
  bool? get filterEncadenado => _filterEncadenado;
  bool get filterSugerencia => _filterSugerencia;
  int? get filterQuarterYear => _filterQuarterYear;
  int? get filterQuarterQ => _filterQuarterQ;
  bool get filterQuarterIsChurn => _filterQuarterIsChurn;

  // Pagination getters
  int get currentPage => _currentPage;
  int get pageSize => kPageSize;

  // Doc filter getters
  String? get docFilterInstitucion => _docFilterInstitucion;
  Set<String> get docFilterProductos => _docFilterProductos;
  String? get docFilterModalidad => _docFilterModalidad;
  String? get docFilterEstado => _docFilterEstado;
  Set<String> get docFilterTipos => _docFilterTipos;
  int get docCurrentPage => _docCurrentPage;
  bool get docSortAscending => _docSortAscending;

  // Sorting getters
  int? get sortColumn => _sortColumn;
  bool get sortAscending => _sortAscending;
  bool get estadoSortAsc => _estadoSortAsc;

  // DERIVED STATE
  List<Proyecto> get filteredProyectos => _applyFilters(_proyectos);

  List<Proyecto> get pageItems {
    final sorted = _applySorting(filteredProyectos);
    final pageStart = _currentPage * kPageSize;
    final pageEnd = (pageStart + kPageSize).clamp(0, sorted.length);
    return sorted.isEmpty ? <Proyecto>[] : sorted.sublist(pageStart, pageEnd);
  }

  int get totalPages => (filteredProyectos.length / kPageSize).ceil();

  List<DocItem> get docItems => _buildDocItems(_proyectos);

  List<DocItem> get _filteredDocItems => _applyDocFilters(docItems);

  List<DocItem> get docPageItems {
    final sorted = _filteredDocItems
      ..sort((a, b) {
        final da = a.fecha ?? DateTime(0);
        final db = b.fecha ?? DateTime(0);
        return _docSortAscending ? da.compareTo(db) : db.compareTo(da);
      });
    final pageStart = _docCurrentPage * kPageSize;
    final pageEnd = (pageStart + kPageSize).clamp(0, sorted.length);
    return sorted.isEmpty ? <DocItem>[] : sorted.sublist(pageStart, pageEnd);
  }

  int get docTotalPages => (_filteredDocItems.length / kPageSize).ceil();

  bool get hasActiveFilters =>
      _filterInstitucion != null ||
      _filterProductos.isNotEmpty ||
      _filterModalidad != null ||
      _filterEstado != null ||
      _filterReclamo != null ||
      _filterVencer != null ||
      _filterEncadenado != null ||
      _filterQuarterYear != null ||
      _filterSugerencia;

  /// Count of individual active filters (for badge display).
  int get activeFilterCount =>
      [
        _filterInstitucion,
        _filterModalidad,
        _filterEstado,
        _filterReclamo,
        _filterVencer,
      ].where((v) => v != null).length +
      (_filterProductos.isNotEmpty ? 1 : 0) +
      (_filterQuarterYear != null ? 1 : 0) +
      (_filterEncadenado != null ? 1 : 0) +
      (_filterSugerencia ? 1 : 0);

  bool get hasActiveDocFilters =>
      _docFilterInstitucion != null ||
      _docFilterProductos.isNotEmpty ||
      _docFilterModalidad != null ||
      _docFilterEstado != null ||
      _docFilterTipos.isNotEmpty;

  // PUBLIC METHODS (ACTIONS)

  Future<void> cargar({bool forceRefresh = false}) async {
    if (_fetching && !forceRefresh) return;
    _fetching = true;
    _cargando = true;
    _error = null;
    notifyListeners();

    try {
      // Carga requerida: proyectos. Si falla, propagamos el error.
      _proyectos = await _proyectosRepository.loadProyectos(forceRefresh: forceRefresh);

      // Carga opcional: configuración. Si falla, usamos los valores por defecto.
      try {
        _config = await _proyectosRepository.loadConfig();
      } catch (e) {
        _config = ConfiguracionData.defaults();
        debugPrint('Config load failed, using defaults: $e');
      }

      _cargando = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _cargando = false;
      notifyListeners();
    } finally {
      _fetching = false;
    }
  }

  Future<void> cargarRadar({bool forceRefresh = false}) async {
    if (_radarCargando) return;
    _radarCargando = true;
    _radarError = null;
    notifyListeners();

    try {
      _radarOportunidades =
          await _proyectosRepository.loadRadarOportunidades(forceRefresh: forceRefresh);
    } catch (e) {
      _radarError = e.toString();
    } finally {
      _radarCargando = false;
      notifyListeners();
    }
  }

  Future<void> sincronizarPostulacionDesdeOcds() async {
    await _proyectosRepository.sincronizarPostulacionDesdeOcds(_proyectos);
    await cargar(forceRefresh: true);
  }

  Future<void> updateProyectoEstadoManual(String projectId, String? estadoManual) async {
    await _proyectosRepository.updateProyectoEstadoManual(projectId, estadoManual);
    await cargar(forceRefresh: true);
  }

  void clearFilters() {
    _filterInstitucion = null;
    _filterProductos = {};
    _filterModalidad = null;
    _filterEstado = null;
    _filterReclamo = null;
    _filterVencer = null;
    _filterEncadenado = null;
    _filterSugerencia = false;
    _filterQuarterYear = null;
    _filterQuarterQ = null;
    _filterQuarterOnlyWithOC = false;
    _filterQuarterIsChurn = false;
    _filterQuarterOnlyIngresos = false;
    _currentPage = 0;
    notifyListeners();
  }

  void clearDocFilters() {
    _docFilterInstitucion = null;
    _docFilterProductos = {};
    _docFilterModalidad = null;
    _docFilterEstado = null;
    _docFilterTipos = {};
    _docCurrentPage = 0;
    notifyListeners();
  }

  void setSort(int col) {
    if (_sortColumn == col) {
      _sortAscending = !_sortAscending;
    } else {
      _sortColumn = col;
      _sortAscending = true;
    }
    _currentPage = 0;
    notifyListeners();
  }

  void setEstadoSort(bool asc) {
    _estadoSortAsc = asc;
    _sortColumn = null;
    notifyListeners();
  }

  void setPage(int page) {
    _currentPage = page;
    notifyListeners();
  }

  void setDocPage(int page) {
    _docCurrentPage = page;
    notifyListeners();
  }

  void setDocSort(bool asc) {
    _docSortAscending = asc;
    notifyListeners();
  }

  void setGanttMode(String mode) {
    _ganttMode = mode;
    _ganttWindowStart = null;
    _ganttWindowEnd = null;
    _ganttExpandedRows.clear();
    if (mode == 'postulacion') {
      sincronizarPostulacionDesdeOcds();
    }
    notifyListeners();
  }

  void toggleGanttRow(String id) {
    if (_ganttExpandedRows.contains(id)) {
      _ganttExpandedRows.remove(id);
    } else {
      _ganttExpandedRows.add(id);
    }
    notifyListeners();
  }

  void setGanttWindow(DateTime start, DateTime end) {
    _ganttWindowStart = start;
    _ganttWindowEnd = end;
    notifyListeners();
  }

  void resetGanttWindow() {
    _ganttWindowStart = null;
    _ganttWindowEnd = null;
    notifyListeners();
  }

  void setFilter({
    String? institucion,
    Set<String>? productos,
    String? modalidad,
    String? estado,
    String? reclamo,
    String? vencer,
    bool? encadenado,
    bool? sugerencia,
  }) {
    bool changed = false;
    if (institucion != _filterInstitucion) { _filterInstitucion = institucion; changed = true; }
    if (productos != null && productos != _filterProductos) { _filterProductos = productos; changed = true; }
    if (modalidad != _filterModalidad) { _filterModalidad = modalidad; changed = true; }
    if (estado != _filterEstado) { _filterEstado = estado; changed = true; }
    if (reclamo != _filterReclamo) { _filterReclamo = reclamo; changed = true; }
    if (vencer != _filterVencer) { _filterVencer = vencer; changed = true; }
    if (encadenado != _filterEncadenado) { _filterEncadenado = encadenado; changed = true; }
    if (sugerencia != null && sugerencia != _filterSugerencia) { _filterSugerencia = sugerencia; changed = true; }

    if (changed) {
      _currentPage = 0;
      notifyListeners();
    }
  }

  void setSingleFilter({
    String? institucion,
    Set<String>? productos,
    String? modalidad,
    String? estado,
    String? reclamo,
    String? vencer,
    bool? encadenado,
    bool? sugerencia,
  }) {
    if (institucion != null) _filterInstitucion = institucion;
    if (productos != null) _filterProductos = productos;
    if (modalidad != null) _filterModalidad = modalidad;
    if (estado != null) _filterEstado = estado;
    if (reclamo != null) _filterReclamo = reclamo;
    if (vencer != null) _filterVencer = vencer;
    if (encadenado != null) _filterEncadenado = encadenado;
    if (sugerencia != null) _filterSugerencia = sugerencia;
    _currentPage = 0;
    notifyListeners();
  }

  void setDocFilter({
    String? institucion,
    Set<String>? productos,
    String? modalidad,
    String? estado,
    Set<String>? tipos,
  }) {
    _docFilterInstitucion = institucion ?? _docFilterInstitucion;
    _docFilterProductos = productos ?? _docFilterProductos;
    _docFilterModalidad = modalidad ?? _docFilterModalidad;
    _docFilterEstado = estado ?? _docFilterEstado;
    _docFilterTipos = tipos ?? _docFilterTipos;
    _docCurrentPage = 0;
    notifyListeners();
  }

  void setQuarterFilter(
    int year,
    int quarter, {
    bool onlyWithOC = false,
    bool onlyIngresos = false,
    bool isChurn = false,
  }) {
    _filterQuarterYear = year;
    _filterQuarterQ = quarter;
    _filterQuarterOnlyWithOC = onlyWithOC;
    _filterQuarterIsChurn = isChurn;
    _filterQuarterOnlyIngresos = onlyIngresos;
    _currentPage = 0;
    notifyListeners();
  }

  // PRIVATE HELPERS

  List<Proyecto> _applySorting(List<Proyecto> list) {
    final sorted = [...list];
    if (_sortColumn == null) {
      if (_filterEncadenado == true) {
        sorted.sort((a, b) {
          final da = a.fechaInicio ?? a.fechaCreacion ?? DateTime(0);
          final db = b.fechaInicio ?? b.fechaCreacion ?? DateTime(0);
          return db.compareTo(da);
        });
        return sorted;
      }
      final now = DateTime.now();
      sorted.sort((a, b) {
        final cmp = kEstadoOrder[a.estadoAt(now)] ?? 99;
        final cmp2 = kEstadoOrder[b.estadoAt(now)] ?? 99;
        return _estadoSortAsc ? cmp.compareTo(cmp2) : cmp2.compareTo(cmp);
      });
      return sorted;
    }
    sorted.sort((a, b) {
      int cmp;
      switch (_sortColumn) {
        case 0:
          cmp = a.institucion.compareTo(b.institucion);
          break;
        case 1:
          cmp = a.productos.compareTo(b.productos);
          break;
        case 2:
          cmp = (a.valorMensual ?? 0).compareTo(b.valorMensual ?? 0);
          break;
        case 3:
          cmp = (a.fechaInicio ?? DateTime(0)).compareTo(b.fechaInicio ?? DateTime(0));
          break;
        case 4:
          cmp = (a.fechaTermino ?? DateTime(0)).compareTo(b.fechaTermino ?? DateTime(0));
          break;
        default:
          cmp = 0;
      }
      return _sortAscending ? cmp : -cmp;
    });
    return sorted;
  }

  List<Proyecto> _applyFilters(List<Proyecto> all) {
    // 1. Encontrar a qué cadena pertenece cada proyecto
    final parentMap = <String, Proyecto>{};
    for (final p in all) {
      for (final cid in p.proyectoContinuacionIds) {
        parentMap[cid] = p;
      }
    }

    var filtered = all;

    if (hasActiveFilters) {
      final now = DateTime.now();
      filtered = all.where((p) {
        if (_filterInstitucion != null &&
            _filterInstitucion!.isNotEmpty &&
            !cleanInst(p.institucion)
                .toLowerCase()
                .contains(_filterInstitucion!.toLowerCase())) {
          return false;
        }
        if (_filterProductos.isNotEmpty) {
          final pp = p.productos.split(',').map((s) => s.trim()).toSet();
          if (!_filterProductos.any((prod) => pp.contains(prod))) return false;
        }
        if (_filterModalidad != null &&
            _filterModalidad!.isNotEmpty &&
            p.modalidadCompra != _filterModalidad) {
          return false;
        }
        if (_filterEstado != null &&
            _filterEstado!.isNotEmpty &&
            p.estadoAt(now) != _filterEstado) {
          return false;
        }
        if (_filterReclamo != null && _filterReclamo!.isNotEmpty) {
          if (_filterReclamo == 'Pendiente' &&
              !p.reclamos.any((r) => r.estado == 'Pendiente')) { return false; }
          if (_filterReclamo == 'Respondido' &&
              !p.reclamos.any((r) => r.estado == 'Respondido')) { return false; }
        }
        if (_filterVencer != null) {
          final dias = _vencerDias(_filterVencer!);
          final now = DateTime.now();
          final limite = now.add(Duration(days: dias));
          if (p.fechaTermino == null ||
              !p.fechaTermino!.isAfter(now) ||
              !p.fechaTermino!.isBefore(limite)) {
            return false;
          }
        }
        if (_filterEncadenado != null) {
          final parent = parentMap[p.id] ?? (p.proyectoContinuacionIds.isNotEmpty ? p : null);
          final tieneContinuacion = parent != null;
          if (_filterEncadenado! != tieneContinuacion) return false;
        }
        if (_filterSugerencia && !p.hasSugerenciasPendientes) return false;
        if (_filterQuarterYear != null && _filterQuarterQ != null) {
          final fecha = p.fechaInicio ?? p.fechaCreacion;
          if (fecha == null) return false;
          final q = ((fecha.month - 1) ~/ 3) + 1;
          if (_filterQuarterIsChurn) {
            // Churn = projects that were active (started) BEFORE this quarter
            // i.e. not new — they are renewals/continuations from a prior period
            final esDelMismoTrimestre = fecha.year == _filterQuarterYear && q == _filterQuarterQ;
            if (esDelMismoTrimestre) return false; // exclude projects that started THIS quarter
          } else {
            if (fecha.year != _filterQuarterYear || q != _filterQuarterQ) return false;
          }
          if (_filterQuarterOnlyWithOC && p.idsOrdenesCompra.isEmpty) return false;
          if (_filterQuarterOnlyIngresos && (p.valorMensual ?? 0) == 0) return false;
        }
        return true;
      }).toList();
    }

    // 2. Sin filtros activos: mostrar solo el head de cada cadena.
    //    Procesamos cada cadena UNA sola vez (BFS desde el primer proyecto no
    //    visitado) para evitar que predecesores/sucesores aparezcan como
    //    entradas independientes cuando el link existe en Firestore.
    //    Con filtros activos: devolver exactamente los proyectos que matchean.
    if (!hasActiveFilters) {
      final processed = <String>{};
      final headsToKeep = <String>{};

      for (final p in all) {
        if (processed.contains(p.id)) continue;
        final chainIds = resolveChainIds(p.id, all);
        for (final id in chainIds) processed.add(id);
        // Head = el más reciente del chain
        final chain = all.where((x) => chainIds.contains(x.id)).toList()
          ..sort((a, b) => (b.fechaInicio ?? b.fechaCreacion ?? DateTime(0))
              .compareTo(a.fechaInicio ?? a.fechaCreacion ?? DateTime(0)));
        headsToKeep.add(chain.first.id);
      }
      return all.where((p) => headsToKeep.contains(p.id)).toList();
    }

    return filtered;
  }

  List<DocItem> _buildDocItems(List<Proyecto> proyectos) {
    final items = <DocItem>[];
    for (final p in proyectos) {
      final estadoItem = _config.estados.firstWhere(
        (e) => e.nombre == p.estado,
        orElse: () => EstadoItem(nombre: p.estado, color: '64748B'),
      );
      final color = estadoItem.colorValue;

      for (final doc in p.documentos) {
        final tipo = doc.tipo.isNotEmpty ? doc.tipo : 'Documento';
        items.add(
          DocItem(
            tipoDoc: tipo,
            proyecto: p,
            descripcion: doc.nombre?.isNotEmpty == true ? doc.nombre! : tipo,
            fecha: null,
            labelFecha: null,
            urls: [doc.url],
            color: color,
            tabTarget: 'Documentos',
          ),
        );
      }
      for (final cert in p.certificados) {
        items.add(
          DocItem(
            tipoDoc: 'Certificado',
            proyecto: p,
            descripcion: cert.descripcion,
            fecha: cert.fechaEmision,
            labelFecha: 'Emisión',
            urls: cert.url != null ? [cert.url!] : [],
            color: color,
            tabTarget: 'Certificados',
          ),
        );
      }
      for (final rec in p.reclamos) {
        final tipoDoc = rec.estado == 'Respondido' ? 'Reclamo Respondido' : 'Reclamo Pendiente';
        items.add(
          DocItem(
            tipoDoc: tipoDoc,
            proyecto: p,
            descripcion: rec.descripcion,
            fecha: rec.fechaReclamo,
            labelFecha: 'Ingreso',
            fechaSecundaria: rec.fechaRespuesta,
            labelFechaSecundaria: rec.fechaRespuesta != null ? 'Respuesta' : null,
            urls: [...rec.documentos.map((d) => d.url), ...rec.documentosRespuesta.map((d) => d.url)],
            color: color,
            tabTarget: 'Reclamos',
          ),
        );
      }
    }
    return items;
  }

  List<DocItem> _applyDocFilters(List<DocItem> all) {
    return all.where((item) {
      final p = item.proyecto;
      if (_docFilterInstitucion != null && _docFilterInstitucion!.isNotEmpty) {
        if (!p.institucion.toLowerCase().contains(_docFilterInstitucion!.toLowerCase())) {
          return false;
        }
      }
      if (_docFilterProductos.isNotEmpty) {
        final pp = p.productos.split(',').map((s) => s.trim()).toSet();
        if (!_docFilterProductos.any((prod) => pp.contains(prod))) return false;
      }
      if (_docFilterModalidad != null && _docFilterModalidad!.isNotEmpty) {
        if (p.modalidadCompra != _docFilterModalidad) return false;
      }
      if (_docFilterEstado != null && _docFilterEstado!.isNotEmpty) {
        if (p.estado != _docFilterEstado) return false;
      }
      if (_docFilterTipos.isNotEmpty) {
        if (!_docFilterTipos.contains(item.tipoDoc)) return false;
      }
      return true;
    }).toList();
  }

  int _vencerDias(String periodo) {
    switch (periodo) {
      case '30 días':
        return 30;
      case '3 meses':
        return 90;
      case '6 meses':
        return 180;
      default:
        return 365;
    }
  }
}