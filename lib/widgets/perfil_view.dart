import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../core/theme/app_colors.dart';
import '../features/proyecto/presentation/providers/sidebar_provider.dart';
import 'walkthrough.dart';

class PerfilView extends StatefulWidget {
  const PerfilView({super.key});

  @override
  State<PerfilView> createState() => _PerfilViewState();
}

class _PerfilViewState extends State<PerfilView> {
  static const _primaryColor = AppColors.primary;
  static const _bgColor = AppColors.background;

  final _nombreCtrl = TextEditingController();
  final _currPassCtrl = TextEditingController();
  final _newPassCtrl = TextEditingController();
  final _confPassCtrl = TextEditingController();

  bool _savingNombre = false;
  bool _savingPass = false;
  String? _nombreMsg;
  String? _passMsg;
  bool _nombreOk = false;
  bool _passOk = false;
  bool _showCurr = false;
  bool _showNew = false;
  bool _showConf = false;

  @override
  void initState() {
    super.initState();
    _nombreCtrl.text = AuthService.instance.perfil?.nombre ?? '';
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _currPassCtrl.dispose();
    _newPassCtrl.dispose();
    _confPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardarNombre() async {
    final nombre = _nombreCtrl.text.trim();
    if (nombre.isEmpty) {
      setState(() { _nombreMsg = 'El nombre no puede estar vacío'; _nombreOk = false; });
      return;
    }
    setState(() { _savingNombre = true; _nombreMsg = null; _nombreOk = false; });
    final err = await AuthService.instance.actualizarNombre(nombre);
    if (mounted) {
      setState(() {
        _savingNombre = false;
        _nombreMsg = err ?? '¡Nombre actualizado!';
        _nombreOk = err == null;
      });
    }
  }

  Future<void> _cambiarPassword() async {
    final curr = _currPassCtrl.text;
    final nueva = _newPassCtrl.text;
    final conf = _confPassCtrl.text;
    if (curr.isEmpty || nueva.isEmpty || conf.isEmpty) {
      setState(() { _passMsg = 'Completa todos los campos'; _passOk = false; });
      return;
    }
    if (nueva != conf) {
      setState(() { _passMsg = 'Las contraseñas no coinciden'; _passOk = false; });
      return;
    }
    if (nueva.length < 6) {
      setState(() { _passMsg = 'La contraseña debe tener al menos 6 caracteres'; _passOk = false; });
      return;
    }
    setState(() { _savingPass = true; _passMsg = null; _passOk = false; });
    final err = await AuthService.instance.cambiarPassword(curr, nueva);
    if (mounted) {
      setState(() {
        _savingPass = false;
        _passMsg = err ?? '¡Contraseña actualizada!';
        _passOk = err == null;
        if (err == null) {
          _currPassCtrl.clear();
          _newPassCtrl.clear();
          _confPassCtrl.clear();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final perfil = AuthService.instance.perfil;
    return LayoutBuilder(builder: (ctx, constraints) {
      final isMobile = constraints.maxWidth < 700;
      final hPad = isMobile ? 20.0 : 32.0;

      return Scaffold(
        backgroundColor: _bgColor,
        body: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(hPad, isMobile ? 80 : 24, hPad, 48),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Avatar + info
                  Row(children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundColor: _primaryColor.withValues(alpha: 0.1),
                      child: Text(
                        (perfil?.nombre.isNotEmpty == true
                                ? perfil!.nombre[0]
                                : '?')
                            .toUpperCase(),
                        style: GoogleFonts.inter(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: _primaryColor),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(
                        perfil?.nombre ?? '—',
                        style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        perfil?.email ?? '',
                        style: GoogleFonts.inter(
                            fontSize: 13, color: Colors.grey.shade500),
                      ),
                      if (perfil?.esAdmin == true) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: _primaryColor.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'Administrador',
                            style: GoogleFonts.inter(
                                fontSize: 11,
                                color: _primaryColor,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ]),
                  ]),
                  const SizedBox(height: 32),

                  // Section: Nombre
                  _sectionTitle('Datos personales'),
                  const SizedBox(height: 14),
                  _card(children: [
                    _fieldLabel('NOMBRE COMPLETO'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _nombreCtrl,
                      style: GoogleFonts.inter(fontSize: 14),
                      decoration: _deco('Ej: Juan Pérez'),
                    ),
                    if (_nombreMsg != null) ...[
                      const SizedBox(height: 8),
                      _msgRow(_nombreMsg!, _nombreOk),
                    ],
                    const SizedBox(height: 16),
                    _fieldLabel('CORREO ELECTRÓNICO'),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceAlt,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Text(
                        perfil?.email ?? '',
                        style: GoogleFonts.inter(
                            fontSize: 14, color: Colors.grey.shade500),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _saveBtn(
                      label: 'Guardar nombre',
                      loading: _savingNombre,
                      onPressed: _guardarNombre,
                    ),
                  ]),

                  const SizedBox(height: 24),

                  // Section: Password
                  _sectionTitle('Cambiar contraseña'),
                  const SizedBox(height: 14),
                  _card(children: [
                    _fieldLabel('CONTRASEÑA ACTUAL'),
                    const SizedBox(height: 6),
                    _passField(_currPassCtrl, 'Contraseña actual', _showCurr,
                        () => setState(() => _showCurr = !_showCurr)),
                    const SizedBox(height: 12),
                    _fieldLabel('NUEVA CONTRASEÑA'),
                    const SizedBox(height: 6),
                    _passField(_newPassCtrl, 'Mínimo 6 caracteres', _showNew,
                        () => setState(() => _showNew = !_showNew)),
                    const SizedBox(height: 12),
                    _fieldLabel('CONFIRMAR NUEVA CONTRASEÑA'),
                    const SizedBox(height: 6),
                    _passField(_confPassCtrl, 'Repite la nueva contraseña', _showConf,
                        () => setState(() => _showConf = !_showConf)),
                    if (_passMsg != null) ...[
                      const SizedBox(height: 8),
                      _msgRow(_passMsg!, _passOk),
                    ],
                    const SizedBox(height: 20),
                    _saveBtn(
                      label: 'Cambiar contraseña',
                      loading: _savingPass,
                      onPressed: _cambiarPassword,
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }

  Widget _sectionTitle(String t) => Text(
        t,
        style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary),
      );

  Widget _card({required List<Widget> children}) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );

  Widget _fieldLabel(String t) => Text(
        t,
        style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade400,
            letterSpacing: 0.4),
      );

  InputDecoration _deco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.inter(fontSize: 14, color: Colors.grey.shade300),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade200)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade200)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide:
                const BorderSide(color: _primaryColor, width: 1.5)),
      );

  Widget _passField(TextEditingController ctrl, String hint, bool show,
          VoidCallback toggle) =>
      TextField(
        controller: ctrl,
        obscureText: !show,
        style: GoogleFonts.inter(fontSize: 14),
        decoration: _deco(hint).copyWith(
          suffixIcon: IconButton(
            icon: Icon(
              show ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              size: 18,
              color: Colors.grey.shade400,
            ),
            onPressed: toggle,
          ),
        ),
      );

  Widget _msgRow(String msg, bool ok) => Row(children: [
        Icon(
          ok ? Icons.check_circle_outline : Icons.error_outline,
          size: 14,
          color: ok ? AppColors.success : Colors.red.shade600,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            msg,
            style: GoogleFonts.inter(
                fontSize: 12,
                color: ok ? AppColors.success : Colors.red.shade600),
          ),
        ),
      ]);

  Widget _saveBtn(
          {required String label,
          required bool loading,
          required VoidCallback onPressed}) =>
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: loading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: _primaryColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            elevation: 0,
          ),
          child: loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : Text(label,
                  style: GoogleFonts.inter(
                      fontSize: 14, fontWeight: FontWeight.w600)),
        ),
      );
}
