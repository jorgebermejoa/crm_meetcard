import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

import 'licitaciones_table.dart' show LicitacionUI;

// ── Bottom sheet helper ────────────────────────────────────────────────────────

/// Muestra el detalle de una licitación como bottom sheet (mobile) o sidebar (desktop).
void mostrarDetalleLicitacionSheet(
    BuildContext context, Map<String, dynamic> rawData) {
  final h = MediaQuery.of(context).size.height;
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => Container(
      height: h * 0.92,
      decoration: const BoxDecoration(
        color: Color(0xFFF2F2F7),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(children: [
        // Drag handle
        Container(
          width: 36,
          height: 4,
          margin: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Expanded(
          child: DetalleLicitacionSidebar(
            rawData: rawData,
            onClose: () => Navigator.of(context).pop(),
          ),
        ),
      ]),
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// PANEL DETALLE LICITACIÓN
// ══════════════════════════════════════════════════════════════════════════════

class DetalleLicitacionSidebar extends StatefulWidget {
  final Map<String, dynamic> rawData;
  final VoidCallback onClose;

  const DetalleLicitacionSidebar(
      {super.key, required this.rawData, required this.onClose});

  @override
  State<DetalleLicitacionSidebar> createState() =>
      _DetalleLicitacionSidebarState();
}

class _DetalleLicitacionSidebarState extends State<DetalleLicitacionSidebar>
    with SingleTickerProviderStateMixin {
  static const _cf =
      'https://us-central1-licitaciones-prod.cloudfunctions.net';
  static const _primary = Color(0xFF5B21B6);
  static const _bg = Color(0xFFF2F2F7);

  Map<String, dynamic>? _intel;
  bool _cargandoIntel = false;
  late TabController _tabController;

  // Foro
  List<Map<String, dynamic>> _enquiries = [];
  bool _cargandoForo = false;
  bool _foroCargado = false;
  DateTime? _foroFechaCache;
  final TextEditingController _foroSearch = TextEditingController();
  String _foroQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
    _foroSearch.addListener(() => setState(() => _foroQuery = _foroSearch.text.toLowerCase()));
    _fetchIntel();
  }

  void _onTabChanged() {
    if (_tabController.index == 1 && !_foroCargado && !_cargandoForo) {
      _fetchForo();
    }
  }

  @override
  void didUpdateWidget(DetalleLicitacionSidebar old) {
    super.didUpdateWidget(old);
    if (old.rawData['id'] != widget.rawData['id']) {
      setState(() {
        _intel = null;
        _enquiries = [];
        _foroCargado = false;
        _foroFechaCache = null;
        _foroSearch.clear();
      });
      _fetchIntel();
      if (_tabController.index == 1) _fetchForo();
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _foroSearch.dispose();
    super.dispose();
  }

  // ── Foro fetch (Firestore caché + OCDS API) ───────────────────────────────

  Future<void> _fetchForo({bool forceRefresh = false}) async {
    final id = widget.rawData['id']?.toString() ?? '';
    if (id.isEmpty) return;
    setState(() => _cargandoForo = true);
    try {
      final db = FirebaseFirestore.instance;
      final docRef = db.collection('licitaciones_ocds').doc(id);

      // 1. Read from Firestore cache unless force refresh
      if (!forceRefresh) {
        final snap = await docRef.get();
        if (snap.exists) {
          final cached = snap.data()?['_foro_enquiries'];
          if (cached is List && cached.isNotEmpty) {
            final ts = snap.data()?['_foro_fetchedAt'];
            if (mounted) {
              setState(() {
                _enquiries = cached.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
                _foroFechaCache = ts is Timestamp ? ts.toDate() : null;
                _foroCargado = true;
              });
            }
            return;
          }
        }
      }

      // 2. Fetch via CF proxy (avoids CORS on web)
      final uri = Uri.parse('$_cf/buscarLicitacionPorId?id=${Uri.encodeComponent(id)}&type=tender');
      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) return;

      final data = json.decode(resp.body) as Map<String, dynamic>;
      final releases = (data['releases'] as List?) ?? [];
      final seen = <String>{};
      final all = <Map<String, dynamic>>[];
      for (final release in releases) {
        if (release is! Map) continue;
        final tender = release['tender'];
        if (tender is! Map) continue;
        final eqs = tender['enquiries'];
        if (eqs is! List) continue;
        for (final e in eqs) {
          if (e is! Map) continue;
          final eid = e['id']?.toString() ?? '';
          if (seen.add(eid)) all.add(Map<String, dynamic>.from(e));
        }
      }

      // 3. Actualizar UI primero
      if (mounted) {
        setState(() {
          _enquiries = all;
          _foroFechaCache = DateTime.now();
          _foroCargado = true;
        });
      }

      // 4. Persistir caché (best-effort)
      try {
        await docRef.set({
          '_foro_enquiries': all,
          '_foro_fetchedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (_) {}

    } catch (_) {
      if (mounted) setState(() => _foroCargado = true);
    } finally {
      if (mounted) setState(() => _cargandoForo = false);
    }
  }

  Future<void> _fetchIntel() async {
    setState(() => _cargandoIntel = true);
    try {
      final id = widget.rawData['id'] ?? '';
      final comprador = widget.rawData['comprador'] ??
          widget.rawData['tender']?['procuringEntity']?['name'] ??
          widget.rawData['buyer']?['name'] ??
          '';
      final uri = Uri.parse(
          '$_cf/obtenerInteligenciaLicitacion?id=$id&comprador_nombre=${Uri.encodeComponent(comprador)}');
      final resp =
          await http.get(uri).timeout(const Duration(seconds: 15));
      if (resp.statusCode == 200 && mounted) {
        setState(() => _intel = json.decode(resp.body));
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _cargandoIntel = false);
    }
  }

  void _abrirFicha() {
    final id = widget.rawData['id']?.toString();
    if (id == null || id.isEmpty) return;
    web.window.open(
      'http://www.mercadopublico.cl/Procurement/Modules/RFB/DetailsAcquisition.aspx?idlicitacion=$id',
      '_blank',
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 700;
    return Container(
      width: isMobile ? screenWidth : 520,
      color: _bg,
      child: Column(
        children: [
          _buildHeader(),
          Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              labelStyle: GoogleFonts.inter(
                  fontSize: 12, fontWeight: FontWeight.w600),
              unselectedLabelStyle:
                  GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w400),
              labelColor: _primary,
              unselectedLabelColor: Colors.grey.shade400,
              indicatorColor: _primary,
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              tabs: const [
                Tab(text: 'Información'),
                Tab(text: 'Foro'),
                Tab(text: 'Análisis'),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _panelInformacion(),
                _panelForo(),
                _panelAnalisis(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    final raw = widget.rawData;
    final id = raw['id']?.toString() ?? '';
    final titulo = raw['titulo'] ??
        raw['tender']?['title'] ??
        'Sin título';
    final comprador = raw['comprador'] ??
        raw['buyer']?['name'] ??
        raw['tender']?['procuringEntity']?['name'] ??
        '';
    final esVigente = LicitacionUI(id, titulo, '', '', raw['fechaCierre'] ?? '').esVigente;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Close button
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 10),
            child: InkWell(
              onTap: widget.onClose,
              borderRadius: BorderRadius.circular(8),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close, size: 18, color: Color(0xFF64748B)),
              ),
            ),
          ),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ID + badges
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      id,
                      style: GoogleFonts.robotoMono(
                          fontSize: 10,
                          color: const Color(0xFF64748B),
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _estadoBadge(esVigente),
                  const Spacer(),
                  // Ver Ficha button
                  InkWell(
                    onTap: _abrirFicha,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: _primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Ver Ficha',
                              style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: _primary)),
                          const SizedBox(width: 3),
                          const Icon(Icons.open_in_new,
                              size: 10, color: _primary),
                        ],
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 6),
                // Título
                Text(
                  titulo.toString(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1E293B),
                    height: 1.3,
                  ),
                ),
                if (comprador.toString().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    _truncarComprador(comprador.toString()),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                        fontSize: 11, color: Colors.grey.shade500),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _estadoBadge(bool vigente) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
        decoration: BoxDecoration(
          color: vigente
              ? const Color(0xFF10B981).withValues(alpha: 0.12)
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          vigente ? 'Vigente' : 'Cerrada',
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: vigente
                ? const Color(0xFF059669)
                : Colors.grey.shade500,
          ),
        ),
      );

  // ── Panel Información ──────────────────────────────────────────────────────

  /// Normaliza `tender`: en Firestore puede llegar como List o Map.
  Map<String, dynamic> _tender(Map<String, dynamic> raw) {
    final t = raw['tender'];
    if (t is Map) return t.cast<String, dynamic>();
    if (t is List && t.isNotEmpty && t.first is Map) {
      return (t.first as Map).cast<String, dynamic>();
    }
    return {};
  }

  /// Convierte Timestamp Firestore `{_seconds, _nanoseconds}` o ISO string a DateTime?.
  DateTime? _toDate(dynamic v) {
    if (v == null) return null;
    if (v is Map) {
      final s = v['_seconds'] ?? v['seconds'];
      if (s != null) return DateTime.fromMillisecondsSinceEpoch((s as num).toInt() * 1000);
    }
    if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
    return null;
  }

  String _fmtDate(dynamic v) {
    final dt = _toDate(v);
    if (dt == null) return 'S/F';
    return '${dt.day.toString().padLeft(2, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.year}';
  }

  Widget _panelInformacion() {
    final raw = widget.rawData;
    final tender = _tender(raw);

    // buyer: nivel raíz o dentro de parties
    Map<String, dynamic> buyer = {};
    if (raw['buyer'] is Map) {
      buyer = (raw['buyer'] as Map).cast<String, dynamic>();
    } else {
      final parties = (raw['parties'] as List?) ?? [];
      for (final p in parties) {
        if (p is Map) {
          final roles = p['roles'];
          if (roles is List && (roles.contains('buyer') || roles.contains('procuringEntity'))) {
            buyer = p.cast<String, dynamic>();
            break;
          }
        }
      }
    }

    final value = tender['value'] is Map
        ? (tender['value'] as Map).cast<String, dynamic>()
        : <String, dynamic>{};
    final tenderPeriod = tender['tenderPeriod'] is Map
        ? (tender['tenderPeriod'] as Map).cast<String, dynamic>()
        : <String, dynamic>{};
    final enquiryPeriod = tender['enquiryPeriod'] is Map
        ? (tender['enquiryPeriod'] as Map).cast<String, dynamic>()
        : <String, dynamic>{};
    final items = tender['items'] is List
        ? (tender['items'] as List).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList()
        : <Map<String, dynamic>>[];
    final awards = raw['awards'] is List
        ? (raw['awards'] as List).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList()
        : <Map<String, dynamic>>[];
    final contracts = raw['contracts'] is List
        ? (raw['contracts'] as List).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList()
        : <Map<String, dynamic>>[];

    final descripcion = raw['descripcion']?.toString().isNotEmpty == true
        ? raw['descripcion'].toString()
        : (tender['description']?.toString().isNotEmpty == true ? tender['description'].toString() : 'Sin descripción');
    final monto = raw['monto']?.toString().isNotEmpty == true && raw['monto'] != 'S/M'
        ? raw['monto'].toString()
        : _formatMonto(value['amount'], value['currency']);
    final fechaPub = raw['fechaPublicacion']?.toString().isNotEmpty == true && raw['fechaPublicacion'] != 'S/F'
        ? raw['fechaPublicacion'].toString()
        : _fmtDate(tenderPeriod['startDate'] ?? raw['date']);
    final fechaCierreRaw = tenderPeriod['endDate'];
    final fechaCierre = raw['fechaCierre']?.toString().isNotEmpty == true && raw['fechaCierre'] != 'S/F'
        ? raw['fechaCierre'].toString()
        : _fmtDate(fechaCierreRaw);
    final compradorFull = raw['comprador']?.toString().isNotEmpty == true
        ? raw['comprador'].toString()
        : (buyer['name'] ?? tender['procuringEntity']?['name'] ?? '').toString();

    final vigente = LicitacionUI('', '', '', '', fechaCierre).esVigente;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Descripción
          _sectionCard(children: [
            _label('DESCRIPCIÓN DEL PROCESO'),
            Text(descripcion,
                style: GoogleFonts.inter(fontSize: 12, height: 1.6, color: const Color(0xFF334155))),
          ]),
          const SizedBox(height: 10),

          // Entidad compradora
          if (compradorFull.isNotEmpty)
            _sectionCard(children: [
              _label('ENTIDAD COMPRADORA'),
              Text(compradorFull,
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
              if ((buyer['identifier']?['id'] ?? buyer['id']) != null) ...[
                const SizedBox(height: 3),
                Text('RUT: ${buyer['identifier']?['id'] ?? buyer['id']}',
                    style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade500)),
              ],
              if (buyer['address'] is Map) ...[
                const SizedBox(height: 3),
                Text(_fmtAddress(buyer['address'] as Map),
                    style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade500)),
              ],
            ]),
          if (compradorFull.isNotEmpty) const SizedBox(height: 10),

          // Fechas
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: _sectionCard(children: [
              _label('PUBLICACIÓN'),
              Text(fechaPub,
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
            ])),
            const SizedBox(width: 8),
            Expanded(child: _sectionCard(children: [
              _label('CIERRE'),
              Text(fechaCierre,
                  style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: vigente ? const Color(0xFF1E293B) : Colors.redAccent)),
            ])),
          ]),
          const SizedBox(height: 10),

          // Consultas
          if (enquiryPeriod['endDate'] != null) ...[
            _sectionCard(children: [
              _label('PERÍODO DE CONSULTAS'),
              Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Inicio', style: GoogleFonts.inter(fontSize: 10, color: Colors.grey.shade400)),
                  Text(_fmtDate(enquiryPeriod['startDate']),
                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                ])),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Fin', style: GoogleFonts.inter(fontSize: 10, color: Colors.grey.shade400)),
                  Text(_fmtDate(enquiryPeriod['endDate']),
                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                ])),
              ]),
            ]),
            const SizedBox(height: 10),
          ],

          // Monto estimado
          _sectionCard(children: [
            _label('MONTO ESTIMADO'),
            Text(
              monto?.isNotEmpty == true ? monto! : 'S/M',
              style: GoogleFonts.inter(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: (monto == null || monto.isEmpty || monto == 'S/M')
                    ? Colors.grey.shade400
                    : const Color(0xFF059669),
                letterSpacing: -0.5,
              ),
            ),
            if (value['currency'] != null)
              Text(value['currency'].toString(),
                  style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade400)),
          ]),
          const SizedBox(height: 10),

          // Detalles técnicos
          _sectionCard(children: [
            _label('DETALLES'),
            if (_val(tender['mainProcurementCategory']) != null)
              _infoRow('Categoría', _val(tender['mainProcurementCategory'])!),
            if (_val(tender['status']) != null)
              _infoRow('Estado', _val(tender['status'])!),
            if (_val(tender['procurementMethod']) != null)
              _infoRow('Método', _val(tender['procurementMethod'])!),
            if (_val(tender['procurementMethodDetails']) != null)
              _infoRow('Modalidad', _val(tender['procurementMethodDetails'])!),
            if (_val(tender['procurementMethodRationale']) != null)
              _infoRow('Justificación', _val(tender['procurementMethodRationale'])!),
            if (tender['numberOfTenderers'] != null)
              _infoRow('Nº Oferentes', tender['numberOfTenderers'].toString()),
            if (_val(tender['submissionMethod']?.toString()) != null)
              _infoRow('Presentación', tender['submissionMethod'].toString()),
            if (_val(raw['ocid']) != null)
              _infoRow('OCID', _val(raw['ocid'])!),
          ]),

          // Ítems
          if (items.isNotEmpty) ...[
            const SizedBox(height: 10),
            _sectionCard(children: [
              _label('ÍTEMS (${items.length})'),
              ...items.take(10).map((it) => _itemRow(it)),
              if (items.length > 10)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('+ ${items.length - 10} más…',
                      style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade400)),
                ),
            ]),
          ],

          // Adjudicaciones
          if (awards.isNotEmpty) ...[
            const SizedBox(height: 10),
            _sectionCard(children: [
              _label('ADJUDICACIONES (${awards.length})'),
              ...awards.map((a) => _awardRow(a)),
            ]),
          ],

          // Contratos
          if (contracts.isNotEmpty) ...[
            const SizedBox(height: 10),
            _sectionCard(children: [
              _label('CONTRATOS (${contracts.length})'),
              ...contracts.map((c) => _contractRow(c)),
            ]),
          ],
        ],
      ),
    );
  }

  String? _val(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  String _fmtAddress(Map addr) {
    final parts = [addr['streetAddress'], addr['locality'], addr['region'], addr['countryName']]
        .whereType<String>().where((s) => s.isNotEmpty).toList();
    return parts.join(', ');
  }

  Widget _awardRow(Map<String, dynamic> award) {
    final suppliers = (award['suppliers'] as List?)
        ?.whereType<Map>()
        .map((s) => s['name']?.toString() ?? '')
        .where((s) => s.isNotEmpty)
        .join(', ') ?? '';
    final value = award['value'] is Map ? (award['value'] as Map) : null;
    final monto = value != null ? _formatMonto(value['amount'], value['currency']) : null;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 6, height: 6, margin: const EdgeInsets.only(top: 4, right: 8),
            decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle)),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (suppliers.isNotEmpty)
            Text(suppliers,
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF334155))),
          if (monto != null)
            Text(monto, style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF059669), fontWeight: FontWeight.w600)),
          if (_val(award['status']) != null)
            Text('Estado: ${award['status']}',
                style: GoogleFonts.inter(fontSize: 10, color: Colors.grey.shade400)),
        ])),
      ]),
    );
  }

  Widget _contractRow(Map<String, dynamic> contract) {
    final value = contract['value'] is Map ? (contract['value'] as Map) : null;
    final monto = value != null ? _formatMonto(value['amount'], value['currency']) : null;
    final inicio = _fmtDate(contract['period'] is Map ? (contract['period'] as Map)['startDate'] : null);
    final fin = _fmtDate(contract['period'] is Map ? (contract['period'] as Map)['endDate'] : null);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_val(contract['id']) != null)
          Text('Contrato ${contract['id']}',
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
        if (monto != null)
          Text(monto, style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF059669), fontWeight: FontWeight.w600)),
        if (inicio != 'S/F' || fin != 'S/F')
          Text('$inicio → $fin', style: GoogleFonts.inter(fontSize: 10, color: Colors.grey.shade400)),
        if (_val(contract['status']) != null)
          Text('Estado: ${contract['status']}',
              style: GoogleFonts.inter(fontSize: 10, color: Colors.grey.shade400)),
      ]),
    );
  }

  Widget _itemRow(Map<String, dynamic> item) {
    final desc =
        item['description']?.toString() ?? item['id']?.toString() ?? '—';
    final qty = item['quantity'];
    final unit = item['unit']?['name'];
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 4, right: 8),
            decoration: const BoxDecoration(
                color: Color(0xFF94A3B8), shape: BoxShape.circle),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(desc,
                    style: GoogleFonts.inter(
                        fontSize: 12, color: const Color(0xFF334155))),
                if (qty != null || unit != null)
                  Text(
                    [
                      if (qty != null) 'Cant: $qty',
                      if (unit != null) unit.toString(),
                    ].join(' '),
                    style: GoogleFonts.inter(
                        fontSize: 10, color: Colors.grey.shade400),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Panel Foro ─────────────────────────────────────────────────────────────

  Widget _panelForo() {
    if (_cargandoForo) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    final filtered = _foroQuery.isEmpty
        ? _enquiries
        : _enquiries.where((e) {
            final desc = (e['description'] ?? '').toString().toLowerCase();
            final ans  = (e['answer']      ?? '').toString().toLowerCase();
            return desc.contains(_foroQuery) || ans.contains(_foroQuery);
          }).toList();

    String? fechaStr;
    if (_foroFechaCache != null) {
      final d = _foroFechaCache!;
      fechaStr =
          '${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year} '
          '${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';
    }

    return Column(children: [
      // Barra superior: caché info + botón actualizar
      Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
        child: Row(children: [
          if (fechaStr != null) ...[
            Icon(Icons.cloud_done_outlined, size: 13, color: Colors.grey.shade400),
            const SizedBox(width: 5),
            Text('Caché: $fechaStr',
                style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade400)),
          ] else if (_foroCargado)
            Text('Sin caché', style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade400)),
          const Spacer(),
          InkWell(
            onTap: _cargandoForo ? null : () => _fetchForo(forceRefresh: true),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.refresh, size: 14, color: _primary),
                const SizedBox(width: 4),
                Text('Actualizar',
                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: _primary)),
              ]),
            ),
          ),
        ]),
      ),
      // Barra de búsqueda
      Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: TextField(
          controller: _foroSearch,
          style: GoogleFonts.inter(fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Buscar en preguntas y respuestas…',
            hintStyle: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade400),
            prefixIcon: Icon(Icons.search, size: 18, color: Colors.grey.shade400),
            suffixIcon: _foroQuery.isNotEmpty
                ? IconButton(
                    icon: Icon(Icons.close, size: 16, color: Colors.grey.shade400),
                    onPressed: () => _foroSearch.clear(),
                    padding: EdgeInsets.zero,
                  )
                : null,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.shade200)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.shade200)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _primary)),
          ),
        ),
      ),
      const Divider(height: 1, color: Color(0xFFE2E8F0)),
      // Lista
      if (_enquiries.isEmpty)
        Expanded(
          child: Center(
            child: Text(
              _foroCargado ? 'No hay consultas registradas' : 'Selecciona este tab para cargar el foro',
              style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade400),
            ),
          ),
        )
      else if (filtered.isEmpty)
        Expanded(
          child: Center(
            child: Text('Sin resultados para "$_foroQuery"',
                style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade400)),
          ),
        )
      else
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
            itemCount: filtered.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _foroItem(filtered[i]),
          ),
        ),
      // Footer contador
      Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        child: Row(children: [
          Icon(Icons.forum_outlined, size: 13, color: Colors.grey.shade400),
          const SizedBox(width: 5),
          Text(
            _foroQuery.isEmpty
                ? '${_enquiries.length} consulta${_enquiries.length != 1 ? 's' : ''}'
                : '${filtered.length} de ${_enquiries.length}',
            style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade400),
          ),
        ]),
      ),
    ]);
  }

  Widget _foroItem(Map<String, dynamic> e) {
    final pregunta    = e['description']?.toString()  ?? '';
    final respuesta   = e['answer']?.toString()        ?? '';
    final fechaP      = _fmtDate(e['date']);
    final fechaR      = _fmtDate(e['dateAnswered']);
    final tieneRespuesta = respuesta.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Pregunta
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text('P', style: GoogleFonts.inter(
                    fontSize: 10, fontWeight: FontWeight.w700, color: const Color(0xFF3B82F6))),
              ),
              const SizedBox(width: 6),
              Text(fechaP, style: GoogleFonts.inter(fontSize: 10, color: Colors.grey.shade400)),
            ]),
            const SizedBox(height: 6),
            Text(pregunta, style: GoogleFonts.inter(
                fontSize: 12, color: const Color(0xFF334155), height: 1.5)),
          ]),
        ),
        // Respuesta
        if (tieneRespuesta)
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              color: Color(0xFFF0FDF4),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
            ),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text('R', style: GoogleFonts.inter(
                      fontSize: 10, fontWeight: FontWeight.w700, color: const Color(0xFF059669))),
                ),
                const SizedBox(width: 6),
                Text(fechaR, style: GoogleFonts.inter(fontSize: 10, color: Colors.grey.shade400)),
              ]),
              const SizedBox(height: 4),
              Text(respuesta, style: GoogleFonts.inter(
                  fontSize: 12, color: const Color(0xFF166534), height: 1.5, fontWeight: FontWeight.w500)),
            ]),
          )
        else
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              color: Color(0xFFFFF7ED),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
            ),
            padding: const EdgeInsets.fromLTRB(12, 7, 12, 8),
            child: Text('Sin respuesta',
                style: GoogleFonts.inter(fontSize: 11, color: Colors.orange.shade400)),
          ),
      ]),
    );
  }

  // ── Panel Análisis ─────────────────────────────────────────────────────────

  Widget _panelAnalisis() {
    if (_cargandoIntel) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_intel == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text('No hay análisis disponible',
              style: GoogleFonts.inter(
                  fontSize: 13, color: Colors.grey.shade400)),
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        children: [
          _TarjetaEstrategiaDeep(_intel!['estrategia']),
          const SizedBox(height: 10),
          _TarjetaPermanencia(_intel!['permanencia']),
          const SizedBox(height: 10),
          _TarjetaPrediccion(_intel!['prediccion']),
          const SizedBox(height: 10),
          if ((_intel!['referencias'] as List?)?.isNotEmpty == true) ...[
            _label('REFERENCIAS DE MERCADO'),
            const SizedBox(height: 6),
            ...(_intel!['referencias'] as List)
                .map((r) => _CardReferencia(r as Map<String, dynamic>)),
          ],
        ],
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Widget _sectionCard({required List<Widget> children}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      );

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          t,
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade400,
            letterSpacing: 0.5,
          ),
        ),
      );

  Widget _infoRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Row(
          children: [
            SizedBox(
              width: 90,
              child: Text(label,
                  style: GoogleFonts.inter(
                      fontSize: 12, color: Colors.grey.shade500)),
            ),
            Expanded(
              child: Text(value,
                  style: GoogleFonts.inter(
                      fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );

  String _truncarComprador(String s) {
    for (final sep in [' | ', '|', ' - ']) {
      final i = s.indexOf(sep);
      if (i > 0) return s.substring(0, i).trim();
    }
    return s;
  }

  String? _formatMonto(dynamic amount, dynamic currency) {
    if (amount == null) return null;
    final n = (amount as num).toInt();
    final buf = StringBuffer();
    final s = n.toString();
    int c = 0;
    for (int i = s.length - 1; i >= 0; i--) {
      if (c > 0 && c % 3 == 0) buf.write('.');
      buf.write(s[i]);
      c++;
    }
    final formatted = buf.toString().split('').reversed.join('');
    final cur = currency?.toString() ?? 'CLP';
    return '$formatted $cur';
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// TARJETAS ANÁLISIS
// ══════════════════════════════════════════════════════════════════════════════

class _TarjetaEstrategiaDeep extends StatelessWidget {
  final Map<String, dynamic>? e;
  const _TarjetaEstrategiaDeep(this.e);
  @override
  Widget build(BuildContext context) {
    if (e == null) return const SizedBox();
    final prioridad = e!['Nivel_Prioridad']?.toString() ?? 'Media';
    final color = prioridad == 'Alta'
        ? const Color(0xFFEF4444)
        : const Color(0xFFF59E0B);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _boxDeco(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          _Chip(prioridad.toUpperCase(),
              color: color.withValues(alpha: 0.1), txtColor: color),
          Icon(Icons.military_tech, size: 16, color: Colors.grey.shade400),
        ]),
        const SizedBox(height: 10),
        Text(e!['Accion_Tactica']?.toString() ?? 'Analizar bases',
            style: GoogleFonts.inter(
                fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(e!['Argumento_Semantico']?.toString() ?? '—',
            style: GoogleFonts.inter(
                fontSize: 12,
                color: const Color(0xFF64748B),
                height: 1.5)),
      ]),
    );
  }
}

class _TarjetaPermanencia extends StatelessWidget {
  final Map<String, dynamic>? p;
  const _TarjetaPermanencia(this.p);
  @override
  Widget build(BuildContext context) {
    if (p == null) return const SizedBox();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _boxDeco(),
      child: Row(children: [
        Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(p!['proveedor_nombre']?.toString() ?? 'S/I',
                  style: GoogleFonts.inter(
                      fontSize: 13, fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              Text('Atrincheramiento histórico',
                  style: GoogleFonts.inter(
                      fontSize: 10, color: Colors.grey.shade400)),
            ])),
        _statCircular('${p!['anios']}', 'Años'),
      ]),
    );
  }
}

class _TarjetaPrediccion extends StatelessWidget {
  final Map<String, dynamic>? pr;
  const _TarjetaPrediccion(this.pr);
  @override
  Widget build(BuildContext context) {
    if (pr == null) return const SizedBox();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _boxDeco().copyWith(
          color: const Color(0xFFECFDF5),
          border: Border.all(color: const Color(0xFF10B981))),
      child:
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('PRÓXIMA COMPRA ESTIMADA (ML)',
            style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF059669))),
        const SizedBox(height: 8),
        Text(pr!['proxima']?.toString() ?? 'No estimada',
            style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF064E3B))),
        Text(
            'Categoría: ${pr!['Categoria_Nombre_Referencia']?.toString() ?? '—'}',
            style: GoogleFonts.inter(
                fontSize: 10, color: const Color(0xFF059669))),
      ]),
    );
  }
}

class _CardReferencia extends StatelessWidget {
  final Map<String, dynamic> d;
  const _CardReferencia(this.d);
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: _boxDeco(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(d['titulo']?.toString() ?? '—',
            style: GoogleFonts.inter(
                fontSize: 12, fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          _Chip(d['ganador']?.toString() ?? 'S/I'),
          Text('\$${d['monto_adjudicado']}',
              style: GoogleFonts.inter(
                  fontSize: 12,
                  color: const Color(0xFF059669),
                  fontWeight: FontWeight.w700)),
        ]),
      ]),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

BoxDecoration _boxDeco() => BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFE2E8F0)),
    );

class _Chip extends StatelessWidget {
  final String texto;
  final Color? color, txtColor;
  const _Chip(this.texto, {this.color, this.txtColor});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: color ?? const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(6)),
        child: Text(texto,
            style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: txtColor ?? const Color(0xFF64748B))),
      );
}

Widget _statCircular(String valor, String label) => Container(
      padding: const EdgeInsets.all(10),
      decoration: const BoxDecoration(
          color: Color(0xFFF1F5F9), shape: BoxShape.circle),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(valor,
            style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF334155))),
        Text(label,
            style:
                GoogleFonts.inter(fontSize: 8, color: Colors.grey.shade500)),
      ]),
    );
