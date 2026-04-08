#!/usr/bin/env node

/**
 * Script de test para debugging de parsing del foro
 * 
 * Uso:
 *   node examples/foro_html/test_parsing.js
 *   node examples/foro_html/test_parsing.js licitacion_ejemplo
 * 
 * Muestra qué se parsea correctamente y dónde falla
 */

const foroHelper = require('./parser_helper.js');
const path = require('path');

console.log('\n╔════════════════════════════════════════════════════════════╗');
console.log('║     TEST DE PARSING - EJEMPLOS DE FORO LICITACIÓN         ║');
console.log('╚════════════════════════════════════════════════════════════╝\n');

// Obtener argumento: node test_parsing.js [nombre_licitacion]
const args = process.argv.slice(2);
const targetExample = args[0];

// Listar ejemplos disponibles
const ejemplos = foroHelper.listarEjemplos();

if (ejemplos.length === 0) {
  console.error('❌ No hay ejemplos disponibles en examples/foro_html/');
  console.error('\n📝 Pasos para agregar ejemplos:');
  console.error('   1. Navega a https://www.mercadopublico.cl/Licitacion/Detalle');
  console.error('   2. Inspecciona el HTML del foro (F12 → Right click → Inspect)');
  console.error('   3. Guarda el HTML como: licitacion_XXXXX.html');
  console.error('   4. Coloca el archivo en: examples/foro_html/');
  console.error('\n   O copia el contenido de template_estructura.html como referencia\n');
  process.exit(1);
}

console.log(`📋 Ejemplos disponibles (${ejemplos.length}):\n`);
ejemplos.forEach((nombre, idx) => {
  console.log(`   ${idx + 1}. ${nombre}`);
});
console.log();

if (targetExample && !ejemplos.includes(targetExample)) {
  console.error(`❌ Ejemplo no encontrado: ${targetExample}`);
  process.exit(1);
}

const nodesToTest = targetExample ? [targetExample] : ejemplos;

// ─────────────────────────────────────────────────────────────────────────────

console.log('\n🔍 INICIANDO TESTS...\n');

let totalPreguntas = 0;
let totalFallas = 0;
const resultados = [];

for (const nombre of nodesToTest) {
  const resultado = {
    nombre,
    exito: false,
    preguntas: 0,
    errores: [],
  };

  process.stdout.write(`  Testing ${nombre}... `);

  try {
    const foro = foroHelper.cargarYParsearEjemplo(nombre);

    if (foro.length === 0) {
      console.log('\n    ⚠️  No se encontraron preguntas');
      resultado.errores.push('No se encontraron preguntas');
    } else {
      resultado.exito = true;
      resultado.preguntas = foro.length;
      totalPreguntas += foro.length;

      console.log(`✓ (${foro.length} preguntas)\n`);

      foro.forEach((item, idx) => {
        const num = idx + 1;
        const hasAnswer = item.Respuesta && item.Respuesta.trim().length > 0;
        const status = hasAnswer ? '✓' : '○';

        console.log(`      ${status} [${num}] Pregunta:`);
        console.log(`          "${item.Pregunta.substring(0, 70)}${item.Pregunta.length > 70 ? '...' : ''}"`);

        if (item.FechaPregunta) {
          console.log(`          Fecha: ${item.FechaPregunta}`);
        } else {
          console.log(`          Fecha: (no encontrada)`);
        }

        if (hasAnswer) {
          console.log(`      ${status} Respuesta:`);
          console.log(`          "${item.Respuesta.substring(0, 70)}${item.Respuesta.length > 70 ? '...' : ''}"`);

          if (item.FechaRespuesta) {
            console.log(`          Fecha: ${item.FechaRespuesta}`);
          }
        } else {
          console.log(`      ${status} Respuesta: (sin responder aún)`);
        }

        console.log();
      });
    }
  } catch (err) {
    console.log(`❌ ERROR\n`);
    console.log(`      Error: ${err.message}\n`);
    resultado.errores.push(err.message);
    totalFallas++;
  }

  resultados.push(resultado);
}

// ─────────────────────────────────────────────────────────────────────────────

console.log('\n╔════════════════════════════════════════════════════════════╗');
console.log('║                      RESUMEN DE RESULTADOS                ║');
console.log('╚════════════════════════════════════════════════════════════╝\n');

const exitosos = resultados.filter(r => r.exito).length;
const fallidos = resultados.filter(r => !r.exito).length;

console.log(`  Total de ejemplos testeados: ${resultados.length}`);
console.log(`  ✓ Exitosos: ${exitosos}`);
console.log(`  ❌ Con errores: ${fallidos}`);
console.log(`  📊 Total de preguntas parseadas: ${totalPreguntas}\n`);

if (fallidos > 0) {
  console.log('❌ EJEMPLOS CON ERRORES:\n');
  resultados.filter(r => !r.exito).forEach(r => {
    console.log(`  • ${r.nombre}`);
    r.errores.forEach(err => {
      console.log(`    - ${err}`);
    });
  });
  console.log();
}

// ─────────────────────────────────────────────────────────────────────────────

console.log('💡 PRÓXIMOS PASOS:\n');

if (totalPreguntas > 0) {
  console.log('  ✓ El parsing está funcionando correctamente');
  console.log('  • Si encuentras errores, agrega más ejemplos para debugging');
  console.log('  • Prueba con diferentes tipos de licitaciones\n');
} else {
  console.log('  ⚠️  No se están parseando preguntas correctamente');
  console.log('  • Verifica la estructura HTML de Mercado Público');
  console.log('  • Usa Firefox DevTools para inspeccionar elementos (F12)');
  console.log('  • Actualiza los selectores CSS en parser_helper.js');
  console.log('  • Consulta: examples/foro_html/INTEGRACION.js para ayuda\n');
}

process.exit(fallidos > 0 ? 1 : 0);
