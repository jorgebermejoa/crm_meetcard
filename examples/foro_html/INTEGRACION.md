# 📋 Integración: Procesamiento de Archivos XLS del Foro

## Resumen Ejecutivo

Se ha integrado exitosamente un sistema **completo y automático** de carga, parseo y procesamiento de archivos XLS de foros de Mercado Público. El sistema incluye:

✅ **Cloud Function**: `procesarForoXLS`  
✅ **Parser robusto**: Detecta automáticamente estructura XLS  
✅ **Resumen IA**: Integración con Gemini 2.5  
✅ **Guardado en Firestore**: Dos niveles de caché  
✅ **3 clientes**: Node.js, Flutter/Dart, cURL/PowerShell  

---

## Arquitectura

```
┌─────────────────────┐
│   Usuario carga     │
│   archivo XLS       │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────────────────────────────────────────┐
│         Cloud Function: procesarForoXLS                  │
├──────────────────────────────────────────────────────────┤
│                                                           │
│  1. Recibe buffer binario (multipart/XLS)               │
│  2. Parsea con parseXLSForoMP() helper                  │
│  3. Valida estructura (# Fecha Tipo Pregunta Respuesta) │
│  4. Extrae 11 Q&A items                                 │
│  5. Guarda en Firestore:                                │
│     • proyectos/{proyectoId}/foro/{licitacionId}       │
│     • licitaciones_foro/{licitacionId}  (caché)        │
│  6. Genera resumen IA con Gemini (opcional)             │
│  7. Retorna JSON con stats                              │
│                                                           │
└──────────────────────────────────────────────────────────┘
           │
           ▼
┌─────────────────────────────────────────────────────────┐
│         Firestore Collections                            │
├──────────────────────────────────────────────────────────┤
│                                                           │
│  proyectos/                                             │
│    └─ {proyectoId}/                                     │
│         └─ foro/                                        │
│              └─ {licitacionId}  ← Foro + Resumen       │
│                     enquiries: [...]                    │
│                     resumen: "texto..."                 │
│                     resumenGeneradoAt: Timestamp        │
│                     fetchedMethod: "xls_upload"         │
│                                                           │
│  licitaciones_foro/                                     │
│    └─ {licitacionId}  ← Caché global                   │
│           enquiries: [...]                              │
│           fetchedMethod: "xls_upload"                   │
│                                                           │
└─────────────────────────────────────────────────────────┘
```

---

## Cambios Realizados

### 1. En `functions/index.js`

#### a) Import de XLSX (línea 18)
```javascript
const XLSX = require('xlsx');
```

#### b) Función Helper: `parseXLSForoMP()` (líneas ~3030-3100)
- Lee archivo XLS
- Detecta encabezados automáticamente
- Mapea columnas: #, Fecha, Tipo, Preguntas, Respuestas
- Retorna array de objetos con estructura:
  ```javascript
  {
    description: "Pregunta?",
    answer: "Respuesta",
    date: "fecha",
    number: 1
  }
  ```

#### c) Cloud Function: `procesarForoXLS` (líneas ~3100-3200)
- **Endpoint**: `POST /procesarForoXLS`
- **Parámetros**:
  - `proyectoId` (required)
  - `licitacionId` (required)
  - `generarResumen` (optional, default=true)
- **Body**: archivo XLS como buffer binario
- **Retorna**: JSON con stats y resumen (preview)

### 2. Archivos Creados

```
examples/foro_html/
├── PROCESAMIENTO_XLS.md           ← Documentación técnica completa
├── EJEMPLOS_USO.md                ← Ejemplos para cada lenguaje
├── procesar_foro_client.js        ← Cliente Node.js
├── foro_xls_service.dart          ← Servicio Flutter/Dart
└── INTEGRACION.md (NEW)           ← Este archivo
```

---

## Cómo Usar

### Opción 1: Node.js (Desarrollo/Backend)

```bash
# Pasos:
1. Descargar archivo desde Mercado Público
2. Ejecutar client:

node examples/foro_html/procesar_foro_client.js \
  "./Foro_PreguntasRespuestas_06-04-2026_17-06.xls" \
  "mi_proyecto" \
  "2026-123456" \
  "$FIREBASE_TOKEN"

# Resultado: ✓ 11 preguntas cargadas, resumen generado
```

### Opción 2: Flutter/Dart (Aplicación móvil/web)

```dart
import 'foro_xls_service.dart';

// En tu widget:
final resultado = await ForoXLSService.procesarArchivoXLS(
  archivo: File('/ruta/al/archivo.xls'),
  proyectoId: 'mi_proyecto',
  licitacionId: '2026-123456',
  generarResumen: true,
);

print('✓ ${resultado['totalPreguntas']} preguntas');
print('Resumen:\n${resultado['resumen']}');
```

### Opción 3: cURL (Testing rápido)

```bash
TOKEN=eyJhbGciOiJSUzI1NiIs...

curl -X POST \
  'https://us-central1-licitaciones-prod.cloudfunctions.net/procesarForoXLS?proyectoId=P1&licitacionId=L1&generarResumen=true' \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/octet-stream' \
  --data-binary @archivo.xls | jq .
```

---

## Características

### ✅ Parseo Automático
- Detecta estructura XLS automáticamente
- Mapea columnas sin configuración
- Maneja formatos variados de Mercado Público

### ✅ Resumen IA con Gemini
- Analiza Q&A y genera puntos clave
- Identifica cambios de plazos
- Detecta alertas importantes
- Responde en español, formato markdown

### ✅ Guardado Dual en Firestore
```
proyectos/{proyectoId}/foro/{licitacionId}  ← Específico del proyecto
licitaciones_foro/{licitacionId}             ← Caché global (acceso rápido)
```

### ✅ Metadatos Completos
Cada guardado incluye:
- `enquiries`: preguntas y respuestas
- `fetchedMethod`: "xls_upload"
- `uploadedAt`: timestamp
- `resumen`: texto generado por IA
- `resumenGeneradoAt`: timestamp

### ✅ Manejo de Errores
- Validación de archivo
- Verificación de estructura
- Autenticación requerida
- Timeout: 180 segundos
- Logs en Cloud Functions

---

## Ejemplo de Respuesta

```json
{
  "ok": true,
  "licitacionId": "2026-123456",
  "totalPreguntas": 11,
  "respondidas": 11,
  "sinResponder": 0,
  "resumenGenerado": true,
  "resumen": "## Puntos Clave\n- Plazo de implementación: 15 días\n- Se solicita diseño, desarrollo, migración e implementación\n...\n"
}
```

---

## Integración con OCDS API

Para reemplazar datos de la API OCDS automáticamente:

```javascript
// En functions/index.js u otra lógica:

// 1. Datos del XLS están guardados
const xls_foro = await db.collection('licitaciones_foro').doc(licitacionId).get();

// 2. Si queremos usar XLS instead of API:
if (document.fetchedMethod === 'xls_upload') {
  // Usar xls_foro.enquiries en lugar de API OCDS
  return xls_foro.data();
}

// 3. También está disponible el resumen:
const resumen = xls_foro.data().resumen;
```

---

## Flujo de Trabajo Recomendado

### Para Administrador

```
1. Usuario descarga archivo XLS desde Mercado Público
   (ej: Foro_PreguntasRespuestas_06-04-2026_17-06.xls)

2. Carga archivo vía:
   • Web/App Flutter (UI file picker)
   • Node.js script (backend)
   • cURL (manual)

3. Sistema automáticamente:
   ✓ Parsea estructura
   ✓ Extrae 11 Q&A items
   ✓ Genera resumen IA
   ✓ Guarda en Firestore (2 locations)
   ✓ Retorna stats

4. Datos disponibles para:
   • Mostrar en UI de licitación
   • Usar en reportes
   • Acceso API OCDS
```

### Para Desarrollo

```
1. Verificar estructura con diagnóstico:
   node functions/diagnosticar_xls.js archivo.xls

2. Testear en local con emulador:
   firebase emulators:start --only functions

3. Validar Cloud Function puede parsear:
   node procesar_foro_client.js archivo.xls P1 L1 TOKEN

4. Monitorear logs:
   firebase functions:log --follow

5. Verificar Firestore:
   firebase firestore:get proyectos/P1/foro/L1
```

---

## Testing

### Archivo de Prueba Disponible
```
examples/foro_html/Foro_PreguntasRespuestas_06-04-2026_17-06.xls
```
- 11 preguntas reales
- Todas con respuesta
- Estructura MP estándar

### Comandos de Prueba
```bash
# 1. Verificar estructura
node functions/convertir_xls_v3.js examples/foro_html/Foro_*.xls

# 2. Procesar con Cloud Function
node examples/foro_html/procesar_foro_client.js \
  examples/foro_html/Foro_*.xls \
  test_proyecto \
  2026-123456 \
  $FIREBASE_TOKEN

# 3. Verificar guardado en Firestore
firebase firestore:get proyectos/test_proyecto/foro/2026-123456
```

---

## Documentación Referencia

| Documento | Contenido |
|-----------|----------|
| [PROCESAMIENTO_XLS.md](./PROCESAMIENTO_XLS.md) | Especificación técnica completa, estructura Firestore, parámetros API |
| [EJEMPLOS_USO.md](./EJEMPLOS_USO.md) | Ejemplos de código para Node.js, Dart, cURL, PowerShell, flujo completo |
| [convertir_xls_v3.js](../../functions/convertir_xls_v3.js) | Script local para pruebas y diagnóstico |
| [procesar_foro_client.js](./procesar_foro_client.js) | Cliente Node.js para carga remota |
| [foro_xls_service.dart](./foro_xls_service.dart) | Servicio Dart/Flutter listo para integrar |

---

## Próximos Pasos (Opcionales)

1. **UI en Flutter**: 
   - Agregar botón "Cargar archivo XLS" en proyectos
   - File picker + animación de progreso
   - Mostrar resumen en detalle

2. **Automación**:
   - Webhooks de Mercado Público para notificar nuevo foro
   - Procesamiento automático sin intervención manual

3. **Gestión de Cambios**:
   - Detectar diferencias entre versiones de foro
   - Notificar a usuarios sobre cambios
   - Historial de cambios

4. **Integraciones**:
   - Exportar resumen a email
   - Sincronizar con Google Docs
   - Enviar alertas a Slack

---

## Soporte

### Errores Comunes

| Error | Causa | Solución |
|-------|-------|----------|
| "No se encontraron encabezados" | Estructura XLS inválida | Ejecutar `diagnosticar_xls.js` para debug |
| "No autorizado (401)" | Token expirado/inválido | Generar nuevo token Firebase |
| "Body debe ser buffer" | Formato incorrecto | Enviar como `application/octet-stream` |
| Timeout (504) | Función tardó >180s | Archivo muy grande, dividir o aumentar timeout |

### Logs
```bash
firebase functions:log --follow
# O ver en Firebase Console > Cloud Functions > procesarForoXLS
```

---

## Resumen de Archivos Modificados

| Archivo | Cambio | Líneas |
|---------|--------|--------|
| `functions/index.js` | ✅ Agregado: import XLSX, helper parseXLSForoMP(), Cloud Function procesarForoXLS | +200 |
| `examples/foro_html/PROCESAMIENTO_XLS.md` | ✅ Creado | Doc técnica |
| `examples/foro_html/EJEMPLOS_USO.md` | ✅ Creado | Ejemplos código |
| `examples/foro_html/procesar_foro_client.js` | ✅ Creado | Cliente Node.js |
| `examples/foro_html/foro_xls_service.dart` | ✅ Creado | Servicio Dart |

**Total**: 1 archivo modificado, 4 archivos creados

---

**Estado**: ✅ **COMPLETADO**  
**Fecha**: 2026-04-08  
**Versión**: v1.0
