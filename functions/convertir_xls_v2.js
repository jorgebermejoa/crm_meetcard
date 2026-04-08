#!/usr/bin/env node

/**
 * Convertidor avanzado para XLS de foro de Mercado Público
 * Maneja la estructura con encabezados en diferentes filas
 */

const fs = require('fs');
const path = require('path');
const XLSX = require('xlsx');

function convertirXLSForo(rutaXLS) {
  console.log(`\n📂 Leyendo: ${path.basename(rutaXLS)}\n`);

  const workbook = XLSX.readFile(rutaXLS);
  const nombreHoja = workbook.SheetNames[0];
  const worksheet = workbook.Sheets[nombreHoja];
  
  // Obtener todas las filas como arrays (sin procesar JSON)
  const datosRaw = XLSX.utils.sheet_to_json(worksheet, { header: 1 });
  
  console.log(`📊 Hoja: "${nombreHoja}"`);
  console.log(`📋 Total de filas: ${datosRaw.length}\n`);

  // Buscar la fila de encabezados (típicamente contiene #, Fecha, Tipo, Preguntas, Respuestas)
  let filaEncabezado = -1;
  for (let i = 0; i < datosRaw.length; i++) {
    const row = datosRaw[i];
    if (row.some(cell => cell && cell.toString().toLowerCase().includes('pregunta'))) {
      filaEncabezado = i;
      console.log(`✓ Encabezados encontrados en fila ${i}`);
      console.log(`  Columnas: ${row.join(' | ')}\n`);
      break;
    }
  }

  if (filaEncabezado === -1) {
    console.error('❌ No se encontraron encabezados (esperaba fila con "Pregunta")');
    return null;
  }

  // Extraer nombres de columnas
  const encabezados = datosRaw[filaEncabezado];
  const idxFecha = encabezados.findIndex(h => h && h.toString().toLowerCase().includes('fecha'));
  const idxTipo = encabezados.findIndex(h => h && h.toString().toLowerCase().includes('tipo'));
  const idxPregunta = encabezados.findIndex(h => h && h.toString().toLowerCase().includes('pregunta'));
  const idxRespuesta = encabezados.findIndex(h => h && h.toString().toLowerCase().includes('respuesta'));

  console.log('🔍 Índices de columnas mapeados:');
  console.log(`  • Fecha: ${idxFecha}`);
  console.log(`  • Tipo: ${idxTipo}`);
  console.log(`  • Pregunta: ${idxPregunta}`);
  console.log(`  • Respuesta: ${idxRespuesta}\n`);

  // Procesar datos (filas después del encabezado)
  const foro = [];
  for (let i = filaEncabezado + 1; i < datosRaw.length; i++) {
    const row = datosRaw[i];
    if (row.length === 0 || !row.some(cell => cell)) continue; // Saltar filas vacías

    const pregunta = row[idxPregunta]?.toString().trim() || '';
    const respuesta = row[idxRespuesta]?.toString().trim() || '';
    const fecha = row[idxFecha]?.toString().trim() || null;
    const tipo = row[idxTipo]?.toString().trim() || null;

    if (pregunta) {
      foro.push({
        Pregunta: pregunta,
        Respuesta: respuesta,
        FechaPregunta: fecha,
        FechaRespuesta: null, // MP no separa en estructura de descarga
        Tipo: tipo, // P = Pregunta, R = Respuesta
        hasAnswer: respuesta.length > 0,
      });
    }
  }

  return foro;
}

function guardarJSON(foro, rutaXLS, dirSalida) {
  const nombreBase = path.basename(rutaXLS, path.extname(rutaXLS));
  const rutaJSON = path.join(dirSalida, `${nombreBase}.json`);

  const datos = {
    fuente: 'Mercado Público - XLS Descargado',
    archivo: path.basename(rutaXLS),
    fecha: new Date().toISOString(),
    total: foro.length,
    respondidas: foro.filter(f => f.hasAnswer).length,
    sinResponder: foro.filter(f => !f.hasAnswer).length,
    preguntas: foro,
  };

  fs.writeFileSync(rutaJSON, JSON.stringify(datos, null, 2), 'utf-8');
  console.log(`✅ JSON: ${rutaJSON}`);
  return rutaJSON;
}

function guardarHTML(foro, rutaXLS, dirSalida) {
  const nombreBase = path.basename(rutaXLS, path.extname(rutaXLS));
  const rutaHTML = path.join(dirSalida, `${nombreBase}.html`);

  let html = `<!-- Foro de Mercado Público - Descargado desde: ${path.basename(rutaXLS)} -->
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>Foro - Mercado Público</title>
  <style>
    * { box-sizing: border-box; }
    body { 
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      margin: 0;
      padding: 20px;
      background: #f5f5f5;
    }
    .container { max-width: 1000px; margin: 0 auto; }
    h1 { 
      color: #0066cc; 
      border-bottom: 3px solid #0066cc;
      padding-bottom: 10px;
    }
    .stats { 
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
      gap: 15px;
      margin: 20px 0;
    }
    .stat-card {
      background: white;
      padding: 15px;
      border-radius: 6px;
      box-shadow: 0 2px 4px rgba(0,0,0,0.1);
    }
    .stat-card strong { display: block; color: #0066cc; font-size:24px; }
    .stat-card small { color: #666; }
    .question-block { 
      background: white;
      margin: 15px 0;
      border-radius: 6px;
      box-shadow: 0 2px 4px rgba(0,0,0,0.1);
      overflow: hidden;
    }
    .question-header {
      background: linear-gradient(135deg, #0066cc 0%, #0052a3 100%);
      color: white;
      padding: 12px 15px;
      font-weight: 600;
    }
    .question-content { padding: 15px; }
    .question-text { 
      font-size: 15px;
      line-height: 1.6;
      color: #333;
      margin: 10px 0;
    }
    .question-meta {
      font-size: 12px;
      color: #999;
      margin-top: 10px;
      display: flex;
      gap: 20px;
    }
    .answer-block {
      background: #f9fafb;
      border-top: 1px solid #e5e5e5;
      padding: 15px;
      margin-top: 10px;
    }
    .answer-block strong { 
      display: block;
      color: #28a745;
      margin-bottom: 8px;
    }
    .answer-text {
      font-size: 14px;
      line-height: 1.6;
      color: #444;
    }
    .no-answer {
      color: #999;
      font-style: italic;
    }
  </style>
</head>
<body>

<div class="container">
  <h1>📋 Foro de Preguntas y Respuestas</h1>
  <p>Descargado desde Mercado Público el <strong>${new Date().toLocaleDateString('es-CL')}</strong></p>

  <div class="stats">
    <div class="stat-card">
      <strong>${foro.length}</strong>
      <small>Total de preguntas</small>
    </div>
    <div class="stat-card">
      <strong>${foro.filter(f => f.hasAnswer).length}</strong>
      <small>Respondidas</small>
    </div>
    <div class="stat-card">
      <strong>${foro.filter(f => !f.hasAnswer).length}</strong>
      <small>Sin responder</small>
    </div>
  </div>

  <hr style="border: none; border-top: 2px solid #e5e5e5; margin: 30px 0;">

`;

  foro.forEach((item, idx) => {
    html += `
  <div class="question-block">
    <div class="question-header">
      Pregunta #${idx + 1}
    </div>
    <div class="question-content">
      <div class="question-text">${item.Pregunta}</div>
      <div class="question-meta">
        ${item.FechaPregunta ? `<span>📅 ${item.FechaPregunta}</span>` : ''}
        ${item.Tipo ? `<span>🏷️ Tipo: ${item.Tipo}</span>` : ''}
      </div>

`;

    if (item.Respuesta && item.Respuesta.trim()) {
      html += `
      <div class="answer-block">
        <strong>✓ Respuesta:</strong>
        <div class="answer-text">${item.Respuesta}</div>
      </div>
`;
    } else {
      html += `
      <div class="answer-block">
        <div class="no-answer">Sin respuesta aún</div>
      </div>
`;
    }

    html += `
    </div>
  </div>

`;
  });

  html += `
</div>

</body>
</html>`;

  fs.writeFileSync(rutaHTML, html, 'utf-8');
  console.log(`✅ HTML: ${rutaHTML}`);
  return rutaHTML;
}

// ─────────────────────────────────────────────────────────────────────────────

const rutaXLS = process.argv[2];

if (!rutaXLS) {
  console.error('\n❌ Especifica la ruta del archivo XLS');
  console.error('Uso: node convertir_xls_v2.js <ruta/archivo.xls>\n');
  process.exit(1);
}

const rutaCompleta = path.resolve(rutaXLS);
if (!fs.existsSync(rutaCompleta)) {
  console.error(`\n❌ Archivo no encontrado: ${rutaCompleta}\n`);
  process.exit(1);
}

console.log('\n╔════════════════════════════════════════════════════════════╗');
console.log('║    CONVERTIDOR XLS → JSON/HTML v2 (Mercado Público)     ║');
console.log('╚════════════════════════════════════════════════════════════╝');

const foro = convertirXLSForo(rutaCompleta);

if (!foro) {
  console.error('\n❌ Error al procesar el archivo');
  process.exit(1);
}

const dirSalida = path.dirname(rutaCompleta);
console.log(`\n✅ Preguntas parseadas: ${foro.length}`);
console.log(`  • Con respuesta: ${foro.filter(f => f.hasAnswer).length}`);
console.log(`  • Sin respuesta: ${foro.filter(f => !f.hasAnswer).length}\n`);

guardarJSON(foro, path.basename(rutaXLS), dirSalida);
guardarHTML(foro, path.basename(rutaXLS), dirSalida);

console.log('\n✨ Conversión completada exitosamente\n');
