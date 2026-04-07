import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/usuario.dart';
import '../services/auth_service.dart';
import '../core/theme/app_colors.dart';

class AdminUsuariosView extends StatefulWidget {
  const AdminUsuariosView({super.key});

  @override
  State<AdminUsuariosView> createState() => _AdminUsuariosViewState();
}

class _AdminUsuariosViewState extends State<AdminUsuariosView> {
  static const _primaryColor = AppColors.primary;
  static const _bgColor = AppColors.background;

  UserProfile? _selected;

  // Section labels for permission UI
  static const _secciones = [
    (key: 'inicio', label: 'Inicio', icon: Icons.home_outlined),
    (key: 'proyectos', label: 'Proyectos', icon: Icons.folder_outlined),
    (key: 'configuracion', label: 'Configuración', icon: Icons.settings_outlined),
  ];

  static const _accionesPorSeccion = {
    'inicio': [('ver', 'Ver')],
    'proyectos': [
      ('ver', 'Ver'),
      ('crear', 'Crear'),
      ('editar', 'Editar'),
      ('eliminar', 'Eliminar'),
    ],
    'configuracion': [('ver', 'Ver'), ('editar', 'Editar')],
  };

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, constraints) {
      final isMobile = constraints.maxWidth < 700;
      final hPad = isMobile ? 20.0 : 32.0;

      return Scaffold(
        backgroundColor: _bgColor,
        body: StreamBuilder<List<UserProfile>>(
          stream: AuthService.instance.usuariosStream(),
          builder: (context, snap) {
            final usuarios = snap.data ?? [];

            if (isMobile) {
              return _buildMobile(usuarios, hPad);
            }
            return _buildDesktop(usuarios, hPad);
          },
        ),
      );
    });
  }

  // ── DESKTOP layout: list + side panel ────────────────────────────────────

  Widget _buildDesktop(List<UserProfile> usuarios, double hPad) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left: user list
          SizedBox(
            width: 320,
            child: Column(children: [
              _addButton(),
              const SizedBox(height: 12),
              Expanded(child: _userList(usuarios)),
            ]),
          ),
          const SizedBox(width: 20),
          // Right: permissions panel
          Expanded(
            child: _selected == null
                ? _emptyPanel()
                : _permisosPanel(_selected!),
          ),
        ],
      ),
    );
  }

  // ── MOBILE layout: list only; tap opens bottom sheet ─────────────────────

  Widget _buildMobile(List<UserProfile> usuarios, double hPad) {
    final isMobile = MediaQuery.of(context).size.width < 700;
    return Padding(
      padding: EdgeInsets.fromLTRB(hPad, isMobile ? 80 : 24, hPad, 48),
      child: Column(children: [
        _addButton(),
        const SizedBox(height: 12),
        Expanded(child: _userList(usuarios)),
      ]),
    );
  }

  void _openPermisosSheet(UserProfile u) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, ctrl) => StreamBuilder<List<UserProfile>>(
          stream: AuthService.instance.usuariosStream(),
          builder: (context, snap) {
            final fresh =
                snap.data?.firstWhere((x) => x.uid == u.uid, orElse: () => u) ?? u;
            return _permisosPanel(fresh, scrollController: ctrl);
          },
        ),
      ),
    );
  }

  // ── User list ─────────────────────────────────────────────────────────────

  Widget _userList(List<UserProfile> usuarios) {
    if (usuarios.isEmpty) {
      return Container(
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(14)),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.people_outline, size: 40, color: Colors.grey.shade200),
            const SizedBox(height: 8),
            Text('Sin usuarios',
                style: GoogleFonts.inter(fontSize: 14, color: Colors.grey.shade400)),
          ]),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const ClampingScrollPhysics(),
        itemCount: usuarios.length,
        separatorBuilder: (_, __) =>
            const Divider(height: 1, indent: 16, endIndent: 16),
        itemBuilder: (_, i) {
          final u = usuarios[i];
          final isSelf =
              u.uid == AuthService.instance.currentUser?.uid;
          final isSelected = _selected?.uid == u.uid;
          return ListTile(
            shape: i == 0
                ? const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(14)))
                : i == usuarios.length - 1
                    ? const RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.vertical(bottom: Radius.circular(14)))
                    : null,
            selected: isSelected,
            selectedTileColor: _primaryColor.withValues(alpha: 0.05),
            leading: CircleAvatar(
              radius: 18,
              backgroundColor: _primaryColor.withValues(alpha: 0.1),
              child: Text(
                (u.nombre.isNotEmpty ? u.nombre[0] : '?').toUpperCase(),
                style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _primaryColor),
              ),
            ),
            title: Text(
              u.nombre,
              style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary),
            ),
            subtitle: Text(
              u.email,
              style: GoogleFonts.inter(
                  fontSize: 12, color: Colors.grey.shade400),
            ),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              if (u.esAdmin)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: _primaryColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('Admin',
                      style: GoogleFonts.inter(
                          fontSize: 10,
                          color: _primaryColor,
                          fontWeight: FontWeight.w600)),
                ),
              if (!isSelf) ...[
                const SizedBox(width: 4),
                IconButton(
                  icon: Icon(Icons.delete_outline,
                      size: 18, color: Colors.red.shade300),
                  onPressed: () => _confirmDelete(u),
                  tooltip: 'Eliminar usuario',
                ),
              ],
            ]),
            onTap: () {
              final isMobile = MediaQuery.of(context).size.width < 700;
              if (isMobile) {
                _openPermisosSheet(u);
              } else {
                setState(() => _selected = u);
              }
            },
          );
        },
      ),
    );
  }

  // ── Permissions panel ─────────────────────────────────────────────────────

  Widget _emptyPanel() {
    return Container(
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.touch_app_outlined, size: 40, color: Colors.grey.shade200),
          const SizedBox(height: 8),
          Text('Selecciona un usuario para editar sus permisos',
              style: GoogleFonts.inter(
                  fontSize: 13, color: Colors.grey.shade400),
              textAlign: TextAlign.center),
        ]),
      ),
    );
  }

  Widget _permisosPanel(UserProfile u, {ScrollController? scrollController}) {
    final isSelf = u.uid == AuthService.instance.currentUser?.uid;
    final permisos = Map<String, Map<String, bool>>.from(
        u.permisos.map((k, v) => MapEntry(k, Map<String, bool>.from(v))));

    return StatefulBuilder(builder: (ctx, setS) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
          children: [
            // Handle (mobile)
            if (scrollController != null)
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),

            // Header
            Row(children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: _primaryColor.withValues(alpha: 0.1),
                child: Text(
                  (u.nombre.isNotEmpty ? u.nombre[0] : '?').toUpperCase(),
                  style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: _primaryColor),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(u.nombre,
                      style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                  Text(u.email,
                      style: GoogleFonts.inter(
                          fontSize: 12, color: Colors.grey.shade400)),
                ]),
              ),
            ]),
            const SizedBox(height: 16),

            // Rol toggle
            if (!isSelf) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(children: [
                  Icon(Icons.admin_panel_settings_outlined,
                      size: 16, color: Colors.grey.shade500),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Rol de administrador',
                        style: GoogleFonts.inter(
                            fontSize: 13, color: AppColors.textPrimary)),
                  ),
                  Switch(
                    value: u.rol == 'admin',
                    activeThumbColor: _primaryColor,
                    onChanged: (v) async {
                      final err = await AuthService.instance
                          .actualizarRol(u.uid, v ? 'admin' : 'usuario');
                      if (err != null && ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text(err)));
                      }
                    },
                  ),
                ]),
              ),
              const SizedBox(height: 16),
            ],

            if (u.esAdmin && !isSelf) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _primaryColor.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Los administradores tienen acceso completo a todas las secciones.',
                  style: GoogleFonts.inter(
                      fontSize: 12, color: _primaryColor.withValues(alpha: 0.8)),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Permissions by section
            Text('PERMISOS POR SECCIÓN',
                style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade400,
                    letterSpacing: 0.5)),
            const SizedBox(height: 12),

            ..._secciones.map((sec) {
              final acciones =
                  _accionesPorSeccion[sec.key] ?? [];
              final secPermisos =
                  permisos[sec.key] ?? {};
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade100),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                      child: Row(children: [
                        Icon(sec.icon, size: 15, color: _primaryColor.withValues(alpha: 0.7)),
                        const SizedBox(width: 6),
                        Text(sec.label,
                            style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary)),
                      ]),
                    ),
                    const Divider(height: 1),
                    ...acciones.map((accion) {
                      final enabled = secPermisos[accion.$1] ?? true;
                      final isDisabled = u.esAdmin || isSelf;
                      return ListTile(
                        dense: true,
                        title: Text(
                          accion.$2,
                          style: GoogleFonts.inter(
                              fontSize: 13,
                              color: isDisabled
                                  ? Colors.grey.shade400
                                  : AppColors.gray700),
                        ),
                        trailing: Switch(
                          value: u.esAdmin ? true : enabled,
                          activeThumbColor: _primaryColor,
                          onChanged: isDisabled
                              ? null
                              : (v) async {
                                  setS(() {
                                    permisos[sec.key] ??= {};
                                    permisos[sec.key]![accion.$1] = v;
                                  });
                                  final err = await AuthService.instance
                                      .actualizarPermisos(u.uid, permisos);
                                  if (err != null && ctx.mounted) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                        SnackBar(content: Text(err)));
                                  }
                                },
                        ),
                      );
                    }),
                  ],
                ),
              );
            }),
          ],
        ),
      );
    });
  }

  // ── Add user button ───────────────────────────────────────────────────────

  Widget _addButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _showAddUserDialog,
        icon: const Icon(Icons.person_add_outlined, size: 18),
        label: Text('Agregar usuario',
            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(
          backgroundColor: _primaryColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
      ),
    );
  }

  // ── Add user dialog ───────────────────────────────────────────────────────

  Future<void> _showAddUserDialog() async {
    final emailCtrl = TextEditingController();
    final nombreCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    bool loading = false;
    String? error;
    bool showPass = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Nuevo usuario',
              style: GoogleFonts.inter(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          content: SizedBox(
            width: 380,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _dialogField('NOMBRE COMPLETO', nombreCtrl, 'Ej: Juan Pérez'),
              const SizedBox(height: 12),
              _dialogField(
                  'CORREO', emailCtrl, 'usuario@meetcard.cl',
                  keyboardType: TextInputType.emailAddress),
              const SizedBox(height: 12),
              _dialogField('CONTRASEÑA TEMPORAL', passCtrl, 'Mínimo 6 caracteres',
                  obscure: !showPass,
                  suffix: IconButton(
                    icon: Icon(
                      showPass
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 18,
                      color: Colors.grey.shade400,
                    ),
                    onPressed: () => setS(() => showPass = !showPass),
                  )),
              if (error != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(error!,
                      style: GoogleFonts.inter(
                          fontSize: 12, color: Colors.red.shade700)),
                ),
              ],
            ]),
          ),
          actions: [
            TextButton(
              onPressed: loading ? null : () => Navigator.pop(ctx),
              child: Text('Cancelar',
                  style: GoogleFonts.inter(color: Colors.grey.shade600)),
            ),
            ElevatedButton(
              onPressed: loading
                  ? null
                  : () async {
                      final email = emailCtrl.text.trim();
                      final nombre = nombreCtrl.text.trim();
                      final pass = passCtrl.text;
                      if (email.isEmpty || nombre.isEmpty || pass.isEmpty) {
                        setS(() => error = 'Completa todos los campos');
                        return;
                      }
                      setS(() { loading = true; error = null; });
                      final err = await AuthService.instance.crearUsuario(
                          email: email, nombre: nombre, password: pass);
                      if (ctx.mounted) {
                        if (err == null) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                                content: Text('Usuario creado correctamente')),
                          );
                        } else {
                          setS(() { loading = false; error = err; });
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              child: loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text('Crear',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dialogField(String label, TextEditingController ctrl, String hint,
      {TextInputType? keyboardType,
      bool obscure = false,
      Widget? suffix}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade400,
                letterSpacing: 0.5)),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          keyboardType: keyboardType,
          obscureText: obscure,
          style: GoogleFonts.inter(fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle:
                GoogleFonts.inter(fontSize: 14, color: Colors.grey.shade300),
            suffixIcon: suffix,
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade200)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade200)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _primaryColor, width: 1.5)),
          ),
        ),
      ]);

  // ── Delete user ───────────────────────────────────────────────────────────

  Future<void> _confirmDelete(UserProfile u) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Eliminar usuario',
            style: GoogleFonts.inter(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
        content: Text(
          '¿Estás seguro de eliminar a ${u.nombre} (${u.email})? Esta acción no se puede deshacer.',
          style: GoogleFonts.inter(fontSize: 14, color: Colors.grey.shade600),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancelar',
                style: GoogleFonts.inter(color: Colors.grey.shade600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: Text('Eliminar',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final err = await AuthService.instance.eliminarUsuario(u.uid);
      if (mounted) {
        if (err != null) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(err)));
        } else {
          if (_selected?.uid == u.uid) setState(() => _selected = null);
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Usuario eliminado')));
        }
      }
    }
  }
}
