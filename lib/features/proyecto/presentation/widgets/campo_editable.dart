import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/utils/responsive_helper.dart';

enum TipoCampo { texto, numero, email, fecha, descripcion, url }

class CampoEditable extends StatefulWidget {
  final String label;
  final String? valor;
  final String campoDb;
  final TipoCampo tipo;
  final int maxLines;
  final bool isNumeric;
  final bool isDate;
  final bool isList;
  final Function(dynamic value)? onSave;

  const CampoEditable({
    super.key,
    required this.label,
    this.valor,
    required this.campoDb,
    this.tipo = TipoCampo.texto,
    this.maxLines = 1,
    this.isNumeric = false,
    this.isDate = false,
    this.isList = false,
    this.onSave,
  });

  @override
  State<CampoEditable> createState() => _CampoEditableState();
}

class _CampoEditableState extends State<CampoEditable> {
  bool _editando = false;
  bool _guardando = false;
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.valor ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(CampoEditable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.valor != widget.valor && !_editando) {
      _controller.text = widget.valor ?? '';
    }
  }

  Future<void> _guardar() async {
    final nuevoValor = _controller.text.trim();
    if (nuevoValor == (widget.valor ?? '')) {
      setState(() => _editando = false);
      return;
    }

    // Validaciones básicas
    if (widget.tipo == TipoCampo.email && nuevoValor.isNotEmpty && !nuevoValor.contains('@')) {
      _showError('Email no válido');
      return;
    }

    setState(() => _guardando = true);
    try {
      if (widget.onSave != null) {
        dynamic val = nuevoValor;
        if (widget.isNumeric) val = double.tryParse(nuevoValor.replaceAll('.', '').replaceAll(',', '.')) ?? 0.0;
        if (widget.isList) val = nuevoValor.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
        await widget.onSave!(val);
      }
      
      setState(() {
        _guardando = false;
        _editando = false;
      });
      
      _showSuccess('Campo actualizado');
    } catch (e) {
      setState(() => _guardando = false);
      _showError('Error al actualizar: $e');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red.shade700),
    );
  }

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.green.shade700),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveHelper.isMobile(context);
    final valueStyle = GoogleFonts.inter(
      fontSize: isMobile ? 14 : 15,
      color: const Color(0xFF1E293B),
      fontWeight: FontWeight.w500,
    );

    return InkWell(
      onTap: _guardando ? null : () => setState(() => _editando = true),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.label.toUpperCase(),
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade500,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            if (_editando)
              _buildEditor()
            else
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.valor?.isNotEmpty == true ? widget.valor! : '—',
                      style: valueStyle.copyWith(
                        color: widget.valor?.isNotEmpty == true 
                            ? const Color(0xFF1E293B) 
                            : Colors.grey.shade400,
                      ),
                      maxLines: widget.maxLines,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (!_guardando)
                    Icon(Icons.edit_outlined, size: 14, color: Colors.grey.shade400),
                  if (_guardando)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF007AFF)),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditor() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            autofocus: true,
            maxLines: widget.maxLines,
            keyboardType: _getKeyboardType(),
            style: GoogleFonts.inter(fontSize: 14),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 8),
              border: InputBorder.none,
            ),
            onSubmitted: (_) => _guardar(),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close, size: 18, color: Colors.red),
          onPressed: () => setState(() {
            _editando = false;
            _controller.text = widget.valor ?? '';
          }),
        ),
        IconButton(
          icon: const Icon(Icons.check, size: 18, color: Colors.green),
          onPressed: _guardar,
        ),
      ],
    );
  }

  TextInputType _getKeyboardType() {
    if (widget.isNumeric || widget.tipo == TipoCampo.numero) return TextInputType.number;
    if (widget.tipo == TipoCampo.email) return TextInputType.emailAddress;
    if (widget.tipo == TipoCampo.url) return TextInputType.url;
    if (widget.maxLines > 1 || widget.tipo == TipoCampo.descripcion) return TextInputType.multiline;
    return TextInputType.text;
  }
}
