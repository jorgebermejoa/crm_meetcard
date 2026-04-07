import '../../models/proyecto.dart';

typedef QData = ({String label, int year, int quarter, double value});

List<QData> groupByQuarter(
  List<Proyecto> proyectos,
  double Function(Proyecto) getValue, {
  bool onlyWithOC = false,
}) {
  final map = <(int, int), double>{};
  for (final p in proyectos) {
    if (onlyWithOC && p.idsOrdenesCompra.isEmpty) continue;
    final fecha = p.fechaInicio ?? p.fechaCreacion;
    if (fecha == null) continue;
    final q = ((fecha.month - 1) ~/ 3) + 1;
    final key = (fecha.year, q);
    map[key] = (map[key] ?? 0) + getValue(p);
  }
  final entries = map.entries.toList()
    ..sort((a, b) {
      final yc = a.key.$1.compareTo(b.key.$1);
      return yc != 0 ? yc : a.key.$2.compareTo(b.key.$2);
    });
  return entries
      .map(
        (e) => (
          label: 'Q${e.key.$2}',
          year: e.key.$1,
          quarter: e.key.$2,
          value: e.value,
        ),
      )
      .toList();
}

/// Devuelve lista donde cada elemento es el año como String si cambió respecto
/// al anterior (primera barra de ese año), o null si el año es el mismo.
/// [abbreviated] usa formato corto: '24 en lugar de 2024.
List<String?> yearLabels(List<QData> data, {bool abbreviated = false}) {
  int? lastYear;
  return data.map((d) {
    if (d.year != lastYear) {
      lastYear = d.year;
      return abbreviated
          ? "'${(d.year % 100).toString().padLeft(2, '0')}"
          : d.year.toString();
    }
    return null;
  }).toList();
}

/// Proyectos finalizados con OC que no tienen renovación (nueva OC de la misma
/// institución con fechaInicio posterior). Se agrupa por quarter de fechaTermino.
List<QData> churnByQuarter(List<Proyecto> proyectos) {
  // Instituciones que tienen algún proyecto activo (con OC, no finalizado)
  final renovadas = <String>{};
  for (final p in proyectos) {
    if (p.idsOrdenesCompra.isEmpty) continue;
    if (p.estado == EstadoProyecto.finalizado) continue;
    renovadas.add(p.institucion.trim().toLowerCase());
  }

  final map = <(int, int), double>{};
  for (final p in proyectos) {
    if (p.idsOrdenesCompra.isEmpty) continue;
    if (p.estado != EstadoProyecto.finalizado) continue;
    final fechaFin = p.fechaTermino;
    if (fechaFin == null) continue;
    final inst = p.institucion.trim().toLowerCase();

    // Tiene renovación si hay otro proyecto con OC de la misma institución
    // cuyo fechaInicio es posterior a la fecha de término de éste
    final tieneRenovacion =
        renovadas.contains(inst) ||
        proyectos.any(
          (o) =>
              o.id != p.id &&
              o.idsOrdenesCompra.isNotEmpty &&
              o.institucion.trim().toLowerCase() == inst &&
              (o.fechaInicio ?? o.fechaCreacion) != null &&
              (o.fechaInicio ?? o.fechaCreacion)!.isAfter(fechaFin),
        );

    // Período de gracia: 90 días desde fechaTermino antes de contar como churn
    final graceDate = fechaFin.add(const Duration(days: 90));
    if (graceDate.isAfter(DateTime.now())) continue;

    // Encadenado explícitamente → no es churn
    if (p.proyectoContinuacionIds.isNotEmpty) {
      continue;
    }

    if (!tieneRenovacion) {
      final q = ((fechaFin.month - 1) ~/ 3) + 1;
      final key = (fechaFin.year, q);
      map[key] = (map[key] ?? 0) + 1;
    }
  }

  final entries = map.entries.toList()
    ..sort((a, b) {
      final yc = a.key.$1.compareTo(b.key.$1);
      return yc != 0 ? yc : a.key.$2.compareTo(b.key.$2);
    });
  return entries
      .map(
        (e) => (
          label: 'Q${e.key.$2}',
          year: e.key.$1,
          quarter: e.key.$2,
          value: e.value,
        ),
      )
      .toList();
}

/// Une dos listas de QData en un timeline unificado.
/// Retorna labels, yearLabels, valores positivos y valores de churn alineados.
({
  List<String> labels,
  List<String?> yearLabels,
  List<double> positive,
  List<double> churn,
  List<(int, int)> keys,
})
mergeDivergingData(
  List<QData> positiveData,
  List<QData> churnData, {
  bool abbreviated = false,
}) {
  final keys = <(int, int)>{};
  for (final d in [...positiveData, ...churnData]) {
    keys.add((d.year, d.quarter));
  }
  final extremes = keys.toList()
    ..sort((a, b) {
      final yc = a.$1.compareTo(b.$1);
      return yc != 0 ? yc : a.$2.compareTo(b.$2);
    });

  // Fill all intermediate quarters so gaps with 0 activity are visible
  final sorted = <(int, int)>[];
  if (extremes.isNotEmpty) {
    var cur = extremes.first;
    final last = extremes.last;
    while (cur.$1 < last.$1 || (cur.$1 == last.$1 && cur.$2 <= last.$2)) {
      sorted.add(cur);
      cur = cur.$2 < 4 ? (cur.$1, cur.$2 + 1) : (cur.$1 + 1, 1);
    }
  }

  final posMap = {for (final d in positiveData) (d.year, d.quarter): d.value};
  final negMap = {for (final d in churnData) (d.year, d.quarter): d.value};

  final qData = sorted
      .map((k) => (label: 'Q${k.$2}', year: k.$1, quarter: k.$2, value: 0.0))
      .toList();

  return (
    labels: sorted.map((k) => 'Q${k.$2}').toList(),
    yearLabels: yearLabels(qData, abbreviated: abbreviated),
    positive: sorted.map((k) => posMap[k] ?? 0.0).toList(),
    churn: sorted.map((k) => negMap[k] ?? 0.0).toList(),
    keys: sorted,
  );
}

/// Clientes nuevos por quarter.
/// Cada institución se cuenta UNA sola vez, en el quarter de su PRIMERA OC.
/// Proyectos posteriores de la misma institución no suman como cliente nuevo.
List<QData> newClientsByQuarter(List<Proyecto> proyectos) {
  // Para cada institución, encontrar la fecha del proyecto con OC más antiguo
  final firstByInst = <String, DateTime>{};
  for (final p in proyectos) {
    if (p.idsOrdenesCompra.isEmpty) continue;
    final fecha = p.fechaInicio ?? p.fechaCreacion;
    if (fecha == null) continue;
    final inst = p.institucion.trim().toLowerCase();
    final existing = firstByInst[inst];
    if (existing == null || fecha.isBefore(existing)) {
      firstByInst[inst] = fecha;
    }
  }

  final map = <(int, int), double>{};
  for (final fecha in firstByInst.values) {
    final q = ((fecha.month - 1) ~/ 3) + 1;
    final key = (fecha.year, q);
    map[key] = (map[key] ?? 0) + 1;
  }

  final entries = map.entries.toList()
    ..sort((a, b) {
      final yc = a.key.$1.compareTo(b.key.$1);
      return yc != 0 ? yc : a.key.$2.compareTo(b.key.$2);
    });
  return entries
      .map(
        (e) => (
          label: 'Q${e.key.$2}',
          year: e.key.$1,
          quarter: e.key.$2,
          value: e.value,
        ),
      )
      .toList();
}
