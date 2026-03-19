import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/auth_service.dart';

class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  static const _primaryColor = Color(0xFF1E1B6B);

  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  bool _showPass = false;
  String? _error;
  bool _resetMode = false;
  bool _resetSent = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;
    if (email.isEmpty || pass.isEmpty) {
      setState(() => _error = 'Completa todos los campos');
      return;
    }
    setState(() { _loading = true; _error = null; });
    final err = await AuthService.instance.login(email, pass);
    if (mounted) setState(() { _loading = false; _error = err; });
  }

  Future<void> _sendReset() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Ingresa tu correo para recuperar contraseña');
      return;
    }
    setState(() { _loading = true; _error = null; });
    final err = await AuthService.instance.resetPassword(email);
    if (mounted) {
      setState(() {
        _loading = false;
        _error = err;
        if (err == null) _resetSent = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo / brand
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: _primaryColor,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(Icons.search, color: Colors.white, size: 32),
                ),
                const SizedBox(height: 20),
                Text(
                  'CRM',
                  style: GoogleFonts.inter(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF1E293B),
                    letterSpacing: -0.7,
                  ),
                ),
                const SizedBox(height: 36),

                // Card
                Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.07),
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: _resetMode ? _buildResetForm() : _buildLoginForm(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Iniciar sesión',
          style: GoogleFonts.inter(
              fontSize: 18, fontWeight: FontWeight.w700, color: const Color(0xFF1E293B)),
        ),
        const SizedBox(height: 4),
        const SizedBox(height: 24),

        _label('CORREO ELECTRÓNICO'),
        const SizedBox(height: 6),
        _field(
          controller: _emailCtrl,
          hint: 'usuario@correo.cl',
          keyboardType: TextInputType.emailAddress,
          onSubmit: (_) => _login(),
        ),
        const SizedBox(height: 14),

        _label('CONTRASEÑA'),
        const SizedBox(height: 6),
        _field(
          controller: _passCtrl,
          hint: '••••••••',
          obscure: !_showPass,
          suffix: IconButton(
            icon: Icon(
              _showPass ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              size: 18,
              color: Colors.grey.shade400,
            ),
            onPressed: () => setState(() => _showPass = !_showPass),
          ),
          onSubmit: (_) => _login(),
        ),

        if (_error != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Row(children: [
              Icon(Icons.error_outline, size: 14, color: Colors.red.shade600),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_error!,
                    style: GoogleFonts.inter(fontSize: 12, color: Colors.red.shade700)),
              ),
            ]),
          ),
        ],

        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _loading ? null : _login,
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text('Ingresar',
                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(height: 14),
        Center(
          child: TextButton(
            onPressed: () => setState(() { _resetMode = true; _error = null; }),
            child: Text(
              '¿Olvidaste tu contraseña?',
              style: GoogleFonts.inter(
                  fontSize: 12,
                  color: _primaryColor.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w500),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResetForm() {
    if (_resetSent) {
      return Column(
        children: [
          const Icon(Icons.mark_email_read_outlined, size: 48, color: Color(0xFF10B981)),
          const SizedBox(height: 16),
          Text(
            'Correo enviado',
            style: GoogleFonts.inter(
                fontSize: 18, fontWeight: FontWeight.w700, color: const Color(0xFF1E293B)),
          ),
          const SizedBox(height: 8),
          Text(
            'Revisa tu bandeja de entrada y sigue las instrucciones para recuperar tu contraseña.',
            style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade500, height: 1.5),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          TextButton(
            onPressed: () => setState(() { _resetMode = false; _resetSent = false; }),
            child: Text('Volver al inicio de sesión',
                style: GoogleFonts.inter(fontSize: 13, color: _primaryColor, fontWeight: FontWeight.w500)),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recuperar contraseña',
          style: GoogleFonts.inter(
              fontSize: 18, fontWeight: FontWeight.w700, color: const Color(0xFF1E293B)),
        ),
        const SizedBox(height: 4),
        Text(
          'Te enviaremos un enlace para restablecer tu contraseña',
          style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade400, height: 1.4),
        ),
        const SizedBox(height: 24),
        _label('CORREO ELECTRÓNICO'),
        const SizedBox(height: 6),
        _field(
          controller: _emailCtrl,
          hint: 'usuario@correo.cl',
          keyboardType: TextInputType.emailAddress,
          onSubmit: (_) => _sendReset(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: GoogleFonts.inter(fontSize: 12, color: Colors.red.shade600)),
        ],
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _loading ? null : _sendReset,
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text('Enviar enlace',
                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed: () => setState(() { _resetMode = false; _error = null; }),
            child: Text(
              'Volver',
              style: GoogleFonts.inter(
                  fontSize: 12,
                  color: Colors.grey.shade500,
                  fontWeight: FontWeight.w500),
            ),
          ),
        ),
      ],
    );
  }

  Widget _label(String text) => Text(
        text,
        style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade400,
            letterSpacing: 0.5),
      );

  Widget _field({
    required TextEditingController controller,
    required String hint,
    TextInputType? keyboardType,
    bool obscure = false,
    Widget? suffix,
    void Function(String)? onSubmit,
  }) =>
      TextField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscure,
        style: GoogleFonts.inter(fontSize: 14),
        onSubmitted: onSubmit,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.inter(fontSize: 14, color: Colors.grey.shade300),
          suffixIcon: suffix,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade200)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade200)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _primaryColor, width: 1.5)),
        ),
      );
}
