import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:myapp/core/utils/responsive_helper.dart';
import 'package:myapp/features/proyecto/presentation/providers/detalle_proyecto_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../../core/theme/app_colors.dart';

class TabOC extends StatefulWidget {
  const TabOC({super.key});

  @override
  State<TabOC> createState() => _TabOCState();
}

class _TabOCState extends State<TabOC> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = Provider.of<DetalleProyectoProvider>(context, listen: false);
      final proyecto = provider.proyecto;
      // Cargar OCs por ID si el proyecto las tiene
      if (proyecto.idsOrdenesCompra.isNotEmpty) {
        for (final idOC in proyecto.idsOrdenesCompra) {
          if (provider.ordenesData[idOC] == null && provider.ordenesCompraLoading[idOC] != true) {
            provider.cargarOrdenCompra(idOC);
          }
        }
      } else if (provider.externalApiData == null && !provider.cargandoExternalData) {
        // Sin IDs de OC: cargar datos OCDS como fallback
        provider.cargarOcds();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<DetalleProyectoProvider>(context);
    final isMobile = ResponsiveHelper.isMobile(context);
    final proyecto = provider.proyecto;

    // Check if we have purchase order IDs to display
    final idsOC = proyecto.idsOrdenesCompra;

    if (idsOC.isEmpty && (provider.externalApiData == null ||
        ((provider.externalApiData!['contracts'] as List?)?.isEmpty ?? true))) {
      return _buildNoDataState(provider);
    }

    // If we have OC IDs, show them; otherwise try to use OCDS contracts
    if (idsOC.isNotEmpty) {
      return _buildOCFromIdsView(context, idsOC, provider, isMobile);
    }

    // Fallback to OCDS contracts from externalApiData
    final data = provider.externalApiData;
    if (data == null) {
      return _buildNoDataState(provider);
    }

    final releasesList = data['releases'] as List?;
    Map<String, dynamic>? release;

    if (releasesList != null && releasesList.isNotEmpty) {
      release = releasesList.first as Map<String, dynamic>?;
    } else if (data['contracts'] != null || data['awards'] != null) {
      release = data;
    }

    if (release == null) {
      return _buildNoDataState(provider);
    }

    final contracts = (release['contracts'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final awards = (release['awards'] as List?)?.cast<Map<String, dynamic>>() ?? [];

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
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          if (contracts.isEmpty)
            _buildEmptyIndicator('No se encontraron contratos registrados en OCDS')
          else
            ...contracts.map((contract) => _buildOCItem(context, contract, provider)),
          if (awards.isNotEmpty && contracts.isEmpty) ...[
            const SizedBox(height: 24),
            Text(
              'Adjudicaciones (Pre-OC)',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            ...awards.map((award) => _buildAwardItem(context, award, provider)),
          ],
        ],
      ),
    );
  }

  Widget _buildOCFromIdsView(BuildContext context, List<dynamic> idsOC, DetalleProyectoProvider provider, bool isMobile) {
    final pad = isMobile ? 16.0 : 24.0;
    return SingleChildScrollView(
      padding: EdgeInsets.all(pad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Órdenes de Compra',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (context, constraints) {
            final twoCol = constraints.maxWidth >= 560;
            final cards = idsOC.map<Widget>((idOC) {
              final idStr = idOC.toString();
              final isLoading = provider.ordenesCompraLoading[idStr] == true;
              final hasError = provider.ordenesError[idStr] != null;
              final ocData = provider.ordenesData[idStr];

              if (isLoading) {
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: 12),
                      Expanded(child: Text('Cargando OC $idStr...', style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade600))),
                    ],
                  ),
                );
              }

              if (hasError) {
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(Icons.error_outline, size: 16, color: Colors.red.shade600),
                        const SizedBox(width: 8),
                        Expanded(child: Text('Error cargando OC: $idStr', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.red.shade700))),
                      ]),
                      const SizedBox(height: 8),
                      Text(provider.ordenesError[idStr] ?? 'Error desconocido', style: GoogleFonts.inter(fontSize: 11, color: Colors.red.shade600)),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: () => provider.cargarOrdenCompra(idStr, forceRefresh: true),
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Reintentar'),
                        style: TextButton.styleFrom(foregroundColor: Colors.red.shade600, padding: EdgeInsets.zero),
                      ),
                    ],
                  ),
                );
              }

              if (ocData != null) {
                return _buildOCDataCard(context, idStr, ocData, provider);
              }

              return const SizedBox.shrink();
            }).where((w) => w is! SizedBox || (w.key != null)).toList();

            if (!twoCol) {
              return Column(
                children: cards.map((c) => Padding(padding: const EdgeInsets.only(bottom: 12), child: c)).toList(),
              );
            }

            // 2-column grid
            final rows = <Widget>[];
            for (int i = 0; i < cards.length; i += 2) {
              rows.add(Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: cards[i]),
                  if (i + 1 < cards.length) ...[
                    const SizedBox(width: 12),
                    Expanded(child: cards[i + 1]),
                  ] else
                    const Expanded(child: SizedBox()),
                ],
              ));
              if (i + 2 < cards.length) rows.add(const SizedBox(height: 12));
            }
            return Column(children: rows);
          }),
        ],
      ),
    );
  }

  Widget _buildOCDataCard(BuildContext context, String ocId, Map<String, dynamic> ocData, DetalleProyectoProvider provider) {
    final total = ocData['Total'];
    final moneda = ocData['_moneda'] ?? ocData['TipoMoneda'] ?? ocData['Moneda'] ?? 'CLP';
    final totalCLP = ocData['_totalCLP'];
    final ufValor = ocData['_ufValor'];
    final estado = ocData['Estado'];
    final proveedor = ocData['Proveedor'];
    final nombreProveedor = proveedor is Map ? (proveedor['Nombre'] ?? proveedor['RazonSocial']) : proveedor;
    final fechaCreacion = ocData['FechaCreacion'] ?? ocData['Fecha'];
    final items = (ocData['Items']?['Listado'] as List?) ?? [];
    final isUF = moneda == 'UF';

    String fmtTotal(dynamic v) {
      if (v == null) return '—';
      final n = double.tryParse(v.toString());
      if (n == null) return v.toString();
      return provider.fmt(n);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'OC: $ocId',
                        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                      ),
                      if (estado != null) ...[
                        const SizedBox(height: 3),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: _ocStatusColor(estado.toString()).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(estado.toString(), style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: _ocStatusColor(estado.toString()))),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => _launchOcUrl(ocId),
                  icon: const Icon(Icons.open_in_new, size: 18, color: AppColors.primary),
                  tooltip: 'Ver en Mercado Público',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
              ],
            ),
          ),
          // Body
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Total amount — highlight UF→CLP
                if (total != null) ...[
                  if (isUF) ...[
                    Row(children: [
                      Text('${fmtTotal(total)} UF', style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                    ]),
                    if (totalCLP != null) ...[
                      const SizedBox(height: 4),
                      Row(children: [
                        const Icon(Icons.swap_horiz, size: 14, color: AppColors.textMuted),
                        const SizedBox(width: 4),
                        Text(
                          '≈ \$ ${provider.fmt(totalCLP)} CLP',
                          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.green.shade600),
                        ),
                        if (ufValor != null) ...[
                          const SizedBox(width: 8),
                          Text('(UF = \$ ${provider.fmt(ufValor)})', style: GoogleFonts.inter(fontSize: 10, color: AppColors.textMuted)),
                        ],
                      ]),
                    ] else ...[
                      Text('Equivalente CLP no disponible', style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted)),
                    ],
                  ] else ...[
                    Text('\$ ${fmtTotal(total)} $moneda', style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                  ],
                  const SizedBox(height: 14),
                  Divider(height: 1, color: Colors.grey.shade100),
                  const SizedBox(height: 14),
                ],
                // Metadata rows
                if (nombreProveedor != null)
                  _ocInfoRow(Icons.business_outlined, 'Proveedor', nombreProveedor.toString()),
                if (fechaCreacion != null)
                  _ocInfoRow(Icons.calendar_today_outlined, 'Fecha creación', provider.fmtDateStr(fechaCreacion.toString())),
                if (ocData['FechaAceptacion'] != null)
                  _ocInfoRow(Icons.check_circle_outline, 'Aceptación', provider.fmtDateStr(ocData['FechaAceptacion'].toString())),
                if (ocData['FechaVencimiento'] != null)
                  _ocInfoRow(Icons.event_outlined, 'Vencimiento', provider.fmtDateStr(ocData['FechaVencimiento'].toString())),
                if (ocData['NumeroLicitacion'] != null)
                  _ocInfoRow(Icons.tag, 'Licitación', ocData['NumeroLicitacion'].toString()),
                if (ocData['Unidad']?['Nombre'] != null)
                  _ocInfoRow(Icons.account_balance_outlined, 'Unidad compradora', ocData['Unidad']['Nombre'].toString()),
                // Items
                if (items.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Divider(height: 1, color: Colors.grey.shade100),
                  const SizedBox(height: 12),
                  Text('${items.length} ítem(s)', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
                  const SizedBox(height: 8),
                  ...items.take(5).map((item) {
                    final itemMap = item is Map ? item as Map<String, dynamic> : <String, dynamic>{};
                    final nombre = itemMap['NombreProducto'] ?? itemMap['Nombre'] ?? itemMap['Descripcion'] ?? 'Ítem';
                    final cantidad = itemMap['Cantidad'];
                    final precioUnit = itemMap['PrecioUnitario'] ?? itemMap['Precio'];
                    final itemMoneda = ocData['_moneda'] ?? itemMap['Moneda'] ?? moneda;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Container(width: 4, height: 4, margin: const EdgeInsets.only(right: 8, top: 2), decoration: BoxDecoration(color: Colors.grey.shade300, shape: BoxShape.circle)),
                          Expanded(child: Text(nombre.toString(), style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary), overflow: TextOverflow.ellipsis)),
                          if (cantidad != null) ...[
                            const SizedBox(width: 8),
                            Text('x$cantidad', style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted)),
                          ],
                          if (precioUnit != null) ...[
                            const SizedBox(width: 8),
                            Text('${fmtTotal(precioUnit)} $itemMoneda', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                          ],
                        ],
                      ),
                    );
                  }),
                  if (items.length > 5)
                    Text('... y ${items.length - 5} ítem(s) más', style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted, fontStyle: FontStyle.italic)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _ocInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: AppColors.textMuted),
          const SizedBox(width: 8),
          Text('$label: ', style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted)),
          Expanded(child: Text(value, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textPrimary))),
        ],
      ),
    );
  }

  Color _ocStatusColor(String estado) {
    final e = estado.toLowerCase();
    if (e.contains('acept') || e.contains('recep') || e.contains('recib')) return Colors.green;
    if (e.contains('cancel') || e.contains('rechaz')) return Colors.red;
    if (e.contains('pend') || e.contains('enviad')) return Colors.orange;
    return AppColors.primary;
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
              backgroundColor: AppColors.primary,
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
          colors: [AppColors.primary, Color(0xFF0051FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
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
              color: AppColors.textPrimary,
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
                    color: AppColors.primary,
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
              color: AppColors.textBody,
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
                  color: AppColors.textSecondary,
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
            color: AppColors.textSecondary,
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
        return AppColors.primary;
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
