#!/usr/bin/env node

/**
 * Convierte archivo XLS del foro descargado desde Mercado Público
 * a JSON que puede ser parseado
 * 
 * Uso:
 *   node convertir_xls.js <archivo.xls>
 */

const fs = require('fs');
const path = require('path');
const XLSX = require('xlsx');

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
      console.log('\n📌 Primer registro:');
      const firstRow = datos[0];
      Object.entries(firstRow).forEach(([col, valor]) => {
        console.log(`   ${col}: ${valor}`);
      });
    }

    return { datos, hojaUsada, archivo: rutaXLS };
  } catch (err) {
    console.error('❌ Error al leer Excel:', err.message);
    return null;
  }
}

function normalizarForoDeExcel(datos) {
  console.log('\n🔄 Normalizando datos del foro...\n');

  // Detectar columnas automáticamente
  const primerRow = datos[0];
  const colsPosibles = {
    pregunta: ['Pregunta', 'Question', 'P1: Pregunta', 'Título Pregunta', 'pregunta'],
    respuesta: ['Respuesta', 'Answer', 'P1: Respuesta', 'Respuesta Oficial', 'respuesta'],
    fechaPregunta: ['Fecha Pregunta', 'Question Date', 'Fecha'],
    fechaRespuesta: ['Fecha Respuesta', 'Answer Date'],
  };

  const colsEncontradas = {};
  for (const [clave, posibles] of Object.entries(colsPosibles)) {
    for (const posible of posibles) {
      const colEncontrada = Object.keys(primerRow).find(col => 
        col.toLowerCase().includes(posible.toLowerCase())
      );
      if (colEncontrada) {
        colsEncontradas[clave] = colEncontrada;
        break;
      }
    }
  }

  console.log('📌 Columnas mapeadas:');
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

function guardarJSON(foro, rutaXLS, dirSalida) {
  const nombreBase = path.basename(rutaXLS, path.extname(rutaXLS));
  const rutaJSON = path.join(dirSalida, `${nombreBase}.json`);

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
  console.log(`✅ JSON guardado:  ${rutaJSON}`);
  return rutaJSON;
}

function guardarHTML(foro, rutaXLS, dirSalida) {
  const nombreBase = path.basename(rutaXLS, path.extname(rutaXLS));
  const rutaHTML = path.join(dirSalida, `${nombreBase}.html`);

  let html = `<!-- Generado automáticamente desde: ${path.basename(rutaXLS)} -->
<html>
<head>
  <meta charset="UTF-8">
  <title>Foro - Mercado Público</title>
  <style>
    body { font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }
    .forum-section { max-width: 900px; }
    h1 { color: #0066cc; }
    .stats { 
      background: white; 
      padding: 10px 15px; 
      border-radius: 4px; 
      margin-bottom: 20px;
    }
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
    .question-content { margin: 10px 0; }
    .question-date, .answer-date {
      font-size: 0.85em;
      color: #666;
      margin-top: 8px;
    }
    .no-answer { color: #999; font-style: italic; }
  </style>
</head>
<body>

<div class="forum-section">
  <h1>Foro de Preguntas y Respuestas</h1>
  <div class="stats">
    <p><strong>Total de preguntas:</strong> ${foro.length}</p>
    <p><strong>Respondidas:</strong> ${foro.filter(f => f.hasAnswer).length}</p>
    <p><strong>Sin responder:</strong> ${foro.filter(f => !f.hasAnswer).length}</p>
  </div>
  <hr>

`;

  foro.forEach((item, idx) => {
    html += `
  <!-- Pregunta ${idx + 1} -->
  <div class="question-item">
    <strong>Pregunta ${idx + 1}:</strong>
    <div class="question-content">${item.Pregunta}</div>
    <div class="question-date" data-date="${item.FechaPregunta || ''}">
      ${item.FechaPregunta ? `📅 ${item.FechaPregunta}` : '(sin fecha)'}
    </div>
  </div>

`;

    if (item.Respuesta && item.Respuesta.trim()) {
      html += `
  <div class="answer-item">
    <strong>Respuesta:</strong>
    <div class="question-content">${item.Respuesta}</div>
    <div class="answer-date" data-date="${item.FechaRespuesta || ''}">
      ${item.FechaRespuesta ? `📅 ${item.FechaRespuesta}` : '(sin fecha)'}
    </div>
  </div>

`;
    } else {
      html += `
  <div class="answer-item no-answer">
    <em>(Sin respuesta)</em>
  </div>

`;
    }
  });

  html += `
</div>

</body>
</html>`;

  fs.writeFileSync(rutaHTML, html, 'utf-8');
  console.log(`✅ HTML guardado: ${rutaHTML}`);
  return rutaHTML;
}

// ─────────────────────────────────────────────────────────────────────────────

// MAIN
const args = process.argv.slice(2);
const rutaXLS = args[0];

if (!rutaXLS) {
  console.error('\n❌ Error: Especifica la ruta del archivo XLS');
  console.error('\nUso: node convertir_xls.js <ruta/archivo.xls>');
  console.error('Ejemplo: node convertir_xls.js ../examples/foro_html/Foro_*.xls\n');
  process.exit(1);
}

const rutaCompleta = path.resolve(rutaXLS);
if (!fs.existsSync(rutaCompleta)) {
  console.error(`\n❌ Archivo no encontrado: ${rutaCompleta}\n`);
  process.exit(1);
}

console.log('\n╔════════════════════════════════════════════════════════════╗');
console.log('║  CONVERTIDOR: XLS → JSON/HTML (Mercado Público Foro)    ║');
console.log('╚════════════════════════════════════════════════════════════╝');

// Procesar
const resultado = convertirXLSaJSON(rutaCompleta);
if (!resultado) process.exit(1);

const foroNormalizado = normalizarForoDeExcel(resultado.datos);
const dirSalida = path.dirname(rutaCompleta);

console.log(`\n✅ Total de preguntas parseadas: ${foroNormalizado.length}\n`);

// Guardar formatos
const nombreBase = path.basename(rutaXLS, path.extname(rutaXLS));
guardarJSON(foroNormalizado, path.basename(rutaXLS), dirSalida);
guardarHTML(foroNormalizado, path.basename(rutaXLS), dirSalida);

console.log('\n📊 RESUMEN:');
console.log(`  • Preguntascon respuesta: ${foroNormalizado.filter(f => f.hasAnswer).length}`);
console.log(`  • Preguntas sin respuesta: ${foroNormalizado.filter(f => !f.hasAnswer).length}`);

console.log('\n📚 Próximos pasos:');
console.log(`  1. Verifica los archivos generados en: ${dirSalida}`);
console.log(`  2. Ejecuta: node examples/foro_html/test_parsing.js ${nombreBase}`);
console.log('  3. Integra en functions/index.js para parsing en production\n');
