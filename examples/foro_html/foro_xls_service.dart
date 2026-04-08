// ─ INTEGRACIÓN EN FLUTTER: Procesar archivo XLS del foro ─

import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Clase para manejar la carga y procesamiento de archivos XLS del foro
class ForoXLSService {
  static const String CLOUD_FUNCTION_URL =
      'https://us-central1-licitaciones-prod.cloudfunctions.net/procesarForoXLS';

  /// Cargar archivo XLS, procesarlo y guardar foro + resumen en Firestore
  static Future<Map<String, dynamic>> procesarArchivoXLS({
    required File archivo,
    required String proyectoId,
    required String licitacionId,
    bool generarResumen = true,
  }) async {
    try {
      // 1. Obtener token de autenticación
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('No autorizado: usuario no autenticado');
      }

      final token = await user.getIdToken();

      // 2. Leer archivo
      print('[ForoXLS] Leyendo archivo: ${archivo.path}');
      final bytes = await archivo.readAsBytes();
      print('[ForoXLS] Tamaño: ${(bytes.length / 1024).toStringAsFixed(2)} KB');

      // 3. Construir URL con parámetros
      final url = Uri.parse(
        '$CLOUD_FUNCTION_URL?'
        'proyectoId=${Uri.encodeComponent(proyectoId)}&'
        'licitacionId=${Uri.encodeComponent(licitacionId)}&'
        'generarResumen=${generarResumen ? "true" : "false"}',
      );

      // 4. Enviar a Cloud Function
      print('[ForoXLS] Enviando a Cloud Function...');
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/octet-stream',
        },
        body: bytes,
        // Aumentar timeout a 3 minutos
      ).timeout(const Duration(seconds: 180));

      // 5. Procesar respuesta
      if (response.statusCode == 200) {
        final result = jsonDecode(response.body) as Map<String, dynamic>;
        print('[ForoXLS] ✓ Éxito. ${result['totalPreguntas']} preguntas cargadas');
        return result;
      } else {
        final error = jsonDecode(response.body);
        throw Exception('Error: ${error['error'] ?? response.statusCode}');
      }
    } catch (e) {
      print('[ForoXLS] ✗ Error: $e');
      rethrow;
    }
  }

  /// Obtener datos del foro desde Firestore después de procesarlos
  static Future<Map<String, dynamic>?> obtenerForoGuardado({
    required String proyectoId,
    required String licitacionId,
  }) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('proyectos')
          .doc(proyectoId)
          .collection('foro')
          .doc(licitacionId)
          .get();

      if (!doc.exists) {
        print('[ForoXLS] Foro no encontrado en Firestore');
        return null;
      }

      return doc.data();
    } catch (e) {
      print('[ForoXLS] Error al obtener foro: $e');
      rethrow;
    }
  }

  /// Eliminar archivo temporal después de procesar
  static Future<void> eliminarArchivoTemporal(File archivo) async {
    try {
      if (await archivo.exists()) {
        await archivo.delete();
        print('[ForoXLS] Archivo temporal eliminado: ${archivo.path}');
      }
    } catch (e) {
      print('[ForoXLS] Error al eliminar archivo: $e');
    }
  }

  /// Widget helper para UI: selector de archivo + carga
  static Future<void> cargarDesdeUI({
    required String proyectoId,
    required String licitacionId,
    required Function(String) onProgress,
    required Function(Map<String, dynamic>) onSuccess,
    required Function(String) onError,
  }) async {
    try {
      // Aquí iría la lógica de file picker
      // Por ahora es un skeleton para integración
      
      // Ejemplo con file_picker:
      // final result = await FilePicker.platform.pickFiles(
      //   type: FileType.custom,
      //   allowedExtensions: ['xls', 'xlsx'],
      // );
      //
      // if (result != null) {
      //   final file = File(result.files.single.path!);
      //   onProgress('Cargando archivo...');
      //
      //   final resultado = await procesarArchivoXLS(
      //     archivo: file,
      //     proyectoId: proyectoId,
      //     licitacionId: licitacionId,
      //   );
      //
      //   await eliminarArchivoTemporal(file);
      //   onSuccess(resultado);
      // }

      onError('Implementar file picker en UI');
    } catch (e) {
      onError('$e');
    }
  }
}

/// ─ EJEMPLO DE USO EN UN WIDGET ─

// class CargarForoWidget extends StatefulWidget {
//   final String proyectoId;
//   final String licitacionId;
//
//   const CargarForoWidget({
//     required this.proyectoId,
//     required this.licitacionId,
//   });
//
//   @override
//   State<CargarForoWidget> createState() => _CargarForoWidgetState();
// }
//
// class _CargarForoWidgetState extends State<CargarForoWidget> {
//   bool _cargando = false;
//   String? _mensaje;
//   Map<String, dynamic>? _resultado;
//
//   Future<void> _cargarArchivo() async {
//     setState(() => _cargando = true);
//
//     try {
//       // Mostrar selector de archivos
//       await ForoXLSService.cargarDesdeUI(
//         proyectoId: widget.proyectoId,
//         licitacionId: widget.licitacionId,
//         onProgress: (msg) {
//           setState(() => _mensaje = msg);
//         },
//         onSuccess: (resultado) {
//           setState(() {
//             _resultado = resultado;
//             _mensaje = 'Foro cargado exitosamente';
//             _cargando = false;
//           });
//
//           ScaffoldMessenger.of(context).showSnackBar(
//             SnackBar(
//               content: Text(
//                 '✓ ${resultado["totalPreguntas"]} preguntas cargadas',
//               ),
//               backgroundColor: Colors.green,
//             ),
//           );
//         },
//         onError: (error) {
//           setState(() {
//             _mensaje = 'Error: $error';
//             _cargando = false;
//           });
//
//           ScaffoldMessenger.of(context).showSnackBar(
//             SnackBar(
//               content: Text('✗ $error'),
//               backgroundColor: Colors.red,
//             ),
//           );
//         },
//       );
//     } catch (e) {
//       setState(() {
//         _mensaje = 'Error: $e';
//         _cargando = false;
//       });
//     }
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Column(
//       children: [
//         ElevatedButton.icon(
//           onPressed: _cargando ? null : _cargarArchivo,
//           icon: const Icon(Icons.upload_file),
//           label: Text(_cargando ? 'Cargando...' : 'Cargar archivo XLS'),
//         ),
//         if (_mensaje != null)
//           Padding(
//             padding: const EdgeInsets.only(top: 16),
//             child: Text(_mensaje!),
//           ),
//         if (_resultado != null)
//           Padding(
//             padding: const EdgeInsets.only(top: 16),
//             child: Card(
//               child: Padding(
//                 padding: const EdgeInsets.all(16),
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     Text(
//                       'Resultado:',
//                       style: Theme.of(context).textTheme.titleMedium,
//                     ),
//                     const SizedBox(height: 8),
//                     Text('Total: ${_resultado!["totalPreguntas"]}'),
//                     Text('Respondidas: ${_resultado!["respondidas"]}'),
//                     Text('Resumen IA: ${_resultado!["resumenGenerado"] ? "✓" : "✗"}'),
//                   ],
//                 ),
//               ),
//             ),
//           ),
//       ],
//     );
//   }
// }
