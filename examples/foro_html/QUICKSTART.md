# 🚀 QUICKSTART - Debugging del Foro de Licitación

## En 5 minutos

### 1️⃣ Obtén un ejemplo de HTML del foro

**Opción A: Desde el navegador**
1. Ve a https://www.mercadopublico.cl (busca una licitación pública)
2. Haz clic derecho → **Inspeccionar** (o presiona F12)
3. Busca el elemento del foro (usualmente un `<div>` con preguntas/respuestas)
4. **Right-click en el elemento** → **Copy** → **Copy OuterHTML**
5. Abre tu editor favorito y pega el HTML

**Opción B: Usa el template**
```bash
cp template_estructura.html licitacion_ejemplo.html
# Ahora completa el HTML con datos reales
```

### 2️⃣ Guarda el archivo

```bash
# Naming: licitacion_CODIGO.html
# Ejemplos:
examples/foro_html/licitacion_12345.html
examples/foro_html/licitacion_ABC123.html
examples/foro_html/licitacion_problematico.html
```

### 3️⃣ Ejecuta el test

```bash
cd examples/foro_html
node test_parsing.js
# o para un archivo específico:
node test_parsing.js licitacion_12345
```

**Output esperado:**
```
🔍 INICIANDO TESTS...

  Testing licitacion_12345... ✓ (3 preguntas)

      ✓ [1] Pregunta:
          "¿Cuál es el plazo de entrega?"
          Fecha: 15 de Marzo, 2026
      ✓ Respuesta:
          "El plazo es de 30 días calendario"
          Fecha: 16 de Marzo, 2026

      ... más resultados ...
```

### 4️⃣ Si algo no funciona

**Problema: "No se encontraron preguntas"**

1. Abre el HTML en tu editor
2. Busca el selector correcto:
   - `<div class="question">` → `.question`
   - `<div data-qa="forum-question">` → `[data-qa="forum-question"]`
   - Cualquier identificador único

3. Actualiza `parser_helper.js` línea ~40 con el selector correcto:
   ```javascript
   // Cambia esto:
   const preguntas = $('.question-item');
   
   // Por el selector real:
   const preguntas = $('.tu-selector-aqui');
   ```

4. Vuelve a ejecutar: `node test_parsing.js licitacion_12345`

## 📁 Archivos en esta carpeta

| Archivo | Propósito |
|---------|-----------|
| `README.md` | Documentación completa |
| `parser_helper.js` | Helper para cargar y parsear HTML |
| `test_parsing.js` | Script de test automático **ejecuta esto** |
| `INTEGRACION.js` | Cómo integrar en functions/index.js |
| `template_estructura.html` | Ejemplo de estructura esperada |
| `.gitignore` | Solo comentarios/templates en Git |

## 🔗 Archivos HTML reales

**Por defecto .gitignore EXCLUYE archivos .html**

Para guardar ejemplos locales sin hacer commit:
```bash
# No hará commit
examples/foro_html/licitacion_123456.html

# Pero sí hará commit estos:
examples/foro_html/README.md
examples/foro_html/parser_helper.js
examples/foro_html/test_parsing.js
```

## 💻 Integración en Cloud Functions

**Para testing local en desarrollo:**

```javascript
// En functions/index.js, al inicio:
const foroHelper = require('../examples/foro_html/parser_helper.js');

// En fetchForoLicitacion:
if (req.query.debug && process.env.NODE_ENV !== 'production') {
  const foro = foroHelper.cargarYParsearEjemplo(req.query.debug);
  return res.json({ ok: true, foro, source: 'example' });
}
```

**Uso:**
```bash
# Local emulator
curl "http://localhost:5001/.../fetchForoLicitacion?debug=licitacion_12345"
```

## ✅ Checklist

- [ ] Guardé un ejemplo HTML en `examples/foro_html/licitacion_XXX.html`
- [ ] Ejecuté `node test_parsing.js licitacion_XXX`
- [ ] El test muestra preguntas parseadas correctamente
- [ ] Si falló, identifiqué el selector CSS correcto
- [ ] Actualicé `parser_helper.js` con el selector correcto
- [ ] Re-ejecuté el test y ahora funciona ✓

## 🆘 Ayuda

Para más detalles, consulta:
- `README.md` - Documentación completa
- `INTEGRACION.js` - Cómo integrar en functions/index.js
- `parser_helper.js` - Funciones disponibles

---

**Próximo paso:** Una vez que el parsing funcione, integra los cambios en `functions/index.js` y haz deploy.
