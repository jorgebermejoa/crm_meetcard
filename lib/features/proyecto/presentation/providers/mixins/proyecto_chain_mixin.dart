import 'package:flutter/foundation.dart';
import '../../../domain/entities/proyecto_entity.dart';
import '../../../domain/repositories/proyecto_repository.dart';

/// Resolves the chain of predecessor/successor projects for a given project,
/// and exposes add/remove operations that persist to Firestore.
mixin ProyectoChainMixin on ChangeNotifier {
  ProyectoRepository get repository;
  ProyectoEntity get proyecto;
  set proyectoInternal(ProyectoEntity value);
  VoidCallback? get onMutated;

  // ── State ──────────────────────────────────────────────────────────────────
  List<ProyectoEntity> _cadena = [];
  List<ProyectoEntity> _sucesores = [];
  bool _cadenaLoading = false;

  List<ProyectoEntity> get cadena => _cadena;
  List<ProyectoEntity> get sucesores => _sucesores;
  bool get cadenaLoading => _cadenaLoading;

  // ── Load ───────────────────────────────────────────────────────────────────
  Future<void> cargarCadena() async {
    _cadenaLoading = true;
    notifyListeners();
    try {
      final all = await repository.getProyectos();
      _resolveChain(all);
    } catch (_) {
      _cadena = [proyecto];
      _sucesores = [];
    } finally {
      _cadenaLoading = false;
      notifyListeners();
    }
  }

  void _resolveChain(List<ProyectoEntity> all) {
    final fresh = all.firstWhere((p) => p.id == proyecto.id,
        orElse: () => proyecto);

    // Bidirectional BFS: collect ALL connected projects regardless of link direction.
    // This handles non-linear topologies where a project may link to multiple others
    // (e.g., LE21 → [8290SEQK, 0824CPRD]) by following both forward and backward edges.
    final visited = <String>{};
    final chain = <ProyectoEntity>[];
    final toVisit = <String>[fresh.id];

    while (toVisit.isNotEmpty) {
      final id = toVisit.removeAt(0);
      if (visited.contains(id)) continue;
      visited.add(id);
      final proj = all.where((p) => p.id == id).firstOrNull;
      if (proj == null) continue;
      chain.add(proj);
      // Forward edges
      for (final sid in proj.proyectoContinuacionIds) {
        if (!visited.contains(sid)) toVisit.add(sid);
      }
      // Backward edges (projects that point to this one)
      for (final p in all) {
        if (!visited.contains(p.id) && p.proyectoContinuacionIds.contains(id)) {
          toVisit.add(p.id);
        }
      }
    }

    // Sort the full chain oldest → newest for cadena
    chain.sort((a, b) => (a.fechaInicio ?? a.fechaCreacion ?? DateTime(0))
        .compareTo(b.fechaInicio ?? b.fechaCreacion ?? DateTime(0)));

    // Cadena = projects up to and including current (oldest first)
    final freshDate = fresh.fechaInicio ?? fresh.fechaCreacion ?? DateTime(0);
    _cadena = chain
        .where((p) =>
            (p.fechaInicio ?? p.fechaCreacion ?? DateTime(0))
                .compareTo(freshDate) <=
            0)
        .toList();
    // Ensure current project is always in cadena
    if (!_cadena.any((p) => p.id == fresh.id)) _cadena.add(fresh);

    // Sucesores = projects strictly newer than current
    _sucesores = chain
        .where((p) =>
            p.id != fresh.id &&
            (p.fechaInicio ?? p.fechaCreacion ?? DateTime(0))
                    .compareTo(freshDate) >
                0)
        .toList();
  }

  // ── Mutations ──────────────────────────────────────────────────────────────
  Future<void> addSucesorCadena(String sucId) async {
    if (proyecto.proyectoContinuacionIds.contains(sucId)) return;
    final updated = [...proyecto.proyectoContinuacionIds, sucId];
    await _saveContinuaciones(updated, 'Encadenó proyecto sucesor $sucId');
  }

  Future<void> removeSucesorCadena(String sucId) async {
    if (!proyecto.proyectoContinuacionIds.contains(sucId)) return;
    final updated = proyecto.proyectoContinuacionIds
        .where((id) => id != sucId)
        .toList();
    await _saveContinuaciones(updated, 'Desvinculó proyecto sucesor $sucId');
  }

  Future<void> reorderSucesores(int oldIndex, int newIndex) async {
    final ids = List<String>.from(proyecto.proyectoContinuacionIds);
    if (oldIndex < newIndex) newIndex--;
    final id = ids.removeAt(oldIndex);
    ids.insert(newIndex, id);
    await _saveContinuaciones(ids, 'Reordenó sucesores');
  }

  Future<void> setSucesoresOrder(List<String> ids) async {
    await _saveContinuaciones(ids, 'Reordenó sucesores');
  }

  Future<void> _saveContinuaciones(List<String> ids, String accion) async {
    await repository.updateProyectoField(
      id: proyecto.id,
      fieldName: 'proyectoContinuacionIds',
      value: ids,
      historyData: {
        'fecha': DateTime.now().toIso8601String(),
        'accion': accion,
        'valor': ids.join(','),
      },
    );
    proyectoInternal = await repository.getProyecto(proyecto.id);
    onMutated?.call();
    await cargarCadena();
  }
}
