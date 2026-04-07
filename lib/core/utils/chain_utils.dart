import '../../models/proyecto.dart';

/// Returns all project IDs in the same chain as [projectId], traversing both
/// directions (ancestors via reverse-lookup + successors via proyectoContinuacionIds).
Set<String> resolveChainIds(String projectId, List<Proyecto> all) {
  final visited = <String>{};
  final toVisit = <String>[projectId];

  while (toVisit.isNotEmpty) {
    final id = toVisit.removeAt(0);
    if (visited.contains(id)) continue;
    visited.add(id);
    final proj = all.where((x) => x.id == id).firstOrNull;
    if (proj == null) continue;
    // Successors
    for (final sid in proj.proyectoContinuacionIds) {
      if (!visited.contains(sid)) toVisit.add(sid);
    }
    // Ancestors: projects that point TO this id
    for (final x in all) {
      if (!visited.contains(x.id) && x.proyectoContinuacionIds.contains(id)) {
        toVisit.add(x.id);
      }
    }
  }

  return visited;
}

/// Returns the "head" of the chain — the project with the most recent
/// fechaInicio (falling back to fechaCreacion) among all projects in the chain.
Proyecto getChainHead(Proyecto p, List<Proyecto> all) {
  final chainIds = resolveChainIds(p.id, all);
  final chain = all.where((x) => chainIds.contains(x.id)).toList();
  if (chain.isEmpty) return p;
  chain.sort((a, b) => (b.fechaInicio ?? b.fechaCreacion ?? DateTime(0))
      .compareTo(a.fechaInicio ?? a.fechaCreacion ?? DateTime(0)));
  return chain.first;
}
