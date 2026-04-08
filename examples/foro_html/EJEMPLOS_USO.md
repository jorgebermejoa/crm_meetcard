# Ejemplos de Uso - Procesar Foro XLS

## Tabla de Contenidos
- [Desde Node.js](#desde-nodejs)
- [Desde Flutter/Dart](#desde-flutterdart)
- [Desde cURL](#desde-curl)
- [Desde PowerShell](#desde-powershell)
- [Flujo Completo](#flujo-completo)

## Desde Node.js

### Requisitos
```bash
npm install axios firebase-admin
```

### Ejemplo Básico
```javascript
const fs = require('fs');
const axios = require('axios');

async function cargarForo() {
  const buffer = fs.readFileSync('./archivo.xls');
  const token = 'tu_token_firebase';

  const response = await axios.post(
    'https://us-central1-licitaciones-prod.cloudfunctions.net/procesarForoXLS'
    + '?proyectoId=P1&licitacionId=L1&generarResumen=true',
    buffer,
    {
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/octet-stream',
      }
    }
  );

  console.log('✓ Foro cargado:', response.data);
}

cargarForo().catch(console.error);
```

### Usar Script Client
```bash
node procesar_foro_client.js \
  ./Foro_PreguntasRespuestas_06-04-2026_17-06.xls \
  mi_proyecto \
  2026-123456 \
  $FIREBASE_TOKEN

# O sin token (usa FIREBASE_TOKEN env var)
export FIREBASE_TOKEN=eyJhbGciOiJSUzI1NiIs...
node procesar_foro_client.js \
  ./Foro_PreguntasRespuestas_06-04-2026_17-06.xls \
  mi_proyecto \
  2026-123456
```

## Desde Flutter/Dart

### Setup
```yaml
# pubspec.yaml
dependencies:
  firebase_auth: ^latest
  cloud_firestore: ^latest
  http: ^latest
  file_picker: ^latest
```

### Uso Básico
```dart
import 'package:foro_xls_service.dart';

// Cargar archivo y procesar
final resultado = await ForoXLSService.procesarArchivoXLS(
  archivo: File('/ruta/al/archivo.xls'),
  proyectoId: 'mi_proyecto',
  licitacionId: '2026-123456',
  generarResumen: true,
);

print('Preguntas: ${resultado['totalPreguntas']}');
print('Resumen: ${resultado['resumen']}');
```

### Cargar desde UI
```dart
import 'package:file_picker/file_picker.dart';

Future<void> cargarDesdeUI() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['xls', 'xlsx'],
  );

  if (result != null) {
    final file = File(result.files.single.path!);
    
    final resultado = await ForoXLSService.procesarArchivoXLS(
      archivo: file,
      proyectoId: 'mi_proyecto',
      licitacionId: '2026-123456',
    );

    // Limpiar archivo temporal
    await ForoXLSService.eliminarArchivoTemporal(file);

    // Usar resultado
    mostrarDialogo(
      'Éxito',
      '${resultado['totalPreguntas']} preguntas cargadas',
    );
  }
}
```

## Desde cURL

### Prueba Simple
```bash
# 1. Obtener token (desde Firebase Console o CLI)
TOKEN=eyJhbGciOiJSUzI1NiIs...

# 2. Cargar archivo
curl -X POST \
  'https://us-central1-licitaciones-prod.cloudfunctions.net/procesarForoXLS?proyectoId=P1&licitacionId=L1&generarResumen=true' \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/octet-stream' \
  --data-binary @Foro_PreguntasRespuestas_06-04-2026_17-06.xls \
  | jq .
```

### Con Guardado de Respuesta
```bash
curl -X POST \
  'https://us-central1-licitaciones-prod.cloudfunctions.net/procesarForoXLS?proyectoId=P1&licitacionId=L1&generarResumen=true' \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/octet-stream' \
  --data-binary @archivo.xls \
  -o respuesta.json

cat respuesta.json | jq .
```

## Desde PowerShell

### Básico
```powershell
$TOKEN = 'eyJhbGciOiJSUzI1NiIs...'
$ArchivoPath = 'C:\Rutas\archivo.xls'
$Bytes = [System.IO.File]::ReadAllBytes($ArchivoPath)

$Response = Invoke-WebRequest `
  -Uri ('https://us-central1-licitaciones-prod.cloudfunctions.net/procesarForoXLS?' +
        'proyectoId=P1&licitacionId=L1&generarResumen=true') `
  -Method Post `
  -Headers @{
    'Authorization' = "Bearer $TOKEN"
    'Content-Type' = 'application/octet-stream'
  } `
  -Body $Bytes

$Response.Content | ConvertFrom-Json | Format-List
```

### Script Reutilizable
```powershell
param(
  [string]$ArchivoXLS,
  [string]$ProyectoId,
  [string]$LicitacionId,
  [string]$Token
)

if (-not $Token) {
  $Token = $env:FIREBASE_TOKEN
}

$Bytes = [System.IO.File]::ReadAllBytes($ArchivoXLS)

$Response = Invoke-WebRequest `
  -Uri ("https://us-central1-licitaciones-prod.cloudfunctions.net/procesarForoXLS?" +
        "proyectoId=$ProyectoId&licitacionId=$LicitacionId&generarResumen=true") `
  -Method Post `
  -Headers @{
    'Authorization' = "Bearer $Token"
    'Content-Type' = 'application/octet-stream'
  } `
  -Body $Bytes

$Resultado = $Response.Content | ConvertFrom-Json
Write-Host "✓ Completado"
Write-Host "  Preguntas: $($Resultado.totalPreguntas)"
Write-Host "  Respondidas: $($Resultado.respondidas)"
Write-Host "  Resumen: $($Resultado.resumenGenerado)"
```

Uso:
```powershell
.\cargar_foro.ps1 `
  -ArchivoXLS "C:\archivo.xls" `
  -ProyectoId "mi_proyecto" `
  -LicitacionId "2026-123456"
```

## Flujo Completo

### 1. Preparación
```bash
# Descargar archivo desde Mercado Público
# (manual o vía script)

# Verificar estructura con diagnóstico
node functions/diagnosticar_xls.js archivo.xls
```

### 2. Carga y Procesamiento
```bash
# Opción A: Node.js
node examples/foro_html/procesar_foro_client.js \
  archivo.xls \
  mi_proyecto \
  2026-123456

# Opción B: cURL
curl -X POST ... --data-binary @archivo.xls

# Opción C: Flutter/Dart (desde app)
await ForoXLSService.procesarArchivoXLS(...)
```

### 3. Verificación
```bash
# Ver datos en Firestore
firebase firestore:get proyectos/mi_proyecto/foro/2026-123456

# O desde Flutter
final doc = await FirebaseFirestore.instance
  .collection('proyectos')
  .doc('mi_proyecto')
  .collection('foro')
  .doc('2026-123456')
  .get();

print(doc.data());
```

### 4. Cleanup
```dart
// Eliminar archivo temporal
await ForoXLSService.eliminarArchivoTemporal(file);
```

## Respuesta Exitosa Típica
```json
{
  "ok": true,
  "licitacionId": "2026-123456",
  "totalPreguntas": 11,
  "respondidas": 11,
  "sinResponder": 0,
  "resumenGenerado": true,
  "resumen": "Puntos clave:\n- Plazo de implementación 15 días\n- Diseño y migración incluidos..."
}
```

## Errores Comunes

### No autorizado (401)
```
Error: Faltan credenciales o token expirado
Solución: Verificar que Authorization header sea correcto
```

### Archivo vacío (400)
```
Error: Body debe ser buffer o base64
Solución: Asegurarse de enviar Content-Type: application/octet-stream + body binario
```

### Sin encabezados (400)
```
Error: No se encontraron encabezados en el archivo XLS
Solución: Ejecutar diagnostpicar_xls.js para verificar estructura
```

### Timeout (504)
```
Error: La función tardó más de 180 segundos
Solución: Archivo muy grande, dividir o aumentar timeout
```

## Debugging

### Logs en Cloud Functions
```bash
firebase functions:log --follow
```

### Verificar token
```bash
# Firebase CLI
firebase auth:export users.json --account tu_email@gmail.com

# O verificar en Firebase Console > Authentication
```

### Trazas locales
```bash
# Ejecutar emulador local
firebase emulators:start --only functions
```

## Más Información
- Documentación: [PROCESAMIENTO_XLS.md](./PROCESAMIENTO_XLS.md)
- Script Parser: [convertir_xls_v3.js](../../functions/convertir_xls_v3.js)
- Ejemplos: [examples/foro_html/](.)
