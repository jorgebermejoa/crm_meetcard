# Procesamiento de Archivos XLS del Foro

## Descripción

La función `procesarForoXLS` en `functions/index.js` permite:

1. **Cargar archivos XLS** desde Mercado Público directamente
2. **Parsear automáticamente** la estructura de preguntas/respuestas
3. **Generar resumen IA** con Gemini
4. **Guardar en Firestore** tanto el foro como el resumen
5. **Reemplazar datos** de la API OCDS si es necesario

## Flujo de Trabajo

```
[Archivo XLS descargado]
         ↓
  [Parsear estructura]
         ↓
  [Validar datos]
         ↓
  [Guardar en Firestore]
         ↓
  [Generar resumen IA] ← opcional
         ↓
  [Guardado completado]
```

## Cloud Function: `procesarForoXLS`

### URL
```
POST https://us-central1-licitaciones-prod.cloudfunctions.net/procesarForoXLS?proyectoId=XXX&licitacionId=YYY&generarResumen=true
```

### Parámetros Query
- `proyectoId` (required): ID del proyecto en Firestore
- `licitacionId` (required): ID de la licitación (código de MP)
- `generarResumen` (optional, default=true): Si true, genera resumen con Gemini

### Headers
- `Authorization: Bearer <token>` - Token de Firebase Auth
- `Content-Type: application/octet-stream` o `application/json`

### Body
Enviar el archivo XLS como:
- **Buffer binario directo**: `Content-Type: application/octet-stream`
- **Base64 string**: `Content-Type: application/json` con `{"fileBase64": "..."}`

### Respuesta Exitosa
```json
{
  "ok": true,
  "licitacionId": "2026-123456",
  "totalPreguntas": 11,
  "respondidas": 11,
  "sinResponder": 0,
  "resumenGenerado": true,
  "resumen": "Puntos clave:\n- Plazo de implementación...\n"
}
```

### Respuesta de Error
```json
{
  "error": "Error parseando XLS: ..."
}
```

## Estructura de Guardado en Firestore

### Colección: `proyectos/{proyectoId}/foro/{licitacionId}`
```json
{
  "enquiries": [
    {
      "description": "Pregunta 1?",
      "answer": "Respuesta 1",
      "date": "14-09-2022 16:45:20",
      "dateAnswered": "2026-04-08T...",
      "participant": "",
      "number": 1
    }
  ],
  "fetchedMethod": "xls_upload",
  "uploadedAt": "Timestamp",
  "fetchedAt": "Timestamp",
  "resumen": "Resumen IA generado...",
  "resumenGeneradoAt": "Timestamp"
}
```

### Colección: `licitaciones_foro/{licitacionId}`
Se copia la misma estructura anterior para caché global rápido.

## Cómo Usar desde el Cliente (Flutter/Web)

### 1. Carga de archivo desde UI
```dart
// En tu widget Flutter
final File archivoXLS = ...;
final bytes = await archivoXLS.readAsBytes();

const url = 'https://us-central1-licitaciones-prod.cloudfunctions.net/procesarForoXLS'
  '?proyectoId=mi_proyecto'
  '&licitacionId=2026-123456'
  '&generarResumen=true';

final response = await http.post(
  Uri.parse(url),
  headers: {
    'Authorization': 'Bearer $token',
    'Content-Type': 'application/octet-stream',
  },
  body: bytes,
);

if (response.statusCode == 200) {
  final result = jsonDecode(response.body);
  print('✓ Foro cargado: ${result['totalPreguntas']} preguntas');
} else {
  print('✗ Error: ${response.body}');
}
```

### 2. Verificación post-carga
```dart
// Después de cargar el archivo, el foro está disponible en Firestore
final foroDoc = await FirebaseFirestore.instance
  .collection('proyectos')
  .doc(proyectoId)
  .collection('foro')
  .doc(licitacionId)
  .get();

final enquiries = List.from(foroDoc['enquiries'] ?? []);
final resumen = foroDoc['resumen'] ?? '';
```

### 3. Reemplazar datos de API OCDS
```dart
// Si quieres usar datos del XLS en lugar de la API
const apiData = {
  'foro_from': 'mercado_publico_xls',
  'enquiries': enquiries,
  'resumen': resumen,
};
```

## Cómo Usar desde Node.js (Backend)

### Leer archivo local y enviar
```javascript
const fs = require('fs');
const axios = require('axios');

async function cargarForoXLS(rutaArchivo, proyectoId, licitacionId) {
  const buffer = fs.readFileSync(rutaArchivo);
  const token = await obtenerTokenFirebase();

  const response = await axios.post(
    `https://us-central1-licitaciones-prod.cloudfunctions.net/procesarForoXLS?`
    + `proyectoId=${proyectoId}&licitacionId=${licitacionId}&generarResumen=true`,
    buffer,
    {
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/octet-stream',
      },
    }
  );

  return response.data;
}

// Uso
const resultado = await cargarForoXLS(
  './Foro_PreguntasRespuestas_06-04-2026_17-06.xls',
  'mi_proyecto',
  '2026-123456'
);

console.log('✓ Cargado:', resultado);
```

## Opciones de Uso

### Solo guardar sin resumen
```bash
curl -X POST \
  'https://.../procesarForoXLS?proyectoId=P1&licitacionId=L1&generarResumen=false' \
  -H 'Authorization: Bearer TOKEN' \
  --data-binary @archivo.xls
```

### Eliminar archivo después de procesar
```dart
// En tu UI, después de transmitir:
await archivoXLS.delete();
print('✓ Archivo temporal eliminado');
```

### Reemplazar archivo existente
```dart
// Si ya hay un foro en Firestore, procesarForoXLS lo sobrescribe
// (El parámetro merge: true en set() preserva otros campos)
```

## Restricciones

- Tamaño máximo: 50MB (límite Cloud Functions)
- Timeout: 180 segundos
- Requiere autenticación Firebase
- El archivo debe tener estructura MP estándar:
  - Encabezados en una fila con: "#", "Pregunta", "Respuesta"
  - Datos debajo del encabezado

## Troubleshooting

### Error: "No se encontraron encabezados"
- Verifica que el archivo tenga las columnas: #, Fecha, Tipo, Preguntas, Respuestas
- Usa el script local `functions/diagnosticar_xls.js` para verificar estructura:
  ```bash
  node functions/diagnosticar_xls.js tu_archivo.xls
  ```

### Error: "Body debe ser buffer o base64"
- Asegúrate de enviar el archivo como `Content-Type: application/octet-stream`
- O encódifica en base64 y envía como JSON

### Resumen no se genera
- Verifica que GEMINI_API_KEY esté configurada en Cloud Functions
- Revisa los logs en Firebase Console
- El foro sigue guardándose aunque falle el resumen

## Integración con OCDS API

Para reemplazar datos de OCDS automáticamente:

```javascript
// En functions/index.js, agregar lógica:
const ocdsData = {
  releases: [{
    tender: {
      enquiries: enquiries.map(e => ({
        description: e.description,
        answer: e.answer,
        date: e.date,
      }))
    }
  }]
};

// Guardar como sobrescritura temporal si lo deseas
```

## Referencias

- Script de prueba local: `functions/convertir_xls_v3.js`
- Ejemplos de archivos: `examples/foro_html/`
- Función helper: `parseXLSForoMP()` en `functions/index.js`
