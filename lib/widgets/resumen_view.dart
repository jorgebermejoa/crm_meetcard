import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';

import 'categoria_resultados_view.dart';

class ResumenView extends StatefulWidget {
  final VoidCallback? onOpenMenu;
  final VoidCallback? onBack;

  const ResumenView({super.key, this.onOpenMenu, this.onBack});

  @override
  State<ResumenView> createState() => _ResumenViewState();
}

class _ResumenViewState extends State<ResumenView> {
  Map<String, dynamic>? _stats;
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarEstadisticas();
  }

  Future<void> _cargarEstadisticas() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final response = await http.get(
        Uri.parse('https://us-central1-licitaciones-prod.cloudfunctions.net/obtenerResumen'),
      );
      if (response.statusCode == 200) {
        if (mounted) setState(() { _stats = json.decode(response.body); _cargando = false; });
      } else {
        if (mounted) setState(() { _error = 'Error ${response.statusCode}'; _cargando = false; });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _cargando = false; });
    }
  }

  Widget _buildAppBar(bool isMobile) {
    final hPadding = isMobile ? 20.0 : 64.0;
    return AppBar(
      backgroundColor: const Color(0xFFF8FAFC),
      elevation: 0,
      automaticallyImplyLeading: false,
      titleSpacing: 0,
      title: Padding(
        padding: EdgeInsets.symmetric(horizontal: hPadding - 8),
        child: Row(
          children: [
            if (widget.onOpenMenu != null)
              IconButton(
                icon: const Icon(Icons.menu),
                onPressed: widget.onOpenMenu,
                tooltip: 'Menú',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            if (widget.onBack != null) ...[
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onBack,
                tooltip: 'Volver',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: LayoutBuilder(builder: (context, constraints) {
      final isMobile = constraints.maxWidth < 700;
      final padding = isMobile ? 20.0 : 64.0;

      if (_cargando) {
        return Column(children: [
          _buildAppBar(isMobile),
          const Expanded(child: Center(child: CircularProgressIndicator())),
        ]);
      }
      if (_error != null) {
        return Column(children: [
          _buildAppBar(isMobile),
          Expanded(child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 48, color: Colors.grey.shade400),
                const SizedBox(height: 12),
                Text('No se pudo cargar el resumen', style: GoogleFonts.inter(color: Colors.grey.shade600)),
                const SizedBox(height: 8),
                TextButton(onPressed: _cargarEstadisticas, child: const Text('Reintentar')),
              ],
            ),
          )),
        ]);
      }

      final stats = _stats!;

      return Column(
        children: [
          _buildAppBar(isMobile),
          Expanded(
            child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: padding, vertical: isMobile ? 20 : 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Resumen General',
              style: GoogleFonts.inter(
                fontSize: isMobile ? 22 : 32,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Estadísticas del sistema de licitaciones públicas',
              style: GoogleFonts.inter(fontSize: isMobile ? 13 : 16, color: Colors.grey.shade600),
            ),
            SizedBox(height: isMobile ? 20 : 32),

            // Cards principales
            _buildCardsGrid(stats, isMobile),

            SizedBox(height: isMobile ? 24 : 36),

            // Sección TI destacada
            _buildTICard(stats, isMobile),

            SizedBox(height: isMobile ? 24 : 36),

            // Categorías
            _buildCategoriasSection(stats, isMobile),
          ],
        ),
            ),
          ),
        ],
      );
    }),
    );
  }

  Widget _buildCardsGrid(Map<String, dynamic> stats, bool isMobile) {
    final cards = [
      _StatCard(
        label: 'Total Licitaciones',
        value: _fmt(stats['total']),
        icon: Icons.article_outlined,
        color: const Color(0xFF3B82F6),
        subtitle: 'en Firestore',
      ),
      _StatCard(
        label: 'Últimos 7 días',
        value: _fmt(stats['recientes']),
        icon: Icons.today_outlined,
        color: const Color(0xFF10B981),
        subtitle: 'publicadas recientemente',
      ),
      _StatCard(
        label: 'Este Mes',
        value: _fmt(stats['esteMes']),
        icon: Icons.calendar_month_outlined,
        color: const Color(0xFFF59E0B),
        subtitle: 'mes en curso',
      ),
    ];

    if (isMobile) {
      return Column(
        children: [
          Row(
            children: [
              Expanded(child: cards[0]),
              const SizedBox(width: 12),
              Expanded(child: cards[1]),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: cards[2]),
              const SizedBox(width: 12),
              const Expanded(child: SizedBox()),
            ],
          ),
        ],
      );
    }

    return Row(
      children: cards.asMap().entries.map((e) {
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: e.key < cards.length - 1 ? 16 : 0),
            child: e.value,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTICard(Map<String, dynamic> stats, bool isMobile) {
    final tiCount = stats['ti'] ?? 0;
    final total = stats['total'] ?? 1;
    final pct = total > 0 ? (tiCount / total * 100) : 0.0;

    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => CategoriaResultadosView(
          prefix: '43',
          nombre: 'Tecnología de la Información',
          total: tiCount as int,
        ),
      )),
      child: Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6D28D9), Color(0xFF4F46E5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: const Color(0xFF6D28D9).withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 6)),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.computer_outlined, color: Colors.white70, size: 18),
                  const SizedBox(width: 8),
                  Text('Área Tecnología de la Información',
                      style: GoogleFonts.inter(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
                ]),
                const SizedBox(height: 10),
                Text(
                  _fmt(tiCount),
                  style: GoogleFonts.inter(color: Colors.white, fontSize: isMobile ? 36 : 48, fontWeight: FontWeight.bold, letterSpacing: -1.5),
                ),
                const SizedBox(height: 4),
                Text(
                  'licitaciones con ítems UNSPSC 43 (TI hardware) o 81 (servicios TI)',
                  style: GoogleFonts.inter(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          Column(
            children: [
              Text(
                '${pct.toStringAsFixed(1)}%',
                style: GoogleFonts.inter(color: Colors.white, fontSize: isMobile ? 28 : 36, fontWeight: FontWeight.bold),
              ),
              Text('del total', style: GoogleFonts.inter(color: Colors.white54, fontSize: 12)),
            ],
          ),
        ],
      ),
    ));
  }

  Widget _buildCategoriasSection(Map<String, dynamic> stats, bool isMobile) {
    final List<dynamic> categorias = stats['categorias'] ?? [];
    if (categorias.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Categorías por área', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            Row(children: [
              Icon(Icons.info_outline, size: 16, color: Colors.grey.shade400),
              const SizedBox(width: 8),
              Text('Pendiente de calcular.', style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade500)),
            ]),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _calcularEstadisticas,
              icon: const Icon(Icons.calculate_outlined, size: 16),
              label: const Text('Calcular ahora'),
              style: OutlinedButton.styleFrom(textStyle: GoogleFonts.inter(fontSize: 13)),
            ),
          ],
        ),
      );
    }

    final maxVal = categorias
        .map((c) => (c['cantidad'] as num).toDouble())
        .reduce((a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Categorías por área', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w600)),
            const Spacer(),
            if (stats['ultimaActualizacion'] != null)
              Text(
                'Act: ${stats['ultimaActualizacion']}',
                style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade400),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Clasificación UNSPSC — número de licitaciones por categoría',
          style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade500),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Column(
            children: categorias.asMap().entries.map<Widget>((entry) {
              final cat = entry.value as Map<String, dynamic>;
              final nombre = cat['nombre'] as String;
              final cantidad = (cat['cantidad'] as num).toInt();
              final esTI = cat['esTI'] == true;
              final ratio = cantidad / maxVal;
              final barColor = esTI ? const Color(0xFF8B5CF6) : const Color(0xFF93C5FD);
              final labelColor = esTI ? const Color(0xFF6D28D9) : Colors.grey.shade800;

              final prefix = cat['prefix'] as String;
              return InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => CategoriaResultadosView(
                    prefix: prefix,
                    nombre: nombre,
                    total: cantidad,
                  ),
                )),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
                  child: Row(
                    children: [
                      if (esTI)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Icon(Icons.computer, size: 14, color: const Color(0xFF8B5CF6)),
                        ),
                      SizedBox(
                        width: isMobile ? 140 : 260,
                        child: Text(
                          nombre,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: esTI ? FontWeight.w600 : FontWeight.normal,
                            color: labelColor,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Stack(children: [
                            Container(height: 18, color: Colors.grey.shade100),
                            FractionallySizedBox(
                              widthFactor: ratio,
                              child: Container(height: 18, color: barColor),
                            ),
                          ]),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 52,
                        child: Text(
                          _fmt(cantidad),
                          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.grey.shade700),
                          textAlign: TextAlign.right,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.chevron_right, size: 16, color: Colors.grey.shade400),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Future<void> _calcularEstadisticas() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Calculando estadísticas, esto puede tardar unos minutos...')),
    );
    try {
      await http.get(Uri.parse('https://us-central1-licitaciones-prod.cloudfunctions.net/calcularEstadisticas'));
      await _cargarEstadisticas();
    } catch (_) {}
  }

  String _fmt(dynamic n) {
    if (n == null) return '—';
    final str = n.toString();
    final buf = StringBuffer();
    int count = 0;
    for (int i = str.length - 1; i >= 0; i--) {
      if (count > 0 && count % 3 == 0) buf.write('.');
      buf.write(str[i]);
      count++;
    }
    return buf.toString().split('').reversed.join('');
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  label,
                  style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, size: 16, color: color),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: GoogleFonts.inter(fontSize: 30, fontWeight: FontWeight.bold, letterSpacing: -1, color: Colors.grey.shade900),
          ),
          const SizedBox(height: 2),
          Text(subtitle, style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade400)),
        ],
      ),
    );
  }
}