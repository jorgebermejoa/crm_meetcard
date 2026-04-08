/**
 * GUÍA DE INTEGRACIÓN: Usar ejemplos de foro en functions/index.js
 * 
 * Este archivo muestra cómo integrar el helper de ejemplos
 * directamente en tu función fetchForoLicitacion para debugging.
 */

// ─── OPCIÓN 1: Manual en development ───────────────────────────────────────

// En functions/index.js, en la función fetchForoLicitacion:

/*
exports.fetchForoLicitacion = onRequest(
  { cors: true, memory: '256MiB', timeoutSeconds: 30 },
  async (req, res) => {
    try {
      const { id, ticket, debug } = req.query;

      // DEBUG: Si se pasa ?debug=nombre_licitacion, carga ejemplo
      if (debug && process.env.NODE_ENV !== 'production') {
        console.log('[DEBUG] Usando ejemplo de foro:', debug);
        const foroHelper = require('../examples/foro_html/parser_helper.js');
        const html = foroHelper.cargarEjemploForo(debug);
        
        if (!html) {
          return res.status(400).json({
            error: `Ejemplo "${debug}" no encontrado`,
            disponibles: foroHelper.listarEjemplos(),
          });
        }

        // Parsea el HTML de ejemplo
        const $ = cheerio.load(html);
        const enquiries = foroHelper.extraerForoHTML(html);

        console.log(`[DEBUG] Parseadas ${enquiries.length} preguntas de ejemplo`);
        return res.json({
          ok: true,
          count: enquiries.length,
          enquiries,
          source: 'example',
          debug_file: `${debug}.html`,
        });
      }

      // Código normal de fetchForoLicitacion
      // ... resto de la función
    } catch (e) {
      logger.error('fetchForoLicitacion error:', e.message);
      res.status(500).json({ error: e.message });
    }
  }
);
*/

// Uso: 
//   GET /fetchForoLicitacion?debug=licitacion_ejemplo
//   Responde con el foro parseado del archivo de ejemplo

// ─── OPCIÓN 2: Testing automático ─────────────────────────────────────────

// En un archivo test.js:

/*
const foroHelper = require('./examples/foro_html/parser_helper.js');
const cheerio = require('cheerio');

async function testForoParsingEjemplos() {
  const ejemplos = foroHelper.listarEjemplos();
  console.log(`\n📋 Testing ${ejemplos.length} ejemplos de foro...\n`);

  for (const nombre of ejemplos) {
    try {
      console.log(`Testing: ${nombre}.html`);
      const foro = foroHelper.cargarYParsearEjemplo(nombre);
      
      if (foro.length === 0) {
        console.warn(`  ⚠️  No se encontraron preguntas`);
      } else {
        console.log(`  ✓ ${foro.length} preguntas parseadas`);
        foro.forEach((item, idx) => {
          console.log(`    ${idx + 1}. P: ${item.Pregunta.substring(0, 50)}...`);
          if (item.Respuesta) {
            console.log(`       R: ${item.Respuesta.substring(0, 50)}...`);
          } else {
            console.log(`       R: (sin respuesta)`);
          }
        });
      }
    } catch (err) {
      console.error(`  ❌ Error: ${err.message}`);
    }
  }
}

// Ejecutar: node test.js
// Output: Muestra qué se parsea correctamente y dónde falla
*/

// ─── OPCIÓN 3: Debugging Interactivo ──────────────────────────────────────

// Usa HTTP Client (REST Client extension en VS Code):

/*
### Listar ejemplos disponibles
GET http://localhost:5001/licitaciones-prod/us-central1/fetchForoLicitacion?debug=

### Parsear un ejemplo específico
GET http://localhost:5001/licitaciones-prod/us-central1/fetchForoLicitacion?debug=licitacion_ejemplo

### Comparar con API real (si tienes ticket)
GET http://localhost:5001/licitaciones-prod/us-central1/fetchForoLicitacion?id=ABC123&ticket=xyz

### Request curl
curl "http://localhost:5001/licitaciones-prod/us-central1/fetchForoLicitacion?debug=licitacion_ejemplo"
*/

// ─── ESTRUCTURA ESPERADA DEL FORO ──────────────────────────────────────────

const FORO_ESTRUCTURA_ESPERADA = {
  Pregunta: "Texto de la pregunta",
  Respuesta: "Texto de la respuesta (puede estar vacío)",
  FechaPregunta: "Fecha en formato string (ej: '2026-03-15' o 'Mar 15, 2026')",
  FechaRespuesta: "Fecha de respuesta (null si no hay respuesta)",
  hasAnswer: true, // boolean indicando si fue respondida
};

// ─── SELECTORES CSS COMUNES EN MP ──────────────────────────────────────────

const SELECTORES_MERCADOPUBLICO = {
  // Estructura típica 1: DataAttributes
  preguntas: '[data-qa="forum-question"]',
  respuesta: '[data-qa="answer-box"]',
  texto_pregunta: '[data-qa="question-text"]',
  texto_respuesta: '[data-qa="answer-text"]',
  fecha_pregunta: '[data-qa="question-date"]',
  fecha_respuesta: '[data-qa="answer-date"]',

  // Estructura típica 2: Classes
  preguntas_alt: '.forum-item, .question-block',
  texto_alt: '.forum-question-text, .question-content',
  respuesta_alt: '.forum-answer-text, .answer-content',

  // Estructura típica 3: IDs específicos
  foro_contenedor: '#forumContainer, #forum-section, .forum-container',
};

// ─── TROUBLESHOOTING ──────────────────────────────────────────────────────

const TROUBLESHOOTING = {
  problema: "No se encuentran preguntas",
  debugging: [
    "1. Verifica que el HTML de ejemplo esté guardado en examples/foro_html/",
    "2. Carga el HTML en cheerio: const $ = cheerio.load(html)",
    "3. Imprime los selectores disponibles: console.log($.('*').attr('class'))",
    "4. Prueba selectores comunes: $('[data-qa]'), $('.question'), etc.",
    "5. Si Mercado Público cambió estructura, extrae el HTML real del navegador",
  ],

  mejor_practica: [
    "Guarda HTML del foro con nombre descriptivo (ej: licitacion_ABC123.html)",
    "Incluye la fecha de extracción en un comentario HTML al inicio",
    "Para cada HTML problemático, documenta qué no funciona",
    "Prueba con parser_helper.js antes de cambiar functions/index.js",
  ],

  herramientas: [
    "VS Code + REST Client: debugging HTTP requests",
    "Firefox DevTools: inspecciona estructura HTML real",
    "cheerio REPL: prueba selectores en tiempo real",
    "firebase emulator: testing local sin desplegar",
  ],
};

console.log("📚 Para integración, consulta este archivo de documentación");
console.log("📁 Ubicación: examples/foro_html/INTEGRACION.js");
