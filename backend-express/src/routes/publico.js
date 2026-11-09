/* =============================================================
   API PÚBLICA (la usa la web corporativa, sin login)
     GET  /api/modelos                 catálogo con precio y tallas
     GET  /api/modelos/:codigo/stock   disponibilidad por talla
     GET  /api/colores                 colores de catálogo de cada modelo
     POST /api/solicitudes             solicitud (Custom o color de catálogo) -> pedido 'pendiente'
============================================================= */
const express = require("express");
const { consulta, comoUsuario } = require("../db");
const { registrar } = require("../actividad");
const { traducirError, errorPublico } = require("../errores");

const router = express.Router();

const PARTES = ["cuerpo", "franja", "puntera", "talon", "suela", "cordones"];
const COLORES = ["Negro", "Blanco", "Azul eléctrico", "Rojo", "Verde", "Amarillo", "Naranja", "Gris"];
const TIPOS_CLIENTE = ["particular", "club", "equipo"];

let idWeb = null; // id del usuario técnico web_publica (07_web_backend.sql)
async function usuarioWeb() {
  if (idWeb) return idWeb;
  const r = await consulta("SELECT id_usuario FROM usuarios WHERE username = 'web_publica' AND activo");
  if (!r.rows.length) throw errorPublico("Falta ejecutar sql/07_web_backend.sql en la base de datos.", 500);
  idWeb = r.rows[0].id_usuario;
  return idWeb;
}

router.get("/modelos", async (req, res) => {
  try {
    const r = await consulta(
      `SELECT m.codigo, m.nombre, m.categoria, m.precio_base::float AS precio_base,
              coalesce(sum(s.stock_disponible), 0)::int AS stock_total
         FROM modelos m LEFT JOIN stock s USING (id_modelo)
        GROUP BY m.id_modelo ORDER BY m.id_modelo`);
    res.json({ modelos: r.rows, tallas: [38, 39, 40, 41, 42, 43, 44, 45, 46], extras: { personalizacion: 15, texto: 5 } });
  } catch (err) {
    const t = traducirError(err);
    res.status(t.http).json({ error: t.mensaje });
  }
});

router.get("/modelos/:codigo/stock", async (req, res) => {
  try {
    const r = await consulta(
      `SELECT s.talla::int, s.stock_disponible::int
         FROM stock s JOIN modelos m USING (id_modelo)
        WHERE m.codigo = $1 ORDER BY s.talla`, [req.params.codigo]);
    if (!r.rows.length) return res.status(404).json({ error: "Modelo no encontrado" });
    res.json({ codigo: req.params.codigo, stock: r.rows });
  } catch (err) {
    const t = traducirError(err);
    res.status(t.http).json({ error: t.mensaje });
  }
});

// Colores de catálogo agrupados por modelo (vacío si no se ejecutó 11_colores_catalogo.sql)
router.get("/colores", async (req, res) => {
  try {
    const r = await consulta(
      `SELECT m.codigo AS modelo, c.codigo, c.nombre, c.color_cuerpo AS cuerpo, c.color_franja AS franja,
              c.color_puntera AS puntera, c.color_talon AS talon, c.color_suela AS suela,
              c.color_cordones AS cordones, c.color_detalle AS acento
         FROM colores_catalogo c JOIN modelos m USING (id_modelo)
        WHERE c.activo
        ORDER BY m.id_modelo, c.orden`);
    const colores = {};
    r.rows.forEach(({ modelo, ...c }) => (colores[modelo] = colores[modelo] || []).push(c));
    res.json({ colores });
  } catch (err) {
    if (err.code === "42P01") return res.json({ colores: {} });
    const t = traducirError(err);
    res.status(t.http).json({ error: t.mensaje });
  }
});

/* Validación en el servidor (la del navegador se puede saltar).
   Las reglas definitivas (tallas 38-46, colores, cantidad > 0...) están
   además en PostgreSQL como DOMAIN y CHECK. */
function validarSolicitud(b) {
  const errores = [];
  const nombre = String(b.nombre || "").trim();
  const email = String(b.email || "").trim();
  if (nombre.length < 2) errores.push("El nombre es obligatorio.");
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) errores.push("El correo electrónico no es válido.");
  const tipo = TIPOS_CLIENTE.includes(b.tipo_cliente) ? b.tipo_cliente : "particular";
  const modelo = String(b.modelo || "").trim();
  if (!modelo) errores.push("Elige un modelo.");

  let tallas = Array.isArray(b.tallas) ? b.tallas : [];
  tallas = tallas
    .map((t) => ({ talla: parseInt(t.talla, 10), cantidad: parseInt(t.cantidad, 10) }))
    .filter((t) => t.cantidad > 0);
  if (!tallas.length) errores.push("Indica al menos una talla con cantidad.");
  const vistas = new Set();
  for (const t of tallas) {
    if (!(t.talla >= 38 && t.talla <= 46)) errores.push(`Talla ${t.talla} fuera de rango (38-46).`);
    if (t.cantidad > 500) errores.push(`Cantidad demasiado alta en talla ${t.talla}.`);
    if (vistas.has(t.talla)) errores.push(`Talla ${t.talla} repetida.`);
    vistas.add(t.talla);
  }

  let colores = null;
  if (b.colores && typeof b.colores === "object") {
    colores = {};
    for (const p of PARTES) {
      if (!COLORES.includes(b.colores[p])) { errores.push(`Color no válido en ${p}.`); break; }
      colores[p] = b.colores[p];
    }
  }
  const texto = String(b.texto_suela || "").trim().toUpperCase();
  if (texto.length > 12) errores.push("El texto de la suela admite 12 caracteres.");
  if (texto && !colores) errores.push("El texto en la suela solo está disponible en diseños personalizados.");
  // Color de catálogo (solo si no es personalizado). Que exista y sea del modelo lo comprueba la BD.
  const colorCatalogo = colores ? null : String(b.color_catalogo || "").trim() || null;

  if (errores.length) throw errorPublico(errores.join(" "));
  return { nombre, email, telefono: String(b.telefono || "").trim(), tipo, modelo, tallas, colores, colorCatalogo, texto: texto || null };
}

router.post("/solicitudes", async (req, res) => {
  let datos;
  try {
    datos = validarSolicitud(req.body || {});
    const id = await usuarioWeb();
    // UNA transacción: cliente + pedido + líneas. Si una línea falla no queda nada.
    const pedido = await comoUsuario(id, async (db) => {
      const m = await db.query("SELECT id_modelo FROM modelos WHERE codigo = $1", [datos.modelo]);
      if (!m.rows.length) throw errorPublico("El modelo elegido no existe en el catálogo.");
      const cli = await db.query("SELECT fn_cliente_web($1, $2, $3, $4) AS id", [datos.nombre, datos.email, datos.telefono, datos.tipo]);
      const p = await db.query("INSERT INTO pedidos (id_cliente) VALUES ($1) RETURNING id_pedido, referencia", [cli.rows[0].id]);
      const c = datos.colores || {};
      let idColor = null;
      if (datos.colorCatalogo) {
        const col = await db.query(
          "SELECT id_color FROM colores_catalogo WHERE codigo = $1 AND id_modelo = $2 AND activo", [datos.colorCatalogo, m.rows[0].id_modelo]);
        if (!col.rows.length) throw errorPublico("Ese color no existe para el modelo elegido.");
        idColor = col.rows[0].id_color;
      }
      for (const t of datos.tallas) {
        // precio_unitario NULL => lo calcula el trigger t1_lineas_antes
        await db.query(
          `INSERT INTO lineas_pedido (id_pedido, id_modelo, talla, cantidad,
                  color_cuerpo, color_franja, color_puntera, color_talon, color_suela, color_cordones, texto_suela${idColor ? ", id_color" : ""})
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11${idColor ? ", $12" : ""})`,
          [p.rows[0].id_pedido, m.rows[0].id_modelo, t.talla, t.cantidad,
           c.cuerpo || null, c.franja || null, c.puntera || null, c.talon || null, c.suela || null, c.cordones || null, datos.texto,
           ...(idColor ? [idColor] : [])]);
      }
      // El total lo ha recalculado el trigger t2_lineas_total
      const tot = await db.query("SELECT referencia, total::float, tipo, estado FROM pedidos WHERE id_pedido = $1", [p.rows[0].id_pedido]);
      return tot.rows[0];
    });
    const pares = datos.tallas.reduce((s, t) => s + t.cantidad, 0);
    registrar({ usuario: "web_publica", rol: "Web", accion: "solicitud_web", resultado: "correcto", detalle: `pedido=${pedido.referencia} pares=${pares}` });
    res.status(201).json({ ok: true, ...pedido, pares });
  } catch (err) {
    const t = traducirError(err);
    registrar({ usuario: "web_publica", rol: "Web", accion: "solicitud_web", resultado: t.resultado, detalle: "motivo=" + t.mensaje.slice(0, 120) });
    res.status(t.http).json({ error: t.mensaje });
  }
});

module.exports = router;
