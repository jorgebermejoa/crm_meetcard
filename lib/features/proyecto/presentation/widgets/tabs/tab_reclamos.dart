import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:myapp/features/proyecto/domain/entities/proyecto_entity.dart';
import 'package:myapp/services/upload_service.dart';
import 'package:myapp/features/proyecto/presentation/providers/detalle_proyecto_provider.dart';
import 'package:web/web.dart' as web;

class TabReclamos extends StatelessWidget {
  const TabReclamos({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DetalleProyectoProvider>(
      builder: (context, provider, child) {
        final reclamos = provider.proyecto.reclamos;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (reclamos.isEmpty)
              _buildEmptyState()
            else
              _buildReclamosList(context, reclamos, provider),
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
            Icons.gavel_outlined,
            size: 36,
            color: Colors.grey.shade200,
          ),
          const SizedBox(height: 8),
          Text(
            'Sin reclamos registrados',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: Colors.grey.shade400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReclamosList(BuildContext context, List<ReclamoEntity> reclamos, DetalleProyectoProvider provider) {
    return Column(
      children: reclamos.map((r) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: ReclamoCard(reclamo: r),
      )).toList(),
    );
  }

  Widget _buildAddButton(BuildContext context, DetalleProyectoProvider provider) {
    return InkWell(
      onTap: () => _mostrarPopupAgregarReclamo(context, provider),
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
              'Registrar reclamo',
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

  Future<void> _mostrarPopupAgregarReclamo(BuildContext context, DetalleProyectoProvider provider) async {
    final descCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    DateTime? fechaReclamo;
    PickedFile? pickedFile;
    bool uploading = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Registrar reclamo'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: descCtrl,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Descripción del reclamo', hintText: 'Ej: Incumplimiento en plazo de entrega'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: urlCtrl,
                decoration: const InputDecoration(
                  labelText: 'Enlace a Mercado Público (opcional)',
                  hintText: 'https://www.mercadopublico.cl/...',
                  prefixIcon: Icon(Icons.link, size: 18),
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                title: Text(fechaReclamo == null ? 'Seleccionar fecha' : provider.fmtDateStr(fechaReclamo!.toIso8601String())),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: DateTime.now(),
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) setS(() => fechaReclamo = picked);
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
                    storagePath: 'proyectos/${provider.proyecto.id}/reclamos',
                  );
                }
                
                await provider.addReclamo(
                  ReclamoEntity(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    descripcion: desc,
                    fechaReclamo: fechaReclamo ?? DateTime.now(),
                    documentos: url != null ? [DocumentoEntity(tipo: 'Reclamo', url: url, nombre: pickedFile!.name)] : [],
                    urlFicha: urlCtrl.text.trim().isNotEmpty ? urlCtrl.text.trim() : null,
                  ),
                );
                
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: uploading 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) 
                : const Text('Registrar'),
            ),
          ],
        ),
      ),
    );
  }
}

class ReclamoCard extends StatefulWidget {
  final ReclamoEntity reclamo;

  const ReclamoCard({super.key, required this.reclamo});

  @override
  State<ReclamoCard> createState() => _ReclamoCardState();
}

class _ReclamoCardState extends State<ReclamoCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final provider = context.read<DetalleProyectoProvider>();
    final r = widget.reclamo;
    final respondido = r.estado == 'Respondido';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  respondido ? Icons.check_circle_outline : Icons.pending_outlined,
                  size: 16,
                  color: respondido ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 8),
                Text(
                  r.estado,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: respondido ? Colors.green : Colors.orange,
                  ),
                ),
                const Spacer(),
                Text(
                  provider.fmtDateStr(r.fechaReclamo?.toIso8601String()),
                  style: GoogleFonts.inter(fontSize: 11, color: Colors.grey),
                ),
                IconButton(
                  onPressed: () => provider.deleteReclamo(r.id),
                  icon: const Icon(Icons.close, size: 14),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              r.descripcion,
              maxLines: _expanded ? null : 3,
              overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
              style: GoogleFonts.inter(fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: () => setState(() => _expanded = !_expanded),
            child: Text(_expanded ? 'Ver menos' : 'Ver más', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF007AFF))),
          ),
          if (_expanded) ...[
             const Divider(height: 1, indent: 16, endIndent: 16),
             const SizedBox(height: 12),
             Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('DOCUMENTOS', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.grey.shade400, letterSpacing: 1)),
                    const SizedBox(height: 8),
                    if (r.documentos.isEmpty)
                      Text('No hay documentos adjuntos', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade400, fontStyle: FontStyle.italic))
                    else
                      ...r.documentos.map((doc) => MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () {
                            web.window.open(doc.url, '_blank');
                          },
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEBF5FF),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFC2E0FF)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.description_outlined, size: 14, color: Color(0xFF007AFF)),
                                const SizedBox(width: 8),
                                Flexible(child: Text(doc.nombre ?? 'Ver ficha', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF007AFF), fontWeight: FontWeight.w600))),
                              ],
                            ),
                          ),
                        ),
                      )),
                    const SizedBox(height: 12),
                    Text('ENLACE EXTERNO', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.grey.shade400, letterSpacing: 1)),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () {
                        final url = r.urlFicha ?? 'https://www.mercadopublico.cl/portal/modules/site/reclamos/FichaReclamo.aspx?idReclamo=${r.id}';
                        web.window.open(url, '_blank');
                      },
                      child: Text(
                        r.urlFicha ?? 'Ver ficha',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: const Color(0xFF007AFF),
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
             ),
             const SizedBox(height: 16),
          ],
          if (respondido && r.descripcionRespuesta != null)
             Padding(
               padding: const EdgeInsets.all(16),
               child: Container(
                 padding: const EdgeInsets.all(12),
                 decoration: BoxDecoration(
                   color: Colors.green.shade50,
                   borderRadius: BorderRadius.circular(8),
                 ),
                 child: Column(
                   crossAxisAlignment: CrossAxisAlignment.start,
                   children: [
                     Text('Respuesta:', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12)),
                     const SizedBox(height: 4),
                     Text(r.descripcionRespuesta!, style: GoogleFonts.inter(fontSize: 13)),
                   ],
                 ),
               ),
             ),
        ],
      ),
    );
  }
}
