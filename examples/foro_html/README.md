# Ejemplos de HTML del Foro de Licitación

Esta carpeta contiene ejemplos de HTML del foro de licitación de Mercado Público para testing y depuración del parsing.

## Estructura

```
examples/foro_html/
├── README.md (este archivo)
├── licitacion_XXXXX.html    # Respectivos HTML del foro para cada licitación
├── licitacion_YYYYY.html
└── foro_api_response.json   # Respuesta JSON de la API de foro (opcional)
```

## Cómo usar

### 1. Guardar HTML del foro

Navega a una licitación en Mercado Público (ej: https://www.mercadopublico.cl/Licitacion/Detalle) y:
- Click derecho → **Inspeccionar** (o F12)
- Busca el elemento que contiene el foro
- Copia el HTML completo
- Guarda el archivo aquí con nombre descriptivo: `licitacion_XXXXX.html`

### 2. Guardar respuesta JSON de la API

Si tienes la URL del API del foro (usualmente `https://api.mercadopublico.cl/servicios/v1/publico/licitaciones/foro.json?codigo=XXXXX`):
- Abre en navegador o Postman
- Copia la respuesta JSON
- Guarda como `licitacion_XXXXX_api.json`

### 3. Usar en el código

Para leer estos archivos desde Cloud Functions o scripts:

```javascript
const fs = require('fs');
const path = require('path');

// Leer archivo HTML
function cargarEjemploForo(nombreLicitacion) {
  const filePath = path.join(__dirname, `../examples/foro_html/${nombreLicitacion}.html`);
  try {
    return fs.readFileSync(filePath, 'utf-8');
  } catch (err) {
    console.error(`No se pudo leer ${filePath}:`, err.message);
    return null;
  }
}

// Usar en parsing
const html = cargarEjemploForo('licitacion_12345');
if (html) {
  const $ = cheerio.load(html);
  // Tu lógica de parsing aquí
  console.log('Parseando:', $.('selector').text());
}
```

### 4. Depuración en Cloud Functions

En `functions/index.js`, puedes agregar lógica para cargar ejemplos:

```javascript
// En desarrollo/testing
if (process.env.NODE_ENV === 'development' || !id) {
  const exampleHtml = cargarEjemploForo('licitacion_ejemplo');
  if (exampleHtml) {
    // Procesar HTML de ejemplo
    const $ = cheerio.load(exampleHtml);
    // ... resto del parsing
  }
}
```

## Archivos de Ejemplo

| Archivo | Descripción | Licitación | Estado |
|---------|------------|-----------|--------|
| `licitacion_ejemplo.html` | Ejemplo básico de foro | - | - |
| `licitacion_12345.html` | Foro con preguntas y respuestas | - | - |
| `licitacion_error.html` | Ejemplo que genera error de parsing | - | - |

## Notas Importantes

- No incluyas datos sensibles (números de teléfono, emails personales)
- Sanitiza los nombres de licitaciones si es necesario
- Estos archivos se usa **solo en desarrollo/testing**
- El `.gitignore` puede excluir esta carpeta en algunos repos — asegúrate de agregar si es necesario

## Referencia: Parsing Actual

La función `fetchForoLicitacion` en `functions/index.js` hace:

```
1. Realiza GET a API de MP: /foro.json?codigo={id}
2. Extrae campos: Pregunta, Respuesta, FechaPregunta, FechaRespuesta
3. Mapea a estructura standar: { description, answer, date, dateAnswered }
4. Guarda en Firestore: proyectos/{id}/foro/{licitacionId}
```

Si el parsing no funciona correctamente:
1. Guarda el HTML recibido aquí
2. Identifica dónde falla el parsing con cheerio
3. Prueba selectores CSS/XPath con `console.log($('selector').html())`
4. Actualiza la lógica en `functions/index.js`
