import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../app_shell.dart';
import '../models/configuracion.dart';
import '../services/config_service.dart';
import 'app_breadcrumbs.dart';

// re-export para usar en este archivo sin prefix
typedef _Hex = String;

const _primaryColor = Color(0xFF5B21B6);
const _bgColor = Color(0xFFF2F2F7);
const _cfBase = 'https://us-central1-licitaciones-prod.cloudfunctions.net';

class ConfiguracionView extends StatefulWidget {
  final VoidCallback? onOpenMenu;
  const ConfiguracionView({super.key, this.onOpenMenu});

  @override
  State<ConfiguracionView> createState() => _ConfiguracionViewState();
}

class _ConfiguracionViewState extends State<ConfiguracionView> {
  ConfiguracionData? _data;
  Map<String, int> _usoModalidades = {};
  bool _cargando = true;
  bool _guardando = false;
  bool _isDirty = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final results = await Future.wait([
        http.get(Uri.parse('$_cfBase/obtenerConfiguracion')),
        http.get(Uri.parse('$_cfBase/contarUsoModalidades')),
      ]);
      if (!mounted) return;
      setState(() {
        _data = results[0].statusCode == 200
            ? ConfiguracionData.fromJson(jsonDecode(results[0].body))
            : ConfiguracionData.defaults();
        _usoModalidades = results[1].statusCode == 200
            ? Map<String, int>.from(
                (jsonDecode(results[1].body) as Map).map(
                    (k, v) => MapEntry(k as String, (v as num).toInt())))
            : {};
        _cargando = false;
        _isDirty = false;
      });
    } catch (_) {
      if (mounted) setState(() { _data = ConfiguracionData.defaults(); _cargando = false; });
    }
  }

  Future<void> _guardar() async {
    if (_data == null) return;
    setState(() => _guardando = true);
    try {
      final res = await http.post(
        Uri.parse('$_cfBase/guardarConfiguracion'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(_data!.toJson()),
      );
      if (res.statusCode == 200) {
        ConfigService.instance.invalidate();
        if (!mounted) return;
        setState(() { _isDirty = false; _guardando = false; });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Configuración guardada', style: GoogleFonts.inter()),
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      } else {
        throw Exception('Error al guardar');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: $e', style: GoogleFonts.inter()),
        backgroundColor: Colors.red.shade400,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  void _markDirty() => setState(() => _isDirty = true);

  // Muestra confirmación y ejecuta onConfirm si acepta
  Future<void> _confirmarBorrado({
    required String titulo,
    required String mensaje,
    required VoidCallback onConfirm,
    bool bloqueado = false,
    String? mensajeBloqueo,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              bloqueado ? Icons.lock_outline : Icons.warning_amber_rounded,
              size: 20,
              color: bloqueado ? Colors.grey.shade500 : Colors.orange.shade600,
            ),
            const SizedBox(width: 8),
            Text(titulo, style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 16)),
          ],
        ),
        content: Text(
          bloqueado ? (mensajeBloqueo ?? mensaje) : mensaje,
          style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF475569)),
        ),
        actions: bloqueado
            ? [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Entendido', style: GoogleFonts.inter(color: _primaryColor, fontWeight: FontWeight.w600)),
                ),
              ]
            : [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Cancelar', style: GoogleFonts.inter(color: Colors.grey.shade600)),
                ),
                TextButton(
                  onPressed: () { Navigator.pop(ctx); onConfirm(); },
                  child: Text('Eliminar', style: GoogleFonts.inter(color: Colors.red.shade500, fontWeight: FontWeight.w600)),
                ),
              ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final isMobile = constraints.maxWidth < 700;
      final hPad = isMobile ? 20.0 : 32.0;
      return Scaffold(
        backgroundColor: _bgColor,
        body: Column(
          children: [
            _buildAppBar(hPad, isMobile),
            Expanded(
              child: _cargando
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 880),
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(hPad, 16, hPad, 48),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Configuración',
                                    style: GoogleFonts.inter(
                                        fontSize: isMobile ? 24 : 30,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -0.7,
                                        color: const Color(0xFF1E293B))),
                                const SizedBox(height: 4),
                                Text('Administra los valores disponibles en el sistema',
                                    style: GoogleFonts.inter(
                                        fontSize: isMobile ? 13 : 14,
                                        color: Colors.grey.shade500)),
                                const SizedBox(height: 24),
                                _sectionLabel('ESTADOS'),
                                _estadosCard(),
                                const SizedBox(height: 20),
                                _sectionLabel('MODALIDADES DE COMPRA'),
                                _modalidadesCard(),
                                const SizedBox(height: 20),
                                _sectionLabel('TIPOS DE DOCUMENTO'),
                                _tiposDocumentoCard(),
                                const SizedBox(height: 20),
                                _sectionLabel('PRODUCTOS'),
                                _productosCard(),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      );
    });
  }

  Widget _buildAppBar(double hPad, bool isMobile) {
    return buildBreadcrumbAppBar(
      context: context,
      hPad: hPad,
      onOpenMenu: openAppDrawer,
      crumbs: [BreadcrumbItem('Configuración')],
      actions: [
        if (_isDirty)
          _guardando
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: _primaryColor))
              : TextButton.icon(
                  onPressed: _guardar,
                  icon: const Icon(Icons.check, size: 16),
                  label: Text('Guardar', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                  style: TextButton.styleFrom(
                    foregroundColor: _primaryColor,
                    backgroundColor: _primaryColor.withValues(alpha: 0.08),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                ),
      ],
    );
  }

  Widget _sectionLabel(String label) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(label,
            style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade400,
                letterSpacing: 0.8)),
      );

  // ── ESTADOS (con color picker) ────────────────────────────────────────────

  Widget _estadosCard() {
    final items = _data!.estados;
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: Text('Sin estados configurados',
                  style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade400)),
            )
          else
            ...items.asMap().entries.map((e) {
              final item = e.value;
              final isLast = e.key == items.length - 1;
              return Column(children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                  child: Row(children: [
                    // Color circle — tap to pick
                    GestureDetector(
                      onTap: () => _mostrarColorPicker(item.color, (hex) {
                        setState(() => _data!.estados[e.key].color = hex);
                        _markDirty();
                      }),
                      child: Container(
                        width: 24, height: 24,
                        decoration: BoxDecoration(
                          color: item.colorValue,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [BoxShadow(color: item.colorValue.withValues(alpha: 0.4), blurRadius: 4, offset: const Offset(0, 1))],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(item.nombre,
                          style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF1E293B))),
                    ),
                    GestureDetector(
                      onTap: () => _confirmarBorrado(
                        titulo: 'Eliminar estado',
                        mensaje: '¿Eliminar el estado "${item.nombre}"?\n\nEsto solo afecta los filtros.',
                        onConfirm: () { setState(() => _data!.estados.removeAt(e.key)); _markDirty(); },
                      ),
                      child: Icon(Icons.remove_circle_outline, size: 18, color: Colors.grey.shade400),
                    ),
                  ]),
                ),
                if (!isLast) const Divider(height: 1, indent: 52, endIndent: 16),
              ]);
            }),
          const Divider(height: 1),
          _addEstadoRow(),
        ],
      ),
    );
  }

  Widget _addEstadoRow() {
    final ctrl = TextEditingController();
    String colorSel = '10B981';
    return StatefulBuilder(builder: (_, setSt) {
      bool showing = false;
      return StatefulBuilder(builder: (_, setSt2) {
        if (!showing) {
          return TextButton.icon(
            onPressed: () => setSt2(() => showing = true),
            icon: const Icon(Icons.add, size: 16),
            label: Text('Agregar estado', style: GoogleFonts.inter(fontSize: 13)),
            style: TextButton.styleFrom(
              foregroundColor: _primaryColor,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Row(children: [
            GestureDetector(
              onTap: () => _mostrarColorPicker(colorSel, (hex) => setSt2(() => colorSel = hex)),
              child: Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: hexToColor(colorSel),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [BoxShadow(color: hexToColor(colorSel).withValues(alpha: 0.4), blurRadius: 4)],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: ctrl,
                autofocus: true,
                style: GoogleFonts.inter(fontSize: 13),
                decoration: _inputDecor('Nombre del estado, ej: Vigente'),
                onSubmitted: (v) {
                  final s = v.trim();
                  if (s.isNotEmpty) {
                    setState(() => _data!.estados.add(EstadoItem(nombre: s, color: colorSel)));
                    _markDirty();
                    ctrl.clear();
                    setSt2(() => showing = false);
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () {
                final s = ctrl.text.trim();
                if (s.isNotEmpty) {
                  setState(() => _data!.estados.add(EstadoItem(nombre: s, color: colorSel)));
                  _markDirty();
                  ctrl.clear();
                  setSt2(() => showing = false);
                }
              },
              style: TextButton.styleFrom(foregroundColor: _primaryColor, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
              child: Text('Agregar', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            IconButton(
              onPressed: () { ctrl.clear(); setSt2(() => showing = false); },
              icon: Icon(Icons.close, size: 16, color: Colors.grey.shade400),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ]),
        );
      });
    });
  }

  void _mostrarColorPicker(_Hex current, void Function(_Hex) onSelect) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
        child: SizedBox(
          width: 300,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Elegir color', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: const Color(0xFF1E293B))),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: kColorPaleta.map((hex) {
                    final c = hexToColor(hex);
                    final selected = hex == current;
                    return GestureDetector(
                      onTap: () { Navigator.pop(ctx); onSelect(hex); },
                      child: Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: selected ? const Color(0xFF1E293B) : Colors.transparent,
                            width: 2.5,
                          ),
                          boxShadow: [BoxShadow(color: c.withValues(alpha: 0.4), blurRadius: 4, offset: const Offset(0, 2))],
                        ),
                        child: selected
                            ? const Icon(Icons.check, color: Colors.white, size: 18)
                            : null,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text('Cancelar', style: GoogleFonts.inter(color: Colors.grey.shade600)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── MODALIDADES (con conteo de uso) ───────────────────────────────────────

  Widget _modalidadesCard() {
    final items = _data!.modalidades;
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: Text('Sin modalidades configuradas',
                  style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade400)),
            )
          else
            ...items.asMap().entries.map((e) {
              final uso = _usoModalidades[e.value] ?? 0;
              return _stringItem(
                e.value,
                showDivider: e.key < items.length - 1,
                enUso: uso,
                onDeleteTap: () {
                  if (uso > 0) {
                    _confirmarBorrado(
                      titulo: 'No se puede eliminar',
                      mensaje: '',
                      onConfirm: () {},
                      bloqueado: true,
                      mensajeBloqueo:
                          '"${e.value}" está asociada a $uso proyecto${uso > 1 ? 's' : ''}.\n\nPara eliminarla, primero reasigna esos proyectos a otra modalidad.',
                    );
                  } else {
                    _confirmarBorrado(
                      titulo: 'Eliminar modalidad',
                      mensaje: '¿Eliminar la modalidad "${e.value}"?',
                      onConfirm: () { setState(() => _data!.modalidades.removeAt(e.key)); _markDirty(); },
                    );
                  }
                },
              );
            }),
          const Divider(height: 1),
          _addRow(
            label: 'Agregar modalidad',
            hint: 'Ej: Licitación Pública',
            onAdd: (v) { setState(() => _data!.modalidades.add(v)); _markDirty(); },
          ),
        ],
      ),
    );
  }

  Widget _stringItem(String value, {
    required bool showDivider,
    required int? enUso,      // null = no mostrar, 0 = libre, >0 = en uso
    required VoidCallback onDeleteTap,
  }) {
    final bloqueado = enUso != null && enUso > 0;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(value,
                    style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF1E293B))),
              ),
              if (enUso != null && enUso > 0) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Text(
                    '$enUso proyecto${enUso > 1 ? 's' : ''}',
                    style: GoogleFonts.inter(
                        fontSize: 11, color: Colors.orange.shade700, fontWeight: FontWeight.w500),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              GestureDetector(
                onTap: onDeleteTap,
                child: Icon(
                  bloqueado ? Icons.lock_outline : Icons.remove_circle_outline,
                  size: 18,
                  color: bloqueado ? Colors.grey.shade300 : Colors.grey.shade400,
                ),
              ),
            ],
          ),
        ),
        if (showDivider) const Divider(height: 1, indent: 16, endIndent: 16),
      ],
    );
  }

  // ── ADD ROW ───────────────────────────────────────────────────────────────

  Widget _addRow({required String label, required String hint, required void Function(String) onAdd}) {
    final ctrl = TextEditingController();
    return StatefulBuilder(builder: (_, __) {
      bool showing = false;
      return StatefulBuilder(builder: (_, setSt) {
        if (!showing) {
          return TextButton.icon(
            onPressed: () => setSt(() => showing = true),
            icon: const Icon(Icons.add, size: 16),
            label: Text(label, style: GoogleFonts.inter(fontSize: 13)),
            style: TextButton.styleFrom(
              foregroundColor: _primaryColor,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: ctrl,
                  autofocus: true,
                  style: GoogleFonts.inter(fontSize: 13),
                  decoration: _inputDecor(hint),
                  onSubmitted: (v) {
                    final s = v.trim();
                    if (s.isNotEmpty) { onAdd(s); ctrl.clear(); setSt(() => showing = false); }
                  },
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () {
                  final s = ctrl.text.trim();
                  if (s.isNotEmpty) { onAdd(s); ctrl.clear(); setSt(() => showing = false); }
                },
                style: TextButton.styleFrom(
                  foregroundColor: _primaryColor,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
                child: Text('Agregar', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              IconButton(
                onPressed: () { ctrl.clear(); setSt(() => showing = false); },
                icon: Icon(Icons.close, size: 16, color: Colors.grey.shade400),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        );
      });
    });
  }

  // ── TIPOS DE DOCUMENTO ────────────────────────────────────────────────────

  Widget _tiposDocumentoCard() {
    final items = _data!.tiposDocumento;
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: Text('Sin tipos configurados',
                  style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade400)),
            )
          else
            ...items.asMap().entries.map((e) => _stringItem(
                  e.value,
                  showDivider: e.key < items.length - 1,
                  enUso: null,
                  onDeleteTap: () => _confirmarBorrado(
                    titulo: 'Eliminar tipo de documento',
                    mensaje: '¿Eliminar el tipo "${e.value}"?',
                    onConfirm: () {
                      setState(() => _data!.tiposDocumento.removeAt(e.key));
                      _markDirty();
                    },
                  ),
                )),
          const Divider(height: 1),
          _addRow(
            label: 'Agregar tipo',
            hint: 'Ej: Contrato, Acta de Evaluación',
            onAdd: (v) {
              setState(() => _data!.tiposDocumento.add(v));
              _markDirty();
            },
          ),
        ],
      ),
    );
  }

  // ── PRODUCTOS ─────────────────────────────────────────────────────────────

  Widget _productosCard() {
    final productos = _data!.productos;
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          if (productos.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: Text('Sin productos configurados',
                  style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade400)),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 90,
                    child: Text('Abreviatura',
                        style: GoogleFonts.inter(
                            fontSize: 11, fontWeight: FontWeight.w600,
                            color: Colors.grey.shade400, letterSpacing: 0.5)),
                  ),
                  Expanded(
                    child: Text('Nombre completo',
                        style: GoogleFonts.inter(
                            fontSize: 11, fontWeight: FontWeight.w600,
                            color: Colors.grey.shade400, letterSpacing: 0.5)),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ...productos.asMap().entries.map((e) => _productoItem(
                  e.value,
                  index: e.key,
                  showDivider: e.key < productos.length - 1,
                  onDelete: () => _confirmarBorrado(
                    titulo: 'Eliminar producto',
                    mensaje: '¿Eliminar el producto "${e.value.abreviatura} – ${e.value.nombre}"?',
                    onConfirm: () { setState(() => _data!.productos.removeAt(e.key)); _markDirty(); },
                  ),
                )),
          ],
          const Divider(height: 1),
          _addProductoRow(),
        ],
      ),
    );
  }

  Widget _productoItem(ProductoItem p, {
    required bool showDivider,
    required int index,
    required VoidCallback onDelete,
  }) {
    final icono = kIconosProducto[p.icono] ?? kIconosProducto['label']!;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(
            children: [
              // Icono con color
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: p.bgColor,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icono, size: 18, color: p.fgColor),
              ),
              const SizedBox(width: 10),
              // Abreviatura badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: p.bgColor,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(p.abreviatura,
                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: p.fgColor)),
              ),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(p.nombre,
                      style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF1E293B)))),
              IconButton(
                onPressed: () => _showEditProductoDialog(p, index),
                icon: Icon(Icons.edit_outlined, size: 16, color: Colors.grey.shade400),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onDelete,
                child: Icon(Icons.remove_circle_outline, size: 18, color: Colors.grey.shade400),
              ),
            ],
          ),
        ),
        if (showDivider) const Divider(height: 1, indent: 16, endIndent: 16),
      ],
    );
  }

  void _showEditProductoDialog(ProductoItem p, int index) {
    final nombreCtrl = TextEditingController(text: p.nombre);
    final abrevCtrl = TextEditingController(text: p.abreviatura);
    String colorSel = p.color;
    String iconoSel = p.icono;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: SizedBox(
            width: 420,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Editar producto', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: const Color(0xFF1E293B))),
                  const SizedBox(height: 16),
                  Row(children: [
                    SizedBox(width: 110, child: TextField(
                      controller: abrevCtrl,
                      style: GoogleFonts.inter(fontSize: 13),
                      decoration: _inputDecor('Abreviatura'),
                    )),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(
                      controller: nombreCtrl,
                      style: GoogleFonts.inter(fontSize: 13),
                      decoration: _inputDecor('Nombre completo'),
                    )),
                  ]),
                  const SizedBox(height: 14),
                  Text('Color', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade400, letterSpacing: 0.5)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: kColorPaleta.map((hex) {
                    final c = hexToColor(hex);
                    final sel = hex == colorSel;
                    return GestureDetector(
                      onTap: () => setSt(() => colorSel = hex),
                      child: Container(
                        width: 28, height: 28,
                        decoration: BoxDecoration(
                          color: c, shape: BoxShape.circle,
                          border: Border.all(color: sel ? const Color(0xFF1E293B) : Colors.transparent, width: 2.5),
                          boxShadow: [BoxShadow(color: c.withValues(alpha: 0.4), blurRadius: 3)],
                        ),
                        child: sel ? const Icon(Icons.check, color: Colors.white, size: 14) : null,
                      ),
                    );
                  }).toList()),
                  const SizedBox(height: 14),
                  Text('Icono', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade400, letterSpacing: 0.5)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 6, children: kIconosProducto.entries.map((e) {
                    final sel = e.key == iconoSel;
                    final c = hexToColor(colorSel);
                    return GestureDetector(
                      onTap: () => setSt(() => iconoSel = e.key),
                      child: Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: sel ? c.withValues(alpha: 0.15) : const Color(0xFFF2F2F7),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: sel ? c : Colors.transparent, width: 1.5),
                        ),
                        child: Icon(e.value, size: 18, color: sel ? c : Colors.grey.shade400),
                      ),
                    );
                  }).toList()),
                  const SizedBox(height: 20),
                  Row(children: [
                    Expanded(child: TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: TextButton.styleFrom(
                        backgroundColor: const Color(0xFFF2F2F7),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                      ),
                      child: Text('Cancelar', style: GoogleFonts.inter(fontSize: 14, color: Colors.grey.shade700)),
                    )),
                    const SizedBox(width: 10),
                    Expanded(child: ElevatedButton(
                      onPressed: () {
                        final n = nombreCtrl.text.trim();
                        final a = abrevCtrl.text.trim();
                        if (n.isNotEmpty && a.isNotEmpty) {
                          setState(() => _data!.productos[index] = ProductoItem(
                            nombre: n, abreviatura: a, color: colorSel, icono: iconoSel));
                          _markDirty();
                          Navigator.pop(ctx);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryColor, foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 11), elevation: 0,
                      ),
                      child: Text('Guardar', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600)),
                    )),
                  ]),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _addProductoRow() {
    final nombreCtrl = TextEditingController();
    final abrevCtrl = TextEditingController();
    return StatefulBuilder(builder: (_, __) {
      bool showing = false;
      return StatefulBuilder(builder: (_, setSt) {
        if (!showing) {
          return TextButton.icon(
            onPressed: () => setSt(() => showing = true),
            icon: const Icon(Icons.add, size: 16),
            label: Text('Agregar producto', style: GoogleFonts.inter(fontSize: 13)),
            style: TextButton.styleFrom(
              foregroundColor: _primaryColor,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                SizedBox(width: 100, child: TextField(
                  controller: abrevCtrl, autofocus: true,
                  style: GoogleFonts.inter(fontSize: 13),
                  decoration: _inputDecor('Abrev.'),
                )),
                const SizedBox(width: 8),
                Expanded(child: TextField(
                  controller: nombreCtrl,
                  style: GoogleFonts.inter(fontSize: 13),
                  decoration: _inputDecor('Nombre completo'),
                )),
              ]),
              const SizedBox(height: 8),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(
                  onPressed: () { abrevCtrl.clear(); nombreCtrl.clear(); setSt(() => showing = false); },
                  style: TextButton.styleFrom(foregroundColor: Colors.grey.shade500),
                  child: Text('Cancelar', style: GoogleFonts.inter(fontSize: 13)),
                ),
                const SizedBox(width: 4),
                TextButton(
                  onPressed: () {
                    final a = abrevCtrl.text.trim();
                    final n = nombreCtrl.text.trim();
                    if (a.isNotEmpty && n.isNotEmpty) {
                      setState(() => _data!.productos.add(ProductoItem(nombre: n, abreviatura: a)));
                      _markDirty();
                      abrevCtrl.clear(); nombreCtrl.clear();
                      setSt(() => showing = false);
                    }
                  },
                  style: TextButton.styleFrom(foregroundColor: _primaryColor),
                  child: Text('Agregar', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ]),
            ],
          ),
        );
      });
    });
  }

  InputDecoration _inputDecor(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade400),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.grey.shade200)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.grey.shade200)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _primaryColor, width: 1.5)),
      );
}
