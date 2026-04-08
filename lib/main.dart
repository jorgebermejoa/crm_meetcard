import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

// Importaciones de vistas y servicios
import 'app_shell.dart';
import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'services/app_update_service.dart';
import 'widgets/admin_usuarios_view.dart';
import 'widgets/migracion_view.dart';
import 'widgets/home_view.dart';
import 'widgets/login_view.dart';
import 'widgets/perfil_view.dart';
import 'widgets/proyectos_view.dart';
import 'widgets/radar_view.dart';
import 'widgets/configuracion_view.dart';

import 'features/proyecto/domain/entities/proyecto_entity.dart';
import 'features/proyecto/domain/repositories/proyecto_repository.dart';
import 'features/proyecto/data/repositories/proyecto_repository_impl.dart';
import 'features/proyecto/data/datasources/proyecto_remote_datasource.dart';
import 'features/proyecto/presentation/pages/detalle_proyecto_page.dart';
import 'features/proyectos/data/datasources/proyectos_remote_datasource.dart'
    as plural_datasource;
import 'features/proyectos/data/repositories/proyectos_repository_impl.dart'
    as plural_repo;
import 'features/proyectos/presentation/providers/proyectos_provider.dart';
import 'features/productos/presentation/pages/productos_page.dart';
import 'features/proyecto/presentation/providers/sidebar_provider.dart';
import 'features/dashboard/presentation/providers/dashboard_provider.dart';
import 'features/search/presentation/providers/search_provider.dart';
import 'core/theme/app_theme.dart';

Future<void> main() async {
  // 1. Configuración básica de Flutter
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();

  try {
    // 2. Inicialización CRÍTICA de Firebase
    // Si esto falla, no debemos continuar con el flujo normal
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // 3. Inicialización de servicios dependientes de Firebase
    AuthService.instance.init();
    AppUpdateService.instance.init();

    // 4. Configuración de Repositorios y Navegación
    final proyectoRepository = ProyectoRepositoryImpl(
      remoteDataSource: ProyectoRemoteDataSourceImpl(),
    );

    final proyectosRemoteDatasource = plural_datasource.ProyectosRemoteDatasource();
    final proyectosRepository = plural_repo.ProyectosRepositoryImpl(
      remoteDatasource: proyectosRemoteDatasource,
    );

    final rootNavigatorKey = GlobalKey<NavigatorState>();
    final shellNavigatorKey = GlobalKey<NavigatorState>();
    final authNotifier = _AuthNotifier();

    final router = GoRouter(
      navigatorKey: rootNavigatorKey,
      initialLocation: '/proyectos',
      refreshListenable: authNotifier,
      redirect: (context, state) {
        final user = FirebaseAuth.instance.currentUser;
        final isLogin = state.uri.path == '/login';
        
        if (user == null && !isLogin) return '/login';
        if (user != null && isLogin) return '/proyectos';
        return null;
      },
      routes: [
        GoRoute(
          path: '/login',
          pageBuilder: (_, __) => _fadePage(const LoginView()),
        ),
        ShellRoute(
          navigatorKey: shellNavigatorKey,
          builder: (context, state, child) {
            return AppShell(currentPath: state.uri.path, child: child);
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
                  // :modalidad/:id — ej. licitacion_publica/4412-36-LQ26
                  path: ':modalidad/:id',
                  pageBuilder: (_, state) {
                    final id = state.pathParameters['id']!;
                    final extra = state.extra;
                    final ProyectoEntity? fromExtra = extra is Map
                        ? extra['proyecto'] as ProyectoEntity?
                        : extra is ProyectoEntity
                            ? extra
                            : null;
                    final String? initialTabName =
                        extra is Map ? extra['tab'] as String? : null;

                    return _fadePage(
                      DetalleProyectoPage(
                        proyectoId: id,
                        proyectoFromExtra: fromExtra,
                        initialTabName: initialTabName,
                        repository: proyectoRepository,
                      ),
                    );
                  },
                ),
                // Legacy route without modalidad — redirect to canonical URL
                // (handles old bookmarks: /proyectos/:id)
                GoRoute(
                  path: ':id',
                  redirect: (_, state) {
                    // Can't redirect without knowing modalidad — just load the page
                    return null;
                  },
                  pageBuilder: (_, state) {
                    final id = state.pathParameters['id']!;
                    final extra = state.extra;
                    final ProyectoEntity? fromExtra = extra is Map
                        ? extra['proyecto'] as ProyectoEntity?
                        : extra is ProyectoEntity
                            ? extra
                            : null;
                    final String? initialTabName =
                        extra is Map ? extra['tab'] as String? : null;

                    return _fadePage(
                      DetalleProyectoPage(
                        proyectoId: id,
                        proyectoFromExtra: fromExtra,
                        initialTabName: initialTabName,
                        repository: proyectoRepository,
                      ),
                    );
                  },
                ),
              ],
            ),
            GoRoute(
              path: '/productos',
              pageBuilder: (_, __) => _fadePage(const ProductosPage()),
            ),
            GoRoute(
              path: '/radar',
              pageBuilder: (_, __) => _fadePage(const RadarView()),
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

    // 5. Lanzamiento de la App
    runApp(
      MultiProvider(
        providers: [
          Provider<ProyectoRepository>.value(value: proyectoRepository),
          ChangeNotifierProvider(create: (_) => SidebarProvider()),
          ChangeNotifierProvider(create: (_) => DashboardProvider()),
          ChangeNotifierProvider(create: (_) => SearchProvider()),
          ChangeNotifierProvider(
            create: (_) => ProyectosProvider(proyectosRepository: proyectosRepository),
          ),
        ],
        child: MiBuscadorApp(router: router),
      ),
    );

  } catch (e, stack) {
    // Si algo falla en la inicialización, mostramos el error claramente
    debugPrint('FALTA CRÍTICA EN MAIN: $e');
    debugPrint(stack.toString());
    
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SelectableText('Error de Inicialización:\n$e'),
          ),
        ),
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

CustomTransitionPage<void> _fadePage(Widget child) => CustomTransitionPage<void>(
      child: child,
      transitionDuration: const Duration(milliseconds: 200),
      transitionsBuilder: (_, animation, __, child) =>
          FadeTransition(opacity: animation, child: child),
    );

class _AuthNotifier extends ChangeNotifier {
  _AuthNotifier() {
    FirebaseAuth.instance.authStateChanges().listen((_) => notifyListeners());
  }
}

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