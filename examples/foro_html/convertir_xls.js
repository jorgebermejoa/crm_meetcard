#!/usr/bin/env node

/**
 * Convierte archivo XLS del foro descargado desde Mercado Público
 * a JSON que puede ser parseado por parser_helper.js
 * 
 * Instalación:
 *   npm install xlsx
 * 
 * Uso:
 *   node convertir_xls.js "Foro_PreguntasRespuestas_06-04-2026_17-06.xls"
 *   node convertir_xls.js (detecta automáticamente)
 */

const fs = require('fs');
const path = require('path');

// Intenta cargar xlsx, si no está instalado, lo sugiere
let XLSX;
try {
  XLSX = require('xlsx');
} catch (err) {
  console.error('❌ Error: El módulo "xlsx" no está instalado');
  console.error('Instálalo con: npm install xlsx');
  console.error('O en la carpeta functions: npm install xlsx');
  process.exit(1);
}

// ─────────────────────────────────────────────────────────────────────────────

function encontrarArchivoXLS() {
  const archivos = fs.readdirSync(__dirname, { withFileTypes: true })
    .filter(f => f.isFile() && (f.name.endsWith('.xls') || f.name.endsWith('.xlsx')))
    .map(f => f.name);
  
  return archivos.length > 0 ? archivos[0] : null;
}

function convertirXLSaJSON(rutaXLS) {
  console.log(`\n📂 Leyendo archivo: ${path.basename(rutaXLS)}\n`);

  try {
    // Leer archivo Excel
    const workbook = XLSX.readFile(rutaXLS);
    console.log(`📊 Hojas disponibles: ${workbook.SheetNames.join(', ')}`);

    let datos = [];
    let hojaUsada = null;

    // Prueba diferentes nombres de hoja común
    const nombresHojasComunes = [
      'Foro', 'Forum', 'Preguntas', 'Questions',
      workbook.SheetNames[0], // Primera hoja
    ];

    for (const nombreHoja of nombresHojasComunes) {
      if (workbook.SheetNames.includes(nombreHoja)) {
        console.log(`\n✓ Usando hoja: "${nombreHoja}"`);
        const worksheet = workbook.Sheets[nombreHoja];
        datos = XLSX.utils.sheet_to_json(worksheet);
        hojaUsada = nombreHoja;
        break;
      }
    }

    if (datos.length === 0) {
      console.error('❌ No se encontraron datos en el archivo Excel');
      return null;
    }

    console.log(`📋 Total de filas: ${datos.length}\n`);

    // Mostrar estructura
    if (datos.length > 0) {
      console.log('🔍 Estructura de datos:');
      console.log('Columnas encontradas:', Object.keys(datos[0]));
      console.log('\nPrimer registro:');
      console.log(JSON.stringify(datos[0], null, 2));
    }

    return { datos, hojaUsada, archivo: rutaXLS };
  } catch (err) {
    console.error('❌ Error al leer Excel:', err.message);
    return null;
  }
}

function normalizarForoDeExcel(datos) {
  console.log('🔄 Normalizando datos del foro...\n');

  // Detectar columnas automáticamente
  const primerRow = datos[0];
  const colsPosibles = {
    pregunta: ['Pregunta', 'Question', 'P1: Pregunta', 'Título Pregunta'],
    respuesta: ['Respuesta', 'Answer', 'P1: Respuesta', 'Respuesta Oficial'],
    fechaPregunta: ['Fecha Pregunta', 'Question Date', 'Fecha'],
    fechaRespuesta: ['Fecha Respuesta', 'Answer Date', 'Fecha Respuesta'],
  };

  const colsEncontradas = {};
  for (const [clave, posibles] of Object.entries(colsPosibles)) {
    for (const posible of posibles) {
      if (Object.keys(primerRow).some(col => col.toLowerCase().includes(posible.toLowerCase()))) {
        colsEncontradas[clave] = Object.keys(primerRow).find(col => 
          col.toLowerCase().includes(posible.toLowerCase())
        );
        break;
      }
    }
  }

  console.log('📌 Columnas detectadas:');
  Object.entries(colsEncontradas).forEach(([clave, col]) => {
    console.log(`  • ${clave}: "${col}"`);
  });
  console.log();

  // Normalizar datos
  const foroNormalizado = datos.map((row, idx) => {
    const pregunta = (row[colsEncontradas.pregunta] || '').toString().trim();
    const respuesta = (row[colsEncontradas.respuesta] || '').toString().trim();
    const fechaPregunta = row[colsEncontradas.fechaPregunta] || null;
    const fechaRespuesta = row[colsEncontradas.fechaRespuesta] || null;

    if (!pregunta) return null; // Saltar filas vacías

    return {
      Pregunta: pregunta,
      Respuesta: respuesta,
      FechaPregunta: fechaPregunta ? fechaPregunta.toString() : null,
      FechaRespuesta: fechaRespuesta ? fechaRespuesta.toString() : null,
      hasAnswer: respuesta.length > 0,
    };
  }).filter(Boolean);

  return foroNormalizado;
}

function guardarJSON(foro, rutaXLS) {
  const nombreBase = path.basename(rutaXLS, path.extname(rutaXLS));
  const rutaJSON = path.join(__dirname, `${nombreBase}.json`);

  const datos = {
    fuente: 'Mercado Público - Descargado',
    archivo: path.basename(rutaXLS),
    fecha: new Date().toISOString(),
    total: foro.length,
    respondidas: foro.filter(f => f.hasAnswer).length,
    sinResponder: foro.filter(f => !f.hasAnswer).length,
    preguntas: foro,
  };

  fs.writeFileSync(rutaJSON, JSON.stringify(datos, null, 2), 'utf-8');
  console.log(`✅ Archivo guardado: ${rutaJSON}`);
  return rutaJSON;
}

function guardarHTML(foro, rutaXLS) {
  const nombreBase = path.basename(rutaXLS, path.extname(rutaXLS));
  const rutaHTML = path.join(__dirname, `${nombreBase}.html`);

  let html = `<!-- Generado automáticamente desde: ${path.basename(rutaXLS)} -->
<html>
<head>
  <meta charset="UTF-8">
  <title>Foro - Mercado Público</title>
  <style>
    body { font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }
    .forum-section { max-width: 900px; }
    .question-item { 
      background: white; 
      padding: 15px; 
      margin: 10px 0; 
      border-left: 4px solid #0066cc;
      border-radius: 4px;
    }
    .answer-item {
      background: #f9f9f9;
      padding: 15px;
      margin: 5px 0 15px 20px;
      border-left: 4px solid #28a745;
      border-radius: 4px;
    }
    .question-date, .answer-date {
      font-size: 0.85em;
      color: #666;
      margin-top: 8px;
    }
  </style>
</head>
<body>

<div class="forum-section">
  <h1>Foro de Preguntas y Respuestas</h1>
  <p><strong>Total de preguntas:</strong> ${foro.length}</p>
  <p><strong>Respondidas:</strong> ${foro.filter(f => f.hasAnswer).length}</p>
  <p><strong>Sin responder:</strong> ${foro.filter(f => !f.hasAnswer).length}</p>
  <hr>

`;

  foro.forEach((item, idx) => {
    html += `
  <!-- Pregunta ${idx + 1} -->
  <div class="question-item">
    <strong>Pregunta ${idx + 1}:</strong>
    <p>${item.Pregunta}</p>
    <div class="question-date">
      ${item.FechaPregunta ? `📅 ${item.FechaPregunta}` : '(sin fecha)'}
    </div>
  </div>

`;

    if (item.Respuesta) {
      html += `
  <div class="answer-item">
    <strong>Respuesta:</strong>
    <p>${item.Respuesta}</p>
    <div class="answer-date">
      ${item.FechaRespuesta ? `📅 ${item.FechaRespuesta}` : '(sin fecha)'}
    </div>
  </div>

`;
    }
  });

  html += `
</div>

</body>
</html>`;

  fs.writeFileSync(rutaHTML, html, 'utf-8');
  console.log(`✅ Archivo HTML guardado: ${rutaHTML}`);
  return rutaHTML;
}

// ─────────────────────────────────────────────────────────────────────────────

// MAIN
const args = process.argv.slice(2);
const rutaXLS = args[0] || encontrarArchivoXLS();

if (!rutaXLS) {
  console.error('❌ No se encontró archivo XLS/XLSX');
  console.error('Uso: node convertir_xls.js [ruta_archivo.xls]');
  process.exit(1);
}

const rutaCompleta = path.join(__dirname, rutaXLS);
if (!fs.existsSync(rutaCompleta)) {
  console.error(`❌ Archivo no encontrado: ${rutaCompleta}`);
  process.exit(1);
}

console.log('\n╔════════════════════════════════════════════════════════════╗');
console.log('║  CONVERTIDOR DE FORO XLS → JSON/HTML - Mercado Público   ║');
console.log('╚════════════════════════════════════════════════════════════╝');

// Procesar
const resultado = convertirXLSaJSON(rutaCompleta);
if (!resultado) process.exit(1);

const foroNormalizado = normalizarForoDeExcel(resultado.datos);

console.log(`✅ Total de preguntas parseadas: ${foroNormalizado.length}\n`);

// Guardar formatos
guardarJSON(foroNormalizado, rutaXLS);
guardarHTML(foroNormalizado, rutaXLS);

console.log('\n📚 Próximos pasos:');
console.log('  1. node test_parsing.js ' + path.basename(rutaXLS, path.extname(rutaXLS)));
console.log('  2. Revisa el JSON/HTML generado');
console.log('  3. Integra en functions/index.js para parsing real\n');
