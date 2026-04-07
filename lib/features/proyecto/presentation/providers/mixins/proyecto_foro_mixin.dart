import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart';
import 'package:csv/csv.dart';
import '../../../domain/entities/proyecto_entity.dart';
import '../../../domain/repositories/proyecto_repository.dart';

/// Estado y operaciones del foro de consultas (licitación).
mixin ProyectoForoMixin on ChangeNotifier {
  ProyectoRepository get repository;
  ProyectoEntity get proyecto;
  String? get errorMessage;
  set errorMessage(String? value);

  bool cargandoForo = false;
  DateTime? foroFechaCache;
  List<Map<String, dynamic>> foroEnquiries = [];
  String? foroResumen;
  bool cargandoResumen = false;
  String foroQuery = '';
  bool isForoFromLocalFile = false;

  List<Map<String, dynamic>> get filteredForo {
    if (foroQuery.isEmpty) return foroEnquiries;
    return foroEnquiries.where((e) {
      final text = (e['description'] ?? '') + (e['answer'] ?? '');
      return text.toLowerCase().contains(foroQuery.toLowerCase());
    }).toList();
  }

  void setForoQuery(String query) {
    foroQuery = query;
    notifyListeners();
  }

  Future<void> cargarForo({bool forceRefresh = false}) async {
    if (cargandoForo) return;
    if (isForoFromLocalFile && !forceRefresh) return; // Do not overwrite if it's from local file unless forced
    cargandoForo = true;
    notifyListeners();
    try {
      if (proyecto.idLicitacion != null) {
        foroEnquiries = await repository.getForoData(proyecto.idLicitacion!, forceRefresh: forceRefresh);
        foroFechaCache = DateTime.now();
        isForoFromLocalFile = false;
      }
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      cargandoForo = false;
      notifyListeners();
    }
  }

  Future<void> generarResumenForo() async {
    if (cargandoResumen || foroEnquiries.isEmpty) return;
    cargandoResumen = true;
    notifyListeners();
    try {
      if (proyecto.idLicitacion != null) {
        foroResumen = await repository.generateForoSummary(proyecto.idLicitacion!, foroEnquiries);
      }
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      cargandoResumen = false;
      notifyListeners();
    }
  }

  Future<void> cargarForoDesdeArchivo() async {
    try {
      FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'xls', 'xlsx'],
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        final bytes = file.bytes;
        if (bytes == null) return;

        List<Map<String, dynamic>> parsedEnquiries = [];
        bool hasData = false;
        String fileName = (file.name).toLowerCase();

        // Intenta parsear como Excel primero si es xlsx o xls
        if (fileName.endsWith('.xlsx') || fileName.endsWith('.xls')) {
          try {
            var excel = Excel.decodeBytes(bytes);
            for (var table in excel.tables.keys) {
              var sheet = excel.tables[table];
              if (sheet != null && sheet.rows.length >= 5) {
                // The first 4 rows are title/headers. Data starts at row 5 (index 4).
                for (int i = 4; i < sheet.rows.length; i++) {
                  var row = sheet.rows[i];
                  
                  String fecha = row.length > 1 && row[1] != null ? row[1]!.value.toString() : '';
                  String pregunta = row.length > 3 && row[3] != null ? row[3]!.value.toString() : '';
                  String respuesta = row.length > 4 && row[4] != null ? row[4]!.value.toString() : '';

                  if (fecha.startsWith("'")) fecha = fecha.substring(1);

                  if (pregunta.isNotEmpty || respuesta.isNotEmpty) {
                    parsedEnquiries.add({
                      'description': pregunta,
                      'answer': respuesta,
                      'date': fecha,
                      'dateAnswered': fecha,
                    });
                  }
                }
                if (parsedEnquiries.isNotEmpty) {
                   hasData = true;
                   break;
                }
              }
            }
          } catch (e) {
            // Si falla decodificar como Excel, continuará y probará como CSV (muy común en portales que exportan CSV/HTML como .xls)
            debugPrint('Fallo al parsear como Excel, intentando como CSV: \$e');
          }
        }

        // Si no pudo leerse como Excel, o si era CSV directamente, intentar como CSV
        if (!hasData) {
          try {
            final csvString = utf8.decode(bytes, allowMalformed: true);
            List<List<dynamic>> csvTable = Csv(fieldDelimiter: '\t', quoteCharacter: '"').decode(csvString);
            
            // Portales chilenos a veces usan ; o , 
            if (csvTable.length < 5 || (csvTable.length > 4 && csvTable[4].length < 3)) {
              csvTable = Csv(fieldDelimiter: ';', quoteCharacter: '"').decode(csvString);
            }
            if (csvTable.length < 5 || (csvTable.length > 4 && csvTable[4].length < 3)) {
              csvTable = Csv(fieldDelimiter: ',', quoteCharacter: '"').decode(csvString);
            }

            if (csvTable.length >= 5) {
              for (int i = 4; i < csvTable.length; i++) {
                var row = csvTable[i];
                String fecha = row.length > 1 ? row[1].toString() : '';
                String pregunta = row.length > 3 ? row[3].toString() : '';
                String respuesta = row.length > 4 ? row[4].toString() : '';

                if (fecha.startsWith("'")) fecha = fecha.substring(1);

                if (pregunta.isNotEmpty || respuesta.isNotEmpty) {
                  parsedEnquiries.add({
                    'description': pregunta,
                    'answer': respuesta,
                    'date': fecha,
                    'dateAnswered': fecha,
                  });
                }
              }
              if (parsedEnquiries.isNotEmpty) hasData = true;
            }
          } catch (e) {
            debugPrint('Fallo al parsear como CSV: \$e');
          }
        }

        if (hasData) {
          foroEnquiries = parsedEnquiries;
          foroFechaCache = DateTime.now();
          isForoFromLocalFile = true;
          foroResumen = null; // Clear previous IA summary
          errorMessage = null; // Limpiar errores si los había
          notifyListeners();
        } else {
          errorMessage = 'El archivo no tiene el formato esperado (se requieren datos desde la fila 5) o es inválido.';
          notifyListeners();
        }
      }
    } catch (e) {
      errorMessage = 'Error al leer el archivo: \$e';
      notifyListeners();
    }
  }
}
