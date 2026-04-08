# Reparación: Detalle de Convenio Marco con Tabs

## Cambios Realizados

Se ha creado un nuevo widget completo para mostrar detalles de Convenios Marco con una interfaz de tabs, similar al que existe para Licitaciones Públicas.

### 1. Nuevo Widget: `detalle_convenio_marco.dart`

**Ubicación**: `lib/widgets/detalle_convenio_marco.dart`

**Características**:
- **Panel de Información**: Muestra todos los campos extraídos de la URL del Convenio Marco
  - Título del convenio
  - Comprador/Organismo
  - Número de convenio
  - Estado del processo (Finalizada, Desestimada, Revocada, etc.)
  - Todos los campos dinámicos extraídos del HTML

- **Panel de Calendario**: Extrae automáticamente las fechas importantes
  - Publicación
  - Cierre de Publicación
  - Inicio de Evaluación
  - Fin de Evaluación
  - Vigencia de Cotización/Contrato
  - Plazo para preguntas
  - Muestra una timeline visual con las fechas

- **Header con información rápida**:
  - Estado del convenio (con color según estado)
  - Botón "Abrir en Mercado Público"
  - Título y comprador del convenio

### 2. Funciones Exportadas

```dart
// Mostrar el detalle en un bottom sheet (modal):
mostrarDetalleConvenioMarcoSheet(BuildContext context, Map<String, dynamic> rawData)

// Componente principal (también se puede usar directamente):
DetalleConvenioMarcoSidebar(rawData, onClose: callback)
```

### 3. Integración en Formulario

**Archivo modificado**: `lib/widgets/proyecto_form_dialog.dart`

**Cambios**:
- Se importó `detalle_convenio_marco.dart`
- Función `_buscarConvenio()` ahora:
  1. Obtiene los datos del Convenio Marco desde la Cloud Function
  2. Rellena automáticamente el campo "Institución" (comprador)
  3. **Muestra un sheet con el widget de detalle** para que el usuario vea todos los datos extraídos
  4. El usuario puede ver el calendario de evaluación, todos los campos, y hacer clic en "Abrir" para ver la página original en Mercado Público

## Cómo se Usa

### Opción 1: Desde el Formulario de Creación de Proyecto

1. Abre el diálogo "Crear Proyecto"
2. Selecciona "Convenio Marco" como modalidad
3. Pega la URL del convenio en el campo "URL Convenio Marco"
4. Haz clic en "Buscar"
5. **Automáticamente aparecerá un sheet con los detalles extraídos del convenio marco**, con dos tabs:
   - **Información**: Todos los campos extraídos del HTML
   - **Calendario**: Fechas importantes en una timeline visual

### Opción 2: Uso Directo del Widget

```dart
import 'package:licitaciones_app/widgets/detalle_convenio_marco.dart';

// En cualquier parte de la aplicación:
mostrarDetalleConvenioMarcoSheet(context, {
  'titulo': 'Nombre del Convenio',
  'comprador': 'Institución Compradora',
  'estado': 'Finalizada',
  'url': 'https://...',
  'campos': [
    {'label': 'Inicio de evaluación', 'valor': '15/02/2024'},
    {'label': 'Fin de evaluación', 'valor': '20/02/2024'},
    // ... otros campos
  ],
});
```

## Structure de Datos

La Cloud Function `obtenerDetalleConvenioMarco` devuelve:

```json
{
  "id": "5802363-1914YBCF",
  "url": "https://conveniomarco2.mercadopublico.cl/...",
  "titulo": "Nombre del Convenio",
  "comprador": "Institución | RUT",
  "convenioMarco": "Número de Convenio",
  "estado": "Finalizada",
  "campos": [
    {
      "label": "Inicio de publicación",
      "valor": "15/02/2024"
    },
    {
      "label": "Fin de evaluación", 
      "valor": "20/02/2024"
    },
    // ... más campos extraídos
  ],
  "fetchError": null
}
```

## Características del Widget

### Extracción Automática de Fechas

El widget detecta automáticamente fechas importantes basándose en las etiquetas:
- Contiene "Inicio" + "Publicación" → "Publicación"
- Contiene "Fin" + "Evaluación" → "Fin Evaluación"
- Contiene "Plazo" + "Preguntas" → "Plazo Preguntas"
- Y más...

### Estados de Convenio con Colores

- ✅ Finalizada/Adjudicada → Verde (Éxito)
- ⚠️ Revocada/Desierta → Naranja (Advertencia)
- ❌ Desestimada → Rojo
- 🔵 Evaluación/Abierta → Azul (Primario)
- ⚪ Otros → Gris

### Responsividad

- Se adapta automáticamente a Mobile y Desktop
- En mobile: ocupa el 92% de la altura como bottom sheet
- En desktop: ancho de 520px como sidebar

## Testing

Para verificar que funciona correctamente:

1. Navega a "Crear Proyecto"
2. Selecciona "Convenio Marco"
3. Pega una URL como:
   `https://conveniomarco2.mercadopublico.cl/software3/quote_public/requestquote/view/id/5802363-1914YBCF/`
4. Haz clic en "Buscar"
5. Debería aparecer un sheet con los dos tabs y los datos extraídos

## Notas Técnicas

- El widget usa `SingleChildScrollView` para permitir scroll en contenido largo
- Las fechas se extraen con detección automática de palabras clave
- Se cachea el estado del sheet mientras está abierto
- Los errores de extracción se muestran de forma amigable

## Futuras Mejoras

- Agregar más tipos de campos personalizados
- Integrar notificaciones para seguimiento de fechas
- Agregar historial de cambios del convenio
- Exportar datos a PDF
