import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'app_shell.dart';
import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'widgets/admin_usuarios_view.dart';
import 'widgets/migracion_view.dart';
import 'widgets/home_view.dart';
import 'widgets/login_view.dart';
import 'widgets/perfil_view.dart';
import 'widgets/proyectos_view.dart';
import 'widgets/configuracion_view.dart';

// Clean Architecture Imports
import 'features/proyecto/domain/entities/proyecto_entity.dart';
import 'features/proyecto/domain/repositories/proyecto_repository.dart';
import 'features/proyecto/data/repositories/proyecto_repository_impl.dart';
import 'features/proyecto/data/datasources/proyecto_remote_datasource.dart';
import 'features/proyecto/presentation/pages/detalle_proyecto_page.dart';
import 'features/proyecto/presentation/providers/sidebar_provider.dart';
import 'features/dashboard/presentation/providers/dashboard_provider.dart';
import 'features/search/presentation/providers/search_provider.dart';
import 'core/theme/app_theme.dart';

void main() {
  usePathUrlStrategy();
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } catch (e) {
      debugPrint('Firebase init warning (non-fatal): $e');
    }
    AuthService.instance.init();

    final proyectoRepository = ProyectoRepositoryImpl(
      remoteDataSource: ProyectoRemoteDataSourceImpl(),
    );

    final shellNavigatorKey = GlobalKey<NavigatorState>();
    final rootNavigatorKey = GlobalKey<NavigatorState>();

    final authNotifier = _AuthNotifier();
    final router = GoRouter(
      navigatorKey: rootNavigatorKey,
      initialLocation: '/proyectos',
      redirect: (context, state) {
        final user = FirebaseAuth.instance.currentUser;
        final isLogin = state.uri.path == '/login';
        if (user == null && !isLogin) return '/login';
        if (user != null && isLogin) return '/proyectos';
        return null;
      },
      refreshListenable: authNotifier,
      routes: [
        GoRoute(
          path: '/login',
          pageBuilder: (_, __) => _fadePage(const LoginView()),
        ),
        ShellRoute(
          navigatorKey: shellNavigatorKey,
          builder: (context, state, child) {
            final path = state.uri.path;
            return AppShell(currentPath: path, child: child);
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
                    final ProyectoEntity proyecto;
                    String? initialTabName;
                    if (extra is Map) {
                      proyecto = extra['proyecto'] as ProyectoEntity;
                      initialTabName = extra['tab'] as String?;
                    } else {
                      proyecto = extra as ProyectoEntity;
                    }
                    return _fadePage(DetalleProyectoPage(
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
            GoRoute(
              path: '/admin/migracion',
              pageBuilder: (_, __) => _fadePage(const MigracionView()),
            ),
          ],
        ),
      ],
    );

  runApp(
    MultiProvider(
      providers: [
        Provider<ProyectoRepository>.value(value: proyectoRepository),
        ChangeNotifierProvider(create: (_) => SidebarProvider()),
        ChangeNotifierProvider(create: (_) => DashboardProvider()),
        ChangeNotifierProvider(create: (_) => SearchProvider()),
      ],
      child: MiBuscadorApp(router: router),
    ),
  );
}, (error, stack) {
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

// Moved keys and router initialization inside main() to ensure Firebase is ready.

class _AuthNotifier extends ChangeNotifier {
  _AuthNotifier() {
    FirebaseAuth.instance.authStateChanges().listen((_) => notifyListeners());
  }
}

// ── App ───────────────────────────────────────────────────────────────────────

class MiBuscadorApp extends StatelessWidget {
  final GoRouter router;
  const MiBuscadorApp({super.key, required this.router});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Buscador Mercado Público',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: AppTheme.lightTheme,
    );
  }
}
