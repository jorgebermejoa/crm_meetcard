#!/usr/bin/env node

/**
 * Convertidor v3 - Manejo avanzado de estructuras XLSX complejas
 * Lee celdas individuales para mejor comprensión de la estructura
 */

const fs = require('fs');
const path = require('path');
const XLSX = require('xlsx');

function convertirXLSForoV3(rutaXLS) {
  console.log(`\n📂 Leyendo: ${path.basename(rutaXLS)}\n`);

  const workbook = XLSX.readFile(rutaXLS);
  const nombreHoja = workbook.SheetNames[0];
  const worksheet = workbook.Sheets[nombreHoja];
  
  console.log(`📊 Hoja: "${nombreHoja}"`);

  // Obtener rangos y celdas
  const range = XLSX.utils.decode_range(worksheet['!ref']);
  console.log(`📐 Rango: ${worksheet['!ref']}`);
  console.log(`   Filas: ${range.s.r} a ${range.e.r}`);
  console.log(`   Columnas: ${range.s.c} a ${range.e.c}\n`);

  // Analizar estructura celda por celda
  console.log('🔬 Análisis de estructura:\n');
  
  const filas = [];
  for (let r = range.s.r; r <= range.e.r; r++) {
    const fila = [];
    for (let c = range.s.c; c <= range.e.c; c++) {
      const celda_ref = XLSX.utils.encode_col(c) + XLSX.utils.encode_row(r);
      const celda = worksheet[celda_ref];
      fila.push(celda ? celda.v : '');
    }
    filas.push(fila);
    
    // Mostrar primeras filas para entender estructura
    if (r < 8) {
      console.log(`[Fila ${r}]: ${fila.join(' | ')}`);
    }
  }

  console.log();

  // Buscar estructura de datos (típicamente #, Fecha, Tipo, Preguntas, Respuestas)
  let filaEncabezado = -1;
  for (let i = 0; i < filas.length; i++) {
    const row = filas[i];
    // Buscar fila que contenga "Preguntas" Y "Respuestas" (patrón típico de encabezados)
    const hayPreguntas = row.some(cell => cell && cell.toString().toLowerCase().includes('pregunta'));
    const hayRespuestas = row.some(cell => cell && cell.toString().toLowerCase().includes('respuesta'));
    const hayHash = row.some(cell => cell && cell.toString().includes('#'));
    
    if (hayPreguntas && hayRespuestas && hayHash) {
      filaEncabezado = i;
      console.log(`✓ Encabezados encontrados en fila ${i} (Excel: fila ${i + 1})\n`);
      break;
    }
  }

  if (filaEncabezado === -1 || filaEncabezado >= filas.length - 1) {
    console.error('❌ No se encontró estructura de datos válida');
    return null;
  }

  // Extraer encabezados
  const encabezados = filas[filaEncabezado];
  console.log('📌 Mapeo de columnas:');
  encabezados.forEach((h, idx) => {
    if (h) console.log(`  Columna ${idx}: "${h}"`);
  });
  console.log();

  // Buscar índices
  const idxNum = encabezados.findIndex(h => h && (h.toString() === '#' || h.toString().toLowerCase().includes('#')));
  const idxFecha = encabezados.findIndex(h => h && h.toString().toLowerCase().includes('fecha'));
  const idxTipo = encabezados.findIndex(h => h && h.toString().toLowerCase().includes('tipo'));
  const idxPregunta = encabezados.findIndex(h => h && h.toString().toLowerCase().includes('pregunta'));
  const idxRespuesta = encabezados.findIndex(h => h && h.toString().toLowerCase().includes('respuesta'));

  console.log('🎯 Índices: # ' + idxNum, '| Fecha ' + idxFecha, '| Tipo ' + idxTipo, '| Pregunta ' + idxPregunta, '| Respuesta ' + idxRespuesta);
  console.log();

  // Procesar datos
  const foro = [];
  for (let i = filaEncabezado + 1; i < filas.length; i++) {
    const row = filas[i];
    if (!row || row.every(cell => !cell)) continue; // Saltar vacías

    const num = row[Math.max(idxNum, 0)];
    const pregunta = row[idxPregunta] || '';
    const respuesta = row[idxRespuesta] || '';
    const fecha = row[idxFecha] || null;
    const tipo = row[idxTipo] || null;

    if (pregunta.toString().trim()) {
      foro.push({
        numero: num,
        Pregunta: pregunta.toString().trim(),
        Respuesta: respuesta.toString().trim(),
        FechaPregunta: fecha ? fecha.toString().trim() : null,
        FechaRespuesta: null,
        Tipo: tipo ? tipo.toString().trim() : null,
        hasAnswer: (respuesta?.toString().trim() || '').length > 0,
      });
    }
  }

  return foro;
}

function guardarJSON(foro, rutaXLS, dirSalida) {
  const nombreBase = path.basename(rutaXLS, path.extname(rutaXLS));
  const rutaJSON = path.join(dirSalida, `${nombreBase}.json`);

  const datos = {
    fuente: 'Mercado Público - Descargado XLS',
    archivo: path.basename(rutaXLS),
    descargadoEn: new Date().toISOString(),
    total: foro.length,
    respondidas: foro.filter(f => f.hasAnswer).length,
    sinResponder: foro.filter(f => !f.hasAnswer).length,
    preguntas: foro,
  };

  fs.writeFileSync(rutaJSON, JSON.stringify(datos, null, 2), 'utf-8');
  console.log(`✅ JSON: ${path.basename(rutaJSON)}`);
  return rutaJSON;
}

function guardarHTML(foro, rutaXLS, dirSalida) {
  const nombreBase = path.basename(rutaXLS, path.extname(rutaXLS));
  const rutaHTML = path.join(dirSalida, `${nombreBase}.html`);

  let html = `<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Foro - Mercado Público</title>
  <style>
    * { box-sizing: border-box; }
    body { 
      font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
      margin: 0; padding: 20px;
      background: linear-gradient(135deg, #f5f7fa 0%, #c3cfe2 100%);
      min-height: 100vh;
    }
    .container { max-width: 1000px; margin: 0 auto; }
    header {
      background: white;
      padding: 30px;
      border-radius: 8px;
      box-shadow: 0 2px 8px rgba(0,0,0,0.1);
      margin-bottom: 20px;
    }
    header h1 { 
      margin: 0 0 10px 0; 
      color: #0066cc;
      font-size: 28px;
    }
    header p { 
      margin: 5px 0; 
      color: #666;
      font-size: 14px;
    }
    .stats { 
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
      gap: 15px;
      margin-top: 20px;
    }
    .stat {
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      color: white;
      padding: 15px;
      border-radius: 6px;
      text-align: center;
    }
    .stat strong { 
      display: block; 
      font-size: 28px; 
      margin-bottom: 5px;
    }
    .stat.respondidas { background: linear-gradient(135deg, #28a745 0%, #20c997 100%); }
    .stat.sin-responder { background: linear-gradient(135deg, #ffc107 0%, #fd7e14 100%); }
    .item {
      background: white;
      margin: 15px 0;
      border-radius: 8px;
      box-shadow: 0 2px 8px rgba(0,0,0,0.1);
      overflow: hidden;
      transition: transform 0.2s, box-shadow 0.2s;
    }
    .item:hover {
      transform: translateY(-2px);
      box-shadow: 0 4px 12px rgba(0,0,0,0.15);
    }
    .item-header {
      background: linear-gradient(135deg, #0066cc 0%, #0052a3 100%);
      color: white;
      padding: 12px 15px;
      font-weight: 600;
      display: flex;
      justify-content: space-between;
      align-items: center;
    }
    .item-num { 
      display: inline-block;
      background: rgba(255,255,255,0.2);
      padding: 2px 8px;
      border-radius: 20px;
      font-size: 12px;
    }
    .item-content { padding: 15px; }
    .field-label { 
      font-weight: 600;
      color: #0066cc;
      font-size: 12px;
      margin-top: 10px;
      margin-bottom: 5px;
    }
    .field-value {
      color: #333;
      line-height: 1.6;
      padding: 8px 0;
    }
    .pregunta { 
      border-left: 4px solid #0066cc;
      padding-left: 12px;
    }
    .respuesta {
      background: #f0f7ff;
      border-left: 4px solid #28a745;
      padding: 10px;
      padding-left: 12px;
      border-radius: 4px;
      margin-top: 10px;
    }
    .sin-respuesta {
      color: #999;
      font-style: italic;
    }
    .meta {
      font-size: 12px;
      color: #999;
      margin-top: 10px;
      display: flex;
      gap: 15px;
      flex-wrap: wrap;
    }
    .meta span { display: flex; align-items: center; gap: 5px; }
    footer {
      text-align: center;
      padding: 20px;
      color: #666;
      font-size: 12px;
    }
  </style>
</head>
<body>

<div class="container">
  <header>
    <h1>📋 Foro de Preguntas y Respuestas</h1>
    <p><strong>Fuente:</strong> Mercado Público</p>
    <p><strong>Descargado:</strong> ${new Date().toLocaleDateString('es-CL', { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric', hour: '2-digit', minute: '2-digit' })}</p>
    
    <div class="stats">
      <div class="stat">
        <strong>${foro.length}</strong>
        <span>Preguntas</span>
      </div>
      <div class="stat respondidas">
        <strong>${foro.filter(f => f.hasAnswer).length}</strong>
        <span>Respondidas</span>
      </div>
      <div class="stat sin-responder">
        <strong>${foro.filter(f => !f.hasAnswer).length}</strong>
        <span>Sin responder</span>
      </div>
    </div>
  </header>

  <main>
`;

  foro.forEach((item) => {
    html += `
    <div class="item">
      <div class="item-header">
        <span>Pregunta #${item.numero}</span>
        <span class="item-num">${item.hasAnswer ? '✓ Respondida' : 'Abierta'}</span>
      </div>
      <div class="item-content">
        <div class="field-label">❓ Pregunta:</div>
        <div class="field-value pregunta">${item.Pregunta}</div>
`;

    if (item.hasAnswer && item.Respuesta) {
      html += `
        <div class="field-label">✓ Respuesta:</div>
        <div class="field-value respuesta">${item.Respuesta}</div>
`;
    } else {
      html += `
        <div class="field-value sin-respuesta">(Sin respuesta)</div>
`;
    }

    if (item.FechaPregunta || item.Tipo) {
      html += `
        <div class="meta">
          ${item.FechaPregunta ? `<span>📅 ${item.FechaPregunta}</span>` : ''}
          ${item.Tipo ? `<span>🏷️ ${item.Tipo}</span>` : ''}
        </div>
`;
    }

    html += `
      </div>
    </div>
`;
  });

  html += `
  </main>

  <footer>
    <p>Generado automáticamente | Fuente: ${path.basename(rutaXLS)} | Encoding: UTF-8</p>
  </footer>
</div>

</body>
</html>`;

  fs.writeFileSync(rutaHTML, html, 'utf-8');
  console.log(`✅ HTML: ${path.basename(rutaHTML)}`);
}

// ─────────────────────────────────────────────────────────────────────────────

const rutaXLS = process.argv[2];

if (!rutaXLS) {
  console.error('\nUso: node convertir_xls_v3.js <archivo.xls>\n');
  process.exit(1);
}

const rutaCompleta = path.resolve(rutaXLS);
if (!fs.existsSync(rutaCompleta)) {
  console.error(`\nArchivo no encontrado: ${rutaCompleta}\n`);
  process.exit(1);
}

console.log('\n╔════════════════════════════════════════════════════════════╗');
console.log('║        CONVERTIDOR XLS v3 - Análisis Avanzado            ║');
console.log('╚════════════════════════════════════════════════════════════╝');

const foro = convertirXLSForoV3(rutaCompleta);

if (!foro) {
  process.exit(1);
}

const dirSalida = path.dirname(rutaCompleta);

console.log(`\n✅ Parseadas: ${foro.length} preguntas`);
console.log(`  ✓ Con respuesta: ${foro.filter(f => f.hasAnswer).length}`);
console.log(`  ○ Sin respuesta: ${foro.filter(f => !f.hasAnswer).length}\n`);

guardarJSON(foro, path.basename(rutaXLS), dirSalida);
guardarHTML(foro, path.basename(rutaXLS), dirSalida);

console.log('\n✨ Listo\n');
