import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/configuracion.dart';
import '../models/proyecto.dart';
import '../core/theme/app_colors.dart';

// ── Single-select searchable filter dialog ─────────────────────────────────────────

class FilterSearchDialog extends StatefulWidget {
  final String hint;
  final String? value;
  final List<String> items;
  final String Function(String) displayLabel;
  const FilterSearchDialog({
    super.key,
    required this.hint,
    required this.value,
    required this.items,
    required this.displayLabel,
  });
  @override
  State<FilterSearchDialog> createState() => _FilterSearchDialogState();
}

class _FilterSearchDialogState extends State<FilterSearchDialog> {
  final _ctrl = TextEditingController();
  late List<String> _filtered;

  @override
  void initState() {
    super.initState();
    _filtered = widget.items;
    _ctrl.addListener(() {
      final q = _ctrl.text.toLowerCase();
      setState(
        () => _filtered = widget.items
            .where((s) => widget.displayLabel(s).toLowerCase().contains(q))
            .toList(),
      );
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 540),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle + header – same style as bottom sheets
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
              child: Column(
                children: [
                  Center(
                    child: Container(
                      width: 32,
                      height: 3,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.hint,
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      if (widget.value != null)
                        TextButton(
                          onPressed: () => Navigator.pop(context, '\x00'),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          child: Text(
                            'Limpiar',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: Colors.red.shade400,
                            ),
                          ),
                        ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => Navigator.pop(context),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        color: Colors.grey.shade500,
                      ),
                      const SizedBox(width: 4),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                ],
              ),
            ),
            // Search input
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _ctrl,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Buscar ${widget.hint.toLowerCase()}...',
                  hintStyle: GoogleFonts.inter(
                    fontSize: 13,
                    color: Colors.grey.shade400,
                  ),
                  prefixIcon: const Icon(Icons.search, size: 18),
                  filled: true,
                  fillColor: AppColors.surfaceAlt,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: AppColors.primary,
                      width: 1.5,
                    ),
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                ),
                style: GoogleFonts.inter(fontSize: 13),
              ),
            ),
            Divider(height: 1, color: Colors.grey.shade100),
            // Results list
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _filtered.length,
                itemBuilder: (ctx, i) {
                  final item = _filtered[i];
                  final display = widget.displayLabel(item);
                  final isSelected = item == widget.value;
                  return InkWell(
                    onTap: () => Navigator.pop(context, item),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 13,
                      ),
                      color: isSelected
                          ? AppColors.primary.withValues(alpha: 0.05)
                          : null,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              display,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: isSelected
                                    ? AppColors.primary
                                    : AppColors.textPrimary,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                          if (isSelected)
                            const Icon(
                              Icons.check,
                              size: 16,
                              color: AppColors.primary,
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ── Active Filter Chip ─────────────────────────────────────────────────────────────

class ActiveFilterChip extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;

  const ActiveFilterChip({
    super.key,
    required this.label,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.primary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(width: 4),
          GestureDetector(onTap: onRemove, child: Icon(Icons.close, size: 11, color: AppColors.primary)),
        ],
      ),
    );
  }
}

// ── Picker de estado ────────────────────────────────────────────────────────────────

String _cleanInst(String raw) {
  var s = raw;
  if (s.contains('|')) s = s.substring(0, s.indexOf('|')).trim();
  const prefix = 'Unidad de compra:';
  if (s.startsWith(prefix)) s = s.substring(prefix.length).trim();
  return s;
}

class EstadoPickerSheet extends StatelessWidget {
  final Proyecto proyecto;
  final List<EstadoItem> cfgEstados;

  const EstadoPickerSheet({
    super.key,
    required this.proyecto,
    required this.cfgEstados,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Cambiar Estado',
              style: GoogleFonts.inter(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _cleanInst(proyecto.institucion),
              style: GoogleFonts.inter(
                fontSize: 13,
                color: Colors.grey.shade400,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
            ...cfgEstados.map((e) {
              final isSelected = proyecto.estadoManual == e.nombre;
              return InkWell(
                onTap: () => Navigator.pop(context, e.nombre),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  margin: const EdgeInsets.only(bottom: 4),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? e.colorValue.withValues(alpha: 0.10)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: e.colorValue,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          e.nombre,
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                            color: isSelected ? e.colorValue : AppColors.textPrimary,
                          ),
                        ),
                      ),
                      if (isSelected)
                        Icon(Icons.check_rounded, size: 18, color: e.colorValue),
                    ],
                  ),
                ),
              );
            }),
            const Divider(height: 20),
            InkWell(
              onTap: () => Navigator.pop(context, ''),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                child: Row(
                  children: [
                    Icon(Icons.autorenew_rounded, size: 16, color: Colors.grey.shade400),
                    const SizedBox(width: 12),
                    Text(
                      'Automático (según fechas del contrato)',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
