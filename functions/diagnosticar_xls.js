#!/usr/bin/env node

/**
 * Diagnóstico - Analiza la estructura del archivo XLS descargado
 * 
 * Uso:
 *   node diagnosticar_xls.js <archivo.xls>
 */

const fs = require('fs');
const path = require('path');
const XLSX = require('xlsx');

const rutaXLS = process.argv[2];

if (!rutaXLS) {
  console.error('Uso: node diagnosticar_xls.js <archivo.xls>');
  process.exit(1);
}

const rutaCompleta = path.resolve(rutaXLS);
if (!fs.existsSync(rutaCompleta)) {
  console.error(`Archivo no encontrado: ${rutaCompleta}`);
  process.exit(1);
}

console.log('\n╔════════════════════════════════════════════════════════════╗');
console.log('║              DIAGNÓSTICO DE ARCHIVO XLS                  ║');
console.log('╚════════════════════════════════════════════════════════════╝\n');

console.log(`📂 Archivo: ${path.basename(rutaXLS)}`);
console.log(`📊 Ruta: ${rutaCompleta}\n`);

const workbook = XLSX.readFile(rutaCompleta);

console.log(`📑 Hojas (${workbook.SheetNames.length}):`);
workbook.SheetNames.forEach((nombre, idx) => {
  console.log(`   ${idx + 1}. "${nombre}"`);
});

console.log('\n─────────────────────────────────────────────────────────────');

workbook.SheetNames.forEach((nombreHoja, hIdx) => {
  console.log(`\n📋 HOJA: "${nombreHoja}"\n`);

  const worksheet = workbook.Sheets[nombreHoja];
  const datos = XLSX.utils.sheet_to_json(worksheet, { header: 1 }); // Header: 1 para obtener arrays
  
  console.log(`   Filas: ${datos.length}`);
  console.log(`   Columnas: ${datos[0]?.length || 0}`);
  console.log(`\n   Primeras 5 filas:`);

  datos.slice(0, 5).forEach((row, rowIdx) => {
    console.log(`\n   [Fila ${rowIdx}]`);
    row.forEach((celda, colIdx) => {
      if (celda) {
        const valor = (celda.toString()).substring(0, 80);
        console.log(`      Col${colIdx}: "${valor}${(celda.toString()).length > 80 ? '...' : ''}"`);
      }
    });
  });

  // Análisis de estructura
  console.log(`\n   📊 Resumen de datos:`);
  
  // Detectar si hay múltiples columnas con datos
  const colsConDatos = datos[0]?.map((_, colIdx) => {
    const hayDatos = datos.some((row, rowIdx) => rowIdx > 0 && row[colIdx]);
    return hayDatos;
  }) || [];

  console.log(`      Columnas con datos: ${colsConDatos.filter(Boolean).length}`);
  
  // Si solo hay una columna, intentar parsearla como texto delimitado
  if (colsConDatos.filter(Boolean).length === 1) {
    console.log(`      ⚠️  Estructura de texto único detectada`);
    const textoCompleto = datos.slice(1).map((row) => row[0]).filter(Boolean).join(' ');
    console.log(`      Total de caracteres: ${textoCompleto.length}`);
    
    // Buscar patrones
    const tienePreguntas = textoCompleto.match(/pregunta|question|¿/gi);
    const tieneRespuestas = textoCompleto.match(/respuesta|answer|:\s/gi);
    const tieneFechas = textoCompleto.match(/\d{2}[-/]\d{2}[-/]\d{4}|\d{4}[-/]\d{2}[-/]\d{2}/gi);
    
    console.log(`\n      Patrones detectados:`);
    console.log(`      • Palabras de pregunta: ${tienePreguntas ? tienePreguntas.length : 0}`);
    console.log(`      • Palabras de respuesta: ${tieneRespuestas ? tieneRespuestas.length : 0}`);
    console.log(`      • Fechas: ${tieneFechas ? tieneFechas.length : 0}`);
  }
});

console.log('\n└────────────────────────────────────────────────────────────\n');
