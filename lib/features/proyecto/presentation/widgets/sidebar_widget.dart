import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../../../models/usuario.dart';
import '../../../../services/auth_service.dart';
import '../../../../widgets/walkthrough.dart';
import '../providers/sidebar_provider.dart';
import '../../../../core/theme/app_colors.dart';

class SidebarWidget extends StatelessWidget {
  const SidebarWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final sidebarProvider = context.watch<SidebarProvider>();
    // En mobile el sidebar está dentro de un Drawer — siempre expandido
    final isDrawer = Scaffold.maybeOf(context)?.hasDrawer ?? false;
    final isMobile = MediaQuery.of(context).size.width < 768;
    final isExpanded = sidebarProvider.isExpanded || isMobile || isDrawer;

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
                      color: AppColors.textApple,
                      letterSpacing: 2.0,
                    ),
                  ),
                if (!isMobile)
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
                            color: AppColors.systemGray,
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
                _buildNavItem(
                  context,
                  icon: Icons.inventory_2_outlined,
                  label: 'Productos',
                  path: '/productos',
                  isActive: GoRouterState.of(context).uri.path.startsWith('/productos'),
                ),
                _buildNavItem(
                  context,
                  icon: Icons.radar_outlined,
                  label: 'Radar',
                  path: '/radar',
                  isActive: GoRouterState.of(context).uri.path == '/radar',
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                  child: Divider(color: Color(0xFFE2E2E2), height: 1),
                ),
                _NavGroup(
                  icon: Icons.settings_outlined,
                  label: 'Configuración',
                  isSidebarExpanded: isExpanded,
                  onExpandSidebar: () => context.read<SidebarProvider>().toggleSidebar(),
                  children: [
                    _buildNavItem(
                      context,
                      icon: Icons.settings_applications_outlined,
                      label: 'General',
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
                    _buildNavItem(
                      context,
                      icon: Icons.help_outline,
                      label: 'Guía de ayuda',
                      onTap: () => WalkthroughDialog.show(context),
                    ),
                    _buildInspectorToggle(context),
                  ],
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
                  ? AppColors.primary.withValues(alpha: 0.1) 
                  : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: isExpanded ? MainAxisAlignment.start : MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 20,
                    color: isActive ? AppColors.primary : AppColors.systemGray,
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
                          color: isActive ? AppColors.textApple : AppColors.systemGray,
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
    return StreamBuilder<UserProfile?>(
      stream: AuthService.instance.perfilStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data == null) {
          // No user logged in, or stream hasn't emitted yet.
          // Since this part of the UI is only for logged-in users,
          // a small empty box is fine.
          return const SizedBox.shrink();
        }
        
        final userProfile = snapshot.data!;
        final initial = userProfile.nombre.isNotEmpty ? userProfile.nombre[0].toUpperCase() : '?';

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
                  initial,
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
                userProfile.nombre,
                style: GoogleFonts.inter(
                  color: AppColors.textApple,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 2),
              Text(
                userProfile.rol,
                style: GoogleFonts.inter(
                  color: AppColors.systemGray,
                  fontSize: 11,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              _buildLogoutBtn(context),
            ],
          ],
        );
      },
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

  Widget _buildInspectorToggle(BuildContext context) {
    final isExpanded = context.watch<SidebarProvider>().isExpanded;
    final active = context.watch<SidebarProvider>().inspectorMode;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Tooltip(
        message: isExpanded ? '' : (active ? 'Desactivar inspector' : 'Inspector de código'),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => context.read<SidebarProvider>().toggleInspectorMode(),
            borderRadius: BorderRadius.circular(10),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: EdgeInsets.symmetric(
                horizontal: isExpanded ? 16 : 0,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                color: active
                    ? const Color(0xFF6366F1).withValues(alpha: 0.12)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: active
                    ? Border.all(
                        color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                      )
                    : null,
              ),
              child: Row(
                mainAxisAlignment:
                    isExpanded ? MainAxisAlignment.start : MainAxisAlignment.center,
                children: [
                  Icon(
                    active ? Icons.code_rounded : Icons.code_outlined,
                    size: 20,
                    color: active
                        ? const Color(0xFF6366F1)
                        : AppColors.systemGray,
                  ),
                  if (isExpanded) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        active ? 'Inspector activo' : 'Inspector de código',
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                          color: active
                              ? const Color(0xFF6366F1)
                              : AppColors.systemGray,
                        ),
                      ),
                    ),
                    if (active)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6366F1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'ON',
                          style: GoogleFonts.inter(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
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

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Cerrar sesión', 
          style: GoogleFonts.inter(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
        ),
        content: Text(
          '¿Estás seguro que deseas salir?', 
          style: GoogleFonts.inter(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancelar', 
              style: GoogleFonts.inter(color: AppColors.textSecondary, fontWeight: FontWeight.w500),
            ),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              AuthService.instance.logout();
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(
              'Salir', 
              style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavGroup extends StatefulWidget {
  final IconData icon;
  final String label;
  final List<Widget> children;
  final bool isSidebarExpanded;
  final VoidCallback onExpandSidebar;

  const _NavGroup({
    required this.icon,
    required this.label,
    required this.children,
    required this.isSidebarExpanded,
    required this.onExpandSidebar,
  });

  @override
  State<_NavGroup> createState() => _NavGroupState();
}

class _NavGroupState extends State<_NavGroup> {
  bool _isGroupExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Tooltip(
            message: widget.isSidebarExpanded ? '' : widget.label,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  if (!widget.isSidebarExpanded) {
                    widget.onExpandSidebar();
                    setState(() => _isGroupExpanded = true);
                  } else {
                    setState(() => _isGroupExpanded = !_isGroupExpanded);
                  }
                },
                borderRadius: BorderRadius.circular(10),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: EdgeInsets.symmetric(
                    horizontal: widget.isSidebarExpanded ? 16 : 0, 
                    vertical: 12
                  ),
                  decoration: BoxDecoration(
                    color: _isGroupExpanded 
                      ? AppColors.primary.withValues(alpha: 0.05) 
                      : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisAlignment: widget.isSidebarExpanded ? MainAxisAlignment.start : MainAxisAlignment.center,
                    children: [
                      Icon(
                        widget.icon,
                        size: 20,
                        color: _isGroupExpanded ? AppColors.primary : AppColors.systemGray,
                      ),
                      if (widget.isSidebarExpanded) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            widget.label,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: _isGroupExpanded ? FontWeight.w600 : FontWeight.w500,
                              color: _isGroupExpanded ? AppColors.textApple : AppColors.systemGray,
                            ),
                          ),
                        ),
                        Icon(
                          _isGroupExpanded ? Icons.expand_less : Icons.expand_more,
                          size: 16,
                          color: _isGroupExpanded ? AppColors.primary : AppColors.systemGray,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (widget.isSidebarExpanded && _isGroupExpanded)
          Padding(
            padding: const EdgeInsets.only(left: 12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: widget.children,
            ),
          ),
      ],
    );
  }
}

