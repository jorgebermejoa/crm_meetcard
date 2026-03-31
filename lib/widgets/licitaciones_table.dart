import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ── Model ─────────────────────────────────────────────────────────────────────

class LicitacionUI {
  final String id;
  final String titulo;
  final String descripcion;
  final String fechaPublicacion;
  final String fechaCierre;
  final Map<String, dynamic> rawData;

  LicitacionUI(
    this.id,
    this.titulo,
    this.descripcion,
    this.fechaPublicacion,
    this.fechaCierre, {
    this.rawData = const {},
  });

  /// Parses DD-MM-YYYY or YYYY-MM-DD or ISO strings.
  static DateTime? _parseDate(String s) {
    if (s.isEmpty || s == 'S/F') return null;
    // DD-MM-YYYY
    final dmy = RegExp(r'^(\d{2})-(\d{2})-(\d{4})$');
    final m = dmy.firstMatch(s);
    if (m != null) {
      return DateTime.tryParse('${m.group(3)}-${m.group(2)}-${m.group(1)}');
    }
    return DateTime.tryParse(s);
  }

  DateTime? get fechaCierreDate => _parseDate(fechaCierre);
  DateTime? get fechaPublicacionDate => _parseDate(fechaPublicacion);

  bool get esVigente {
    final dt = fechaCierreDate;
    if (dt == null) return true;
    return dt.isAfter(DateTime.now());
  }

  /// Days remaining (negative = overdue)
  int? get diasRestantes {
    final dt = fechaCierreDate;
    if (dt == null) return null;
    return dt.difference(DateTime.now()).inDays;
  }
}

// ── Table ─────────────────────────────────────────────────────────────────────

class LicitacionesTable extends StatefulWidget {
  final List<LicitacionUI> licitaciones;
  final Function(Map<String, dynamic>)? onSelected;
  final Map<String, dynamic>? selected;

  const LicitacionesTable({
    super.key,
    required this.licitaciones,
    this.onSelected,
    this.selected,
  });

  @override
  State<LicitacionesTable> createState() => _LicitacionesTableState();
}

class _LicitacionesTableState extends State<LicitacionesTable> {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widget.licitaciones.map((l) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _LicitacionCard(
              lic: l,
              isSelected: widget.selected?['id'] == l.id,
              onTap: widget.onSelected != null
                  ? () => widget.onSelected!(l.rawData)
                  : null,
            ),
          )).toList(),
    );
  }
}

// ── Card ──────────────────────────────────────────────────────────────────────

class _LicitacionCard extends StatelessWidget {
  final LicitacionUI lic;
  final bool isSelected;
  final VoidCallback? onTap;

  static const _primary = Color(0xFF007AFF);

  const _LicitacionCard({
    required this.lic,
    required this.isSelected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final comprador = _truncar(lic.rawData['comprador']?.toString());
    final monto = lic.rawData['monto']?.toString();
    final hasMonto = monto != null && monto.isNotEmpty && monto != 'S/M';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isSelected
              ? _primary.withValues(alpha: 0.2)
              : Colors.transparent,
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isSelected ? 0.08 : 0.03),
            blurRadius: isSelected ? 16 : 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Fila 1: ID + badge estado ──────────────────────────────
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        lic.id,
                        style: GoogleFonts.robotoMono(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF64748B)),
                      ),
                    ),
                    const Spacer(),
                    _estadoBadge(),
                  ],
                ),
                const SizedBox(height: 8),
                // ── Título ─────────────────────────────────────────────────
                Text(
                  lic.titulo,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1E293B),
                    height: 1.35,
                  ),
                ),
                // ── Comprador ──────────────────────────────────────────────
                if (comprador != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    comprador,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                        fontSize: 11, color: Colors.grey.shade500),
                  ),
                ],
                const SizedBox(height: 10),
                // ── Fila 2: fechas + monto ─────────────────────────────────
                Row(
                  children: [
                    Icon(Icons.calendar_today_outlined,
                        size: 11, color: Colors.grey.shade400),
                    const SizedBox(width: 3),
                    Text(lic.fechaPublicacion,
                        style: GoogleFonts.inter(
                            fontSize: 11, color: Colors.grey.shade500)),
                    const SizedBox(width: 10),
                    Icon(Icons.event_busy_outlined,
                        size: 11,
                        color: lic.esVigente
                            ? Colors.grey.shade400
                            : Colors.redAccent.withValues(alpha: 0.7)),
                    const SizedBox(width: 3),
                    Text(
                      lic.fechaCierre,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: lic.esVigente
                            ? Colors.grey.shade500
                            : Colors.redAccent,
                      ),
                    ),
                    const Spacer(),
                    if (hasMonto)
                      Text(
                        '\$$monto',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF059669),
                        ),
                      ),
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right,
                        size: 16, color: Colors.grey.shade300),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _estadoBadge() {
    if (lic.esVigente) {
      final dias = lic.diasRestantes;
      final label =
          dias != null && dias <= 3 ? 'Cierra en $dias día${dias == 1 ? '' : 's'}' : 'Vigente';
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFF10B981).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF059669))),
      );
    } else {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text('Cerrada',
            style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade500)),
      );
    }
  }

  String? _truncar(String? s) {
    if (s == null || s.isEmpty) return null;
    for (final sep in [' | ', '|', ' - ']) {
      final i = s.indexOf(sep);
      if (i > 0) return s.substring(0, i).trim();
    }
    return s;
  }
}
