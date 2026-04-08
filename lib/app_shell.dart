import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'core/theme/app_colors.dart';
import 'features/proyecto/presentation/providers/sidebar_provider.dart';
import 'features/proyecto/presentation/widgets/sidebar_widget.dart';
import 'widgets/app_update_banner.dart';
import 'widgets/shared/dev_tooltip.dart' show InspectorBanner;

/// Global key for the root shell Scaffold.
final GlobalKey<ScaffoldState> appShellKey = GlobalKey<ScaffoldState>();

class AppShell extends StatelessWidget {
  final String currentPath;
  final Widget child;

  const AppShell({
    super.key,
    required this.currentPath,
    required this.child,
  });

  int _calculateSelectedIndex(String path) {
    if (path.startsWith('/radar')) return 3;
    if (path.startsWith('/productos')) return 2;
    if (path.startsWith('/proyectos')) return 1;
    if (path == '/') return 0;
    return 1; // Default to proyectos if unknown, or maybe 0
  }

  void _onItemTapped(int index, BuildContext context) {
    switch (index) {
      case 0:
        context.go('/');
        break;
      case 1:
        context.go('/proyectos');
        break;
      case 2:
        context.go('/productos');
        break;
      case 3:
        context.go('/radar');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 768;
    
    // Determine if we should show nav elements based on path
    final hideNav = currentPath == '/login';
    if (hideNav) return child;

    final content = Column(
      children: [
        const InspectorBanner(),
        Expanded(child: AppUpdateBanner(child: child)),
      ],
    );

    if (isMobile) {
      final currentIndex = _calculateSelectedIndex(currentPath);
      return Scaffold(
        key: appShellKey,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          title: Text(
            'CRM MEETCARD',
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              letterSpacing: 1.0,
            ),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(
              height: 1,
              color: AppColors.border,
            ),
          ),
        ),
        body: content,
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: currentIndex,
          onTap: (index) => _onItemTapped(index, context),
          type: BottomNavigationBarType.shifting,
          backgroundColor: Colors.white,
          selectedItemColor: AppColors.primary,
          unselectedItemColor: AppColors.systemGray,
          selectedLabelStyle: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600),
          unselectedLabelStyle: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_outlined),
              activeIcon: Icon(Icons.dashboard_rounded),
              label: 'Inicio',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.folder_outlined),
              activeIcon: Icon(Icons.folder_rounded),
              label: 'Proyectos',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.inventory_2_outlined),
              activeIcon: Icon(Icons.inventory_2_rounded),
              label: 'Productos',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.radar_outlined),
              activeIcon: Icon(Icons.radar_rounded),
              label: 'Radar',
            ),
          ],
        ),
      );
    }

    return Scaffold(
      key: appShellKey,
      body: Row(
        children: [
          // SIDEBAR COLAPSABLE (Desktop/Tablet)
          Consumer<SidebarProvider>(
            builder: (context, sidebarProvider, _) {
              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                width: sidebarProvider.sidebarWidth,
                child: const SidebarWidget(),
              );
            },
          ),

          // MAIN CONTENT
          Expanded(
            child: Container(
              color: AppColors.surfaceAlt,
              child: content,
            ),
          ),
        ],
      ),
    );
  }
}
