import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/app_update_service.dart';
import '../services/platform_reload.dart';

class AppUpdateBanner extends StatelessWidget {
  final Widget child;
  const AppUpdateBanner({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return child;

    return ListenableBuilder(
      listenable: AppUpdateService.instance,
      builder: (context, _) {
        final hasUpdate = AppUpdateService.instance.hasUpdate;
        return Column(
          children: [
            if (hasUpdate) const _UpdateBar(),
            Expanded(child: child),
          ],
        );
      },
    );
  }
}

class _UpdateBar extends StatelessWidget {
  const _UpdateBar();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1E40AF),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.system_update_alt_rounded,
                  size: 16, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Hay una nueva versión disponible.',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: reloadPage,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Actualizar',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1E40AF),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => AppUpdateService.instance.dismiss(),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close, size: 16, color: Colors.white70),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
