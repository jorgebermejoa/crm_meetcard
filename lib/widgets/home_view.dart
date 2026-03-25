import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../app_shell.dart';
import '../services/resumen_service.dart';
import 'app_breadcrumbs.dart';
import 'global_search_bar.dart';
import 'licitaciones_table.dart';
import 'detalle_licitacion.dart';
import 'categoria_resultados_view.dart';

class HomeView extends StatefulWidget {
  final VoidCallback? onOpenMenu;

  const HomeView({super.key, this.onOpenMenu});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView>
    with SingleTickerProviderStateMixin {
  static const _primaryColor = Color(0xFF5B21B6);
  static const _bgColor = Color(0xFFF2F2F7);

  late TabController _tabController;

  // ── Búsqueda ──────────────────────────────────────────────────────────────
  List<LicitacionUI> _licitaciones = [];
  bool _cargandoBusqueda = false;
  Map<String, dynamic>? _licitacionSeleccionada;
  bool _mostrarCerradas = false;

  // ── Resumen ───────────────────────────────────────────────────────────────
  Map<String, dynamic>? _stats;
  bool _cargandoResumen = true;
  String? _errorResumen;
  bool _disparandoIngesta = false;

  // Firestore real-time listeners para ingesta y procesamiento
  StreamSubscription<DocumentSnapshot>? _ingestaSub;
  StreamSubscription<DocumentSnapshot>? _procesamientoSub;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 1 && _licitaciones.isEmpty) {
        // noop — búsqueda carga al escribir
      }
    });
    _cargarResumen();
    _suscribirStatsEnTiempoReal();
  }

  void _suscribirStatsEnTiempoReal() {
    final db = FirebaseFirestore.instance;
    _ingestaSub = db.collection('_stats').doc('ingesta').snapshots().listen((snap) {
      if (!mounted || !snap.exists || _stats == null) return;
      final d = snap.data()!;
      final ts = (d['fecha'] as Timestamp?)?.toDate();
      final fecha = ts == null ? null : _fmtChile(ts);
      setState(() {
        _stats = {
          ..._stats!,
          'ingesta': {
            'estado': d['estado'],
            'fecha': fecha,
            'encoladas': d['encoladas'],
            'error': d['error'],
          },
        };
      });
    });
    _procesamientoSub = db.collection('_stats').doc('procesamiento').snapshots().listen((snap) {
      if (!mounted || !snap.exists || _stats == null) return;
      final d = snap.data()!;
      final ts = (d['fecha'] as Timestamp?)?.toDate();
      final fecha = ts == null ? null : _fmtChile(ts);
      setState(() {
        _stats = {
          ..._stats!,
          'procesamiento': {
            'estado': d['estado'],
            'fecha': fecha,
            'procesadas': d['procesadas'],
            'error': d['error'],
          },
        };
      });
    });
  }

  String _fmtChile(DateTime dt) {
    final local = dt.toLocal();
    final d = local.day.toString().padLeft(2, '0');
    final m = local.month.toString().padLeft(2, '0');
    final y = local.year;
    final h = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$d-$m-$y, $h:$min';
  }

  @override
  void dispose() {
    _ingestaSub?.cancel();
    _procesamientoSub?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  // ── DATA ──────────────────────────────────────────────────────────────────

  Future<void> _ejecutarBusqueda(String query) async {
    if (query.isEmpty) return;
    setState(() => _cargandoBusqueda = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      final token = await user?.getIdToken() ?? '';
      final resp = await http.get(
          Uri.parse(
              'https://us-central1-licitaciones-prod.cloudfunctions.net/buscarLicitacionesAI?q=${Uri.encodeComponent(query)}'),
          headers: {'Authorization': 'Bearer $token'});
      if (resp.statusCode == 200) {
        final decoded = json.decode(resp.body);
        final List<dynamic> data = decoded is List
            ? decoded
            : ((decoded as Map)['resultados'] as List? ?? []);
        setState(() {
          _licitaciones = data.map((item) {
            final m = item as Map<String, dynamic>;
            return LicitacionUI(
              m['id']?.toString() ?? 'S/I',
              m['titulo']?.toString() ?? 'Sin título',
              m['descripcion']?.toString() ?? 'Sin descripción',
              m['fechaPublicacion']?.toString() ?? 'S/F',
              m['fechaCierre']?.toString() ?? 'S/F',
              rawData: m,
            );
          }).toList();
        });
      }
    } catch (_) {} finally {
      setState(() => _cargandoBusqueda = false);
    }
  }

  void _limpiarBusqueda() => setState(() {
        _licitaciones = [];
        _licitacionSeleccionada = null;
        _mostrarCerradas = false;
      });

  Future<void> _cargarResumen({bool forceRefresh = false}) async {
    setState(() { _cargandoResumen = true; _errorResumen = null; });
    try {
      final data = await ResumenService.instance.load(forceRefresh: forceRefresh);
      if (mounted) setState(() { _stats = data; _cargandoResumen = false; });
    } catch (e) {
      if (mounted) setState(() { _errorResumen = e.toString(); _cargandoResumen = false; });
    }
  }

  Future<void> _dispararIngesta() async {
    if (_disparandoIngesta) return;
    setState(() => _disparandoIngesta = true);
    try {
      final resp = await http
          .get(Uri.parse('https://us-central1-licitaciones-prod.cloudfunctions.net/dispararIngestaOCDS'))
          .timeout(const Duration(seconds: 560));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          resp.statusCode == 200
              ? 'Cola y estadísticas actualizadas. Los conteos de licitaciones se reflejarán en ~2 min.'
              : 'Error ${resp.statusCode}',
          style: GoogleFonts.inter(fontSize: 13),
        ),
        duration: const Duration(seconds: 6),
        backgroundColor: resp.statusCode == 200 ? const Color(0xFF10B981) : Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
      if (resp.statusCode == 200) { await _cargarResumen(forceRefresh: true); }
    } catch (e) {
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: $e', style: GoogleFonts.inter(fontSize: 13)),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      )); }
    } finally {
      if (mounted) setState(() => _disparandoIngesta = false);
    }
  }

  Future<void> _calcularEstadisticas() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Calculando estadísticas, puede tardar unos minutos…'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    try {
      await http.get(Uri.parse(
          'https://us-central1-licitaciones-prod.cloudfunctions.net/calcularEstadisticas'));
      await _cargarResumen(forceRefresh: true);
    } catch (_) {}
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, constraints) {
      final isMobile = constraints.maxWidth < 700;
      final hPad = isMobile ? 20.0 : 32.0;

      return Scaffold(
        backgroundColor: _bgColor,
        appBar: buildBreadcrumbAppBar(
          context: context,
          hPad: hPad,
          onOpenMenu: openAppDrawer,
          crumbs: [BreadcrumbItem('Inicio')],
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _buildMain(hPad, isMobile),
                  ),
                  if (!isMobile && _licitacionSeleccionada != null)
                    DetalleLicitacionSidebar(
                      rawData: _licitacionSeleccionada!,
                      onClose: () => setState(() => _licitacionSeleccionada = null),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _buildMain(double hPad, bool isMobile) {
    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Padding(
            padding: EdgeInsets.fromLTRB(hPad, 16, hPad, 48),
            child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tabs Apple style
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _tabController,
              labelStyle: GoogleFonts.inter(
                  fontSize: 13, fontWeight: FontWeight.w600),
              unselectedLabelStyle:
                  GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w400),
              labelColor: _primaryColor,
              unselectedLabelColor: Colors.grey.shade400,
              indicatorColor: _primaryColor,
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              tabs: const [
                Tab(text: 'Resumen'),
                Tab(text: 'Búsqueda'),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Tab content (no TabBarView — manual to avoid height issues in scroll)
          AnimatedBuilder(
            animation: _tabController,
            builder: (_, __) {
              if (_tabController.index == 0) {
                return _buildTabResumen(isMobile);
              }
              return _buildTabBusqueda(isMobile);
            },
          ),
        ],
            ),
          ),
        ),
      ),
    );
  }

  // ── TAB BÚSQUEDA ──────────────────────────────────────────────────────────

  Widget _buildTabBusqueda(bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GlobalSearchBar(
          onSearch: _ejecutarBusqueda,
          onClear: _limpiarBusqueda,
        ),
        const SizedBox(height: 20),
        if (_cargandoBusqueda)
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 64),
              child: CircularProgressIndicator(),
            ),
          )
        else if (_licitaciones.isEmpty)
          _buildBusquedaEmpty()
        else
          _buildResultados(isMobile),
      ],
    );
  }

  Widget _buildBusquedaEmpty() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFFF2F2F7),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.search, size: 26, color: _primaryColor),
          ),
          const SizedBox(height: 14),
          Text(
            'Busca licitaciones',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Escribe una palabra clave, ID o entidad\npara encontrar licitaciones relevantes',
            style: GoogleFonts.inter(
                fontSize: 13, color: Colors.grey.shade400, height: 1.5),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildResultados(bool isMobile) {
    final vigentes = _licitaciones.where((l) => l.esVigente).toList();
    final cerradas = _licitaciones.where((l) => !l.esVigente).toList();
    final visible = _mostrarCerradas ? _licitaciones : vigentes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Encabezado resultados ──────────────────────────────────────────
        Row(children: [
          Text(
            '${visible.length} resultado${visible.length != 1 ? 's' : ''}',
            style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _primaryColor),
          ),
          const SizedBox(width: 10),
          // Chip "ver cerradas / ocultar cerradas"
          if (cerradas.isNotEmpty)
            GestureDetector(
              onTap: () =>
                  setState(() => _mostrarCerradas = !_mostrarCerradas),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _mostrarCerradas
                      ? Colors.grey.shade200
                      : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(
                    _mostrarCerradas
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 12,
                    color: Colors.grey.shade500,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _mostrarCerradas
                        ? 'Ocultar cerradas'
                        : '+ ${cerradas.length} cerrada${cerradas.length != 1 ? 's' : ''}',
                    style: GoogleFonts.inter(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500),
                  ),
                ]),
              ),
            ),
        ]),
        const SizedBox(height: 12),
        // ── Lista ──────────────────────────────────────────────────────────
        LicitacionesTable(
          licitaciones: visible,
          selected: isMobile ? null : _licitacionSeleccionada,
          onSelected: (lic) {
            if (isMobile) {
              mostrarDetalleLicitacionSheet(context, lic);
            } else {
              setState(() => _licitacionSeleccionada = lic);
            }
          },
        ),
      ],
    );
  }

  // ── TAB RESUMEN ───────────────────────────────────────────────────────────

  Widget _buildTabResumen(bool isMobile) {
    if (_cargandoResumen) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 64),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (_errorResumen != null) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.error_outline, size: 40, color: Colors.grey.shade300),
            const SizedBox(height: 8),
            Text(_errorResumen!,
                style: GoogleFonts.inter(
                    fontSize: 13, color: Colors.grey.shade500)),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _cargarResumen,
              icon: const Icon(Icons.refresh, size: 16),
              label: Text('Reintentar', style: GoogleFonts.inter()),
            ),
          ]),
        ),
      );
    }
    if (_stats == null) return const SizedBox();

    final stats = _stats!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStatsGrid(stats, isMobile),
        const SizedBox(height: 14),
        _buildTIHero(stats, isMobile),
        const SizedBox(height: 24),
        _buildCategoriasSection(stats, isMobile),
        const SizedBox(height: 24),
        // ── Ingesta manual ────────────────────────────────────────────────
        _buildIngestaCard(stats, isMobile),
      ],
    );
  }

  Widget _buildIngestaCard(Map<String, dynamic> stats, bool isMobile) {
    final ingesta = stats['ingesta'] as Map<String, dynamic>?;
    final proc = stats['procesamiento'] as Map<String, dynamic>?;

    Widget statusRow(String label, Map<String, dynamic>? data) {
      if (data == null) {
        return Row(children: [
          Icon(Icons.remove_circle_outline, size: 12, color: Colors.grey.shade300),
          const SizedBox(width: 5),
          Text(label, style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade400)),
          const SizedBox(width: 4),
          Text('Sin datos', style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade400)),
        ]);
      }
      final estado = data['estado'] as String? ?? '';
      final esError = estado == 'error';
      final esOk = estado == 'ok' || estado == 'ok_con_errores';
      final color = esError ? const Color(0xFFEF4444) : esOk ? const Color(0xFF10B981) : const Color(0xFFF59E0B);
      final icon = esError ? Icons.error_outline : esOk ? Icons.check_circle_outline : Icons.hourglass_top_outlined;
      final fecha = data['fecha'] as String? ?? '';
      final extra = esError
          ? (data['error'] as String? ?? '')
          : esOk && data['procesadas'] != null
              ? '${data['procesadas']} procesadas'
              : esOk && data['encoladas'] != null
                  ? '${data['encoladas']} encoladas'
                  : '';

      return Row(children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 5),
        Text(label, style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
        const SizedBox(width: 4),
        if (fecha.isNotEmpty)
          Text(fecha, style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade500)),
        if (extra.isNotEmpty) ...[
          Text(' · ', style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade400)),
          Flexible(
            child: Text(extra,
                style: GoogleFonts.inter(fontSize: 11, color: esError ? const Color(0xFFEF4444) : Colors.grey.shade500),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ]);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: isMobile
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _primaryColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.cloud_download_outlined, size: 18, color: _primaryColor),
                ),
                const SizedBox(width: 12),
                Text('Buscar nuevas licitaciones',
                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B))),
              ]),
              const SizedBox(height: 8),
              statusRow('Ingesta:', ingesta),
              const SizedBox(height: 2),
              statusRow('Procesamiento:', proc),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: _disparandoIngesta
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: _primaryColor))
                    : TextButton(
                        onPressed: _dispararIngesta,
                        style: TextButton.styleFrom(
                          foregroundColor: _primaryColor,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        ),
                        child: Text('Actualizar', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
              ),
            ])
          : Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _primaryColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.cloud_download_outlined, size: 18, color: _primaryColor),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Buscar nuevas licitaciones',
                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B))),
                const SizedBox(height: 4),
                statusRow('Ingesta:', ingesta),
                const SizedBox(height: 2),
                statusRow('Procesamiento:', proc),
              ])),
              const SizedBox(width: 12),
              _disparandoIngesta
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: _primaryColor))
                  : TextButton(
                      onPressed: _dispararIngesta,
                      style: TextButton.styleFrom(
                        foregroundColor: _primaryColor,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                      child: Text('Actualizar', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
            ]),
    );
  }

  Widget _buildStatsGrid(Map<String, dynamic> stats, bool isMobile) {
    final items = [
      _ResumenStat(
        label: 'TOTAL',
        sublabel: 'licitaciones',
        value: _fmt(stats['total']),
        color: const Color(0xFF3B82F6),
        icon: Icons.article_outlined,
      ),
      _ResumenStat(
        label: '14 DÍAS',
        sublabel: 'últimos 14 días',
        value: _fmt(stats['recientes']),
        color: const Color(0xFF10B981),
        icon: Icons.today_outlined,
      ),
      _ResumenStat(
        label: 'ESTE MES',
        sublabel: 'mes en curso',
        value: _fmt(stats['esteMes']),
        color: const Color(0xFFF59E0B),
        icon: Icons.calendar_month_outlined,
      ),
    ];

    if (isMobile) {
      return Column(children: [
        Row(children: [
          Expanded(child: _statCard(items[0])),
          const SizedBox(width: 10),
          Expanded(child: _statCard(items[1])),
        ]),
        const SizedBox(height: 10),
        _statCard(items[2]),
      ]);
    }

    return Row(
      children: items.asMap().entries.map((e) => Expanded(
        child: Padding(
          padding: EdgeInsets.only(right: e.key < items.length - 1 ? 10 : 0),
          child: _statCard(e.value),
        ),
      )).toList(),
    );
  }

  Widget _statCard(_ResumenStat s) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                s.label,
                style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade400,
                    letterSpacing: 0.5),
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: s.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(s.icon, size: 14, color: s.color),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            s.value,
            style: GoogleFonts.inter(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
              color: const Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            s.sublabel,
            style: GoogleFonts.inter(
                fontSize: 11, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }

  Widget _buildTIHero(Map<String, dynamic> stats, bool isMobile) {
    final tiCount = stats['ti'] ?? 0;
    final total = stats['total'] ?? 1;
    final pct = total > 0 ? (tiCount / total * 100) : 0.0;

    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => CategoriaResultadosView(
          prefix: '43',
          nombre: 'Tecnología de la Información',
          total: (tiCount as num).toInt(),
        ),
      )),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF5B21B6), Color(0xFF4F46E5)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.computer_outlined,
                          size: 12, color: Colors.white70),
                      const SizedBox(width: 5),
                      Text(
                        'Tecnología de la Información',
                        style: GoogleFonts.inter(
                            fontSize: 11,
                            color: Colors.white70,
                            fontWeight: FontWeight.w500),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _fmt(tiCount),
                    style: GoogleFonts.inter(
                      fontSize: isMobile ? 36 : 44,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -1.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'ítems UNSPSC 43 o 81',
                    style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.55)),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${pct.toStringAsFixed(1)}%',
                  style: GoogleFonts.inter(
                    fontSize: isMobile ? 30 : 36,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -1,
                  ),
                ),
                Text(
                  'del total',
                  style: GoogleFonts.inter(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.55)),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(
                      'Ver detalle',
                      style: GoogleFonts.inter(
                          fontSize: 11,
                          color: Colors.white,
                          fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_forward,
                        size: 11, color: Colors.white),
                  ]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoriasSection(
      Map<String, dynamic> stats, bool isMobile) {
    final List<dynamic> categorias = stats['categorias'] ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CATEGORÍAS',
                  style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade400,
                      letterSpacing: 0.5),
                ),
                const SizedBox(height: 2),
                Text(
                  'Clasificación UNSPSC por área',
                  style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1E293B)),
                ),
              ],
            ),
          ),
          if (stats['ultimaActualizacion'] != null)
            Text(
              'Act: ${stats['ultimaActualizacion']}',
              style: GoogleFonts.inter(
                  fontSize: 11, color: Colors.grey.shade400),
            ),
        ]),
        const SizedBox(height: 12),
        if (categorias.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Estadísticas pendientes de calcular',
                  style: GoogleFonts.inter(
                      fontSize: 14, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: _calcularEstadisticas,
                  icon: const Icon(Icons.calculate_outlined, size: 16),
                  label: Text('Calcular ahora',
                      style: GoogleFonts.inter(fontSize: 13)),
                  style: TextButton.styleFrom(
                      foregroundColor: _primaryColor,
                      padding: EdgeInsets.zero),
                ),
              ],
            ),
          )
        else
          _buildCategoriasList(categorias, isMobile),
      ],
    );
  }

  Widget _buildCategoriasList(
      List<dynamic> categorias, bool isMobile) {
    final tiCats = categorias
        .where((c) => (c as Map<String, dynamic>)['esTI'] == true)
        .toList();
    if (tiCats.isEmpty) return const SizedBox.shrink();
    final maxVal = tiCats
        .map((c) => ((c['cantidad'] as num?)?.toDouble()) ?? 0.0)
        .fold(1.0, (a, b) => a > b ? a : b);

    return Container(
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: categorias.asMap().entries.map<Widget>((entry) {
          final cat = entry.value as Map<String, dynamic>;
          final nombre = cat['nombre'] as String;
          final cantidad = ((cat['cantidad'] as num?)?.toInt()) ?? 0;
          final esTI = cat['esTI'] == true;
          final ratio = cantidad / maxVal;
          final barColor = esTI
              ? const Color(0xFF6D28D9)
              : _primaryColor.withValues(alpha: 0.35);
          final prefix = cat['prefix'] as String;
          final isLast = entry.key == categorias.length - 1;

          return Column(children: [
            InkWell(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => CategoriaResultadosView(
                  prefix: prefix,
                  nombre: nombre,
                  total: cantidad,
                ),
              )),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                child: Row(children: [
                  SizedBox(
                    width: isMobile ? 130 : 240,
                    child: Row(children: [
                      if (esTI) ...[
                        const Icon(Icons.computer,
                            size: 13, color: Color(0xFF6D28D9)),
                        const SizedBox(width: 5),
                      ],
                      Expanded(
                        child: Text(
                          nombre,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: esTI
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: esTI
                                ? const Color(0xFF4C1D95)
                                : const Color(0xFF1E293B),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Stack(children: [
                        Container(
                            height: 16,
                            color: const Color(0xFFF2F2F7)),
                        FractionallySizedBox(
                          widthFactor: ratio,
                          child: Container(
                              height: 16, color: barColor),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 48,
                    child: Text(
                      _fmt(cantidad),
                      style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700),
                      textAlign: TextAlign.right,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right,
                      size: 16, color: Colors.grey.shade300),
                ]),
              ),
            ),
            if (!isLast)
              const Divider(height: 1, indent: 16, endIndent: 16),
          ]);
        }).toList(),
      ),
    );
  }

  // ── HELPERS ───────────────────────────────────────────────────────────────

  String _fmt(dynamic n) {
    if (n == null) return '—';
    final s = n.toString();
    final buf = StringBuffer();
    int c = 0;
    for (int i = s.length - 1; i >= 0; i--) {
      if (c > 0 && c % 3 == 0) buf.write('.');
      buf.write(s[i]);
      c++;
    }
    return buf.toString().split('').reversed.join('');
  }
}

class _ResumenStat {
  final String label;
  final String sublabel;
  final String value;
  final Color color;
  final IconData icon;
  const _ResumenStat({
    required this.label,
    required this.sublabel,
    required this.value,
    required this.color,
    required this.icon,
  });
}
