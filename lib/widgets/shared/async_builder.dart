import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';

/// Widget genérico para manejar los tres estados de una operación async:
/// cargando → error → datos.
///
/// Uso:
/// ```dart
/// AsyncBuilder<List<Foo>>(
///   loading: provider.cargando,
///   error: provider.error,
///   hasData: provider.items.isNotEmpty,
///   skeleton: MySkeletonWidget(),
///   onRetry: () => provider.cargar(forceRefresh: true),
///   builder: (context) => MyDataWidget(),
/// )
/// ```
class AsyncBuilder<T> extends StatelessWidget {
  final bool loading;
  final String? error;
  final bool hasData;

  /// Widget skeleton que se muestra mientras [loading] es true.
  /// Si es null se muestra un CircularProgressIndicator centrado.
  final Widget? skeleton;

  /// Construye el contenido cuando los datos están disponibles.
  final WidgetBuilder builder;

  /// Callback para el botón "Reintentar" del estado de error.
  final VoidCallback? onRetry;

  /// Mensaje alternativo al error genérico.
  final String? emptyMessage;

  const AsyncBuilder({
    super.key,
    required this.loading,
    required this.hasData,
    required this.builder,
    this.error,
    this.skeleton,
    this.onRetry,
    this.emptyMessage,
  });

  @override
  Widget build(BuildContext context) {
    if (loading && !hasData) {
      return skeleton ??
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 64),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
    }

    if (error != null && !hasData) {
      return _ErrorState(message: error!, onRetry: onRetry);
    }

    if (!hasData && emptyMessage != null) {
      return _EmptyState(message: emptyMessage!);
    }

    return builder(context);
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const _ErrorState({required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: AppColors.errorDark.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(
              'Ocurrió un error',
              style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 16),
                label: Text('Reintentar', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String message;

  const _EmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 40, color: AppColors.textFaint.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
