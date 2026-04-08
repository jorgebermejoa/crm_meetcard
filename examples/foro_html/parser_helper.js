/**
 * Helper para cargar y parsear ejemplos de HTML del foro de licitación
 * Ubicación: examples/foro_html/
 * 
 * Uso:
 *   const foroHelper = require('../examples/foro_html/parser_helper.js');
 *   const html = foroHelper.cargarEjemploForo('licitacion_12345');
 */

const fs = require('fs');
const path = require('path');
const cheerio = require('cheerio');

/**
 * Carga un archivo HTML de ejemplo del foro
 * @param {string} nombreLicitacion - Nombre del archivo sin extensión (ej: 'licitacion_12345')
 * @returns {string|null} Contenido HTML o null si no existe
 */
function cargarEjemploForo(nombreLicitacion) {
  const filePath = path.join(__dirname, `${nombreLicitacion}.html`);
  try {
    if (!fs.existsSync(filePath)) {
      console.warn(`[ForoHelper] Archivo no encontrado: ${filePath}`);
      return null;
    }
    const html = fs.readFileSync(filePath, 'utf-8');
    console.log(`[ForoHelper] Cargado: ${nombreLicitacion}.html (${html.length} bytes)`);
    return html;
  } catch (err) {
    console.error(`[ForoHelper] Error al leer ${nombreLicitacion}.html:`, err.message);
    return null;
  }
}

/**
 * Extrae preguntas y respuestas del HTML usando cheerio
 * @param {string} html - HTML del foro
 * @returns {Array} Array de { pregunta, respuesta, fecha_pregunta, fecha_respuesta }
 */
function extraerForoHTML(html) {
  if (!html) return [];

  try {
    const $ = cheerio.load(html);
    const items = [];

    // Intenta común selector 1: div.question-item + div.answer-item
    const preguntas = $('.question-item');
    if (preguntas.length > 0) {
      console.log(`[ForoHelper] Encontradas ${preguntas.length} preguntas con selector .question-item`);

      preguntas.each((idx, el) => {
        const $q = $(el);
        const pregunta = $q.find('.question-content').text()?.trim() || '';
        const fechaPregunta = $q.find('.question-date').attr('data-date') || 
                            $q.find('.question-date').text()?.trim() || null;
        
        // Busca respuesta en el siguiente elemento (frecuentemente)
        const $respuesta = $q.next('.answer-item');
        const respuesta = $respuesta.length > 0 
          ? $respuesta.find('.answer-content').text()?.trim() || ''
          : '';
        const fechaRespuesta = $respuesta.length > 0
          ? $respuesta.find('.answer-date').attr('data-date') || 
            $respuesta.find('.answer-date').text()?.trim() || null
          : null;

        if (pregunta) {
          items.push({
            Pregunta: pregunta,
            Respuesta: respuesta,
            FechaPregunta: fechaPregunta,
            FechaRespuesta: fechaRespuesta,
            hasAnswer: !!respuesta,
          });
        }
      });

      return items;
    }

    // Intenta selector 2: Estructura de Mercado Público real
    const mpPreguntas = $('[data-qa="forum-question"]') || $('.mp-forum-item');
    if (mpPreguntas.length > 0) {
      console.log(`[ForoHelper] Encontradas ${mpPreguntas.length} preguntas con selector MP real`);

      mpPreguntas.each((idx, el) => {
        const $item = $(el);
        const pregunta = $item.find('[data-qa="question-text"]').text()?.trim() || '';
        const respuesta = $item.find('[data-qa="answer-text"]').text()?.trim() || '';
        const fechaPregunta = $item.find('[data-qa="question-date"]').text()?.trim() || null;
        const fechaRespuesta = $item.find('[data-qa="answer-date"]').text()?.trim() || null;

        if (pregunta) {
          items.push({
            Pregunta: pregunta,
            Respuesta: respuesta,
            FechaPregunta: fechaPregunta,
            FechaRespuesta: fechaRespuesta,
            hasAnswer: !!respuesta,
          });
        }
      });

      return items;
    }

    console.warn('[ForoHelper] No se encontraron preguntas con selectores conocidos');
    console.warn('[ForoHelper] Prueba con:', {
      '.question-item': $('.question-item').length,
      '[data-qa="forum-question"]': $('[data-qa="forum-question"]').length,
      '.mp-forum-item': $('.mp-forum-item').length,
    });

    return [];
  } catch (err) {
    console.error('[ForoHelper] Error al extraer foro:', err.message);
    return [];
  }
}

/**
 * Carga y parsea un archivo de ejemplo en una sola llamada
 * @param {string} nombreLicitacion - Nombre del archivo
 * @returns {Array} Array de preguntas/respuestas
 */
function cargarYParsearEjemplo(nombreLicitacion) {
  const html = cargarEjemploForo(nombreLicitacion);
  if (!html) {
    console.warn(`[ForoHelper] No se pudo cargar ejemplo: ${nombreLicitacion}`);
    return [];
  }
  const foro = extraerForoHTML(html);
  console.log(`[ForoHelper] Parseadas ${foro.length} preguntas de ${nombreLicitacion}`);
  return foro;
}

/**
 * Lista todos los ejemplos disponibles
 * @returns {Array} Array de nombres de archivos
 */
function listarEjemplos() {
  const dir = __dirname;
  try {
    const archivos = fs.readdirSync(dir, { withFileTypes: true })
      .filter(f => f.isFile() && f.name.endsWith('.html'))
      .map(f => f.name.replace('.html', ''));
    console.log(`[ForoHelper] Ejemplos disponibles: ${archivos.join(', ')}`);
    return archivos;
  } catch (err) {
    console.error('[ForoHelper] Error al listar ejemplos:', err.message);
    return [];
  }
}

module.exports = {
  cargarEjemploForo,
  extraerForoHTML,
  cargarYParsearEjemplo,
  listarEjemplos,
};

// ─── USO EN TESTING ───────────────────────────────────────────────────────────

// En un archivo de test o función de debugging:
//
// const foroHelper = require('../examples/foro_html/parser_helper.js');
//
// // Listar ejemplos
// console.log('Ejemplos disponibles:', foroHelper.listarEjemplos());
//
// // Cargar y parsear
// const foro = foroHelper.cargarYParsearEjemplo('licitacion_ejemplo');
// console.log('Foro parseado:', foro);
//
// // O manualmente
// const html = foroHelper.cargarEjemploForo('licitacion_12345');
// const items = foroHelper.extraerForoHTML(html);
// items.forEach(item => {
//   console.log(`Q: ${item.Pregunta}`);
//   console.log(`A: ${item.Respuesta}`);
// });
