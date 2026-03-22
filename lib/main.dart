import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_shell.dart';
import 'firebase_options.dart';
import 'models/proyecto.dart';
import 'services/auth_service.dart';
import 'widgets/admin_usuarios_view.dart';
import 'widgets/home_view.dart';
import 'widgets/login_view.dart';
import 'widgets/perfil_view.dart';
import 'widgets/proyectos_view.dart';
import 'widgets/configuracion_view.dart';
import 'widgets/detalle_proyecto_view.dart';

void main() {
  usePathUrlStrategy();
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    AuthService.instance.init();
    runApp(const MiBuscadorApp());
  }, (error, stack) {
    // Suppress uncaught zone errors from Firebase SDK internal pigeon decoding.
    // These are non-fatal and occur when Firebase Auth's WebChannel fails
    // (e.g., in proxied environments like Cloud Workstations).
    debugPrint('Zone error (non-fatal): $error');
  });
}

// ── Helpers ───────────────────────────────────────────────────────────────────

CustomTransitionPage<void> _fadePage(Widget child) => CustomTransitionPage<void>(
      child: child,
      transitionDuration: const Duration(milliseconds: 200),
      transitionsBuilder: (_, animation, __, child) =>
          FadeTransition(opacity: animation, child: child),
    );

// ── Router ────────────────────────────────────────────────────────────────────

final _shellNavigatorKey = GlobalKey<NavigatorState>();
final _rootNavigatorKey = GlobalKey<NavigatorState>();

final _router = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/',
  redirect: (context, state) {
    final user = FirebaseAuth.instance.currentUser;
    final isLogin = state.uri.path == '/login';
    if (user == null && !isLogin) return '/login';
    if (user != null && isLogin) return '/';
    return null;
  },
  refreshListenable: _AuthNotifier(),
  routes: [
    GoRoute(
      path: '/login',
      pageBuilder: (_, __) => _fadePage(const LoginView()),
    ),
    ShellRoute(
      navigatorKey: _shellNavigatorKey,
      builder: (context, state, child) {
        final path = state.uri.path;
        return _AppShell(currentPath: path, child: child);
      },
      routes: [
        GoRoute(
          path: '/',
          pageBuilder: (_, __) => _fadePage(const HomeView()),
        ),
        GoRoute(
          path: '/proyectos',
          pageBuilder: (_, __) => _fadePage(const ProyectosView()),
          routes: [
            GoRoute(
              path: ':id',
              redirect: (_, state) =>
                  state.extra == null ? '/proyectos' : null,
              pageBuilder: (_, state) {
                final extra = state.extra!;
                final Proyecto proyecto;
                String? initialTabName;
                if (extra is Map) {
                  proyecto = extra['proyecto'] as Proyecto;
                  initialTabName = extra['tab'] as String?;
                } else {
                  proyecto = extra as Proyecto;
                }
                return _fadePage(DetalleProyectoView(
                  proyecto: proyecto,
                  initialTabName: initialTabName,
                ));
              },
            ),
          ],
        ),
        GoRoute(
          path: '/configuracion',
          pageBuilder: (_, __) => _fadePage(const ConfiguracionView()),
        ),
        GoRoute(
          path: '/perfil',
          pageBuilder: (_, __) => _fadePage(const PerfilView()),
        ),
        GoRoute(
          path: '/admin/usuarios',
          pageBuilder: (_, __) => _fadePage(const AdminUsuariosView()),
        ),
      ],
    ),
  ],
);

/// Notifies GoRouter to re-evaluate redirects on auth state changes.
class _AuthNotifier extends ChangeNotifier {
  _AuthNotifier() {
    FirebaseAuth.instance.authStateChanges().listen((_) => notifyListeners());
  }
}

// ── App ───────────────────────────────────────────────────────────────────────

class MiBuscadorApp extends StatelessWidget {
  const MiBuscadorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Buscador Mercado Público',
      debugShowCheckedModeBanner: false,
      routerConfig: _router,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF5B21B6)),
        scaffoldBackgroundColor: const Color(0xFFF2F2F7),
        textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme),
      ),
    );
  }
}

// ── Shell ─────────────────────────────────────────────────────────────────────

class _AppShell extends StatelessWidget {
  final String currentPath;
  final Widget child;

  const _AppShell({required this.currentPath, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: appShellKey,
      backgroundColor: const Color(0xFFF2F2F7),
      drawer: _AppDrawer(currentPath: currentPath),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // SelectionArea intercepts taps on mobile web, blocking the keyboard.
          // Only enable it on wider (desktop) screens.
          if (constraints.maxWidth >= 700) {
            return SelectionArea(child: child);
          }
          return child;
        },
      ),
    );
  }
}

// ── Drawer ────────────────────────────────────────────────────────────────────

class _AppDrawer extends StatelessWidget {
  final String currentPath;
  const _AppDrawer({required this.currentPath});

  int get _selectedIndex {
    if (currentPath.startsWith('/configuracion')) return 2;
    if (currentPath.startsWith('/proyectos')) return 1;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final perfil = AuthService.instance.perfil;

    return Drawer(
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Brand header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Licitaciones',
                    style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1E293B),
                      letterSpacing: -0.5,
                    ),
                  ),
                  Text(
                    'Inteligencia de Mercado Público',
                    style: GoogleFonts.inter(
                        fontSize: 12, color: Colors.grey.shade400),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 8),

            // Navigation items
            _DrawerItem(
              icon: Icons.search_outlined,
              label: 'Búsqueda',
              selected: _selectedIndex == 0,
              onTap: () {
                Navigator.pop(context);
                context.go('/');
              },
            ),
            _DrawerItem(
              icon: Icons.folder_outlined,
              label: 'Proyectos',
              selected: _selectedIndex == 1,
              onTap: () {
                Navigator.pop(context);
                context.go('/proyectos');
              },
            ),
            _DrawerItem(
              icon: Icons.settings_outlined,
              label: 'Configuración',
              selected: _selectedIndex == 2,
              onTap: () {
                Navigator.pop(context);
                context.go('/configuracion');
              },
            ),

            // Admin section
            if (perfil?.esAdmin == true) ...[
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Text(
                  'ADMINISTRACIÓN',
                  style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade400,
                      letterSpacing: 0.5),
                ),
              ),
              _DrawerItem(
                icon: Icons.people_outline,
                label: 'Gestión de usuarios',
                selected: currentPath.startsWith('/admin'),
                onTap: () {
                  Navigator.pop(context);
                  context.go('/admin/usuarios');
                },
              ),
            ],

            const Spacer(),
            const Divider(height: 1),

            // User profile
            if (perfil != null)
              ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                leading: CircleAvatar(
                  radius: 16,
                  backgroundColor:
                      const Color(0xFF5B21B6).withValues(alpha: 0.1),
                  child: Text(
                    (perfil.nombre.isNotEmpty ? perfil.nombre[0] : '?')
                        .toUpperCase(),
                    style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF5B21B6)),
                  ),
                ),
                title: Text(
                  perfil.nombre,
                  style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF1E293B)),
                ),
                subtitle: Text(
                  perfil.esAdmin ? 'Administrador' : 'Usuario',
                  style: GoogleFonts.inter(
                      fontSize: 11, color: Colors.grey.shade400),
                ),
                trailing: IconButton(
                  icon: Icon(Icons.settings_outlined,
                      size: 18, color: Colors.grey.shade400),
                  tooltip: 'Mi perfil',
                  onPressed: () {
                    Navigator.pop(context);
                    context.go('/perfil');
                  },
                ),
                onTap: () {
                  Navigator.pop(context);
                  context.go('/perfil');
                },
              ),

            // Logout
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: ListTile(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                leading: Icon(Icons.logout_outlined,
                    size: 20, color: Colors.red.shade400),
                title: Text(
                  'Cerrar sesión',
                  style: GoogleFonts.inter(
                      fontSize: 14,
                      color: Colors.red.shade400,
                      fontWeight: FontWeight.w500),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  await AuthService.instance.logout();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  static const _primaryColor = Color(0xFF5B21B6);

  @override
  Widget build(BuildContext context) {
    final color = selected ? _primaryColor : const Color(0xFF64748B);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: ListTile(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        tileColor:
            selected ? _primaryColor.withValues(alpha: 0.07) : null,
        leading: Icon(icon, color: color, size: 20),
        title: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: color,
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}
