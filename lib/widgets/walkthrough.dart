import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ── Colores del proyecto ──────────────────────────────────────────────────────
const _primaryColor = Color(0xFF007AFF);

// ── Step model ────────────────────────────────────────────────────────────────

class WalkthroughStep {
  final String title;
  final IconData icon;
  final Color color;
  String body; // mutable para edición

  WalkthroughStep({
    required this.title,
    required this.icon,
    required this.color,
    required this.body,
  });

  WalkthroughStep copyWith({String? title, String? body}) => WalkthroughStep(
    title: title ?? this.title,
    icon: icon,
    color: color,
    body: body ?? this.body,
  );
}

// ── Defaults ──────────────────────────────────────────────────────────────────

List<WalkthroughStep> _defaultSteps() => [
  WalkthroughStep(
    title: 'Resumen del Dashboard',
    icon: Icons.dashboard_outlined,
    color: _primaryColor,
    body:
        'El dashboard muestra el estado general de tu cartera de proyectos.\n\n'
        '• **KPIs superiores**: proyectos vigentes, facturación mensual activa y monto total de órdenes de compra.\n'
        '• **Gráficos**: evolución trimestral de clientes nuevos/perdidos y montos.\n'
        '• **Listado**: todos los proyectos con filtros por estado, institución y período.\n\n'
        'Haz clic en cualquier barra del gráfico para filtrar el listado por ese trimestre.',
  ),
  WalkthroughStep(
    title: 'Clientes Nuevos / Quarter',
    icon: Icons.people_outline_rounded,
    color: Color(0xFF0EA5E9),
    body:
        'Cuenta cuántas instituciones contrataron con Meetcard por primera vez en cada trimestre.\n\n'
        '**Reglas de conteo:**\n'
        '• Solo se cuentan proyectos con al menos una Orden de Compra registrada.\n'
        '• Cada institución se cuenta **una sola vez**, en el trimestre de su primera OC.\n'
        '• Si la misma institución tiene múltiples proyectos, solo suma en su primer trimestre.\n\n'
        '**Barras rojas (Churn):** instituciones que terminaron contrato sin renovar.',
  ),
  WalkthroughStep(
    title: 'Pérdida de Clientes (Churn)',
    icon: Icons.trending_down_rounded,
    color: Color(0xFFEF4444),
    body:
        'Un proyecto se cuenta como churn (cliente perdido) cuando cumple todo esto:\n\n'
        '• Tiene Orden de Compra registrada.\n'
        '• Estado **Finalizado** (fecha de término ya pasó).\n'
        '• Han transcurrido más de **90 días** desde el término (período de gracia).\n'
        '• La institución **no tiene otro proyecto activo** con OC.\n'
        '• No está **encadenado** a un proyecto sucesor.\n\n'
        'Usa el botón **"Encadenar"** en el detalle del proyecto para marcar una renovación.',
  ),
  WalkthroughStep(
    title: 'Monto Mensual / Quarter',
    icon: Icons.bar_chart_rounded,
    color: Color(0xFF8B5CF6),
    body:
        'Muestra la suma de **valor mensual** de todos los proyectos activos por trimestre.\n\n'
        '**Tres vistas disponibles:**\n'
        '• **M (Mensual)**: suma del valor mensual contractual por trimestre de inicio.\n'
        '• **T (Acumulado)**: facturación mensual acumulada histórica.\n'
        '• **∑ OC**: monto total de las órdenes de compra emitidas.\n\n'
        'Haz clic en una barra para ver qué proyectos componen ese trimestre.',
  ),
  WalkthroughStep(
    title: 'Estados de Proyecto',
    icon: Icons.circle_outlined,
    color: Color(0xFF16A34A),
    body:
        'El estado se calcula automáticamente desde la fecha de término:\n\n'
        '• 🟢 **Vigente**: la fecha de término es mayor a 30 días.\n'
        '• 🟡 **X Vencer**: la fecha de término es en menos de 30 días.\n'
        '• 🔴 **Finalizado**: la fecha de término ya pasó.\n'
        '• ⚪ **Sin fecha**: no tiene fecha de término registrada.\n\n'
        'El campo **"Estado manual"** tiene prioridad sobre el estado calculado.',
  ),
  WalkthroughStep(
    title: 'Filtros del Listado',
    icon: Icons.filter_list_rounded,
    color: Color(0xFF0F766E),
    body:
        'Puedes combinar múltiples filtros simultáneamente:\n\n'
        '• **Estado**: Vigente, X Vencer, Finalizado, Sin fecha.\n'
        '• **Institución**: búsqueda por nombre, deduplicada.\n'
        '• **Modalidad**: Licitación Pública, Convenio Marco, etc.\n'
        '• **Trimestre**: activado al hacer clic en una barra del gráfico.\n\n'
        'El botón **"Limpiar"** restablece todos los filtros de una vez.',
  ),
  WalkthroughStep(
    title: 'Detalle del Proyecto',
    icon: Icons.folder_open_outlined,
    color: _primaryColor,
    body:
        'Cada proyecto tiene secciones expandibles:\n\n'
        '• **Órdenes de Compra**: fechas de envío y aceptación, proveedor, monto.\n'
        '• **Reclamos**: registro con estado y documentos de respuesta.\n'
        '• **Certificados de experiencia**: documentos de acreditación emitidos.\n'
        '• **Notas**: observaciones internas.\n\n'
        '**Encadenar**: vincula este proyecto con su sucesor. Evita que se cuente como churn y mantiene la continuidad de la relación comercial.',
  ),
  WalkthroughStep(
    title: 'Análisis BigQuery',
    icon: Icons.analytics_outlined,
    color: Color(0xFF0369A1),
    body:
        'En la vista **Migración CSV** encontrarás herramientas de validación:\n\n'
        '• **Detectar duplicados**: unifica proyectos con el mismo ID de licitación consolidando todas las OCs.\n'
        '• **Analizar OC vs Proyectos**: cruza BigQuery con tus proyectos para detectar:\n'
        '  — OCs en BQ no registradas en el proyecto.\n'
        '  — Licitaciones en BQ sin proyecto creado en la app.\n'
        '• Los botones de corrección aplican los cambios directamente.',
  ),
];

// ── HelpStepsStore ────────────────────────────────────────────────────────────

/// Singleton que gestiona los textos del walkthrough.
/// Carga desde Firestore al inicializar; permite editar y guardar.
class HelpStepsStore extends ChangeNotifier {
  static final instance = HelpStepsStore._();
  HelpStepsStore._();

  List<WalkthroughStep> _steps = _defaultSteps();
  List<WalkthroughStep> get steps => _steps;
  bool loaded = false;

  /// Llama esto una vez al arrancar la app (o al abrir Configuración).
  Future<void> load() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('configuracion')
          .doc('ayuda_textos')
          .get();
      if (doc.exists) {
        final list = (doc.data()?['steps'] as List?)
            ?.cast<Map<String, dynamic>>() ?? [];
        final defaults = _defaultSteps();
        if (list.isNotEmpty) {
          _steps = List.generate(defaults.length, (i) {
            final override = i < list.length ? list[i] : null;
            return defaults[i].copyWith(
              title: override?['title'] as String?,
              body:  override?['body']  as String?,
            );
          });
          notifyListeners();
        }
      }
    } catch (_) {}
    loaded = true;
  }

  /// Actualiza el body de un paso en memoria.
  void updateBody(int index, String body) {
    _steps[index].body = body;
    notifyListeners();
  }

  /// Actualiza el título de un paso en memoria.
  void updateTitle(int index, String title) {
    // crea una copia con el nuevo título
    _steps[index] = _steps[index].copyWith(title: title);
    notifyListeners();
  }

  /// Persiste todos los pasos en Firestore.
  Future<void> save() async {
    await FirebaseFirestore.instance
        .collection('configuracion')
        .doc('ayuda_textos')
        .set({
      'steps': _steps
          .map((s) => {'title': s.title, 'body': s.body})
          .toList(),
    });
  }

  /// Restaura los textos por defecto (en memoria; llama save() para persistir).
  void reset() {
    _steps = _defaultSteps();
    notifyListeners();
  }
}

// ── HelpController ────────────────────────────────────────────────────────────

class HelpController extends ChangeNotifier {
  static final instance = HelpController._();
  HelpController._();

  bool _enabled = false;
  bool get enabled => _enabled;

  void toggle() {
    _enabled = !_enabled;
    notifyListeners();
  }

  void disable() {
    if (_enabled) { _enabled = false; notifyListeners(); }
  }
}

// ── HelpBadge ─────────────────────────────────────────────────────────────────

class HelpBadge extends StatelessWidget {
  final WalkthroughStep step;
  const HelpBadge(this.step, {super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: HelpController.instance,
      builder: (context, _) {
        if (!HelpController.instance.enabled) return const SizedBox.shrink();
        return GestureDetector(
          onTap: () => _showSheet(context),
          child: Container(
            margin: const EdgeInsets.only(left: 6),
            width: 20, height: 20,
            decoration: BoxDecoration(
              color: step.color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(color: step.color.withValues(alpha: 0.4)),
            ),
            child: Icon(Icons.question_mark_rounded, size: 12, color: step.color),
          ),
        );
      },
    );
  }

  void _showSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _HelpSheet(step: step),
    );
  }
}

// ── HelpSheet (estilo Apple) ──────────────────────────────────────────────────

class _HelpSheet extends StatelessWidget {
  final WalkthroughStep step;
  const _HelpSheet({required this.step});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 12, 24, MediaQuery.of(context).viewInsets.bottom + 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(child: Container(
            width: 36, height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFD1D5DB),
              borderRadius: BorderRadius.circular(2),
            ),
          )),
          const SizedBox(height: 20),
          // Icon + title
          Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: step.color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(step.icon, size: 22, color: step.color),
            ),
            const SizedBox(width: 14),
            Expanded(child: Text(step.title,
                style: GoogleFonts.inter(fontSize: 17,
                    fontWeight: FontWeight.w700, color: const Color(0xFF1C1C1E)))),
          ]),
          const SizedBox(height: 18),
          // Body
          _RichBody(step.body, baseColor: step.color),
          const SizedBox(height: 20),
          // Footer actions
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  WalkthroughDialog.show(context);
                },
                icon: Icon(Icons.menu_book_outlined, size: 15, color: step.color),
                label: Text('Ver guía completa',
                    style: GoogleFonts.inter(fontSize: 13,
                        fontWeight: FontWeight.w500, color: step.color)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: step.color.withValues(alpha: 0.4)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFF2F2F7),
                  foregroundColor: const Color(0xFF1C1C1E),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  elevation: 0,
                ),
                child: Text('Cerrar',
                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500)),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

// ── WalkthroughDialog (estilo Apple) ─────────────────────────────────────────

class WalkthroughDialog extends StatefulWidget {
  final int initialStep;
  const WalkthroughDialog({super.key, this.initialStep = 0});

  static void show(BuildContext context, {int initialStep = 0}) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Cerrar',
      barrierColor: Colors.black.withValues(alpha: 0.45),
      transitionDuration: const Duration(milliseconds: 320),
      transitionBuilder: (ctx, anim, _, child) => ScaleTransition(
        scale: CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
        child: FadeTransition(opacity: anim, child: child),
      ),
      pageBuilder: (ctx, _, __) =>
          WalkthroughDialog(initialStep: initialStep),
    );
  }

  @override
  State<WalkthroughDialog> createState() => _WalkthroughDialogState();
}

class _WalkthroughDialogState extends State<WalkthroughDialog> {
  late int _step;
  late final PageController _pc;

  @override
  void initState() {
    super.initState();
    _step = widget.initialStep;
    _pc = PageController(initialPage: _step);
    if (!HelpStepsStore.instance.loaded) HelpStepsStore.instance.load();
  }

  @override
  void dispose() { _pc.dispose(); super.dispose(); }

  void _go(int index) {
    setState(() => _step = index);
    _pc.animateToPage(index,
        duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: HelpStepsStore.instance,
      builder: (context, _) {
        final steps = HelpStepsStore.instance.steps;
        if (_step >= steps.length) _step = 0;
        final step   = steps[_step];
        final isLast = _step == steps.length - 1;

        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 480,
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.82,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 40, offset: const Offset(0, 16)),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── Header con gradiente ──────────────────────────────
                    Container(
                      padding: const EdgeInsets.fromLTRB(22, 22, 18, 18),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            step.color.withValues(alpha: 0.08),
                            step.color.withValues(alpha: 0.02),
                          ],
                        ),
                      ),
                      child: Row(children: [
                        Container(
                          width: 46, height: 46,
                          decoration: BoxDecoration(
                            color: step.color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(step.icon, size: 24, color: step.color),
                        ),
                        const SizedBox(width: 14),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Guía de uso  ${_step + 1}/${steps.length}',
                                style: GoogleFonts.inter(fontSize: 11,
                                    color: step.color, fontWeight: FontWeight.w600,
                                    letterSpacing: 0.3)),
                            const SizedBox(height: 2),
                            Text(step.title,
                                style: GoogleFonts.inter(fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF1C1C1E))),
                          ],
                        )),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20,
                              color: Color(0xFF8E8E93)),
                          onPressed: () => Navigator.pop(context),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        ),
                      ]),
                    ),

                    // ── Content ───────────────────────────────────────────
                    Flexible(
                      child: PageView.builder(
                        controller: _pc,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: steps.length,
                        itemBuilder: (_, i) => SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
                          child: _RichBody(steps[i].body,
                              baseColor: steps[i].color),
                        ),
                      ),
                    ),

                    // ── Footer ────────────────────────────────────────────
                    Container(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                      decoration: const BoxDecoration(
                        border: Border(
                            top: BorderSide(color: Color(0xFFF0F0F0))),
                      ),
                      child: Row(children: [
                        // Progress dots
                        Expanded(
                          child: Wrap(spacing: 5, children:
                            List.generate(steps.length, (i) =>
                              GestureDetector(
                                onTap: () => _go(i),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 220),
                                  width: i == _step ? 20 : 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    color: i == _step
                                        ? step.color
                                        : const Color(0xFFD1D5DB),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        if (_step > 0) ...[
                          _NavBtn(
                            label: 'Anterior',
                            onTap: () => _go(_step - 1),
                            filled: false,
                            color: step.color,
                          ),
                          const SizedBox(width: 8),
                        ],
                        _NavBtn(
                          label: isLast ? 'Cerrar' : 'Siguiente',
                          onTap: isLast
                              ? () => Navigator.pop(context)
                              : () => _go(_step + 1),
                          filled: true,
                          color: step.color,
                        ),
                      ]),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NavBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool filled;
  final Color color;
  const _NavBtn({required this.label, required this.onTap,
      required this.filled, required this.color});

  @override
  Widget build(BuildContext context) {
    if (filled) {
      return FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
        child: Text(label, style: GoogleFonts.inter(fontSize: 13,
            fontWeight: FontWeight.w600)),
      );
    }
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF6B7280),
        side: const BorderSide(color: Color(0xFFE5E7EB)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(label, style: GoogleFonts.inter(fontSize: 13)),
    );
  }
}

// ── HelpToggleButton ──────────────────────────────────────────────────────────

class HelpToggleButton extends StatelessWidget {
  const HelpToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: HelpController.instance,
      builder: (context, _) {
        final on = HelpController.instance.enabled;
        return Row(mainAxisSize: MainAxisSize.min, children: [
          if (on)
            TextButton.icon(
              onPressed: () => WalkthroughDialog.show(context),
              icon: const Icon(Icons.menu_book_outlined, size: 16),
              label: Text('Guía', style: GoogleFonts.inter(fontSize: 12,
                  fontWeight: FontWeight.w500)),
              style: TextButton.styleFrom(
                foregroundColor: _primaryColor,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
          IconButton(
            tooltip: on ? 'Desactivar ayuda' : 'Activar ayuda',
            icon: Icon(
              on ? Icons.help_rounded : Icons.help_outline_rounded,
              size: 22,
              color: on ? _primaryColor : const Color(0xFF94A3B8),
            ),
            onPressed: HelpController.instance.toggle,
          ),
        ]);
      },
    );
  }
}

// ── RichBody ──────────────────────────────────────────────────────────────────

class _RichBody extends StatelessWidget {
  final String text;
  final Color baseColor;
  const _RichBody(this.text, {required this.baseColor});

  @override
  Widget build(BuildContext context) {
    final lines = text.split('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines.map((line) {
        if (line.isEmpty) return const SizedBox(height: 6);
        return Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: _parseLine(line));
      }).toList(),
    );
  }

  Widget _parseLine(String line) {
    final indent = line.startsWith('  — ') ? 16.0 : 0.0;
    final isBullet = line.startsWith('• ') || line.startsWith('  — ');
    final cleaned = isBullet
        ? (line.startsWith('  — ') ? line.substring(4) : line.substring(2))
        : line;

    return Padding(
      padding: EdgeInsets.only(left: indent),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (isBullet) ...[
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 8),
            child: Container(
              width: 5, height: 5,
              decoration: BoxDecoration(
                color: baseColor.withValues(alpha: 0.55),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
        Expanded(child: _parseInline(cleaned)),
      ]),
    );
  }

  Widget _parseInline(String text) {
    final spans = <TextSpan>[];
    final re = RegExp(r'\*\*(.+?)\*\*');
    int last = 0;
    for (final m in re.allMatches(text)) {
      if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
      spans.add(TextSpan(text: m.group(1),
          style: const TextStyle(fontWeight: FontWeight.w700,
              color: Color(0xFF1C1C1E))));
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return RichText(
      text: TextSpan(
        style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF3C3C43),
            height: 1.6),
        children: spans,
      ),
    );
  }
}

// ── HelpTextsEditor ───────────────────────────────────────────────────────────
// Widget para ConfiguracionView (tab de textos de ayuda)

class HelpTextsEditor extends StatefulWidget {
  const HelpTextsEditor({super.key});

  @override
  State<HelpTextsEditor> createState() => _HelpTextsEditorState();
}

class _HelpTextsEditorState extends State<HelpTextsEditor> {
  bool _saving = false;
  bool _dirty  = false;
  late List<TextEditingController> _titleCtrls;
  late List<TextEditingController> _bodyCtrls;

  @override
  void initState() {
    super.initState();
    _initControllers();
    if (!HelpStepsStore.instance.loaded) {
      HelpStepsStore.instance.load().then((_) {
        if (mounted) {
          _disposeControllers();
          _initControllers();
          setState(() {});
        }
      });
    }
  }

  void _initControllers() {
    final steps = HelpStepsStore.instance.steps;
    _titleCtrls = steps.map((s) => TextEditingController(text: s.title)).toList();
    _bodyCtrls  = steps.map((s) => TextEditingController(text: s.body)).toList();
  }

  void _disposeControllers() {
    for (final c in _titleCtrls) { c.dispose(); }
    for (final c in _bodyCtrls)  { c.dispose(); }
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final store = HelpStepsStore.instance;
    for (int i = 0; i < store.steps.length; i++) {
      store.updateTitle(i, _titleCtrls[i].text.trim());
      store.updateBody(i,  _bodyCtrls[i].text.trim());
    }
    await store.save();
    if (mounted) setState(() { _saving = false; _dirty = false; });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Textos guardados')),
      );
    }
  }

  void _reset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Restaurar por defecto',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
        content: Text('Se restaurarán todos los textos a sus valores originales.',
            style: GoogleFonts.inter()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancelar', style: GoogleFonts.inter())),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: Text('Restaurar', style: GoogleFonts.inter(fontWeight: FontWeight.w600))),
        ],
      ),
    );
    if (ok != true) return;
    HelpStepsStore.instance.reset();
    await HelpStepsStore.instance.save();
    _disposeControllers();
    _initControllers();
    if (mounted) setState(() => _dirty = false);
  }

  @override
  Widget build(BuildContext context) {
    final steps = HelpStepsStore.instance.steps;
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 48),
      children: [
        // Info banner
        Container(
          margin: const EdgeInsets.only(bottom: 20),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _primaryColor.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _primaryColor.withValues(alpha: 0.15)),
          ),
          child: Row(children: [
            Icon(Icons.info_outline, size: 16, color: _primaryColor),
            const SizedBox(width: 10),
            Expanded(child: Text(
              'Edita los textos de la guía de ayuda. Usa **negrita** para resaltar '
              'términos. Los cambios se reflejan inmediatamente al abrir la guía.',
              style: GoogleFonts.inter(fontSize: 12, color: _primaryColor),
            )),
          ]),
        ),

        // Step cards
        ...List.generate(steps.length, (i) {
          final step = steps[i];
          return Container(
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Header del paso
              Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                decoration: BoxDecoration(
                  color: step.color.withValues(alpha: 0.05),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  border: Border(bottom: BorderSide(
                      color: step.color.withValues(alpha: 0.12))),
                ),
                child: Row(children: [
                  Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: step.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(step.icon, size: 16, color: step.color),
                  ),
                  const SizedBox(width: 10),
                  Text('Paso ${i + 1}',
                      style: GoogleFonts.inter(fontSize: 12,
                          fontWeight: FontWeight.w600, color: step.color)),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Título
                    Text('Título',
                        style: GoogleFonts.inter(fontSize: 11,
                            color: const Color(0xFF6B7280),
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _titleCtrls[i],
                      onChanged: (_) => setState(() => _dirty = true),
                      style: GoogleFonts.inter(fontSize: 13,
                          fontWeight: FontWeight.w600),
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                                color: Color(0xFFE5E7EB))),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                                color: Color(0xFFE5E7EB))),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: step.color)),
                        filled: true,
                        fillColor: const Color(0xFFFAFAFA),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Body
                    Text('Descripción',
                        style: GoogleFonts.inter(fontSize: 11,
                            color: const Color(0xFF6B7280),
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _bodyCtrls[i],
                      onChanged: (_) => setState(() => _dirty = true),
                      maxLines: 8,
                      style: GoogleFonts.inter(fontSize: 12.5, height: 1.55),
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.all(12),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                                color: Color(0xFFE5E7EB))),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                                color: Color(0xFFE5E7EB))),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: step.color)),
                        filled: true,
                        fillColor: const Color(0xFFFAFAFA),
                        hintText: 'Escribe la descripción...',
                        hintStyle: GoogleFonts.inter(
                            fontSize: 12, color: const Color(0xFF9CA3AF)),
                      ),
                    ),
                  ],
                ),
              ),
            ]),
          );
        }),

        // Botones de acción
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _saving ? null : _reset,
              icon: const Icon(Icons.restart_alt, size: 16),
              label: Text('Restaurar por defecto',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF6B7280),
                side: const BorderSide(color: Color(0xFFE5E7EB)),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.icon(
              onPressed: (_saving || !_dirty) ? null : _save,
              icon: _saving
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2,
                          color: Colors.white))
                  : const Icon(Icons.save_outlined, size: 16),
              label: Text('Guardar cambios',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
              style: FilledButton.styleFrom(
                backgroundColor: _primaryColor,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                disabledBackgroundColor: const Color(0xFFE5E7EB),
              ),
            ),
          ),
        ]),
      ],
    );
  }
}
