import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

import '../models/proyecto.dart';
import '../services/config_service.dart';
import '../services/licitacion_api_service.dart';

class ProyectoFormDialog extends StatefulWidget {
  final bool isEditing;
  final Proyecto? proyecto;

  const ProyectoFormDialog({
    super.key,
    required this.isEditing,
    this.proyecto,
  });

  @override
  State<ProyectoFormDialog> createState() => _ProyectoFormDialogState();
}

class _ProyectoFormDialogState extends State<ProyectoFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _institucionCtrl;
  late final TextEditingController _productosCtrl;
  late final TextEditingController _valorCtrl;
  late final TextEditingController _idLicitacionCtrl;
  late final TextEditingController _idCotizacionCtrl;
  late final TextEditingController _urlConvenioCtrl;
  late final TextEditingController _notasCtrl;

  String _modalidad = 'Licitación Pública';
  DateTime? _fechaInicio;
  DateTime? _fechaTermino;
  bool _buscandoLicitacion = false;
  String? _errorBusqueda;

  List<String> _modalidades = ['Licitación Pública', 'Convenio Marco', 'Trato Directo', 'Otro'];

  static const _primaryColor = Color(0xFF5B21B6);

  @override
  void initState() {
    super.initState();
    final p = widget.proyecto;
    _institucionCtrl = TextEditingController(text: p?.institucion ?? '');
    _productosCtrl = TextEditingController(text: p?.productos ?? '');
    _valorCtrl = TextEditingController(
      text: p?.valorMensual != null ? p!.valorMensual!.toStringAsFixed(0) : '',
    );
    _idLicitacionCtrl = TextEditingController(text: p?.idLicitacion ?? '');
    _idCotizacionCtrl = TextEditingController(text: p?.idCotizacion ?? '');
    _urlConvenioCtrl = TextEditingController(text: p?.urlConvenioMarco ?? '');
    _notasCtrl = TextEditingController(text: p?.notas ?? '');
    _modalidad = p?.modalidadCompra ?? 'Licitación Pública';
    _fechaInicio = p?.fechaInicio;
    _fechaTermino = p?.fechaTermino;
    ConfigService.instance.load().then((cfg) {
      if (!mounted) return;
      setState(() {
        _modalidades = cfg.modalidades.isNotEmpty ? cfg.modalidades : _modalidades;
        if (!_modalidades.contains(_modalidad)) _modalidad = _modalidades.first;
      });
    });
  }

  @override
  void dispose() {
    _institucionCtrl.dispose();
    _productosCtrl.dispose();
    _valorCtrl.dispose();
    _idLicitacionCtrl.dispose();
    _idCotizacionCtrl.dispose();
    _urlConvenioCtrl.dispose();
    _notasCtrl.dispose();
    super.dispose();
  }

  Future<void> _buscarPorId({String type = 'tender'}) async {
    final id = _idLicitacionCtrl.text.trim();
    if (id.isEmpty) return;

    setState(() { _buscandoLicitacion = true; _errorBusqueda = null; });

    try {
      final info = await LicitacionApiService.instance.fetchLP(id, type: type);
      if (info.institucion.isNotEmpty && info.institucion != id) {
        setState(() => _institucionCtrl.text = info.institucion);
      } else {
        setState(() => _errorBusqueda = 'No se encontró la institución');
      }
    } catch (e) {
      setState(() => _errorBusqueda = 'Error al buscar: ${e.toString()}');
    } finally {
      setState(() => _buscandoLicitacion = false);
    }
  }

  Future<void> _buscarConvenio() async {
    final url = _urlConvenioCtrl.text.trim();
    if (url.isEmpty) return;

    setState(() {
      _buscandoLicitacion = true;
      _errorBusqueda = null;
    });

    try {
      final uri = Uri.parse(
        'https://us-central1-licitaciones-prod.cloudfunctions.net/obtenerDetalleConvenioMarco?url=${Uri.encodeComponent(url)}',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final comprador = data['comprador'] as String?;
        if (comprador != null && comprador.isNotEmpty) {
          setState(() => _institucionCtrl.text = comprador);
        } else {
          setState(() => _errorBusqueda = 'No se encontró la institución en la URL');
        }
      } else {
        setState(() => _errorBusqueda = 'No se pudo obtener datos (${response.statusCode})');
      }
    } catch (e) {
      setState(() => _errorBusqueda = 'Error al buscar: ${e.toString()}');
    } finally {
      setState(() => _buscandoLicitacion = false);
    }
  }

  Future<void> _pickDate({required bool isInicio}) async {
    final initial = isInicio ? (_fechaInicio ?? DateTime.now()) : (_fechaTermino ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2035),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: _primaryColor),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        if (isInicio) {
          _fechaInicio = picked;
        } else {
          _fechaTermino = picked;
        }
      });
    }
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return 'Seleccionar fecha';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    const baseUrl = 'https://us-central1-licitaciones-prod.cloudfunctions.net';

    final body = <String, dynamic>{
      'institucion': _institucionCtrl.text.trim(),
      'productos': _productosCtrl.text.trim(),
      'modalidadCompra': _modalidad,
      'completado': widget.proyecto?.completado ?? false,
    };

    if (_valorCtrl.text.trim().isNotEmpty) {
      body['valorMensual'] = double.tryParse(
            _valorCtrl.text.trim().replaceAll('.', '').replaceAll(',', '.')) ??
          0.0;
    }
    if (_fechaInicio != null) body['fechaInicio'] = _fechaInicio!.toIso8601String();
    if (_fechaTermino != null) body['fechaTermino'] = _fechaTermino!.toIso8601String();
    if (_idLicitacionCtrl.text.trim().isNotEmpty) body['idLicitacion'] = _idLicitacionCtrl.text.trim();
    if (_idCotizacionCtrl.text.trim().isNotEmpty) body['idCotizacion'] = _idCotizacionCtrl.text.trim();
    if (_urlConvenioCtrl.text.trim().isNotEmpty) body['urlConvenioMarco'] = _urlConvenioCtrl.text.trim();
    if (_notasCtrl.text.trim().isNotEmpty) body['notas'] = _notasCtrl.text.trim();

    try {
      final String endpoint;
      if (widget.isEditing && widget.proyecto != null) {
        body['id'] = widget.proyecto!.id;
        endpoint = '$baseUrl/actualizarProyecto';
      } else {
        endpoint = '$baseUrl/crearProyecto';
      }

      final response = await http.post(
        Uri.parse(endpoint),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(body),
      );

      if (response.statusCode == 200) {
        if (mounted) Navigator.of(context).pop(true);
      } else {
        final msg = json.decode(response.body)['error'] ?? response.body;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al guardar: $msg')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar: $e')),
        );
      }
    }
  }

  Future<void> _eliminar() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Eliminar proyecto', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
        content: Text('¿Estás seguro de que deseas eliminar este proyecto?', style: GoogleFonts.inter()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancelar', style: GoogleFonts.inter()),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text('Eliminar', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (confirm == true && widget.proyecto != null) {
      try {
        final response = await http.post(
          Uri.parse('https://us-central1-licitaciones-prod.cloudfunctions.net/eliminarProyecto'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'id': widget.proyecto!.id}),
        );
        if (response.statusCode == 200) {
          if (mounted) Navigator.of(context).pop('deleted');
        } else {
          final msg = json.decode(response.body)['error'] ?? response.body;
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error al eliminar: $msg')),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al eliminar: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      constraints: BoxConstraints(maxHeight: screenHeight * 0.90),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle + header
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 12, 0),
            child: Column(children: [
              Center(
                child: Container(
                  width: 32, height: 3,
                  decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: Text(
                    widget.isEditing ? 'Editar Proyecto' : 'Nuevo Proyecto',
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1E293B),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                  color: Colors.grey.shade500,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 4),
              ]),
              const SizedBox(height: 12),
              const Divider(height: 1),
            ]),
          ),
          // Form — scrollable
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(24, 20, 24, 8 + viewInsets),
              child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Modalidad de Compra
                      _fieldLabel('Modalidad de Compra *'),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue: _modalidad,
                        decoration: _inputDecoration('Seleccionar modalidad'),
                        style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF1E293B)),
                        items: _modalidades
                            .map((m) => DropdownMenuItem(value: m, child: Text(m, style: GoogleFonts.inter(fontSize: 14))))
                            .toList(),
                        onChanged: (v) => setState(() => _modalidad = v ?? _modalidad),
                        validator: (v) => v == null || v.isEmpty ? 'Requerido' : null,
                      ),
                      const SizedBox(height: 16),

                      // ID Licitación (solo si modalidad es Licitación Pública)
                      if (_modalidad == 'Licitación Pública') ...[
                        _fieldLabel('ID Licitación'),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _idLicitacionCtrl,
                                style: GoogleFonts.inter(fontSize: 14),
                                decoration: _inputDecoration('ej. 750-2-LE25'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              height: 48,
                              child: ElevatedButton.icon(
                                onPressed: _buscandoLicitacion ? null : _buscarPorId,
                                icon: _buscandoLicitacion
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      )
                                    : const Icon(Icons.search, size: 16),
                                label: Text('Buscar', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _primaryColor,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  padding: const EdgeInsets.symmetric(horizontal: 14),
                                  elevation: 0,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_errorBusqueda != null) ...[
                          const SizedBox(height: 4),
                          Text(_errorBusqueda!, style: GoogleFonts.inter(fontSize: 12, color: Colors.red.shade600)),
                        ],
                        const SizedBox(height: 16),
                      ],

                      // ID Trato Directo (solo si modalidad es Trato Directo)
                      if (_modalidad == 'Trato Directo') ...[
                        _fieldLabel('ID Trato Directo'),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _idLicitacionCtrl,
                                style: GoogleFonts.inter(fontSize: 14),
                                decoration: _inputDecoration('ej. 998-28-TD26'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              height: 48,
                              child: ElevatedButton.icon(
                                onPressed: _buscandoLicitacion ? null : () => _buscarPorId(type: 'award'),
                                icon: _buscandoLicitacion
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      )
                                    : const Icon(Icons.search, size: 16),
                                label: Text('Buscar', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _primaryColor,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  padding: const EdgeInsets.symmetric(horizontal: 14),
                                  elevation: 0,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_errorBusqueda != null) ...[
                          const SizedBox(height: 4),
                          Text(_errorBusqueda!, style: GoogleFonts.inter(fontSize: 12, color: Colors.red.shade600)),
                        ],
                        const SizedBox(height: 16),
                      ],

                      // URL Convenio Marco (solo si modalidad es Convenio Marco)
                      if (_modalidad == 'Convenio Marco') ...[
                        _fieldLabel('ID Cotización'),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _idCotizacionCtrl,
                          style: GoogleFonts.inter(fontSize: 14),
                          decoration: _inputDecoration('ej. 5802363-0824CPRD'),
                        ),
                        const SizedBox(height: 16),
                        _fieldLabel('URL Convenio Marco'),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _urlConvenioCtrl,
                                style: GoogleFonts.inter(fontSize: 14),
                                decoration: _inputDecoration('https://conveniomarco2.mercadopublico.cl/.../id/...'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              height: 48,
                              child: ElevatedButton.icon(
                                onPressed: _buscandoLicitacion ? null : _buscarConvenio,
                                icon: _buscandoLicitacion
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      )
                                    : const Icon(Icons.search, size: 16),
                                label: Text('Buscar', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _primaryColor,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  padding: const EdgeInsets.symmetric(horizontal: 14),
                                  elevation: 0,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_errorBusqueda != null) ...[
                          const SizedBox(height: 4),
                          Text(_errorBusqueda!, style: GoogleFonts.inter(fontSize: 12, color: Colors.red.shade600)),
                        ],
                        const SizedBox(height: 16),
                      ],

                      // Institución
                      _fieldLabel('Institución *'),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _institucionCtrl,
                        style: GoogleFonts.inter(fontSize: 14),
                        decoration: _inputDecoration('Nombre de la institución'),
                        validator: (v) => v == null || v.trim().isEmpty ? 'Requerido' : null,
                      ),
                      const SizedBox(height: 16),

                      // Productos
                      _fieldLabel('Productos / Servicios *'),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _productosCtrl,
                        style: GoogleFonts.inter(fontSize: 14),
                        decoration: _inputDecoration('Descripción de productos o servicios'),
                        validator: (v) => v == null || v.trim().isEmpty ? 'Requerido' : null,
                      ),
                      const SizedBox(height: 16),

                      // Valor Mensual
                      _fieldLabel('Valor Mensual (CLP)'),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _valorCtrl,
                        style: GoogleFonts.inter(fontSize: 14),
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: _inputDecoration('0').copyWith(prefixText: '\$ '),
                      ),
                      const SizedBox(height: 16),

                      // Fechas
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _fieldLabel('Fecha de Inicio'),
                                const SizedBox(height: 6),
                                _datePicker(
                                  label: _formatDate(_fechaInicio),
                                  onTap: () => _pickDate(isInicio: true),
                                  hasValue: _fechaInicio != null,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _fieldLabel('Fecha de Término'),
                                const SizedBox(height: 6),
                                _datePicker(
                                  label: _formatDate(_fechaTermino),
                                  onTap: () => _pickDate(isInicio: false),
                                  hasValue: _fechaTermino != null,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Notas (siempre visible)
                      _fieldLabel('Notas'),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _notasCtrl,
                        style: GoogleFonts.inter(fontSize: 14),
                        decoration: _inputDecoration('Observaciones adicionales'),
                        maxLines: 3,
                        minLines: 2,
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            // Footer buttons
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
              child: Row(
                children: [
                  if (widget.isEditing) ...[
                    TextButton(
                      onPressed: _eliminar,
                      style: TextButton.styleFrom(foregroundColor: Colors.red.shade600),
                      child: Text(
                        'Eliminar',
                        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
                      ),
                    ),
                    const Spacer(),
                  ] else
                    const Spacer(),
                  SizedBox(
                    height: 44,
                    child: ElevatedButton(
                      onPressed: _guardar,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        elevation: 0,
                      ),
                      child: Text(
                        widget.isEditing ? 'Guardar Cambios' : 'Ingresar Proyecto',
                        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
  }

  Widget _fieldLabel(String label) {
    return Text(
      label,
      style: GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: const Color(0xFF475569),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.inter(fontSize: 14, color: Colors.grey.shade400),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
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
        borderSide: const BorderSide(color: _primaryColor, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.red.shade300),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.red.shade400, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      isDense: true,
    );
  }

  Widget _datePicker({required String label, required VoidCallback onTap, required bool hasValue}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_outlined, size: 16, color: hasValue ? _primaryColor : Colors.grey.shade400),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: hasValue ? const Color(0xFF1E293B) : Colors.grey.shade400,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
