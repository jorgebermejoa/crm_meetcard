import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:myapp/features/proyecto/domain/entities/proyecto_entity.dart';
import 'package:myapp/services/upload_service.dart';
import 'package:myapp/features/proyecto/presentation/providers/detalle_proyecto_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class TabCertificados extends StatelessWidget {
  const TabCertificados({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DetalleProyectoProvider>(
      builder: (context, provider, child) {
        final certs = provider.proyecto.certificados;
        final proyecto = provider.proyecto;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info row
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 14,
                    color: Color(0xFF3B82F6),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Los certificados quedan asociados al proyecto: ${proyecto.idLicitacion ?? proyecto.idCotizacion ?? '(sin ID)'}',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: const Color(0xFF1D4ED8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (certs.isEmpty)
              _buildEmptyState()
            else
              _buildCertList(context, certs, provider),
            const SizedBox(height: 12),
            _buildAddButton(context, provider),
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
          Icon(
            Icons.workspace_premium_outlined,
            size: 36,
            color: Colors.grey.shade200,
          ),
          const SizedBox(height: 8),
          Text(
            'Sin certificados cargados',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: Colors.grey.shade400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCertList(BuildContext context, List<CertificadoEntity> certs, DetalleProyectoProvider provider) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: certs.length,
        separatorBuilder: (context, index) => Divider(height: 1, color: Colors.grey.shade50),
        itemBuilder: (context, index) => _buildCertItem(context, certs[index], provider),
      ),
    );
  }

  Widget _buildCertItem(BuildContext context, CertificadoEntity cert, DetalleProyectoProvider provider) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.workspace_premium_outlined,
              size: 18,
              color: Color(0xFF3B82F6),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cert.descripcion,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today_outlined,
                      size: 11,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Emisión: ${provider.fmtDateStr(cert.fechaEmision?.toIso8601String())}',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  ],
                ),
                if (cert.url?.isNotEmpty == true) ...[
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () async {
                      if (cert.url != null && cert.url!.isNotEmpty) {
                        final uri = Uri.parse(cert.url!);
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri);
                        }
                      }
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.attach_file, size: 12, color: Color(0xFF007AFF)),
                        const SizedBox(width: 4),
                        Text(
                          'Ver documento',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: const Color(0xFF007AFF),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            onPressed: () => provider.deleteCertificado(cert.id),
            icon: Icon(Icons.close, size: 14, color: Colors.grey.shade400),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildAddButton(BuildContext context, DetalleProyectoProvider provider) {
    return InkWell(
      onTap: () => _mostrarPopupAgregarCertificado(context, provider),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF007AFF).withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add, size: 16, color: Color(0xFF007AFF)),
            const SizedBox(width: 6),
            Text(
              'Agregar certificado de experiencia',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF007AFF),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _mostrarPopupAgregarCertificado(BuildContext context, DetalleProyectoProvider provider) async {
    final descCtrl = TextEditingController();
    DateTime? fechaEmision;
    PickedFile? pickedFile;
    bool uploading = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Agregar certificado'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: descCtrl,
                decoration: const InputDecoration(labelText: 'Descripción'),
              ),
              const SizedBox(height: 12),
              ListTile(
                title: Text(fechaEmision == null ? 'Seleccionar fecha' : provider.fmtDateStr(fechaEmision!.toIso8601String())),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: DateTime.now(),
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) setS(() => fechaEmision = picked);
                },
              ),
              const SizedBox(height: 12),
              ListTile(
                title: Text(pickedFile == null ? 'Adjuntar archivo (opcional)' : pickedFile!.name),
                trailing: const Icon(Icons.attach_file),
                onTap: () async {
                  final file = await UploadService.instance.pickFile();
                  if (file != null) setS(() => pickedFile = file);
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: uploading ? null : () async {
                final desc = descCtrl.text.trim();
                if (desc.isEmpty) return;
                setS(() => uploading = true);
                
                String? url;
                if (pickedFile != null) {
                  url = await UploadService.instance.upload(
                    bytes: pickedFile!.bytes,
                    filename: pickedFile!.name,
                    storagePath: 'proyectos/${provider.proyecto.id}/certificados',
                  );
                }
                
                await provider.addCertificado(
                  CertificadoEntity(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    descripcion: desc,
                    fechaEmision: fechaEmision,
                    url: url,
                  ),
                );
                
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: uploading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Agregar'),
            ),
          ],
        ),
      ),
    );
  }
}
