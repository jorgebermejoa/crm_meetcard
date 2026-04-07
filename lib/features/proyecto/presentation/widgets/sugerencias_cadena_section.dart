import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../domain/entities/sugerencia_cadena_entity.dart';
import '../providers/detalle_proyecto_provider.dart';
import '../providers/sugerencias_cadena_provider.dart';
import '../../../../features/proyectos/presentation/providers/proyectos_provider.dart';

/// Sección autónoma que muestra sugerencias de encadenamiento pendientes.
/// Se monta debajo de la cadena existente en CadenaTimeline.
class SugerenciasCadenaSection extends StatefulWidget {
  final String proyectoId;

  const SugerenciasCadenaSection({super.key, required this.proyectoId});

  @override
  State<SugerenciasCadenaSection> createState() =>
      _SugerenciasCadenaSectionState();
}

class _SugerenciasCadenaSectionState extends State<SugerenciasCadenaSection> {
  late final SugerenciasCadenaProvider _provider;

  @override
  void initState() {
    super.initState();
    _provider = SugerenciasCadenaProvider(proyectoId: widget.proyectoId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _provider.cargar();
    });
  }

  @override
  void dispose() {
    _provider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<SugerenciasCadenaProvider>.value(
      value: _provider,
      child: Consumer<SugerenciasCadenaProvider>(
        builder: (context, prov, _) {
          if (prov.isLoading) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          if (prov.error != null) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('Error sugerencias: ${prov.error}',
                  style: const TextStyle(fontSize: 11, color: Colors.red)),
            );
          }
          // Solo mostramos sugerencias pendientes.
          // Las aceptadas ya aparecen en la línea de tiempo vía cargarCadena().
          final pendientes = prov.sugerencias.where((s) => s.isPendiente).toList();
          if (pendientes.isEmpty) return const SizedBox.shrink();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              _Header(count: pendientes.length),
              const SizedBox(height: 8),
              ...pendientes.map(
                (s) => _SugerenciaCard(
                  sugerencia: s,
                  onAceptar: () async {
                    await prov.aceptar(s);
                    if (context.mounted) {
                      // Refrescar cadena Y lista global para que el head-de-cadena
                      // en el listado se actualice sin necesidad de recarga manual.
                      await Future.wait([
                        context.read<DetalleProyectoProvider>().cargarCadena(),
                        context.read<ProyectosProvider>().cargar(forceRefresh: true),
                      ]);
                    }
                  },
                  onRechazar: () => prov.rechazar(s),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final int count;
  const _Header({required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xFF6366F1).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.auto_awesome_rounded,
                  size: 13, color: Color(0xFF6366F1)),
              const SizedBox(width: 4),
              Text(
                'Sugerencias de encadenamiento',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF6366F1),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Card de sugerencia ────────────────────────────────────────────────────────

class _SugerenciaCard extends StatelessWidget {
  final SugerenciaCadenaEntity sugerencia;
  final VoidCallback? onAceptar;
  final VoidCallback? onRechazar;

  const _SugerenciaCard({
    required this.sugerencia,
    this.onAceptar,
    this.onRechazar,
  });

  @override
  Widget build(BuildContext context) {
    final isPredecesor = sugerencia.isPredecesor;
    final color =
        isPredecesor ? const Color(0xFF0EA5E9) : const Color(0xFF8B5CF6);
    final bgColor = isPredecesor
        ? const Color(0xFFE0F2FE)
        : const Color(0xFFEDE9FE);
    final label = isPredecesor ? 'Predecesor' : 'Sucesor';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Tipo badge + institución
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    label,
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ),
                if (sugerencia.idProyectoRelacionado != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCFCE7),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'En sistema',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF16A34A),
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                // Score
                Text(
                  '${(sugerencia.score * 100).toStringAsFixed(0)}% relevancia',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: const Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Título
            Text(
              sugerencia.titulo,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF1E293B),
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (sugerencia.institucion.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                sugerencia.institucion,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: const Color(0xFF64748B),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 4),
            // ID contrato + modalidad
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (sugerencia.idLicitacion.isNotEmpty)
                  _InfoTag(
                    icon: Icons.tag_rounded,
                    label: sugerencia.idLicitacion,
                  ),
                if (sugerencia.modalidadCompra != null &&
                    sugerencia.modalidadCompra!.isNotEmpty)
                  _InfoTag(
                    icon: Icons.category_outlined,
                    label: _fmtModalidad(sugerencia.modalidadCompra!),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            // Fechas + monto
            Row(
              children: [
                if (sugerencia.fechaCierre != null)
                  _Chip(
                    icon: Icons.event_rounded,
                    label: _fmtDate(sugerencia.fechaCierre!),
                  ),
                if (sugerencia.monto != null) ...[
                  const SizedBox(width: 6),
                  _Chip(
                    icon: Icons.attach_money_rounded,
                    label: _fmtMonto(sugerencia.monto!),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            // Botón ver proyecto (solo si está en sistema)
            if (sugerencia.idProyectoRelacionado != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _navegarAProyecto(
                        context, sugerencia.idProyectoRelacionado!,
                        sugerencia.modalidadCompra),
                    icon: const Icon(Icons.open_in_new_rounded, size: 14),
                    label: const Text('Ver proyecto encadenado'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF6366F1),
                      side: const BorderSide(color: Color(0xFF6366F1)),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      textStyle: GoogleFonts.inter(
                          fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ),
                ),
              ),
            // Acciones: Ignorar + Encadenar
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onRechazar,
                    icon: const Icon(Icons.close_rounded, size: 14),
                    label: const Text('Ignorar'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF94A3B8),
                      side: const BorderSide(color: Color(0xFFE2E8F0)),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      textStyle: GoogleFonts.inter(
                          fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onAceptar,
                    icon: const Icon(Icons.link_rounded, size: 14),
                    label: const Text('Encadenar'),
                    style: FilledButton.styleFrom(
                      backgroundColor: color,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      textStyle: GoogleFonts.inter(
                          fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _fmtMonto(double m) {
    if (m >= 1000000) return '\$${(m / 1000000).toStringAsFixed(1)}M';
    if (m >= 1000) return '\$${(m / 1000).toStringAsFixed(0)}K';
    return '\$${m.toStringAsFixed(0)}';
  }

  String _fmtModalidad(String raw) {
    return raw
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  void _navegarAProyecto(BuildContext context, String proyectoId,
      String? modalidad) {
    if (modalidad != null && modalidad.isNotEmpty) {
      context.go('/proyectos/$modalidad/$proyectoId');
    } else {
      context.go('/proyectos/$proyectoId');
    }
  }
}

class _InfoTag extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoTag({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: const Color(0xFF64748B)),
          const SizedBox(width: 3),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF475569),
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Chip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: const Color(0xFF94A3B8)),
        const SizedBox(width: 3),
        Text(
          label,
          style: GoogleFonts.inter(
              fontSize: 11, color: const Color(0xFF64748B)),
        ),
      ],
    );
  }
}
