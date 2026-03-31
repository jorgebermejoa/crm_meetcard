import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:myapp/core/utils/responsive_helper.dart';
import 'package:myapp/features/proyecto/presentation/providers/detalle_proyecto_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class TabOC extends StatelessWidget {
  const TabOC({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<DetalleProyectoProvider>(context);
    final isMobile = ResponsiveHelper.isMobile(context);
    final data = provider.externalApiData;

    if (provider.cargandoExternalData) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 64),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (data == null) {
      return _buildNoDataState(provider);
    }

    // 2. Extract releases or handle direct release
    final releasesList = data['releases'] as List?;
    Map<String, dynamic>? release;

    if (releasesList != null && releasesList.isNotEmpty) {
      release = releasesList.first as Map<String, dynamic>?;
    } else if (data['contracts'] != null || data['awards'] != null) {
      // Data might be the release itself
      release = data;
    }

    if (release == null) {
      return _buildNoDataState(provider);
    }

    final contracts =
        (release['contracts'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final awards =
        (release['awards'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    if (contracts.isEmpty && awards.isEmpty) {
      return _buildNoDataState(provider);
    }

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSummaryCard(context, release, provider),
          const SizedBox(height: 24),
          Text(
            'Órdenes de Compra (Contratos)',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 12),
          if (contracts.isEmpty)
            _buildEmptyIndicator(
              'No se encontraron contratos registrados en OCDS',
            )
          else
            ...contracts.map(
              (contract) => _buildOCItem(context, contract, provider),
            ),

          if (awards.isNotEmpty && contracts.isEmpty) ...[
            const SizedBox(height: 24),
            Text(
              'Adjudicaciones (Pre-OC)',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 12),
            ...awards.map((award) => _buildAwardItem(context, award, provider)),
          ],
        ],
      ),
    );
  }

  Widget _buildNoDataState(DetalleProyectoProvider provider) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.shopping_cart_outlined,
            size: 48,
            color: Colors.grey.shade200,
          ),
          const SizedBox(height: 16),
          Text(
            'Sin información de Órdenes de Compra',
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Los datos se sincronizan desde Mercado Público (OCDS).',
            style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade400),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => provider.cargarOcds(forceRefresh: true),
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Consultar API'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF007AFF),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyIndicator(String message) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.grey.shade200,
          style: BorderStyle.solid,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: Colors.grey.shade400),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: Colors.grey.shade500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(
    BuildContext context,
    Map<String, dynamic> release,
    DetalleProyectoProvider provider,
  ) {
    final tender = release['tender'] as Map<String, dynamic>? ?? {};
    final value = tender['value'] as Map<String, dynamic>? ?? {};

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF007AFF), Color(0xFF0051FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF007AFF).withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.analytics_outlined,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 10),
              Text(
                'Resumen de Licitación',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            tender['title']?.toString() ?? 'Sin título',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _buildMetricItem(
                'Monto Est.',
                provider.fmt(value['amount']),
                value['currency']?.toString() ?? 'CLP',
              ),
              const Spacer(),
              _buildMetricItem(
                'Estado',
                tender['status']?.toString().toUpperCase() ?? 'S/E',
                '',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricItem(String label, String value, String unit) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
            if (unit.isNotEmpty) ...[
              const SizedBox(width: 4),
              Text(
                unit,
                style: GoogleFonts.inter(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildOCItem(
    BuildContext context,
    Map<String, dynamic> contract,
    DetalleProyectoProvider provider,
  ) {
    final value = contract['value'] as Map<String, dynamic>? ?? {};
    final status = contract['status']?.toString() ?? 'S/E';
    final id = contract['id']?.toString() ?? 'S/N';
    final date = contract['dateSigned'] ?? contract['period']?['startDate'];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _getStatusColor(status).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  status.toUpperCase(),
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: _getStatusColor(status),
                  ),
                ),
              ),
              const Spacer(),
              Text(
                'ID: $id',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: Colors.grey.shade400,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            contract['title'] ?? 'Orden de Compra / Contrato',
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildSmallInfo(
                Icons.payments_outlined,
                provider.fmt(value['amount']),
                value['currency']?.toString() ?? 'CLP',
              ),
              const SizedBox(width: 24),
              _buildSmallInfo(
                Icons.calendar_today_outlined,
                provider.fmtDateStr(date),
                '',
              ),
              const Spacer(),
              if (id != 'S/N')
                IconButton(
                  onPressed: () => _launchOcUrl(id),
                  icon: const Icon(
                    Icons.open_in_new,
                    size: 18,
                    color: Color(0xFF007AFF),
                  ),
                  tooltip: 'Ver en Mercado Público',
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAwardItem(
    BuildContext context,
    Map<String, dynamic> award,
    DetalleProyectoProvider provider,
  ) {
    final value = award['value'] as Map<String, dynamic>? ?? {};
    final status = award['status']?.toString() ?? 'S/E';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            award['title'] ?? 'Adjudicación de Licitación',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                status.toUpperCase(),
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade600,
                ),
              ),
              const Spacer(),
              Text(
                '${provider.fmt(value['amount'])} ${value['currency'] ?? ''}',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF475569),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSmallInfo(IconData icon, String text, String suffix) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.grey.shade400),
        const SizedBox(width: 6),
        Text(
          text,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF475569),
          ),
        ),
        if (suffix.isNotEmpty) ...[
          const SizedBox(width: 3),
          Text(
            suffix,
            style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade400),
          ),
        ],
      ],
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'active':
      case 'signed':
        return Colors.green;
      case 'terminated':
      case 'cancelled':
        return Colors.red;
      case 'pending':
        return Colors.orange;
      default:
        return Color(0xFF007AFF);
    }
  }

  Future<void> _launchOcUrl(String id) async {
    final url = Uri.parse(
      'https://www.mercadopublico.cl/PurchaseOrder/Modules/PO/DetailsPurchaseOrder.aspx?id=$id',
    );
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }
}
