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
              if (sheet == null || sheet.rows.isEmpty) continue;

              // 1. Detectar fila de encabezados (buscar "Pregunta" y "Respuesta")
              int headerRowIdx = -1;
              int idxPregunta = -1;
              int idxRespuesta = -1;
              
              for (int r = 0; r < sheet.rows.length; r++) {
                var row = sheet.rows[r];
                final rowText = row.map((cell) => cell?.value.toString().toLowerCase() ?? '').join('|');
                
                if (rowText.contains('pregunta') && rowText.contains('respuesta')) {
                  headerRowIdx = r;
                  // Mapear índices de columnas
                  for (int c = 0; c < row.length; c++) {
                    final cellVal = row[c]?.value.toString().toLowerCase() ?? '';
                    if (cellVal.contains('pregunta')) idxPregunta = c;
                    if (cellVal.contains('respuesta')) idxRespuesta = c;
                  }
                  break;
                }
              }

              if (headerRowIdx == -1 || idxPregunta == -1 || idxRespuesta == -1) continue;

              // 2. Extraer datos desde la fila siguiente al encabezado
              for (int i = headerRowIdx + 1; i < sheet.rows.length; i++) {
                var row = sheet.rows[i];
                if (row.isEmpty) continue;

                String pregunta = row.length > idxPregunta && row[idxPregunta] != null 
                    ? row[idxPregunta]!.value.toString().trim() 
                    : '';
                String respuesta = row.length > idxRespuesta && row[idxRespuesta] != null 
                    ? row[idxRespuesta]!.value.toString().trim() 
                    : '';

                if (pregunta.isNotEmpty || respuesta.isNotEmpty) {
                  parsedEnquiries.add({
                    'description': pregunta,
                    'answer': respuesta,
                    'date': DateTime.now().toIso8601String(),
                    'dateAnswered': respuesta.isNotEmpty ? DateTime.now().toIso8601String() : null,
                  });
                }
              }

              if (parsedEnquiries.isNotEmpty) {
                hasData = true;
                break;
              }
            }
          } catch (e) {
            // Silent fallback a CSV
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
