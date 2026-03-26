import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../app_shell.dart';
import '../models/configuracion.dart';
import '../services/config_service.dart';
import 'app_breadcrumbs.dart';
import 'walkthrough.dart';

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

class _ConfiguracionViewState extends State<ConfiguracionView>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  ConfiguracionData? _data;
  // CAMBIO: Ahora es una lista de Strings para coincidir con el nuevo backend
  List<String> _tiposDocumentoList = [];
  Map<String, int> _usoModalidades = {};
  bool _cargando = true;
  bool _loadingTiposDocumento = true;
  bool _guardando = false;
  bool _isDirty = false;

  // Add-row inline state
  bool _showAddModalidad = false;
  final _addModalidadCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _cargar();
    _fetchTiposDocumento();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _addModalidadCtrl.dispose();
    super.dispose();
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
                  (k, v) => MapEntry(k as String, (v as num).toInt()),
                ),
              )
            : {};
        _cargando = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _data = ConfiguracionData.defaults();
          _cargando = false;
        });
      }
    }
  }

  // Método para cargar los tipos de documento corregido para la nueva estructura de lista
  Future<void> _fetchTiposDocumento() async {
    setState(() => _loadingTiposDocumento = true);
    try {
      final res = await http.get(Uri.parse('$_cfBase/obtenerTiposDocumento'));
      if (!mounted) return;
      if (res.statusCode == 200) {
        setState(() {
          // CAMBIO: Se parsea como List<String> directamente
          _tiposDocumentoList = List<String>.from(jsonDecode(res.body));
          _loadingTiposDocumento = false;
        });
      } else {
        throw Exception('Error al obtener tipos de documento');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingTiposDocumento = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error al cargar tipos de documento: $e',
              style: GoogleFonts.inter(),
            ),
            backgroundColor: Colors.red.shade400,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _guardar() async {
    if (_data == null) return;
    setState(() => _guardando = true);
    try {
      final res = await http.post(
        Uri.parse('$_cfBase/guardarConfiguracion'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'estados': _data!.estados.map((e) => e.toJson()).toList(),
          'modalidades': _data!.modalidades,
          'productos': _data!.productos.map((p) => p.toJson()).toList(),
          // Se incluye el campo tiposDocumento para mantener Firestore sincronizado
          'tiposDocumento': _tiposDocumentoList,
        }),
      );
      if (res.statusCode == 200) {
        ConfigService.instance.invalidate();
        if (!mounted) return;
        setState(() {
          _isDirty = false;
          _guardando = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Configuración guardada', style: GoogleFonts.inter()),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      } else {
        throw Exception('Error al guardar');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e', style: GoogleFonts.inter()),
          backgroundColor: Colors.red.shade400,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // Guardar un tipo de documento usando la nueva lógica de arrayUnion
  Future<void> _saveTipoDocumento({required String nombre}) async {
    try {
      final res = await http.post(
        Uri.parse('$_cfBase/guardarTipoDocumento'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'nombre': nombre}),
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        await _fetchTiposDocumento();
        _markDirty();
      } else {
        throw Exception('Error al guardar tipo de documento');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error al guardar tipo de documento: $e',
              style: GoogleFonts.inter(),
            ),
            backgroundColor: Colors.red.shade400,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // Eliminar un tipo de documento usando la nueva lógica de arrayRemove
  Future<void> _deleteTipoDocumento(String nombre) async {
    try {
      final res = await http.post(
        Uri.parse('$_cfBase/eliminarTipoDocumento'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'nombre': nombre}),
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        await _fetchTiposDocumento();
        _markDirty();
      } else {
        throw Exception('Error al eliminar tipo de documento');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error al eliminar tipo de documento: $e',
              style: GoogleFonts.inter(),
            ),
            backgroundColor: Colors.red.shade400,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _markDirty() => setState(() => _isDirty = true);

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
            Text(
              titulo,
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ],
        ),
        content: Text(
          bloqueado ? (mensajeBloqueo ?? mensaje) : mensaje,
          style: GoogleFonts.inter(
            fontSize: 14,
            color: const Color(0xFF475569),
          ),
        ),
        actions: bloqueado
            ? [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(
                    'Entendido',
                    style: GoogleFonts.inter(
                      color: _primaryColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ]
            : [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(
                    'Cancelar',
                    style: GoogleFonts.inter(color: Colors.grey.shade600),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    onConfirm();
                  },
                  child: Text(
                    'Eliminar',
                    style: GoogleFonts.inter(
                      color: Colors.red.shade500,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 700;
        final hPad = isMobile ? 20.0 : 32.0;
        return Scaffold(
          backgroundColor: _bgColor,
          body: Column(
            children: [
              _buildAppBar(hPad, isMobile),
              // TabBar
              Container(
                color: Colors.white,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 880),
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: hPad),
                      child: TabBar(
                        controller: _tabController,
                        labelStyle: GoogleFonts.inter(
                            fontSize: 13, fontWeight: FontWeight.w600),
                        unselectedLabelStyle: GoogleFonts.inter(
                            fontSize: 13, fontWeight: FontWeight.w400),
                        labelColor: _primaryColor,
                        unselectedLabelColor: Colors.grey.shade400,
                        indicatorColor: _primaryColor,
                        indicatorSize: TabBarIndicatorSize.label,
                        indicatorWeight: 2.5,
                        dividerColor: Colors.grey.shade200,
                        tabs: const [
                          Tab(text: 'General'),
                          Tab(text: 'Textos de ayuda'),
                          Tab(text: 'Sistema'),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // ── Tab 1: Configuración general ──────────────────────
                    (_cargando || _loadingTiposDocumento)
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
                                            color: const Color(0xFF1E293B),
                                          )),
                                      const SizedBox(height: 4),
                                      Text('Administra los valores disponibles en el sistema',
                                          style: GoogleFonts.inter(
                                            fontSize: isMobile ? 13 : 14,
                                            color: Colors.grey.shade500,
                                          )),
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
                    // ── Tab 2: Textos de ayuda ────────────────────────────
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 880),
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(hPad, 16, hPad, 0),
                          child: const HelpTextsEditor(),
                        ),
                      ),
                    ),
                    // ── Tab 3: Sistema ────────────────────────────────────
                    SingleChildScrollView(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 880),
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(hPad, 20, hPad, 48),
                            child: const _SistemaTab(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
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
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _primaryColor,
                  ),
                )
              : TextButton.icon(
                  onPressed: _guardar,
                  icon: const Icon(Icons.check, size: 16),
                  label: Text(
                    'Guardar',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: _primaryColor,
                    backgroundColor: _primaryColor.withValues(alpha: 0.08),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                  ),
                ),
      ],
    );
  }

  Widget _sectionLabel(String label) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      label,
      style: GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: Colors.grey.shade400,
        letterSpacing: 0.8,
      ),
    ),
  );

  // ── ESTADOS ────────────────────────────────────────────────────────────

  Widget _estadosCard() {
    final items = _data!.estados;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: Text(
                'Sin estados configurados',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: Colors.grey.shade400,
                ),
              ),
            )
          else
            ReorderableListView.builder(
              shrinkWrap: true,
              buildDefaultDragHandles: false,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              onReorder: (oldIdx, newIdx) {
                setState(() {
                  if (newIdx > oldIdx) newIdx--;
                  final item = _data!.estados.removeAt(oldIdx);
                  _data!.estados.insert(newIdx, item);
                });
                _markDirty();
              },
              itemBuilder: (context, idx) {
                final item = items[idx];
                final isLast = idx == items.length - 1;
                return Column(
                  key: ValueKey('estado_$idx'),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 11,
                      ),
                      child: Row(
                        children: [
                          ReorderableDragStartListener(
                            index: idx,
                            child: Icon(
                              Icons.drag_handle,
                              size: 18,
                              color: Colors.grey.shade300,
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => _mostrarColorPicker(item.color, (hex) {
                              setState(() => _data!.estados[idx].color = hex);
                              _markDirty();
                            }),
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: item.colorValue,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: item.colorValue.withValues(
                                      alpha: 0.4,
                                    ),
                                    blurRadius: 4,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              item.nombre,
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                color: const Color(0xFF1E293B),
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => _confirmarBorrado(
                              titulo: 'Eliminar estado',
                              mensaje:
                                  '¿Eliminar el estado "${item.nombre}"?\n\nEsto solo afecta los filtros.\nEsta acción no es reversible.',
                              onConfirm: () {
                                setState(() => _data!.estados.removeAt(idx));
                                _markDirty();
                              },
                            ),
                            icon: Icon(
                              Icons.delete_outline,
                              size: 18,
                              color: Colors.red.shade300,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            tooltip: 'Eliminar',
                          ),
                        ],
                      ),
                    ),
                    if (!isLast)
                      const Divider(height: 1, indent: 68, endIndent: 16),
                  ],
                );
              },
            ),
          const Divider(height: 1),
          _addEstadoRow(),
        ],
      ),
    );
  }

  Widget _addEstadoRow() {
    final ctrl = TextEditingController();
    String colorSel = '10B981';
    return StatefulBuilder(
      builder: (_, setSt) {
        bool showing = false;
        return StatefulBuilder(
          builder: (_, setSt2) {
            if (!showing) {
              return TextButton.icon(
                onPressed: () => setSt2(() => showing = true),
                icon: const Icon(Icons.add, size: 16),
                label: Text(
                  'Agregar estado',
                  style: GoogleFonts.inter(fontSize: 13),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: _primaryColor,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => _mostrarColorPicker(
                      colorSel,
                      (hex) => setSt2(() => colorSel = hex),
                    ),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: hexToColor(colorSel),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: hexToColor(colorSel).withValues(alpha: 0.4),
                            blurRadius: 4,
                          ),
                        ],
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
                          setState(
                            () => _data!.estados.add(
                              EstadoItem(nombre: s, color: colorSel),
                            ),
                          );
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
                        setState(
                          () => _data!.estados.add(
                            EstadoItem(nombre: s, color: colorSel),
                          ),
                        );
                        _markDirty();
                        ctrl.clear();
                        setSt2(() => showing = false);
                      }
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: _primaryColor,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                    ),
                    child: Text(
                      'Agregar',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      ctrl.clear();
                      setSt2(() => showing = false);
                    },
                    icon: Icon(
                      Icons.close,
                      size: 16,
                      color: Colors.grey.shade400,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
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
                Text(
                  'Elegir color',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: kColorPaleta.map((hex) {
                    final c = hexToColor(hex);
                    final selected = hex == current;
                    return GestureDetector(
                      onTap: () {
                        Navigator.pop(ctx);
                        onSelect(hex);
                      },
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: selected
                                ? const Color(0xFF1E293B)
                                : Colors.transparent,
                            width: 2.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: c.withValues(alpha: 0.4),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: selected
                            ? const Icon(
                                Icons.check,
                                color: Colors.white,
                                size: 18,
                              )
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
                    child: Text(
                      'Cancelar',
                      style: GoogleFonts.inter(color: Colors.grey.shade600),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── MODALIDADES ───────────────────────────────────────────────────────

  Widget _modalidadesCard() {
    final items = _data!.modalidades;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: Text(
                'Sin modalidades configuradas',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: Colors.grey.shade400,
                ),
              ),
            )
          else
            ReorderableListView.builder(
              shrinkWrap: true,
              buildDefaultDragHandles: false,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              onReorder: (oldIdx, newIdx) {
                setState(() {
                  if (newIdx > oldIdx) newIdx--;
                  final item = _data!.modalidades.removeAt(oldIdx);
                  _data!.modalidades.insert(newIdx, item);
                });
                _markDirty();
              },
              itemBuilder: (context, idx) {
                final value = items[idx];
                final uso = _usoModalidades[value] ?? 0;
                final isLast = idx == items.length - 1;
                return Column(
                  key: ValueKey('modalidad_$idx'),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          ReorderableDragStartListener(
                            index: idx,
                            child: Icon(
                              Icons.drag_handle,
                              size: 18,
                              color: Colors.grey.shade300,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              value,
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                color: const Color(0xFF1E293B),
                              ),
                            ),
                          ),
                          if (uso > 0) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: Colors.orange.shade200,
                                ),
                              ),
                              child: Text(
                                '$uso proyecto${uso > 1 ? 's' : ''}',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: Colors.orange.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          IconButton(
                            onPressed: () {
                              if (uso > 0) {
                                _confirmarBorrado(
                                  titulo: 'No se puede eliminar',
                                  mensaje: '',
                                  onConfirm: () {},
                                  bloqueado: true,
                                  mensajeBloqueo:
                                      '"$value" está asociada a $uso proyecto${uso > 1 ? 's' : ''}.\n\nPara eliminarla, primero reasigna esos proyectos a otra modalidad.',
                                );
                              } else {
                                _confirmarBorrado(
                                  titulo: 'Eliminar modalidad',
                                  mensaje:
                                      '¿Eliminar la modalidad "$value"?\nEsta acción no es reversible.',
                                  onConfirm: () {
                                    setState(
                                      () => _data!.modalidades.removeAt(idx),
                                    );
                                    _markDirty();
                                  },
                                );
                              }
                            },
                            icon: Icon(
                              uso > 0
                                  ? Icons.lock_outline
                                  : Icons.delete_outline,
                              size: 18,
                              color: uso > 0
                                  ? Colors.grey.shade300
                                  : Colors.red.shade300,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            tooltip: uso > 0
                                ? 'No se puede eliminar'
                                : 'Eliminar',
                          ),
                        ],
                      ),
                    ),
                    if (!isLast)
                      const Divider(height: 1, indent: 16, endIndent: 16),
                  ],
                );
              },
            ),
          const Divider(height: 1),
          _inlineAddRow(
            showing: _showAddModalidad,
            ctrl: _addModalidadCtrl,
            label: 'Agregar modalidad',
            hint: 'Ej: Licitación Pública',
            onToggle: (v) => setState(() => _showAddModalidad = v),
            onAdd: (v) {
              setState(() {
                _data!.modalidades.add(v);
                _showAddModalidad = false;
              });
              _addModalidadCtrl.clear();
              _markDirty();
            },
          ),
        ],
      ),
    );
  }

  // ── TIPOS DE DOCUMENTO (CORREGIDO PARA LISTA DE STRINGS) ──────────────────

  Widget _tiposDocumentoCard() {
    final items = _tiposDocumentoList;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: Text(
                'Sin tipos configurados',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: Colors.grey.shade400,
                ),
              ),
            )
          else
            ReorderableListView.builder(
              shrinkWrap: true,
              buildDefaultDragHandles: false,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              onReorder: (oldIdx, newIdx) async {
                setState(() {
                  if (newIdx > oldIdx) newIdx--;
                  final item = _tiposDocumentoList.removeAt(oldIdx);
                  _tiposDocumentoList.insert(newIdx, item);
                });
                _markDirty();
              },
              itemBuilder: (context, idx) {
                final value = items[idx]; // 'value' es directamente el String
                final isLast = idx == items.length - 1;
                return Column(
                  key: ValueKey(
                    'tipo_$value',
                  ), // Usar el texto como clave única
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          ReorderableDragStartListener(
                            index: idx,
                            child: Icon(
                              Icons.drag_handle,
                              size: 18,
                              color: Colors.grey.shade300,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              value,
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                color: const Color(0xFF1E293B),
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => _confirmarBorrado(
                              titulo: 'Eliminar tipo de documento',
                              mensaje:
                                  '¿Eliminar el tipo "$value"?\nEsta acción no es reversible.',
                              onConfirm: () async {
                                await _deleteTipoDocumento(value);
                              },
                            ),
                            icon: Icon(
                              Icons.delete_outline,
                              size: 18,
                              color: Colors.red.shade300,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            tooltip: 'Eliminar',
                          ),
                        ],
                      ),
                    ),
                    if (!isLast)
                      const Divider(height: 1, indent: 16, endIndent: 16),
                  ],
                );
              },
            ),
          const Divider(height: 1),
          _addTipoDocRow(),
        ],
      ),
    );
  }

  Widget _addTipoDocRow() {
    final ctrl = TextEditingController();
    return StatefulBuilder(
      builder: (ctx, setSt) {
        bool showing = false;
        return StatefulBuilder(
          builder: (ctx2, setSt2) {
            if (!showing) {
              return TextButton.icon(
                onPressed: () => setSt2(() => showing = true),
                icon: const Icon(Icons.add, size: 16),
                label: Text(
                  'Agregar tipo',
                  style: GoogleFonts.inter(fontSize: 13),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: _primaryColor,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              );
            }
            void submit() async {
              final s = ctrl.text.trim();
              if (s.isNotEmpty) {
                await _saveTipoDocumento(nombre: s);
                ctrl.clear();
                setSt2(() => showing = false);
              }
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
                      decoration: _inputDecor(
                        'Ej: Contrato, Acta de Evaluación',
                      ),
                      onSubmitted: (_) => submit(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: submit,
                    style: TextButton.styleFrom(
                      foregroundColor: _primaryColor,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                    ),
                    child: Text(
                      'Agregar',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      ctrl.clear();
                      setSt2(() => showing = false);
                    },
                    icon: Icon(
                      Icons.close,
                      size: 16,
                      color: Colors.grey.shade400,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ── PRODUCTOS ─────────────────────────────────────────────────────────────

  Widget _productosCard() {
    final productos = _data!.productos;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          if (productos.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: Text(
                'Sin productos configurados',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: Colors.grey.shade400,
                ),
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  const SizedBox(width: 26),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 90,
                    child: Text(
                      'Abreviatura',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade400,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'Nombre completo',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade400,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ReorderableListView.builder(
              shrinkWrap: true,
              buildDefaultDragHandles: false,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: productos.length,
              onReorder: (oldIdx, newIdx) {
                setState(() {
                  if (newIdx > oldIdx) newIdx--;
                  final item = _data!.productos.removeAt(oldIdx);
                  _data!.productos.insert(newIdx, item);
                });
                _markDirty();
              },
              itemBuilder: (context, idx) {
                final p = productos[idx];
                final isLast = idx == productos.length - 1;
                final icono =
                    kIconosProducto[p.icono] ?? kIconosProducto['label']!;
                return Column(
                  key: ValueKey('producto_$idx'),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 11,
                      ),
                      child: Row(
                        children: [
                          ReorderableDragStartListener(
                            index: idx,
                            child: Icon(
                              Icons.drag_handle,
                              size: 18,
                              color: Colors.grey.shade300,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: p.bgColor,
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Icon(icono, size: 18, color: p.fgColor),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: p.bgColor,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              p.abreviatura,
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: p.fgColor,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              p.nombre,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: const Color(0xFF1E293B),
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => _showEditProductoDialog(p, idx),
                            icon: Icon(
                              Icons.edit_outlined,
                              size: 16,
                              color: Colors.grey.shade400,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                          const SizedBox(width: 4),
                          GestureDetector(
                            onTap: () => _confirmarBorrado(
                              titulo: 'Eliminar producto',
                              mensaje:
                                  '¿Eliminar el producto "${p.abreviatura} – ${p.nombre}"?',
                              onConfirm: () {
                                setState(() => _data!.productos.removeAt(idx));
                                _markDirty();
                              },
                            ),
                            child: Icon(
                              Icons.remove_circle_outline,
                              size: 18,
                              color: Colors.grey.shade400,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!isLast)
                      const Divider(height: 1, indent: 16, endIndent: 16),
                  ],
                );
              },
            ),
          ],
          const Divider(height: 1),
          _addProductoRow(),
        ],
      ),
    );
  }

  void _showEditProductoDialog(ProductoItem p, int index) {
    final nombreCtrl = TextEditingController(text: p.nombre);
    final abrevCtrl = TextEditingController(text: p.abreviatura);
    String colorSel = p.color;
    String iconoSel = p.icono;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 32,
            ),
            child: SizedBox(
              width: 420,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Editar producto',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        SizedBox(
                          width: 110,
                          child: TextField(
                            controller: abrevCtrl,
                            style: GoogleFonts.inter(fontSize: 13),
                            decoration: _inputDecor('Abreviatura'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: nombreCtrl,
                            style: GoogleFonts.inter(fontSize: 13),
                            decoration: _inputDecor('Nombre completo'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Color',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade400,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: kColorPaleta.map((hex) {
                        final c = hexToColor(hex);
                        final sel = hex == colorSel;
                        return GestureDetector(
                          onTap: () => setSt(() => colorSel = hex),
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: sel
                                    ? const Color(0xFF1E293B)
                                    : Colors.transparent,
                                width: 2.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: c.withValues(alpha: 0.4),
                                  blurRadius: 3,
                                ),
                              ],
                            ),
                            child: sel
                                ? const Icon(
                                    Icons.check,
                                    color: Colors.white,
                                    size: 14,
                                  )
                                : null,
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Icono',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade400,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: kIconosProducto.entries.map((e) {
                        final sel = e.key == iconoSel;
                        final c = hexToColor(colorSel);
                        return GestureDetector(
                          onTap: () => setSt(() => iconoSel = e.key),
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: sel
                                  ? c.withValues(alpha: 0.15)
                                  : const Color(0xFFF2F2F7),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: sel ? c : Colors.transparent,
                                width: 1.5,
                              ),
                            ),
                            child: Icon(
                              e.value,
                              size: 18,
                              color: sel ? c : Colors.grey.shade400,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            style: TextButton.styleFrom(
                              backgroundColor: const Color(0xFFF2F2F7),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 11),
                            ),
                            child: Text(
                              'Cancelar',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              final n = nombreCtrl.text.trim();
                              final a = abrevCtrl.text.trim();
                              if (n.isNotEmpty && a.isNotEmpty) {
                                setState(
                                  () => _data!.productos[index] = ProductoItem(
                                    nombre: n,
                                    abreviatura: a,
                                    color: colorSel,
                                    icono: iconoSel,
                                  ),
                                );
                                _markDirty();
                                Navigator.pop(ctx);
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _primaryColor,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              elevation: 0,
                            ),
                            child: Text(
                              'Guardar',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _addProductoRow() {
    final nombreCtrl = TextEditingController();
    final abrevCtrl = TextEditingController();
    return StatefulBuilder(
      builder: (_, __) {
        bool showing = false;
        return StatefulBuilder(
          builder: (_, setSt) {
            if (!showing) {
              return TextButton.icon(
                onPressed: () => setSt(() => showing = true),
                icon: const Icon(Icons.add, size: 16),
                label: Text(
                  'Agregar producto',
                  style: GoogleFonts.inter(fontSize: 13),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: _primaryColor,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 100,
                        child: TextField(
                          controller: abrevCtrl,
                          autofocus: true,
                          style: GoogleFonts.inter(fontSize: 13),
                          decoration: _inputDecor('Abrev.'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: nombreCtrl,
                          style: GoogleFonts.inter(fontSize: 13),
                          decoration: _inputDecor('Nombre completo'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () {
                          abrevCtrl.clear();
                          nombreCtrl.clear();
                          setSt(() => showing = false);
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.grey.shade500,
                        ),
                        child: Text(
                          'Cancelar',
                          style: GoogleFonts.inter(fontSize: 13),
                        ),
                      ),
                      const SizedBox(width: 4),
                      TextButton(
                        onPressed: () {
                          final a = abrevCtrl.text.trim();
                          final n = nombreCtrl.text.trim();
                          if (a.isNotEmpty && n.isNotEmpty) {
                            setState(
                              () => _data!.productos.add(
                                ProductoItem(nombre: n, abreviatura: a),
                              ),
                            );
                            _markDirty();
                            abrevCtrl.clear();
                            nombreCtrl.clear();
                            setSt(() => showing = false);
                          }
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: _primaryColor,
                        ),
                        child: Text(
                          'Agregar',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ── INLINE HELPERS ────────────────────────────────────────────────────────

  Widget _inlineAddRow({
    required bool showing,
    required TextEditingController ctrl,
    required String label,
    required String hint,
    required void Function(bool) onToggle,
    required void Function(String) onAdd,
  }) {
    void submit() {
      final s = ctrl.text.trim();
      if (s.isNotEmpty) onAdd(s);
    }

    if (!showing) {
      return TextButton.icon(
        onPressed: () => onToggle(true),
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
              onSubmitted: (_) => submit(),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: submit,
            style: TextButton.styleFrom(
              foregroundColor: _primaryColor,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
            child: Text(
              'Agregar',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            onPressed: () {
              ctrl.clear();
              onToggle(false);
            },
            icon: Icon(Icons.close, size: 16, color: Colors.grey.shade400),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}

// ── Sistema Tab ───────────────────────────────────────────────────────────────

class _SistemaTab extends StatelessWidget {
  const _SistemaTab();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Funciones del Sistema',
                  style: GoogleFonts.inter(
                      fontSize: 17, fontWeight: FontWeight.w700, color: const Color(0xFF1E293B))),
            ),
            TextButton.icon(
              onPressed: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => const _HistorialApiSheet(),  // sin filtro = todos
              ),
              icon: const Icon(Icons.history_rounded, size: 16),
              label: Text('Historial', style: GoogleFonts.inter(fontSize: 13)),
              style: TextButton.styleFrom(foregroundColor: _primaryColor),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Automatizaciones y servicios Cloud Functions que mantienen los datos actualizados.',
          style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade500),
        ),
        const SizedBox(height: 20),
        _sectionHeader('Automáticas — se ejecutan en horario programado'),
        const SizedBox(height: 10),
        _fnCard(context,
          icon: Icons.download_rounded,
          iconColor: const Color(0xFF0EA5E9),
          name: 'obtenerLicitacionesOCDS',
          badge: '2:00 AM UTC · diaria',
          badgeColor: const Color(0xFF0EA5E9),
          description:
              'Ingesta masiva de licitaciones publicadas en Mercado Público. '
              'Descarga los últimos 2 meses desde la API OCDS y guarda los registros '
              'base en `licitaciones_activas` con estado `procesado: false` para que '
              '`procesarLotesDeLicitaciones` los enriquezca.',
        ),
        _fnCard(context,
          icon: Icons.sync_rounded,
          iconColor: const Color(0xFF8B5CF6),
          name: 'procesarLotesDeLicitaciones',
          badge: 'cada 2 min',
          badgeColor: const Color(0xFF8B5CF6),
          description:
              'Lee hasta 200 licitaciones pendientes (`procesado: false`) y consulta '
              'el detalle completo OCDS por cada una. Extrae título, descripción e ítems, '
              'genera el campo `texto_busqueda` e indexa el documento en Discovery Engine '
              'para búsqueda semántica. Marca `procesado: true` al finalizar.',
        ),
        _fnCard(context,
          icon: Icons.bar_chart_rounded,
          iconColor: const Color(0xFF10B981),
          name: 'calcularEstadisticasDiario',
          badge: '6:00 AM UTC · diaria',
          badgeColor: const Color(0xFF10B981),
          description:
              'Recalcula las estadísticas mensuales de compras públicas. '
              'Itera `licitaciones_ocds` del mes actual, extrae prefijos UNSPSC '
              'de los ítems, agrupa por categoría (top 12) y actualiza el documento '
              '`_stats/resumen` que alimenta los KPIs del panel de inicio.',
        ),
        _fnCard(context,
          icon: Icons.cloud_sync_rounded,
          iconColor: const Color(0xFFF59E0B),
          name: 'refrescarCacheExterno',
          badge: '5:00 AM UTC · diaria',
          badgeColor: const Color(0xFFF59E0B),
          description:
              'Actualiza el caché nocturno de proyectos. Para cada proyecto revisa si '
              'el detalle de licitación (`cache/ocds`, `cache/mp_api`) y las órdenes de '
              'compra (`cache/oc_*`) están presentes y vigentes (< 30 días). '
              'Re-fetcha los que falten directamente desde las APIs de Mercado Público '
              'con concurrencia de 5 para no provocar errores 503.',
        ),
        const SizedBox(height: 20),
        _sectionHeader('Bajo demanda — llamadas por la aplicación'),
        const SizedBox(height: 10),
        _fnCard(context,
          icon: Icons.search_rounded,
          iconColor: const Color(0xFF6366F1),
          name: 'buscarLicitacionPorId',
          badge: 'HTTP · GET',
          badgeColor: const Color(0xFF6366F1),
          description:
              'Consulta el detalle OCDS de una licitación por su código. '
              'Parámetros: `id` (código), `type` (tender/award). '
              'Usado al abrir el panel de detalle de un proyecto con licitación pública o trato directo.',
        ),
        _fnCard(context,
          icon: Icons.receipt_long_rounded,
          iconColor: const Color(0xFF6366F1),
          name: 'buscarOrdenCompra',
          badge: 'HTTP · GET',
          badgeColor: const Color(0xFF6366F1),
          description:
              'Consulta el detalle de una orden de compra por su código. '
              'Retorna el primer resultado del Listado de la API REST de Mercado Público. '
              'Usado en la pestaña Órdenes de Compra del detalle de proyecto.',
        ),
        _fnCard(context,
          icon: Icons.link_rounded,
          iconColor: const Color(0xFF6366F1),
          name: 'obtenerDetalleConvenioMarco',
          badge: 'HTTP · GET',
          badgeColor: const Color(0xFF6366F1),
          description:
              'Hace scraping de la página de un Convenio Marco en Mercado Público. '
              'Extrae título, comprador, estado y campos estructurados usando Cheerio. '
              'Usado al abrir proyectos con modalidad Convenio Marco.',
        ),
        _fnCard(context,
          icon: Icons.cached_rounded,
          iconColor: const Color(0xFF64748B),
          name: 'obtenerCacheExterno / guardarCacheExterno',
          badge: 'HTTP · GET / POST',
          badgeColor: const Color(0xFF64748B),
          description:
              'Lee y escribe el caché de datos externos en la subcolección '
              '`proyectos/{id}/cache/{tipo}`. Los tipos posibles son: `ocds`, `mp_api`, '
              '`oc_{código}` y `convenio`. El caché evita llamadas repetidas a APIs externas '
              'y es la fuente primaria antes de consultar Mercado Público.',
        ),
        _fnCard(context,
          icon: Icons.settings_rounded,
          iconColor: const Color(0xFF64748B),
          name: 'obtenerConfiguracion / guardarConfiguracion',
          badge: 'HTTP · GET / POST',
          badgeColor: const Color(0xFF64748B),
          description:
              'Lee y actualiza el documento de configuración global de la app '
              '(`configuracion/global` en Firestore). Incluye estados, modalidades, '
              'productos y tipos de documento disponibles en los formularios.',
        ),
        _fnCard(context,
          icon: Icons.folder_rounded,
          iconColor: const Color(0xFF64748B),
          name: 'obtenerProyectos',
          badge: 'HTTP · GET',
          badgeColor: const Color(0xFF64748B),
          description:
              'Retorna la lista completa de proyectos del usuario autenticado '
              'desde Firestore. Convierte Timestamps a ISO strings para compatibilidad '
              'con el cliente Flutter. Resultados cacheados en memoria en el cliente.',
        ),
        _fnCard(context,
          icon: Icons.analytics_rounded,
          iconColor: const Color(0xFF0EA5E9),
          name: 'analizarClientesMeetcard',
          badge: 'HTTP · GET',
          badgeColor: const Color(0xFF0EA5E9),
          description:
              'Consulta BigQuery para cruzar las órdenes de compra del sistema con '
              'los proyectos registrados. Identifica clientes nuevos (ausentes) y '
              'presentes, útil para análisis de cartera y detección de oportunidades.',
        ),
        _fnCard(context,
          icon: Icons.person_add_rounded,
          iconColor: const Color(0xFF64748B),
          name: 'crearUsuario',
          badge: 'HTTP · POST · Admin',
          badgeColor: const Color(0xFF64748B),
          description:
              'Crea un nuevo usuario en Firebase Auth con email `@meetcard.cl`. '
              'Solo puede ser llamada por usuarios con rol `admin`. '
              'Verifica el token del llamador y su rol en Firestore antes de proceder.',
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 15, color: Colors.grey.shade400),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Las funciones automáticas se despliegan en Cloud Functions us-central1. '
                  'Los logs están disponibles en Google Cloud Console → Cloud Functions.',
                  style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade500),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionHeader(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Text(text,
            style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade400,
                letterSpacing: 0.4)),
      );

  Widget _fnCard(BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String name,
    required String badge,
    required Color badgeColor,
    required String description,
    _BulkAction? bulkAction,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 4,
              offset: const Offset(0, 1))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Fila principal (tappable → historial)
        InkWell(
          borderRadius: bulkAction == null
              ? BorderRadius.circular(10)
              : const BorderRadius.vertical(top: Radius.circular(10)),
          onTap: () => showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => _HistorialApiSheet(funcion: name),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Text(name,
                          style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF1E293B))),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(badge,
                          style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: badgeColor)),
                    ),
                  ]),
                  const SizedBox(height: 5),
                  Text(description,
                      style: GoogleFonts.inter(
                          fontSize: 12.5,
                          color: Colors.grey.shade600,
                          height: 1.5)),
                ]),
              ),
            ]),
          ),
        ),
        // Botón acción masiva (opcional)
        if (bulkAction != null) ...[
          Divider(height: 1, color: Colors.grey.shade100),
          _BulkActionButton(action: bulkAction),
        ],
      ]),
    );
  }
}

// ── Bulk Action ────────────────────────────────────────────────────────────

class _BulkAction {
  final String label;
  final String confirmTitle;
  final String confirmBody;
  final Future<Map<String, dynamic>> Function() execute;

  const _BulkAction({
    required this.label,
    required this.confirmTitle,
    required this.confirmBody,
    required this.execute,
  });
}

class _BulkActionButton extends StatefulWidget {
  final _BulkAction action;
  const _BulkActionButton({required this.action});
  @override
  State<_BulkActionButton> createState() => _BulkActionButtonState();
}

class _BulkActionButtonState extends State<_BulkActionButton> {
  bool _running = false;
  Map<String, dynamic>? _result;
  String? _error;

  Future<void> _ejecutar() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(widget.action.confirmTitle,
            style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 15)),
        content: Text(widget.action.confirmBody,
            style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade600)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancelar', style: GoogleFonts.inter()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: _primaryColor),
            child: Text('Ejecutar', style: GoogleFonts.inter()),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() { _running = true; _result = null; _error = null; });
    try {
      final res = await widget.action.execute();
      if (mounted) setState(() { _result = res; _running = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _running = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          // Botón ejecutar
          _running
              ? const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: _primaryColor))
              : OutlinedButton.icon(
                  onPressed: _ejecutar,
                  icon: const Icon(Icons.play_arrow_rounded, size: 15),
                  label: Text(widget.action.label,
                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _primaryColor,
                    side: const BorderSide(color: _primaryColor),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
          if (_running) ...[
            const SizedBox(width: 10),
            Text('Ejecutando…',
                style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade500)),
          ],
          // Limpiar resultado
          if (_result != null || _error != null) ...[
            const Spacer(),
            InkWell(
              onTap: () => setState(() { _result = null; _error = null; }),
              child: Icon(Icons.close, size: 14, color: Colors.grey.shade400),
            ),
          ],
        ]),
        // Resultado
        if (_result != null) ...[
          const SizedBox(height: 8),
          _ResultChips(_result!),
        ],
        if (_error != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(_error!,
                style: GoogleFonts.inter(
                    fontSize: 11, color: const Color(0xFFDC2626))),
          ),
        ],
      ]),
    );
  }
}

class _ResultChips extends StatelessWidget {
  final Map<String, dynamic> data;
  const _ResultChips(this.data);

  @override
  Widget build(BuildContext context) {
    // Mostrar campos clave del resultado como chips
    final entries = data.entries
        .where((e) => e.key != 'ok' && e.value != null)
        .toList();
    if (entries.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF0FDF4),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text('Completado correctamente',
            style: GoogleFonts.inter(
                fontSize: 12, color: const Color(0xFF16A34A), fontWeight: FontWeight.w600)),
      );
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: entries.map((e) {
        final label = _labelFor(e.key);
        final val = e.value.toString();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFF0FDF4),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text('$label: $val',
              style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF15803D))),
        );
      }).toList(),
    );
  }

  String _labelFor(String key) {
    const map = {
      'licitaciones': 'Licitaciones',
      'oc': 'OCs',
      'omitidas': 'Omitidas',
      'errores': 'Errores',
      'total': 'Total',
      'procesados': 'Procesados',
      'indexados': 'Indexados',
      'meses': 'Meses',
      'encoladas': 'Encoladas',
      'periodo': 'Período',
    };
    return map[key] ?? key;
  }
}

InputDecoration _inputDecor(String hint) => InputDecoration(
  hintText: hint,
  hintStyle: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade400),
  isDense: true,
  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
);

// ── Add-row widget (stable across parent rebuilds) ─────────────────────────
class _AddRow extends StatefulWidget {
  final String label;
  final String hint;
  final void Function(String) onAdd;
  const _AddRow({required this.label, required this.hint, required this.onAdd});

  @override
  State<_AddRow> createState() => _AddRowState();
}

class _AddRowState extends State<_AddRow> {
  final _ctrl = TextEditingController();
  bool _showing = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final s = _ctrl.text.trim();
    if (s.isNotEmpty) {
      widget.onAdd(s);
      _ctrl.clear();
      setState(() => _showing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_showing) {
      return TextButton.icon(
        onPressed: () => setState(() => _showing = true),
        icon: const Icon(Icons.add, size: 16),
        label: Text(widget.label, style: GoogleFonts.inter(fontSize: 13)),
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
              controller: _ctrl,
              autofocus: true,
              style: GoogleFonts.inter(fontSize: 13),
              decoration: _inputDecor(widget.hint),
              onSubmitted: (_) => _submit(),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: _submit,
            style: TextButton.styleFrom(
              foregroundColor: _primaryColor,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
            child: Text(
              'Agregar',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            onPressed: () {
              _ctrl.clear();
              setState(() => _showing = false);
            },
            icon: Icon(Icons.close, size: 16, color: Colors.grey.shade400),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom sheet: historial de consultas a APIs externas
// ---------------------------------------------------------------------------
class _HistorialApiSheet extends StatefulWidget {
  final String? funcion;
  const _HistorialApiSheet({this.funcion});

  @override
  State<_HistorialApiSheet> createState() => _HistorialApiSheetState();
}

class _HistorialApiSheetState extends State<_HistorialApiSheet> {
  bool _loading = true;
  List<Map<String, dynamic>> _logs = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uri = Uri.parse('$_cfBase/obtenerHistorialApi?limit=200');
      final res = await http.get(uri);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final all = List<Map<String, dynamic>>.from(data['logs'] ?? []);
        setState(() {
          _logs = widget.funcion != null
              ? all.where((l) => l['funcion'] == widget.funcion).toList()
              : all;
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'Error ${res.statusCode}';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Color _estadoColor(String? estado) {
    switch (estado) {
      case 'ok':
        return const Color(0xFF16A34A);
      case 'error':
        return const Color(0xFFDC2626);
      default:
        return Colors.grey;
    }
  }

  String _fmtFecha(String? iso) {
    if (iso == null) return '—';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 4),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
                child: Row(
                  children: [
                    const Icon(Icons.history_rounded, size: 20, color: _primaryColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.funcion != null ? 'Historial' : 'Historial de API',
                            style: GoogleFonts.inter(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF1E293B)),
                          ),
                          if (widget.funcion != null)
                            Text(
                              widget.funcion!,
                              style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: Colors.grey.shade500),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _fetch,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      color: Colors.grey.shade500,
                      tooltip: 'Actualizar',
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, size: 18),
                      color: Colors.grey.shade500,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Center(
                            child: Text(_error!,
                                style: GoogleFonts.inter(
                                    color: Colors.red, fontSize: 13)))
                        : _logs.isEmpty
                            ? Center(
                                child: Text('Sin registros',
                                    style: GoogleFonts.inter(
                                        color: Colors.grey, fontSize: 14)))
                            : ListView.separated(
                                controller: scrollController,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                                itemCount: _logs.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (_, i) {
                                  final log = _logs[i];
                                  final estado = log['estado'] as String?;
                                  final ms = log['ms'] as int?;
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 10),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          width: 8,
                                          height: 8,
                                          margin: const EdgeInsets.only(
                                              top: 4, right: 10),
                                          decoration: BoxDecoration(
                                            color: _estadoColor(estado),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                log['funcion'] ?? '—',
                                                style: GoogleFonts.inter(
                                                    fontSize: 13,
                                                    fontWeight:
                                                        FontWeight.w600,
                                                    color: const Color(
                                                        0xFF1E293B)),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                [
                                                  if (log['tipo'] != null)
                                                    log['tipo'],
                                                  if (log['id'] != null)
                                                    'ID: ${log['id']}',
                                                  if (log['statusCode'] != null)
                                                    'HTTP ${log['statusCode']}',
                                                  if (ms != null) '${ms}ms',
                                                ].join(' · '),
                                                style: GoogleFonts.inter(
                                                    fontSize: 12,
                                                    color: Colors.grey.shade500),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          _fmtFecha(log['timestamp'] as String?),
                                          style: GoogleFonts.inter(
                                              fontSize: 11,
                                              color: Colors.grey.shade400),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
              ),
            ],
          ),
        );
      },
    );
  }
}
