import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:web/web.dart' as web;

import '../core/utils/string_utils.dart';
import '../features/proyectos/presentation/providers/proyectos_provider.dart';
import '../models/proyecto.dart';

void exportCSV(List<Proyecto> proyectos) {
  final buf = StringBuffer();
  buf.writeln(
    'ID,Institución,Productos,Modalidad,Estado,Valor Mensual,Fecha Inicio,Fecha Término',
  );
  for (final p in proyectos) {
    String esc(String s) => '"${s.replaceAll('"', '""')}"';
    buf.writeln(
      [
        esc(p.id),
        esc(cleanInst(p.institucion)),
        esc(p.productos),
        esc(p.modalidadCompra),
        esc(p.estado),
        p.valorMensual?.toStringAsFixed(0) ?? '',
        p.fechaInicio != null
            ? '${p.fechaInicio!.day}/${p.fechaInicio!.month}/${p.fechaInicio!.year}'
            : '',
        p.fechaTermino != null
            ? '${p.fechaTermino!.day}/${p.fechaTermino!.month}/${p.fechaTermino!.year}'
            : '',
      ].join(','),
    );
  }
  // Prepend UTF-8 BOM so Excel auto-detects encoding and renders accents correctly
  final bytes = utf8.encode('\uFEFF${buf.toString()}');
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'text/csv;charset=utf-8;'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = 'proyectos_${DateTime.now().millisecondsSinceEpoch}.csv';
  web.document.body!.appendChild(anchor);
  anchor.click();
  web.document.body!.removeChild(anchor);
  web.URL.revokeObjectURL(url);
}

void exportPDF(BuildContext context, List<Proyecto> proyectos) {
  final provider = context.read<ProyectosProvider>();
  String fmtDate(DateTime? d) => d != null
      ? '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}'
      : '—';
  String fmtNum(double n) {
    final digits = n.toInt().toString();
    final buf = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buf.write('.');
      buf.write(digits[i]);
    }
    return buf.toString();
  }

  String fmtVal(double? v) => v != null ? '\$${fmtNum(v)}' : '—';
  String esc(String s) =>
      s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

  final hasFilters = provider.hasActiveFilters;
  // ── KPI computations (same as KPI cards) ──────────────────────────────────
  final now = DateTime.now();
  final all = provider.proyectos; // use full list for KPIs, filtered list for table

  final kpiTotal = all.length;
  final kpiActivos = all
      .where(
        (p) =>
            p.estado == EstadoProyecto.vigente ||
            p.estado == EstadoProyecto.xVencer,
      )
      .length;
  final kpiVigentes =
      all.where((p) => p.estado == EstadoProyecto.vigente).length;
  final kpiXVencer =
      all.where((p) => p.estado == EstadoProyecto.xVencer).length;
  bool esPostulacion(Proyecto p) => p.estadoManual == 'En Evaluación';
  final kpiPostulacion = all.where(esPostulacion).length;
  final kpiFinalizados =
      all.where((p) => p.estado == EstadoProyecto.finalizado).length;

  final kpiValorTotal = all.fold<double>(
    0,
    (s, p) => s + (p.valorMensual ?? 0),
  );
  final kpiValorVigente = all
      .where((p) => p.estado == EstadoProyecto.vigente)
      .fold<double>(0, (s, p) => s + (p.valorMensual ?? 0));
  final kpiValorPostulacion = all
      .where(esPostulacion)
      .fold<double>(0, (s, p) => s + (p.valorMensual ?? 0));

  final kpiReclPend = all.fold<int>(
    0,
    (s, p) => s + p.reclamos.where((r) => r.estado == 'Pendiente').length,
  );
  final kpiReclResp = all.fold<int>(
    0,
    (s, p) => s + p.reclamos.where((r) => r.estado == 'Respondido').length,
  );

  final kpiVencer30 = all.where((p) {
    final ft = p.fechaTermino;
    return ft != null &&
        ft.isAfter(now) &&
        ft.isBefore(now.add(const Duration(days: 30)));
  }).length;
  final kpiVencer90 = all.where((p) {
    final ft = p.fechaTermino;
    return ft != null &&
        ft.isAfter(now) &&
        ft.isBefore(now.add(const Duration(days: 90)));
  }).length;
  final kpiVencer180 = all.where((p) {
    final ft = p.fechaTermino;
    return ft != null &&
        ft.isAfter(now) &&
        ft.isBefore(now.add(const Duration(days: 180)));
  }).length;
  final kpiVencer365 = all.where((p) {
    final ft = p.fechaTermino;
    return ft != null &&
        ft.isAfter(now) && //
        ft.isBefore(now.add(const Duration(days: 365)));
  }).length;

  String kpiCard(String label, String value, String color) =>
      '<div class="kpi-card"><div class="kpi-label">$label</div>' //
      '<div class="kpi-value" style="color:$color">$value</div></div>';

  final dateStr =
      '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';

  final html = StringBuffer('''<!DOCTYPE html> //
<html lang="es"> //
<head>
<meta charset="utf-8">
<title>Proyectos — Mercado Público</title>
<style>
* { box-sizing: border-box; margin: 0; padding: 0; }
body { font-family: Arial, Helvetica, sans-serif; font-size: 11px; color: #1E293B; padding: 20px; }
.header { margin-bottom: 14px; }
.header h1 { font-size: 18px; font-weight: 700; }
.header p { font-size: 10px; color: #64748B; margin-top: 3px; }
/* KPI section */
.kpi-section { margin-bottom: 18px; }
.kpi-section h2 { font-size: 11px; font-weight: 700; color: #64748B; text-transform: uppercase;
  letter-spacing: 0.5px; margin-bottom: 8px; }
.kpi-group { display: flex; gap: 8px; margin-bottom: 8px; flex-wrap: wrap; }
.kpi-card { flex: 1; min-width: 100px; background: #F8FAFC; border: 1px solid #E2E8F0;
  border-radius: 8px; padding: 8px 10px; }
.kpi-label { font-size: 9px; color: #64748B; font-weight: 600; text-transform: uppercase;
  letter-spacing: 0.3px; margin-bottom: 4px; }
.kpi-value { font-size: 16px; font-weight: 700; }
/* Table */
table { width: 100%; border-collapse: collapse; }
.table-title { font-size: 11px; font-weight: 700; color: #64748B; text-transform: uppercase;
  letter-spacing: 0.5px; margin-bottom: 8px; }
thead th { background: #007AFF; color: #fff; padding: 7px 8px; text-align: left;
  font-size: 10px; font-weight: 700; }
tbody td { padding: 6px 8px; border-bottom: 1px solid #E2E8F0; font-size: 10px; vertical-align: top; }
tbody tr:nth-child(even) td { background: #F8FAFC; }
@page { margin: 15mm; }
@media print { body { padding: 0; } .kpi-card { break-inside: avoid; } }
</style>
</head>
<body>
<div class="header">
  <h1>Buscador Mercado Público</h1>
  <p>Informe de proyectos · $dateStr${hasFilters ? ' · Con filtros aplicados' : ''}</p>
</div>

<div class="kpi-section">
  <h2>Resumen de proyectos</h2>
  <div class="kpi-group">
    ${kpiCard('Total', '$kpiTotal', '#1E293B')}
    ${kpiCard('Activos', '$kpiActivos', '#007AFF')}
    ${kpiCard('Vigentes', '$kpiVigentes', '#10B981')}
    ${kpiCard('X Vencer', '$kpiXVencer', '#F59E0B')}
    ${kpiCard('Postulación', '$kpiPostulacion', '#6366F1')}
    ${kpiCard('Finalizados', '$kpiFinalizados', '#64748B')}
  </div>
  <div class="kpi-group">
    ${kpiCard('Valor Total', '\$${fmtNum(kpiValorTotal)}', '#007AFF')}
    ${kpiCard('Valor Vigente', '\$${fmtNum(kpiValorVigente)}', '#10B981')}
    ${kpiCard('Valor Postulación', '\$${fmtNum(kpiValorPostulacion)}', '#6366F1')}
    ${kpiCard('Reclamos Pend.', '$kpiReclPend', '#EF4444')}
    ${kpiCard('Reclamos Resp.', '$kpiReclResp', '#64748B')}
  </div>
  <div class="kpi-group">
    ${kpiCard('Por Vencer 30 días', '$kpiVencer30', '#F59E0B')}
    ${kpiCard('Por Vencer 3 meses', '$kpiVencer90', '#F59E0B')}
    ${kpiCard('Por Vencer 6 meses', '$kpiVencer180', '#F59E0B')}
    ${kpiCard('Por Vencer 12 meses', '$kpiVencer365', '#F59E0B')}
  </div>
</div>

<p class="table-title">Detalle de ${proyectos.length} proyecto${proyectos.length != 1 ? 's' : ''}${hasFilters ? ' (con filtros)' : ''}</p>
<table>
<thead>
<tr>
  <th>#</th><th>Institución</th><th>Productos</th><th>Modalidad</th>
  <th>Estado</th><th>Valor Mensual</th><th>F. Inicio</th><th>F. Término</th>
</tr>
</thead>
<tbody>
''');

  for (int i = 0; i < proyectos.length; i++) {
    final p = proyectos[i];
    html.write('<tr>');
    html.write('<td>${i + 1}</td>');
    html.write('<td>${esc(cleanInst(p.institucion))}</td>');
    html.write('<td>${esc(p.productos)}</td>');
    html.write('<td>${esc(p.modalidadCompra)}</td>');
    html.write('<td>${esc(p.estado)}</td>');
    html.write('<td>${fmtVal(p.valorMensual)}</td>');
    html.write('<td>${fmtDate(p.fechaInicio)}</td>');
    html.write('<td>${fmtDate(p.fechaTermino)}</td>');
    html.write('</tr>\n');
  }

  html.write('''</tbody>
</table>
<script>window.addEventListener('load', function() { window.print(); });</script>
</body>
</html>''');

  final bytes = utf8.encode(html.toString());
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'text/html;charset=utf-8'),
  );
  final url = web.URL.createObjectURL(blob);
  web.window.open(url, '_blank');
  // Revoke after a short delay to allow the new tab to load
  Future.delayed(
    const Duration(seconds: 10),
    () => web.URL.revokeObjectURL(url),
  );
}