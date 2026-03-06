import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'dart:convert'; // <-- Necesario para decodificar JSON
import 'package:http/http.dart' as http; // <-- Necesario para ir a internet

// ¡Aquí están las importaciones mágicas que conectan tus widgets!
import 'widgets/global_search_bar.dart';
import 'widgets/licitaciones_table.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MiBuscadorApp());
}

class MiBuscadorApp extends StatelessWidget {
  const MiBuscadorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Buscador Mercado Público',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
      ),
      home: const HomeView(),
    );
  }
}

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  List<LicitacionUI> _licitaciones = [];
  bool _cargando = false;

  Future<void> _ejecutarBusqueda(String query) async {
    if (query.isEmpty) return;
    
    setState(() => _cargando = true);
    
    try {
      final url = Uri.parse('https://us-central1-licitaciones-prod.cloudfunctions.net/buscarLicitacionesAI?q=$query');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        
        // --- INICIO DE LA SECCIÓN DE DEPURACIÓN ---
        for (var item in data) {
          if (item.containsKey('_debug_data')) {
            final debugData = json.encode(item['_debug_data']); // Lo codificamos para una bonita impresión
            debugPrint("[DEBUG] Datos crudos de Vertex AI: $debugData");
          }
        }
        // --- FIN DE LA SECCIÓN DE DEPURACIÓN ---

        setState(() {
          _licitaciones = data.map((item) => LicitacionUI(
            item['id']?.toString() ?? 'S/I',
            item['titulo']?.toString() ?? 'Sin título',
            item['descripcion']?.toString() ?? 'Sin descripción',
            item['fechaCierre']?.toString() ?? 'S/F',
          )).toList();
        });

      } else {
        debugPrint("Error del servidor: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("Error de conexión: $e");
    } finally {
      setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Inteligencia de Licitaciones',
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: -0.5),
                ),
                const SizedBox(height: 8),
                Text(
                  'Búsqueda semántica impulsada por Vertex AI',
                  style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 40),
                
                GlobalSearchBar(onSearch: _ejecutarBusqueda),
                
                const SizedBox(height: 40),
                
                Expanded(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      width: double.infinity,
                      child: _cargando 
                          ? const Center(child: CircularProgressIndicator()) 
                          : LicitacionesTable(licitaciones: _licitaciones),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
