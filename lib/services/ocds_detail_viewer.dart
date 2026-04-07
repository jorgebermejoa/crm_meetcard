import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme/app_colors.dart';

/// Apple-style OCDS detail viewer with responsive grid layout
class OCDSDetailViewer extends StatefulWidget {
  final Map<String, dynamic> data;
  final bool isMobile;

  const OCDSDetailViewer({
    super.key,
    required this.data,
    required this.isMobile,
  });

  @override
  State<OCDSDetailViewer> createState() => _OCDSDetailViewerState();
}

class _OCDSDetailViewerState extends State<OCDSDetailViewer> {
  String searchQuery = '';
  final Map<String, bool> expandedSections = {};

  @override
  void initState() {
    super.initState();
    // Pre-expand main sections
    expandedSections['tender'] = true;
    expandedSections['parties'] = true;
    expandedSections['contracts'] = false;
    expandedSections['awards'] = false;
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: widget.isMobile ? 12 : 24,
        vertical: 16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSearchBar(),
          const SizedBox(height: 20),
          _buildMainContent(),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: TextField(
        onChanged: (value) => setState(() => searchQuery = value.toLowerCase()),
        decoration: InputDecoration(
          hintText: 'Buscar en datos OCDS...',
          hintStyle: GoogleFonts.inter(color: Colors.grey.shade400),
          prefixIcon: Icon(Icons.search, color: Colors.grey.shade400),
          suffixIcon: searchQuery.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear, color: Colors.grey.shade400),
                  onPressed: () => setState(() => searchQuery = ''),
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    final releases = (widget.data['releases'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    if (releases.isEmpty) {
      return _buildEmptyState();
    }

    final release = releases.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeaderCard(release),
        const SizedBox(height: 20),
        _buildTenderSection(release),
        const SizedBox(height: 20),
        _buildPartiesSection(release),
        const SizedBox(height: 20),
        _buildContractsSection(release),
        const SizedBox(height: 20),
        _buildAwardsSection(release),
        const SizedBox(height: 20),
        _buildMetadataSection(widget.data),
      ],
    );
  }

  Widget _buildHeaderCard(Map<String, dynamic> release) {
    final tender = release['tender'] as Map<String, dynamic>? ?? {};
    final title = tender['title']?.toString() ?? 'Licitación sin título';
    final ocid = release['ocid']?.toString() ?? 'S/N';
    final date = release['date']?.toString() ?? '';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.blue.shade600,
            Colors.blue.shade400,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withValues(alpha: 0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.description_outlined, color: Colors.white, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildHeaderMetric('OCID', ocid, Colors.white),
              const Spacer(),
              _buildHeaderMetric(
                'Publicado',
                _formatDate(date),
                Colors.white,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderMetric(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: color.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: color,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildTenderSection(Map<String, dynamic> release) {
    final tender = release['tender'] as Map<String, dynamic>? ?? {};
    if (tender.isEmpty) return const SizedBox.shrink();

    final value = tender['value'] as Map<String, dynamic>? ?? {};
    final items = (tender['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    return _buildSection(
      title: 'Licitación',
      icon: Icons.gavel_outlined,
      isExpanded: expandedSections['tender'] ?? true,
      onToggle: () => setState(
        () => expandedSections['tender'] = !(expandedSections['tender'] ?? true),
      ),
      children: [
        _buildGridOfFields([
          ('Título', tender['title']?.toString()),
          ('Estado', tender['status']?.toString()),
          ('Tipo', tender['procurementMethodDetails']?.toString()),
          ('Categoría', tender['mainProcurementCategory']?.toString()),
          ('Monto', value['amount']?.toString()),
          ('Moneda', value['currency']?.toString()),
        ]),
        if (tender['description'] != null) ...[
          const SizedBox(height: 16),
          _buildDescriptionField(
            'Descripción',
            tender['description'].toString(),
          ),
        ],
        if (items.isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildItemsList(items),
        ],
      ],
    );
  }

  Widget _buildPartiesSection(Map<String, dynamic> release) {
    final parties = (release['parties'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (parties.isEmpty) return const SizedBox.shrink();

    return _buildSection(
      title: 'Partes Involucradas',
      icon: Icons.people_outline,
      isExpanded: expandedSections['parties'] ?? true,
      onToggle: () => setState(
        () => expandedSections['parties'] = !(expandedSections['parties'] ?? true),
      ),
      children: [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: widget.isMobile ? 200 : 280,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.2,
          ),
          itemCount: parties.length,
          itemBuilder: (context, index) => _buildPartyCard(parties[index]),
        ),
      ],
    );
  }

  Widget _buildPartyCard(Map<String, dynamic> party) {
    final name = party['name']?.toString() ?? 'Parte desconocida';
    final roles = (party['roles'] as List?)?.map((r) => r.toString()).toList() ?? [];
    final id = party['id']?.toString() ?? '';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (roles.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: roles
                  .map(
                    (role) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        role,
                        style: GoogleFonts.inter(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
          if (id.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'ID: $id',
              style: GoogleFonts.inter(
                fontSize: 10,
                color: Colors.grey.shade500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildContractsSection(Map<String, dynamic> release) {
    final contracts = (release['contracts'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (contracts.isEmpty) return const SizedBox.shrink();

    return _buildSection(
      title: 'Contratos',
      icon: Icons.assignment_outlined,
      isExpanded: expandedSections['contracts'] ?? false,
      onToggle: () => setState(
        () => expandedSections['contracts'] = !(expandedSections['contracts'] ?? false),
      ),
      children: [
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: contracts.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) =>
              _buildContractCard(contracts[index], index + 1),
        ),
      ],
    );
  }

  Widget _buildContractCard(Map<String, dynamic> contract, int index) {
    final id = contract['id']?.toString() ?? 'S/N';
    final status = contract['status']?.toString() ?? 'S/E';
    final value = (contract['value'] as Map?)?.cast<String, dynamic>() ?? {};
    final amount = value['amount'];
    final currency = value['currency'];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Contrato #$index',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.green.shade700,
                ),
              ),
              const Spacer(),
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
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'ID: $id',
            style: GoogleFonts.inter(
              fontSize: 11,
              color: Colors.grey.shade600,
            ),
          ),
          if (amount != null) ...[
            const SizedBox(height: 8),
            Text(
              'Monto: ${_formatNumber(amount)} $currency',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.green.shade700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAwardsSection(Map<String, dynamic> release) {
    final awards = (release['awards'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (awards.isEmpty) return const SizedBox.shrink();

    return _buildSection(
      title: 'Adjudicaciones',
      icon: Icons.verified_outlined,
      isExpanded: expandedSections['awards'] ?? false,
      onToggle: () => setState(
        () => expandedSections['awards'] = !(expandedSections['awards'] ?? false),
      ),
      children: [
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: awards.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) => _buildAwardCard(awards[index], index + 1),
        ),
      ],
    );
  }

  Widget _buildAwardCard(Map<String, dynamic> award, int index) {
    final id = award['id']?.toString() ?? 'S/N';
    final status = award['status']?.toString() ?? 'S/E';
    final value = (award['value'] as Map?)?.cast<String, dynamic>() ?? {};

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Adjudicación #$index',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.orange.shade700,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  status.toUpperCase(),
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.orange.shade700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'ID: $id',
            style: GoogleFonts.inter(
              fontSize: 11,
              color: Colors.grey.shade600,
            ),
          ),
          if (value['amount'] != null) ...[
            const SizedBox(height: 8),
            Text(
              'Monto: ${_formatNumber(value['amount'])} ${value['currency']}',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.orange.shade700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetadataSection(Map<String, dynamic> data) {
    return _buildSection(
      title: 'Metadatos',
      icon: Icons.info_outline,
      isExpanded: expandedSections['metadata'] ?? false,
      onToggle: () => setState(
        () => expandedSections['metadata'] = !(expandedSections['metadata'] ?? false),
      ),
      children: [
        _buildGridOfFields([
          ('URI', data['uri']?.toString()),
          ('Versión', data['version']?.toString()),
          ('Publicado', data['publishedDate']?.toString()),
          ('Licencia', data['license']?.toString()),
        ]),
      ],
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required bool isExpanded,
    required VoidCallback onToggle,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onToggle,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(icon, color: Colors.blue.shade600, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    Icon(
                      isExpanded
                          ? Icons.expand_less
                          : Icons.expand_more,
                      color: Colors.grey.shade400,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (isExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: children,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGridOfFields(List<(String, String?)> fields) {
    final filtered = fields.where((f) => f.$2 != null && f.$2!.isNotEmpty).toList();
    if (filtered.isEmpty) return const SizedBox.shrink();

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: widget.isMobile ? 150 : 200,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.3,
      ),
      itemCount: filtered.length,
      itemBuilder: (context, index) => _buildFieldCard(
        filtered[index].$1,
        filtered[index].$2!,
      ),
    );
  }

  Widget _buildFieldCard(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.textBody,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDescriptionField(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: AppColors.textBody,
              height: 1.5,
            ),
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildItemsList(List<Map<String, dynamic>> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Items (${items.length})',
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 8),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) => _buildItemRow(items[index], index + 1),
        ),
      ],
    );
  }

  Widget _buildItemRow(Map<String, dynamic> item, int number) {
    final description = item['description']?.toString() ?? 'Item sin descripción';
    final quantity = item['quantity'];
    final unit = item['unit']?.toString() ?? '';

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.blue.shade100,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(
              child: Text(
                '$number',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Colors.blue.shade700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  description,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textBody,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (quantity != null)
                  Text(
                    'Cantidad: $quantity ${unit.isEmpty ? '' : unit}',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      color: Colors.grey.shade500,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 48,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 16),
          Text(
            'Sin datos OCDS disponibles',
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
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
        return Colors.blue;
    }
  }

  String _formatDate(String? date) {
    if (date == null || date.isEmpty) return 'S/F';
    try {
      final dt = DateTime.parse(date);
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return date.length > 20 ? '${date.substring(0, 20)}...' : date;
    }
  }

  String _formatNumber(dynamic value) {
    if (value == null) return '—';
    if (value is num) {
      return value.toStringAsFixed(0).replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
    }
    return value.toString();
  }
}
