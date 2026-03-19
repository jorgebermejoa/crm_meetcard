import 'package:flutter/material.dart';

class GlobalSearchBar extends StatefulWidget {
  final Function(String) onSearch;
  final VoidCallback onClear;
  final String hintText;

  const GlobalSearchBar({
    super.key,
    required this.onSearch,
    required this.onClear,
    this.hintText = 'Buscar licitaciones por palabra clave, ID o entidad...',
  });

  @override
  State<GlobalSearchBar> createState() => _GlobalSearchBarState();
}

class _GlobalSearchBarState extends State<GlobalSearchBar> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _isFocused = false;

  static const List<String> _sugerencias = [
    'Tecnologías de información',
    'Construcción de edificios',
    'Consultoría y asesoría',
    'Medicamentos y farmacia',
    'Transporte y logística',
    'Equipamiento médico',
    'Servicios de seguridad',
    'Aseo y limpieza',
    'Mobiliario y equipamiento',
    'Obras viales',
    'Capacitación y educación',
    'Arriendo de vehículos',
  ];

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        setState(() => _isFocused = true);
      } else {
        // Delay para que onPressed del chip se ejecute antes de ocultar los chips
        Future.delayed(const Duration(milliseconds: 150), () {
          if (mounted) setState(() => _isFocused = false);
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _clear() {
    _controller.clear();
    widget.onClear();
  }

  void _seleccionarSugerencia(String texto) {
    _controller.text = texto;
    _focusNode.unfocus();
    widget.onSearch(texto);
  }

  @override
  Widget build(BuildContext context) {
    final bool mostrarSugerencias = _isFocused && _controller.text.isEmpty;

    return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
                border: Border.all(color: _isFocused ? Colors.blueAccent.withValues(alpha: 0.4) : Colors.grey.shade200),
              ),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                onSubmitted: widget.onSearch,
                onChanged: (value) => setState(() {}),
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  hintStyle: TextStyle(color: Colors.grey.shade500),
                  prefixIcon: const Icon(Icons.search, color: Colors.blueAccent),
                  suffixIcon: _controller.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.close, color: Colors.grey.shade400, size: 18),
                          onPressed: _clear,
                          splashRadius: 18,
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                ),
              ),
            ),
            if (mostrarSugerencias) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 36,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _sugerencias.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => ActionChip(
                    label: Text(_sugerencias[i], style: const TextStyle(fontSize: 13)),
                    onPressed: () => _seleccionarSugerencia(_sugerencias[i]),
                    backgroundColor: Colors.white,
                    side: BorderSide(color: Colors.grey.shade200),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                ),
              ),
            ],
          ],
        ),
    );
  }
}