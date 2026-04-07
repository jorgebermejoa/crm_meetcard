import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:myapp/features/proyecto/domain/entities/proyecto_entity.dart';
import 'package:myapp/features/proyecto/presentation/providers/detalle_proyecto_provider.dart';
import 'package:web/web.dart' as web;
import '../../../../../core/theme/app_colors.dart';
import '../cadena_timeline.dart' show showAumentoEditSheet;

class TabDocumentos extends StatelessWidget {
  const TabDocumentos({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DetalleProyectoProvider>(
      builder: (context, provider, child) {
        final docs = provider.proyecto.documentos;
        final aumentos = provider.proyecto.aumentos
            .where((a) => a.documentos.isNotEmpty)
            .toList()
          ..sort((a, b) => b.fechaTermino.compareTo(a.fechaTermino));

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info Row
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.successSurface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 14, color: AppColors.successDeep),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Documentos oficiales y anexos del proyecto.',
                      style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF15803D)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (docs.isEmpty && aumentos.isEmpty)
              _buildEmptyState()
            else ...[
              if (docs.isNotEmpty) _buildDocsList(context, docs, provider),
              if (aumentos.isNotEmpty) ...[
                if (docs.isNotEmpty) const SizedBox(height: 16),
                _buildSectionLabel('AUMENTOS DE CONTRATO'),
                const SizedBox(height: 8),
                _buildAumentosDocs(context, aumentos, provider),
              ],
            ],
          ],
        );
      },
    );
  }

  Widget _buildSectionLabel(String label) => Padding(
        padding: const EdgeInsets.only(left: 2),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.textMuted,
            letterSpacing: 0.5,
          ),
        ),
      );

  Widget _buildAumentosDocs(
    BuildContext context,
    List<AumentoEntity> aumentos,
    DetalleProyectoProvider provider,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: aumentos.length,
        separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade50),
        itemBuilder: (context, index) {
          final a = aumentos[index];
          return _buildAumentoDocItem(context, a, provider);
        },
      ),
    );
  }

  Widget _buildAumentoDocItem(
    BuildContext context,
    AumentoEntity aumento,
    DetalleProyectoProvider provider,
  ) {
    final isContrato = aumento.tipo == 'aumento_contrato';
    final badgeColor = isContrato ? const Color(0xFF8B5CF6) : const Color(0xFFF59E0B);
    final day = aumento.fechaTermino.day;
    final month = aumento.fechaTermino.month;
    final year = aumento.fechaTermino.year;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.expand_circle_down_outlined,
                size: 18, color: badgeColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        aumento.badgeLabel.toUpperCase(),
                        style: GoogleFonts.inter(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: badgeColor,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  'Hasta $day/$month/$year',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (aumento.descripcion?.isNotEmpty == true) ...[
                  const SizedBox(height: 2),
                  Text(
                    aumento.descripcion!,
                    style: GoogleFonts.inter(
                        fontSize: 11, color: AppColors.textMuted),
                  ),
                ],
                const SizedBox(height: 6),
                // Document chips
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: aumento.documentos.map((doc) {
                    final label = doc.nombre?.isNotEmpty == true
                        ? doc.nombre!
                        : 'Documento';
                    return GestureDetector(
                      onTap: () {
                        if (doc.url.isNotEmpty) {
                          web.window.open(doc.url, '_blank');
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceAlt,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.attach_file_rounded,
                                size: 11, color: AppColors.textMuted),
                            const SizedBox(width: 4),
                            Text(
                              label,
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          // Edit button
          IconButton(
            icon: Icon(Icons.edit_outlined,
                size: 18, color: Colors.grey.shade400),
            tooltip: 'Editar aumento',
            onPressed: () =>
                showAumentoEditSheet(context, provider, aumento),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.description_outlined, size: 36, color: Colors.grey.shade200),
          const SizedBox(height: 8),
          Text(
            'Sin documentos registrados',
            style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }

  Widget _buildDocsList(BuildContext context, List<DocumentoEntity> docs, DetalleProyectoProvider provider) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: docs.length,
        separatorBuilder: (context, index) => Divider(height: 1, color: Colors.grey.shade50),
        itemBuilder: (context, index) => _buildDocItem(context, docs[index], index, provider),
      ),
    );
  }

  Widget _buildDocItem(BuildContext context, DocumentoEntity doc, int index, DetalleProyectoProvider provider) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(8)),
        child: Icon(_getIconForType(doc.tipo), size: 18, color: const Color(0xFF4B5563)),
      ),
      title: Text(
        doc.nombre ?? 'Ver ficha ${index + 1}',
        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF1F2937)),
      ),
      subtitle: Text(doc.tipo, style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade500)),
      trailing: IconButton(
        icon: const Icon(Icons.open_in_new, size: 20),
        onPressed: () {
          if (doc.url.isNotEmpty) {
            web.window.open(doc.url, '_blank');
          }
        },
      ),
      onTap: () {
        if (doc.url.isNotEmpty) {
          web.window.open(doc.url, '_blank');
        }
      },
    );
  }

  IconData _getIconForType(String tipo) {
    if (tipo.toLowerCase().contains('pdf')) return Icons.picture_as_pdf_outlined;
    if (tipo.toLowerCase().contains('imagen') || tipo.toLowerCase().contains('jpg')) return Icons.image_outlined;
    return Icons.description_outlined;
  }
}
