import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:myapp/core/utils/responsive_helper.dart';
import 'package:myapp/features/proyecto/presentation/providers/detalle_proyecto_provider.dart';

class TabForo extends StatefulWidget {
  const TabForo({super.key});

  @override
  State<TabForo> createState() => _TabForoState();
}

class _TabForoState extends State<TabForo> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final provider = context.read<DetalleProyectoProvider>();
    _searchController.text = provider.foroQuery;
    _searchController.addListener(() {
      provider.setForoQuery(_searchController.text);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DetalleProyectoProvider>(
      builder: (context, provider, child) {
        final isMobile = ResponsiveHelper.isMobile(context);
        final pad = isMobile ? 12.0 : 20.0;
        final filtered = provider.filteredForo;
        final enquiries = provider.foroEnquiries;

        if (provider.cargandoForo && enquiries.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 64),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }

        String? fechaStr;
        if (provider.foroFechaCache != null) {
          final d = provider.foroFechaCache!;
          fechaStr = '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
              '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
        }

        if (provider.errorMessage != null && enquiries.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, size: 48, color: Colors.red.shade200),
                  const SizedBox(height: 16),
                  Text(
                    'Error al cargar el foro',
                    style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    provider.errorMessage!,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade500),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () => provider.cargarForo(forceRefresh: true),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Reintentar'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF007AFF),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cache Bar + IA Summary Button
            Container(
              padding: EdgeInsets.symmetric(horizontal: pad, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  if (fechaStr != null) ...[
                    Icon(Icons.cloud_done_outlined, size: 13, color: Colors.grey.shade400),
                    const SizedBox(width: 4),
                    Text(
                      fechaStr,
                      style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade400),
                    ),
                  ],
                  const Spacer(),
                  IconButton(
                    icon: provider.cargandoForo
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.refresh, size: 18, color: Color(0xFF007AFF)),
                    onPressed: provider.cargandoForo ? null : () => provider.cargarForo(forceRefresh: true),
                    tooltip: 'Recargar foro',
                  ),
                  if (enquiries.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    _buildIAButton(context, provider),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Search Box
            TextField(
              controller: _searchController,
              style: GoogleFonts.inter(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Buscar en preguntas y respuestas...',
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () => _searchController.clear(),
                      )
                    : null,
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Statistics/Count
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Icon(Icons.forum_outlined, size: 13, color: Colors.grey.shade400),
                  const SizedBox(width: 6),
                  Text(
                    provider.foroQuery.isEmpty
                        ? '${enquiries.length} consultas registradas'
                        : '${filtered.length} de ${enquiries.length} resultados',
                    style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade400),
                  ),
                ],
              ),
            ),

            // IA Resume Content if exists
            if (provider.foroResumen != null)
              _buildResumenCard(context, provider.foroResumen!),

            // List of items
            if (enquiries.isEmpty)
              _buildEmptyState('No hay consultas registradas para esta licitación')
            else if (filtered.isEmpty)
              _buildEmptyState('Sin resultados para "${provider.foroQuery}"')
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: filtered.length,
                separatorBuilder: (context, index) => const SizedBox(height: 12),
                itemBuilder: (context, index) => _ForoItemCard(data: filtered[index]),
              ),
          ],
        );
      },
    );
  }

  Widget _buildIAButton(BuildContext context, DetalleProyectoProvider provider) {
    return InkWell(
      onTap: provider.cargandoResumen ? null : () => provider.generarResumenForo(),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF007AFF).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            provider.cargandoResumen
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.auto_awesome, size: 16, color: Color(0xFF007AFF)),
            const SizedBox(width: 8),
            Text(
              'Resumen IA',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF007AFF),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResumenCard(BuildContext context, String resumen) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFF007AFF).withValues(alpha: 0.05), Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF007AFF).withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, size: 16, color: Color(0xFF007AFF)),
              const SizedBox(width: 8),
              Text(
                'Resumen Inteligente del Foro',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF0056B3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            resumen,
            style: GoogleFonts.inter(
              fontSize: 13,
              height: 1.6,
              color: const Color(0xFF334155),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String msg) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(Icons.forum_outlined, size: 32, color: Colors.grey.shade200),
          const SizedBox(height: 12),
          Text(
            msg,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }
}

class _ForoItemCard extends StatelessWidget {
  final Map<String, dynamic> data;

  const _ForoItemCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final pregunta = data['description']?.toString() ?? '';
    final respuesta = data['answer']?.toString() ?? '';
    final provider = context.read<DetalleProyectoProvider>();
    final fechaP = provider.fmtDateStr(data['date']?.toString());
    final fechaR = provider.fmtDateStr(data['dateAnswered']?.toString());
    final tieneRespuesta = respuesta.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Pregunta
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _Label(text: 'P', color: const Color(0xFF3B82F6)),
                    const SizedBox(width: 8),
                    Text(
                      fechaP,
                      style: GoogleFonts.inter(fontSize: 10, color: Colors.grey.shade400),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  pregunta,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: const Color(0xFF1E293B),
                    fontWeight: FontWeight.w500,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          // Respuesta
          if (tieneRespuesta)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: const Color(0xFFF0FDF4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _Label(text: 'R', color: const Color(0xFF10B981)),
                      const SizedBox(width: 8),
                      Text(
                        fechaR,
                        style: GoogleFonts.inter(fontSize: 10, color: Colors.grey.shade400),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    respuesta,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: const Color(0xFF166534),
                      height: 1.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: const Color(0xFFFFF7ED),
              child: Text(
                'Sin respuesta oficial',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: Colors.orange.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  final Color color;

  const _Label({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}
