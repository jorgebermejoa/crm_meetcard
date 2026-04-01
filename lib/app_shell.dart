import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'core/theme/app_colors.dart';
import 'features/proyecto/presentation/providers/sidebar_provider.dart';
import 'features/proyecto/presentation/widgets/sidebar_widget.dart';

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

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 768;
    
    // Determine if we should show nav elements based on path
    final hideNav = currentPath == '/login';
    if (hideNav) return child;

    if (isMobile) {
      return Scaffold(
        key: appShellKey,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.menu, color: AppColors.primary),
            onPressed: () => appShellKey.currentState?.openDrawer(),
          ),
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
        drawer: const Drawer(
          child: SidebarWidget(),
        ),
        body: child,
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
              color: const Color(0xFFF8FAFC),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}
