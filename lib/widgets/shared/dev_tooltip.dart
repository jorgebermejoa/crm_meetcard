import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../features/proyecto/presentation/providers/sidebar_provider.dart';

/// Wraps [child] to highlight it when inspector mode is active.
/// Clicking or tapping on the wrapped widget sets it as the active item
/// in the global InspectorBanner.
class DevTooltip extends StatelessWidget {
  final String filePath;
  final String? description;
  final Widget child;

  const DevTooltip({
    super.key,
    required this.filePath,
    required this.child,
    this.description,
  });

  @override
  Widget build(BuildContext context) {
    final active = context.watch<SidebarProvider>().inspectorMode;
    if (!active) return child;

    final provider = context.watch<SidebarProvider>();
    final activeData = provider.activeInspectorData;
    
    final isActiveNode = activeData?.filePath == filePath &&
                         activeData?.description == description;

    final border = DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(
          color: isActiveNode 
              ? const Color(0xFF16A34A).withValues(alpha: 0.8)
              : const Color(0xFF6366F1).withValues(alpha: 0.55),
          width: isActiveNode ? 2.5 : 1.5,
        ),
        borderRadius: BorderRadius.circular(4),
        color: isActiveNode 
            ? const Color(0xFF16A34A).withValues(alpha: 0.1) 
            : Colors.transparent,
      ),
    );

    final stack = Stack(
      children: [
        child,
        Positioned.fill(child: IgnorePointer(child: border)),
      ],
    );

    void activateNode() {
      provider.setActiveInspectorData(InspectorData(
        filePath: filePath,
        description: description,
      ));
    }

    final isTouch = Theme.of(context).platform == TargetPlatform.iOS ||
                    Theme.of(context).platform == TargetPlatform.android;

    if (isTouch) {
      // Mobile/tablet: tap para activar
      return GestureDetector(
        onTap: activateNode,
        behavior: HitTestBehavior.translucent,
        child: stack,
      );
    }

    // Desktop: hover
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => activateNode(),
      child: GestureDetector(
        onTap: activateNode,
        child: stack,
      ),
    );
  }
}

/// A sticky banner that appears at the top of the screen when Inspector Mode is active.
/// It displays the information of the currently hovered/tapped [DevTooltip].
class InspectorBanner extends StatefulWidget {
  const InspectorBanner({super.key});

  @override
  State<InspectorBanner> createState() => _InspectorBannerState();
}

class _InspectorBannerState extends State<InspectorBanner> {
  bool _copied = false;

  Future<void> _copy(String prompt) async {
    await Clipboard.setData(ClipboardData(text: prompt));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SidebarProvider>();
    if (!provider.inspectorMode) return const SizedBox.shrink();

    final data = provider.activeInspectorData;
    
    // Provide a default message if nothing is selected yet
    final prompt = data != null 
        ? 'Archivo: ${data.filePath}\n'
          '${data.description != null ? 'Sección: ${data.description}\n' : ''}'
          '\nInstrucción: '
        : 'Pasa el cursor o presiona un elemento resaltado para inspeccionarlo.';

    return Container(
      width: double.infinity,
      color: const Color(0xFF1E1E2E),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SafeArea(
        bottom: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(Icons.code_rounded, size: 20, color: Color(0xFF818CF8)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Inspector de Código',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF818CF8),
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (data != null)
                    Text(
                      '${data.filePath} ${data.description != null ? '— ${data.description}' : ''}',
                      style: GoogleFonts.firaCode(
                        fontSize: 12,
                        color: const Color(0xFF7DD3FC),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  else
                    Text(
                      prompt,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: const Color(0xFF94A3B8),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            if (data != null)
              FilledButton.icon(
                onPressed: () => _copy(prompt),
                icon: Icon(
                  _copied ? Icons.check_rounded : Icons.copy_rounded,
                  size: 16,
                ),
                label: Text(
                  _copied ? '¡Copiado!' : 'Copiar prompt',
                  style: GoogleFonts.inter(
                    fontSize: 13, 
                    fontWeight: FontWeight.w600
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: _copied
                      ? const Color(0xFF16A34A)
                      : const Color(0xFF6366F1),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: () => provider.toggleInspectorMode(),
              icon: const Icon(Icons.close_rounded, color: Color(0xFF818CF8)),
              tooltip: 'Cerrar Inspector',
            ),
          ],
        ),
      ),
    );
  }
}
