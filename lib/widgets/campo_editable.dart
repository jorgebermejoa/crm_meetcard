import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

enum TipoCampo { texto, numero, fecha, multilinea, opciones, chips }

class CampoEditable extends StatelessWidget {
  final String label;
  final String valor;
  final TipoCampo tipo;
  final DateTime? valorFecha;
  final Future<void> Function(String nuevoValor) onGuardar;
  final String? placeholder;
  final String? prefijo;
  final List<String>? opciones;

  const CampoEditable({
    super.key,
    required this.label,
    required this.valor,
    required this.onGuardar,
    this.tipo = TipoCampo.texto,
    this.valorFecha,
    this.placeholder,
    this.prefijo,
    this.opciones,
  });

  @override
  Widget build(BuildContext context) {
    final isEmpty = valor.isEmpty || valor == '—';
    return InkWell(
      onTap: () => _mostrarPopup(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade400,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    isEmpty ? (placeholder ?? 'Agregar...') : valor,
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      color: isEmpty ? Colors.grey.shade300 : const Color(0xFF1E293B),
                      fontWeight: FontWeight.w400,
                    ),
                    maxLines: tipo == TipoCampo.multilinea ? 4 : 1,
                    overflow: tipo == TipoCampo.multilinea ? TextOverflow.visible : TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Icon(Icons.edit_outlined, size: 14, color: Colors.grey.shade300),
          ],
        ),
      ),
    );
  }

  void _mostrarPopup(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.25),
      builder: (ctx) => _PopupEditor(
        label: label,
        valorInicial: valor == '—' ? '' : valor,
        tipo: tipo,
        valorFecha: valorFecha,
        prefijo: prefijo,
        opciones: opciones,
        onGuardar: (v) async {
          Navigator.of(ctx).pop();
          await onGuardar(v);
        },
      ),
    );
  }
}

class _PopupEditor extends StatefulWidget {
  final String label;
  final String valorInicial;
  final TipoCampo tipo;
  final DateTime? valorFecha;
  final String? prefijo;
  final List<String>? opciones;
  final Future<void> Function(String) onGuardar;

  const _PopupEditor({
    required this.label,
    required this.valorInicial,
    required this.tipo,
    required this.onGuardar,
    this.valorFecha,
    this.prefijo,
    this.opciones,
  });

  @override
  State<_PopupEditor> createState() => _PopupEditorState();
}

class _PopupEditorState extends State<_PopupEditor> {
  late final TextEditingController _ctrl;
  DateTime? _fecha;
  String? _opcionSeleccionada;
  late Set<String> _selectedChips;
  bool _guardando = false;

  static const _primaryColor = Color(0xFF1E1B6B);

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.valorInicial);
    _fecha = widget.valorFecha;
    _opcionSeleccionada = widget.valorInicial.isNotEmpty ? widget.valorInicial : null;
    _selectedChips = widget.valorInicial.isEmpty
        ? {}
        : widget.valorInicial.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toSet();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    setState(() => _guardando = true);
    final String v;
    if (widget.tipo == TipoCampo.fecha) {
      v = _fecha?.toIso8601String() ?? '';
    } else if (widget.tipo == TipoCampo.opciones) {
      v = _opcionSeleccionada ?? '';
    } else if (widget.tipo == TipoCampo.chips) {
      v = _selectedChips.join(', ');
    } else {
      v = _ctrl.text.trim();
    }
    await widget.onGuardar(v);
  }

  String _formatFecha(DateTime? d) {
    if (d == null) return 'Seleccionar fecha';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      // insetPadding keeps it away from screen edges on mobile;
      // SizedBox(width) caps it on desktop
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      elevation: 0,
      child: SizedBox(
        width: 420,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.label,
                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.grey.shade400, letterSpacing: 0.3),
              ),
              const SizedBox(height: 4),
              Text(
                'Editar',
                style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B)),
              ),
              const SizedBox(height: 18),
              if (widget.tipo == TipoCampo.fecha)
                GestureDetector(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _fecha ?? DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2040),
                      builder: (ctx, child) => Theme(
                        data: Theme.of(ctx).copyWith(colorScheme: const ColorScheme.light(primary: _primaryColor)),
                        child: child!,
                      ),
                    );
                    if (picked != null) setState(() => _fecha = picked);
                  },
                  child: Container(
                    height: 50,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2F2F7),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today_outlined, size: 16, color: _fecha != null ? _primaryColor : Colors.grey.shade400),
                        const SizedBox(width: 10),
                        Text(
                          _formatFecha(_fecha),
                          style: GoogleFonts.inter(fontSize: 15, color: _fecha != null ? const Color(0xFF1E293B) : Colors.grey.shade400),
                        ),
                      ],
                    ),
                  ),
                )
              else if (widget.tipo == TipoCampo.chips && widget.opciones != null)
                _buildChips()
              else if (widget.tipo == TipoCampo.opciones && widget.opciones != null)
                _buildOpciones()
              else
                TextField(
                  controller: _ctrl,
                  autofocus: true,
                  keyboardType: widget.tipo == TipoCampo.numero ? TextInputType.number : (widget.tipo == TipoCampo.multilinea ? TextInputType.multiline : TextInputType.text),
                  maxLines: widget.tipo == TipoCampo.multilinea ? 4 : 1,
                  style: GoogleFonts.inter(fontSize: 15, color: const Color(0xFF1E293B)),
                  decoration: InputDecoration(
                    prefixText: widget.prefijo,
                    prefixStyle: GoogleFonts.inter(fontSize: 15, color: Colors.grey.shade600),
                    filled: true,
                    fillColor: const Color(0xFFF2F2F7),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _primaryColor, width: 1.5)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  ),
                ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: _guardando ? null : () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        backgroundColor: const Color(0xFFF2F2F7),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text('Cancelar', style: GoogleFonts.inter(fontSize: 15, color: Colors.grey.shade700, fontWeight: FontWeight.w500)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _guardando ? null : _guardar,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: 0,
                      ),
                      child: _guardando
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text('Guardar', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: (widget.opciones ?? []).map((op) {
        final selected = _selectedChips.contains(op);
        return FilterChip(
          label: Text(op, style: GoogleFonts.inter(fontSize: 13, fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
          selected: selected,
          onSelected: (v) => setState(() => v ? _selectedChips.add(op) : _selectedChips.remove(op)),
          selectedColor: _primaryColor.withValues(alpha: 0.12),
          checkmarkColor: _primaryColor,
          backgroundColor: const Color(0xFFF2F2F7),
          side: BorderSide(color: selected ? _primaryColor : Colors.transparent),
          showCheckmark: true,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        );
      }).toList(),
    );
  }

  Widget _buildOpciones() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: widget.opciones!.asMap().entries.map((e) {
          final opcion = e.value;
          final selected = _opcionSeleccionada == opcion;
          final isLast = e.key == widget.opciones!.length - 1;
          return Column(
            children: [
              InkWell(
                onTap: () => setState(() => _opcionSeleccionada = opcion),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          opcion,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: selected ? _primaryColor : const Color(0xFF1E293B),
                            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ),
                      if (selected)
                        const Icon(Icons.check, size: 16, color: _primaryColor),
                    ],
                  ),
                ),
              ),
              if (!isLast)
                Divider(height: 1, color: Colors.grey.shade200),
            ],
          );
        }).toList(),
      ),
    );
  }
}
