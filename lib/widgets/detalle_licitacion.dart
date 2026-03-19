import 'dart:convert';
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
  static const _primary = Color(0xFF1E1B6B);
  static const _bg = Color(0xFFF2F2F7);

  Map<String, dynamic>? _intel;
  bool _cargandoIntel = false;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchIntel();
  }

  @override
  void didUpdateWidget(DetalleLicitacionSidebar old) {
    super.didUpdateWidget(old);
    if (old.rawData['id'] != widget.rawData['id']) {
      setState(() => _intel = null);
      _fetchIntel();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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

  Widget _panelInformacion() {
    final raw = widget.rawData;
    final tender = (raw['tender'] as Map?)?.cast<String, dynamic>() ?? {};
    final buyer = (raw['buyer'] as Map?)?.cast<String, dynamic>() ??
        (tender['procuringEntity'] as Map?)?.cast<String, dynamic>() ??
        {};
    final value = (tender['value'] as Map?)?.cast<String, dynamic>() ?? {};
    final items =
        (tender['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final tenderPeriod =
        (tender['tenderPeriod'] as Map?)?.cast<String, dynamic>() ?? {};

    final descripcion = raw['descripcion'] ??
        tender['description'] ??
        'Sin descripción';
    final monto = raw['monto'] ?? _formatMonto(value['amount'], value['currency']);
    final fechaPub = raw['fechaPublicacion'] ?? '';
    final fechaCierre = raw['fechaCierre'] ??
        tenderPeriod['endDate']?.toString().substring(0, 10) ??
        '';
    final compradorFull = raw['comprador'] ??
        buyer['name'] ??
        tender['procuringEntity']?['name'] ??
        '';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Descripción
          _sectionCard(children: [
            _label('DESCRIPCIÓN DEL PROCESO'),
            Text(
              descripcion.toString(),
              style: GoogleFonts.inter(
                  fontSize: 12,
                  height: 1.6,
                  color: const Color(0xFF334155)),
            ),
          ]),
          const SizedBox(height: 10),

          // Entidad
          if (compradorFull.toString().isNotEmpty)
            _sectionCard(children: [
              _label('ENTIDAD COMPRADORA'),
              Text(
                compradorFull.toString(),
                style: GoogleFonts.inter(
                    fontSize: 13, fontWeight: FontWeight.w600),
              ),
              if (buyer['id'] != null) ...[
                const SizedBox(height: 3),
                Text('RUT: ${buyer['id']}',
                    style: GoogleFonts.inter(
                        fontSize: 11, color: Colors.grey.shade500)),
              ],
            ]),
          if (compradorFull.toString().isNotEmpty) const SizedBox(height: 10),

          // Fechas + Monto
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _sectionCard(children: [
                  _label('PUBLICACIÓN'),
                  Text(fechaPub,
                      style: GoogleFonts.inter(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                ]),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _sectionCard(children: [
                  _label('CIERRE'),
                  Text(
                    fechaCierre,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: LicitacionUI('', '', '', '', fechaCierre).esVigente
                          ? const Color(0xFF1E293B)
                          : Colors.redAccent,
                    ),
                  ),
                ]),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Monto estimado
          _sectionCard(children: [
            _label('MONTO ESTIMADO'),
            Text(
              monto?.toString().isNotEmpty == true ? monto.toString() : 'S/M',
              style: GoogleFonts.inter(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: (monto == null || monto == 'S/M')
                    ? Colors.grey.shade400
                    : const Color(0xFF059669),
                letterSpacing: -0.5,
              ),
            ),
            if (value['currency'] != null)
              Text(value['currency'].toString(),
                  style: GoogleFonts.inter(
                      fontSize: 11, color: Colors.grey.shade400)),
          ]),
          const SizedBox(height: 10),

          // Detalles técnicos
          _sectionCard(children: [
            _label('DETALLES'),
            _infoRow('Categoría',
                tender['mainProcurementCategory']?.toString() ?? 'N/A'),
            _infoRow('Estado', tender['status']?.toString() ?? 'N/A'),
            _infoRow('Método',
                tender['procurementMethod']?.toString() ?? 'N/A'),
            if (tender['procurementMethodDetails'] != null)
              _infoRow('Modalidad',
                  tender['procurementMethodDetails'].toString()),
            if (tender['numberOfTenderers'] != null)
              _infoRow(
                  'Nº Oferentes', tender['numberOfTenderers'].toString()),
          ]),

          // Items
          if (items.isNotEmpty) ...[
            const SizedBox(height: 10),
            _sectionCard(children: [
              _label('ÍTEMS (${items.length})'),
              ...items.take(8).map((it) => _itemRow(it)),
              if (items.length > 8)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('+ ${items.length - 8} más…',
                      style: GoogleFonts.inter(
                          fontSize: 11, color: Colors.grey.shade400)),
                ),
            ]),
          ],
        ],
      ),
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
