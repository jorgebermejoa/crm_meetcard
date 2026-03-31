import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:myapp/features/proyecto/domain/entities/proyecto_entity.dart';
import 'package:myapp/features/proyecto/presentation/providers/detalle_proyecto_provider.dart';
import 'package:web/web.dart' as web;

class TabDocumentos extends StatelessWidget {
  const TabDocumentos({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DetalleProyectoProvider>(
      builder: (context, provider, child) {
        final docs = provider.proyecto.documentos;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info Row
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 14, color: Color(0xFF16A34A)),
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
            if (docs.isEmpty)
              _buildEmptyState()
            else
              _buildDocsList(context, docs, provider),
          ],
        );
      },
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
