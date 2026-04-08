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

              debugPrint('[ForoXLS] Sheet: $table, Filas: ${sheet.rows.length}');

              // ── ESTRATEGIA 1: Detección flexible de encabezados ──
              int headerRowIdx = -1;
              int idxPregunta = -1;
              int idxRespuesta = -1;
              int idxFecha = -1;
              
              // Paso 1: Buscar fila que contenga "Pregunta" Y "Respuesta"
              for (int r = 0; r < sheet.rows.length; r++) {
                var row = sheet.rows[r];
                final rowText = row
                    .map((cell) => cell?.value.toString().toLowerCase().trim() ?? '')
                    .join('|');
                
                final hayPregunta = rowText.contains('pregunta');
                final hayRespuesta = rowText.contains('respuesta') || rowText.contains('answer');
                
                if (hayPregunta && hayRespuesta) {
                  headerRowIdx = r;
                  debugPrint('[ForoXLS] Encabezado exacto encontrado en fila $r');
                  // Mapear índices de columnas
                  for (int c = 0; c < row.length; c++) {
                    final cellVal = row[c]?.value.toString().toLowerCase().trim() ?? '';
                    if (cellVal.contains('pregunta') && idxPregunta == -1) idxPregunta = c;
                    if ((cellVal.contains('respuesta') || cellVal.contains('answer')) && idxRespuesta == -1) idxRespuesta = c;
                    if (cellVal.contains('fecha') && idxFecha == -1) idxFecha = c;
                  }
                  break;
                }
              }

              // Paso 2: Si no encontró, buscar por heurística (primeras 2 columnas con contenido)
              if (headerRowIdx == -1) {
                for (int r = 0; r < sheet.rows.length; r++) {
                  var row = sheet.rows[r];
                  final nonEmpty = row
                      .where((c) => c != null && c.value.toString().trim().isNotEmpty)
                      .toList();
                  
                  // Si tiene al menos 2 celdas con contenido
                  if (nonEmpty.length >= 2) {
                    headerRowIdx = r;
                    idxPregunta = 0;
                    idxRespuesta = nonEmpty.length > 1 ? 1 : 0;
                    debugPrint('[ForoXLS] Encabezado heurístico en fila $r (columnas $idxPregunta, $idxRespuesta)');
                    break;
                  }
                }
              }

              if (headerRowIdx == -1 || idxPregunta == -1 || idxRespuesta == -1) {
                debugPrint('[ForoXLS] No se encontró encabezado válido en esta hoja');
                continue;
              }

              // 2. Extraer datos desde la fila siguiente al encabezado
              int dataRows = 0;
              for (int i = headerRowIdx + 1; i < sheet.rows.length; i++) {
                var row = sheet.rows[i];
                if (row.isEmpty || row.every((c) => c == null)) continue;

                final pregunta = (row.length > idxPregunta && row[idxPregunta] != null)
                    ? row[idxPregunta]!.value.toString().trim()
                    : '';
                final respuesta = (row.length > idxRespuesta && row[idxRespuesta] != null)
                    ? row[idxRespuesta]!.value.toString().trim()
                    : '';
                final fecha = (row.length > idxFecha && row[idxFecha] != null)
                    ? row[idxFecha]!.value.toString().trim()
                    : '';

                // Incluir incluso si pregunta está vacía pero hay respuesta
                if (pregunta.isNotEmpty || respuesta.isNotEmpty) {
                  parsedEnquiries.add({
                    'description': pregunta.isEmpty ? '(Sin pregunta)' : pregunta,
                    'answer': respuesta,
                    'date': fecha.isNotEmpty ? fecha : DateTime.now().toIso8601String(),
                    'dateAnswered': respuesta.isNotEmpty ? DateTime.now().toIso8601String() : null,
                  });
                  dataRows++;
                }
              }

              debugPrint('[ForoXLS] Parseadas $dataRows filas de datos');
              if (parsedEnquiries.isNotEmpty) {
                hasData = true;
                break;
              }
            }
          } catch (e) {
            debugPrint('[ForoXLS] Error parseando Excel: $e');
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
            debugPrint('[ForoXLS] Fallo al parsear como CSV: $e');
          }
        }

        if (hasData) {
          foroEnquiries = parsedEnquiries;
          foroFechaCache = DateTime.now();
          isForoFromLocalFile = true;
          foroResumen = null;
          errorMessage = null;
          debugPrint('[ForoXLS] ✅ Éxito: ${parsedEnquiries.length} preguntas cargadas');
          notifyListeners();
        } else {
          errorMessage = 'No se pudieron detectar preguntas y respuestas en el archivo. Verifica que tenga las columnas "Pregunta" y "Respuesta".';
          debugPrint('[ForoXLS] ❌ Error: ningún formato reconocido');
          notifyListeners();
        }
      }
    } catch (e) {
      errorMessage = 'Error al leer el archivo: $e';
      debugPrint('[ForoXLS] ❌ Excepción: $e');
      notifyListeners();
    }
  }
}
