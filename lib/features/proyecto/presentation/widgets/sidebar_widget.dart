import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../../../services/auth_service.dart';
import '../../../../widgets/walkthrough.dart';
import '../providers/sidebar_provider.dart';

class SidebarWidget extends StatelessWidget {
  const SidebarWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final sidebarProvider = context.watch<SidebarProvider>();
    final isExpanded = sidebarProvider.isExpanded;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.8),
        border: Border(
          right: BorderSide(color: Colors.black.withValues(alpha: 0.05), width: 0.5),
        ),
      ),
      child: Column(
        children: [
          // HEADER CON TOGGLE
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
            child: Row(
              mainAxisAlignment: isExpanded 
                ? MainAxisAlignment.spaceBetween 
                : MainAxisAlignment.center,
              children: [
                if (isExpanded)
                  Text(
                    'CRM MEETCARD',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1D1D1F),
                      letterSpacing: 2.0,
                    ),
                  ),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => context.read<SidebarProvider>().toggleSidebar(),
                    borderRadius: BorderRadius.circular(8),
                    child: Tooltip(
                      message: isExpanded ? 'Colapsar' : 'Expandir',
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          isExpanded ? Icons.menu_open : Icons.menu,
                          color: const Color(0xFF8E8E93),
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // NAV ITEMS
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _buildNavItem(
                  context,
                  icon: Icons.dashboard_outlined,
                  label: 'Inicio',
                  path: '/',
                  isActive: GoRouterState.of(context).uri.path == '/',
                ),
                _buildNavItem(
                  context,
                  icon: Icons.folder_outlined,
                  label: 'Proyectos',
                  path: '/proyectos',
                  isActive: GoRouterState.of(context).uri.path.startsWith('/proyectos'),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                  child: Divider(color: Color(0xFFE2E2E2), height: 1),
                ),
                _buildNavItem(
                  context,
                  icon: Icons.settings_outlined,
                  label: 'Configuración',
                  path: '/configuracion',
                  isActive: GoRouterState.of(context).uri.path == '/configuracion',
                ),
                _buildNavItem(
                  context,
                  icon: Icons.people_outline,
                  label: 'Usuarios',
                  path: '/admin/usuarios',
                  isActive: GoRouterState.of(context).uri.path == '/admin/usuarios',
                ),
                _buildNavItem(
                  context,
                  icon: Icons.upload_file_outlined,
                  label: 'Migración CSV',
                  path: '/admin/migracion',
                  isActive: GoRouterState.of(context).uri.path == '/admin/migracion',
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Divider(color: Color(0xFFE2E2E2), height: 1),
                ),
                _buildNavItem(
                  context,
                  icon: Icons.help_outline,
                  label: 'Guía de ayuda',
                  onTap: () => WalkthroughDialog.show(context),
                ),
              ],
            ),
          ),

          // USER PROFILE
          Padding(
            padding: const EdgeInsets.all(16),
            child: _buildUserProfile(context, isExpanded),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    String? path,
    VoidCallback? onTap,
    bool isActive = false,
  }) {
    final isExpanded = context.watch<SidebarProvider>().isExpanded;
    final canTap = path != null || onTap != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Tooltip(
        message: isExpanded ? '' : label,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: canTap ? () {
              debugPrint('Sidebar: Tapped $label, Path: $path');
              // Close drawer if present (for mobile/tablet)
              final scaffold = Scaffold.maybeOf(context);
              if (scaffold != null && scaffold.hasDrawer && scaffold.isDrawerOpen) {
                Navigator.of(context).pop();
              }
              
              if (path != null) {
                debugPrint('Sidebar: Navigating to $path');
                context.go(path);
              } else if (onTap != null) {
                onTap();
              }
            } : null,
            borderRadius: BorderRadius.circular(10),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: EdgeInsets.symmetric(
                horizontal: isExpanded ? 16 : 0, 
                vertical: 12
              ),
              decoration: BoxDecoration(
                color: isActive 
                  ? const Color(0xFF007AFF).withValues(alpha: 0.1) 
                  : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: isExpanded ? MainAxisAlignment.start : MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 20,
                    color: isActive ? const Color(0xFF007AFF) : const Color(0xFF8E8E93),
                  ),
                  if (isExpanded) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                          color: isActive ? const Color(0xFF1D1D1F) : const Color(0xFF8E8E93),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUserProfile(BuildContext context, bool isExpanded) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.blue.shade400, width: 2),
          ),
          child: CircleAvatar(
            radius: 18,
            backgroundColor: Colors.blue.shade600,
            child: Text(
              'J',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
        ),
        if (isExpanded) ...[
          const SizedBox(height: 12),
          Text(
            'Jorge Bermejo',
            style: GoogleFonts.inter(
              color: const Color(0xFF1D1D1F),
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            'Administrador',
            style: GoogleFonts.inter(
              color: const Color(0xFF8E8E93),
              fontSize: 11,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          _buildLogoutBtn(context),
        ],
      ],
    );
  }

  Widget _buildLogoutBtn(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showLogoutDialog(context),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.logout, size: 14, color: Colors.redAccent),
              const SizedBox(width: 8),
              Text(
                'Cerrar sesión',
                style: GoogleFonts.inter(
                  color: Colors.redAccent,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Text('Cerrar sesión', style: GoogleFonts.inter(color: Colors.white)),
        content: Text('¿Estás seguro que deseas salir?', style: GoogleFonts.inter(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancelar', style: GoogleFonts.inter(color: Colors.white60)),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              AuthService.instance.logout();
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: Text('Salir', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
