import 'dart:convert';
import 'package:http/http.dart' as http;

const _cfBase = 'https://us-central1-licitaciones-prod.cloudfunctions.net';
const _mpApiBase =
    'https://api.mercadopublico.cl/servicios/v1/publico/licitaciones.json';
const mpApiTicket = 'EE36DCF4-F727-4EED-9026-20EF36A6DD54';

// ── Resultado unificado ────────────────────────────────────────────────────

class LicitacionInfo {
  final String institucion;
  final DateTime? fechaAdjudicacion;
  final Map<String, dynamic>? ocdsData;
  final Map<String, dynamic>? mpData;

  /// 'ocds' | 'mp_api' | 'none'
  final String source;

  const LicitacionInfo({
    required this.institucion,
    required this.source,
    this.fechaAdjudicacion,
    this.ocdsData,
    this.mpData,
  });

  bool get found => source != 'none';
  Map<String, dynamic>? get data => ocdsData ?? mpData;
  String get cacheKey => source == 'ocds' ? 'ocds' : 'mp_api';
}

// ── Servicio ───────────────────────────────────────────────────────────────

class LicitacionApiService {
  LicitacionApiService._();
  static final instance = LicitacionApiService._();

  /// Extrae la primera fecha válida de un texto.
  /// Soporta: ISO 8601, YYYY-MM-DD embebido, y DD/MM/YYYY (formato Convenio Marco).
  static DateTime? parseDate(String? text) {
    if (text == null || text.isEmpty) return null;
    final trimmed = text.trim();

    // ISO directo
    final direct = DateTime.tryParse(trimmed);
    if (direct != null) return direct;

    // YYYY-MM-DD embebido en texto
    final isoMatch = RegExp(r'\d{4}-\d{2}-\d{2}').firstMatch(trimmed);
    if (isoMatch != null) {
      final d = DateTime.tryParse(isoMatch.group(0)!);
      if (d != null) return d;
    }

    // DD/MM/YYYY o DD-MM-YYYY (Convenio Marco usa guiones: "16-03-2026")
    final part = trimmed.split(' ').first;
    final sep = part.contains('/') ? '/' : '-';
    final pieces = part.split(sep);
    if (pieces.length == 3) {
      final day = int.tryParse(pieces[0]);
      final month = int.tryParse(pieces[1]);
      final year = int.tryParse(pieces[2]);
      // year > 1900 y day ≤ 31 descarta formato ISO (YYYY-MM-DD ya manejado arriba)
      if (day != null && month != null && year != null &&
          year > 1900 && day <= 31) {
        return DateTime.utc(year, month, day);
      }
    }

    return null;
  }

  /// Añade [months] meses a [date].
  static DateTime addMonths(DateTime date, int months) {
    final totalM = (date.year * 12 + date.month - 1) + months;
    return DateTime(totalM ~/ 12, totalM % 12 + 1, date.day);
  }

  /// Resta [months] meses a [date].
  static DateTime subtractMonths(DateTime date, int months) {
    final totalM = (date.year * 12 + date.month - 1) - months;
    return DateTime(totalM ~/ 12, totalM % 12 + 1, date.day);
  }

  // ── Búsqueda LP: OCDS → MP API ──────────────────────────────────────────

  /// Busca datos de una Licitación Pública.
  /// Intenta OCDS primero; si no obtiene institución o fecha, cae al MP API.
  Future<LicitacionInfo> fetchLP(String codigo, {String type = 'tender'}) async {
    // 1. OCDS vía Cloud Function
    LicitacionInfo? ocdsResult;
    try {
      final resp = await http
          .get(Uri.parse(
              '$_cfBase/buscarLicitacionPorId?id=${Uri.encodeComponent(codigo)}&type=$type'))
          .timeout(const Duration(seconds: 20));
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        ocdsResult = _parseOcds(data, codigo);
        // Si obtuvo institución real, retorna directamente
        if (ocdsResult.institucion != codigo) return ocdsResult;
      }
    } catch (_) {}

    // 2. Fallback: MP API
    try {
      final resp = await http
          .get(Uri.parse(
              '$_mpApiBase?codigo=${Uri.encodeComponent(codigo)}&ticket=$mpApiTicket'))
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        final mpResult = _parseMpApi(data, codigo);
        if (mpResult.found) return mpResult;
      }
    } catch (_) {}

    // Retorna resultado OCDS parcial (sin institución) o vacío
    return ocdsResult ??
        const LicitacionInfo(institucion: '', source: 'none');
  }

  // ── Parsers ──────────────────────────────────────────────────────────────

  LicitacionInfo _parseOcds(Map<String, dynamic> data, String fallback) {
    String institucion = fallback;
    DateTime? fecha;

    final releases =
        (data['releases'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (releases.isNotEmpty) {
      final last = releases.last;

      // Institución (buyer)
      final parties =
          (last['parties'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final buyer = parties.firstWhere(
          (p) => (p['roles'] as List?)?.contains('buyer') == true,
          orElse: () => <String, dynamic>{});
      final name = buyer['name']?.toString() ?? '';
      if (name.isNotEmpty) institucion = name.split('|').first.trim();

      // Fecha: awardPeriod.startDate → awards[0].date → tenderPeriod.endDate → release.date
      final tender = last['tender'] as Map<String, dynamic>? ?? {};
      final awards =
          (last['awards'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      for (final raw in [
        tender['awardPeriod']?['startDate']?.toString(),
        awards.firstOrNull?['date']?.toString(),
        tender['tenderPeriod']?['endDate']?.toString(),
        last['date']?.toString(),
      ]) {
        final d = parseDate(raw);
        if (d != null) {
          fecha = d;
          break;
        }
      }
    }

    return LicitacionInfo(
      institucion: institucion,
      fechaAdjudicacion: fecha,
      ocdsData: data,
      source: 'ocds',
    );
  }

  LicitacionInfo _parseMpApi(Map<String, dynamic> data, String fallback) {
    String institucion = fallback;
    DateTime? fecha;

    final listado =
        (data['Listado'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (listado.isNotEmpty) {
      final item = listado.first;
      final org = item['Comprador']?['NombreOrganismo']?.toString() ?? '';
      if (org.isNotEmpty) institucion = org;

      // Fecha: adjudicación estimada → firma estimada → cierre
      final fechas = item['Fechas'] as Map<String, dynamic>? ?? {};
      for (final key in [
        'FechaAdjudicacion',
        'FechaEstimadaAdjudicacion',
        'FechaEstimadaFirma',
        'FechaCierre',
        'FechaPublicacion',
      ]) {
        final d = parseDate(fechas[key]?.toString());
        if (d != null) {
          fecha = d;
          break;
        }
      }
    }

    return LicitacionInfo(
      institucion: institucion,
      fechaAdjudicacion: fecha,
      mpData: data,
      source: institucion != fallback ? 'mp_api' : 'none',
    );
  }
}
