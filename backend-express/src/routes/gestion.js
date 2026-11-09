/* =============================================================
   API DE GESTIÓN (panel interno, requiere login)
   Todas las operaciones se ejecutan con comoUsuario(): la BD conoce al
   usuario autenticado, comprueba su permiso y lo apunta en log_eventos.
============================================================= */
const express = require("express");
const { comoUsuario } = require("../db");
const auth = require("../auth");
const { registrar, describirFiltros } = require("../actividad");
const { traducirError, errorPublico } = require("../errores");
const { aCsv, exportarContrato, exportarUsuariosJson } = require("../exportaciones");

const router = express.Router();

/* Ejecuta una operación, registra el resultado en el TXT y responde.
   El TXT se escribe DESPUÉS de COMMIT/ROLLBACK, así nunca marca como
   "correcto" algo que la base de datos ha deshecho. */
async function operar(req, res, accion, fn, { detalle, instantanea } = {}) {
  const s = req.sesion;
  try {
    const salida = await comoUsuario(s.id, fn, { instantanea });
    const info = typeof detalle === "function" ? detalle(salida) : (detalle || "");
    const vacio = salida && Array.isArray(salida.filas) && salida.filas.length === 0;
    registrar({ usuario: s.usuario, rol: s.rol, accion, resultado: vacio ? "vacio" : "correcto", detalle: info });
    return salida;
  } catch (err) {
    const t = traducirError(err);
    const info = typeof detalle === "function" ? "" : (detalle || "");
    registrar({ usuario: s.usuario, rol: s.rol, accion, resultado: t.resultado, detalle: (info ? info + " " : "") + "motivo=" + t.mensaje.slice(0, 140) });
    res.status(t.http).json({ error: t.mensaje });
    return undefined;
  }
}

// ---------------------------------------------------------------- sesión
router.post("/login", async (req, res) => {
  const { usuario, password } = req.body || {};
  try {
    const s = await auth.login(String(usuario || ""), String(password || ""));
    if (!s) {
      registrar({ usuario: String(usuario || "").slice(0, 40), accion: "login", resultado: "rechazado", detalle: "credenciales no válidas o usuario inactivo" });
      return res.status(401).json({ error: "Usuario o contraseña incorrectos." });
    }
    registrar({ usuario: s.usuario, rol: s.rol, accion: "login", resultado: "correcto" });
    res.json({ token: s.token, usuario: s.usuario, rol: s.rol, permisos: await auth.permisosDe(s.id) });
  } catch (err) {
    const t = traducirError(err);
    registrar({ usuario: String(usuario || "").slice(0, 40), accion: "login", resultado: "error", detalle: t.mensaje });
    res.status(t.http).json({ error: t.mensaje });
  }
});

router.use(auth.requiereSesion);

router.post("/logout", (req, res) => {
  registrar({ usuario: req.sesion.usuario, rol: req.sesion.rol, accion: "logout", resultado: "correcto" });
  auth.logout(req.token);
  res.json({ ok: true });
});

router.get("/me", async (req, res) => {
  res.json({ usuario: req.sesion.usuario, rol: req.sesion.rol, permisos: await auth.permisosDe(req.sesion.id) });
});

// --------------------------------------------------------------- pedidos
const ESTADOS = ["pendiente", "confirmado", "entregado", "cancelado"];
const esFecha = (v) => /^\d{4}-\d{2}-\d{2}$/.test(v);

function leerFiltros(q) {
  const f = {
    cliente: (q.cliente || "").trim() || null,
    modelo: (q.modelo || "").trim() || null,
    estado: ESTADOS.includes(q.estado) ? q.estado : null,
    desde: esFecha(q.desde || "") ? q.desde : null,
    hasta: esFecha(q.hasta || "") ? q.hasta : null,
  };
  if (f.desde && f.hasta && f.desde > f.hasta) throw errorPublico("La fecha «desde» es posterior a «hasta».");
  return f;
}

// Consulta visual con filtros combinables (vacío = sin restricción)
const SQL_BUSCAR = "SELECT referencia, fecha, cliente, estado, tipo, pares, total::float FROM fn_buscar_pedidos($1, $2, $3, $4::date, $5::date)";
const paramsBuscar = (f) => [f.cliente, f.modelo, f.estado, f.desde, f.hasta];

router.get("/pedidos", async (req, res) => {
  let f;
  try { f = leerFiltros(req.query); } catch (e) { return res.status(400).json({ error: e.message }); }
  const accion = req.query.limpiar === "1" ? "limpiar_filtros" : "buscar_pedidos";
  const out = await operar(req, res, accion, async (db) => ({ filas: (await db.query(SQL_BUSCAR, paramsBuscar(f))).rows }),
    { detalle: (o) => `${describirFiltros(f)} filas=${o.filas.length}` });
  if (out) res.json({ filas: out.filas, filtros: f, consultado: new Date().toISOString() });
});

// Exportación CSV del resultado ACTUAL filtrado (mismas filas que la tabla)
router.get("/pedidos/export.csv", async (req, res) => {
  let f;
  try { f = leerFiltros(req.query); } catch (e) { return res.status(400).json({ error: e.message }); }
  const out = await operar(req, res, "exportar_csv_pedidos", async (db) => ({ filas: (await db.query(SQL_BUSCAR, paramsBuscar(f))).rows }),
    { detalle: (o) => `${describirFiltros(f)} filas=${o.filas.length}` });
  if (!out) return;
  const csv = aCsv(["referencia", "fecha", "cliente", "estado", "tipo", "pares", "total"], out.filas);
  res.setHeader("Content-Type", "text/csv; charset=utf-8");
  res.setHeader("Content-Disposition", `attachment; filename="pedidos_filtrados_${Date.now()}.csv"`);
  res.send("﻿" + csv); // BOM para que Excel reconozca UTF-8
});

router.get("/pedidos/:ref", async (req, res) => {
  const ref = String(req.params.ref).toUpperCase();
  const out = await operar(req, res, "ver_pedido", async (db) => ({ filas: (await db.query("SELECT * FROM fn_detalle_pedido($1)", [ref])).rows }),
    { detalle: (o) => `pedido=${ref} lineas=${o.filas.filter((x) => x.id_linea).length}` });
  if (!out) return;
  if (!out.filas.length) return res.status(404).json({ error: `No existe el pedido ${ref}.` });
  const c = out.filas[0];
  res.json({
    referencia: c.referencia, fecha: c.fecha, cliente: c.cliente, estado: c.estado, tipo: c.tipo, total: Number(c.total),
    lineas: out.filas.filter((x) => x.id_linea).map((l) => ({
      id_linea: l.id_linea, modelo: l.modelo, talla: l.talla, cantidad: l.cantidad,
      precio_unitario: Number(l.precio_unitario), personalizacion: l.personalizacion, texto_suela: l.texto_suela })),
  });
});

// Alta desde el panel: cabecera + líneas en UNA transacción
router.post("/pedidos", async (req, res) => {
  const b = req.body || {};
  const lineas = Array.isArray(b.lineas) ? b.lineas : [];
  const out = await operar(req, res, "crear_pedido", async (db) => {
    if (!lineas.length) throw errorPublico("Añade al menos una línea.");
    const p = await db.query("INSERT INTO pedidos (id_cliente) VALUES ($1) RETURNING id_pedido, referencia", [parseInt(b.id_cliente, 10)]);
    for (const l of lineas) {
      const m = await db.query("SELECT id_modelo FROM modelos WHERE codigo = $1", [l.modelo]);
      if (!m.rows.length) throw errorPublico(`Modelo «${l.modelo}» inexistente.`);
      const c = l.colores || {};
      await db.query(
        `INSERT INTO lineas_pedido (id_pedido, id_modelo, talla, cantidad, color_cuerpo, color_franja,
                color_puntera, color_talon, color_suela, color_cordones, texto_suela)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)`,
        [p.rows[0].id_pedido, m.rows[0].id_modelo, parseInt(l.talla, 10), parseInt(l.cantidad, 10),
         c.cuerpo || null, c.franja || null, c.puntera || null, c.talon || null, c.suela || null, c.cordones || null,
         (l.texto_suela || "").trim() || null]);
    }
    return (await db.query("SELECT referencia, total::float, tipo, estado FROM pedidos WHERE id_pedido = $1", [p.rows[0].id_pedido])).rows[0];
  }, { detalle: (o) => `pedido=${o.referencia} lineas=${lineas.length}` });
  if (out) res.status(201).json(out);
});

// Confirmar / cancelar / entregar: el stock lo mueve el trigger t3_pedidos_stock
router.patch("/pedidos/:ref/estado", async (req, res) => {
  const ref = String(req.params.ref).toUpperCase();
  const estado = String((req.body || {}).estado || "");
  const out = await operar(req, res, "cambiar_estado", async (db) => {
    if (!ESTADOS.includes(estado)) throw errorPublico("Estado no válido.");
    const r = await db.query("UPDATE pedidos SET estado = $1 WHERE referencia = $2 RETURNING referencia, estado, total::float", [estado, ref]);
    if (!r.rows.length) throw errorPublico(`No existe el pedido ${ref}.`, 404);
    return r.rows[0];
  }, { detalle: `pedido=${ref} nuevo_estado=${estado}` });
  if (out) res.json(out);
});

router.get("/clientes", async (req, res) => {
  const out = await operar(req, res, "listar_clientes", async (db) => {
    await db.query("SELECT fn_exigir_permiso('consultar_pedidos')");
    return { filas: (await db.query("SELECT id_cliente, nombre, tipo FROM clientes ORDER BY nombre")).rows };
  }, { detalle: (o) => `filas=${o.filas.length}` });
  if (out) res.json(out);
});

// ------------------------------------------------------ indicadores y análisis
router.get("/indicadores", async (req, res) => {
  const out = await operar(req, res, "ver_indicadores", async (db) => {
    const ind = (await db.query("SELECT indicador, valor::float FROM fn_indicadores()")).rows;
    const modelos = (await db.query("SELECT modelo, pedidos::int, pares::int, importe::float FROM fn_analisis_modelos()")).rows;
    const tallas = (await db.query("SELECT talla, pares::int FROM fn_analisis_tallas()")).rows;
    return { indicadores: Object.fromEntries(ind.map((x) => [x.indicador, x.valor])), modelos, tallas };
  });
  if (out) res.json({ ...out, regla_ventas: "Ventas = pedidos confirmados + entregados (sin cancelados ni pendientes)" });
});

router.get("/stock-bajo", async (req, res) => {
  const umbral = Math.max(0, parseInt(req.query.umbral, 10) || 5);
  const out = await operar(req, res, "stock_bajo", async (db) => ({ filas: (await db.query("SELECT * FROM fn_stock_bajo($1)", [umbral])).rows }),
    { detalle: (o) => `umbral=${umbral} filas=${o.filas.length}` });
  if (out) res.json({ umbral, ...out });
});

router.get("/auditoria", async (req, res) => {
  const limite = Math.min(500, Math.max(1, parseInt(req.query.limite, 10) || 50));
  const out = await operar(req, res, "ver_auditoria", async (db) => ({ filas: (await db.query("SELECT * FROM fn_auditoria($1)", [limite])).rows }),
    { detalle: (o) => `filas=${o.filas.length}` });
  if (out) res.json(out);
});

// --------------------------------------------------------------- usuarios
router.get("/usuarios", async (req, res) => {
  const out = await operar(req, res, "listar_usuarios", async (db) => ({ filas: (await db.query("SELECT * FROM fn_listar_usuarios()")).rows }),
    { detalle: (o) => `filas=${o.filas.length}` });
  if (out) res.json(out);
});

/* Tras un cambio CONFIRMADO de usuarios se regenera el JSON en otra
   transacción: si el cambio hizo ROLLBACK nunca llegamos aquí, así que el
   JSON no puede contener usuarios inexistentes. */
async function regenerarJson(req) {
  try {
    const n = await comoUsuario(req.sesion.id, exportarUsuariosJson);
    registrar({ usuario: req.sesion.usuario, rol: req.sesion.rol, accion: "json_usuarios_auto", resultado: "correcto", detalle: `usuarios=${n}` });
  } catch (err) {
    registrar({ usuario: req.sesion.usuario, rol: req.sesion.rol, accion: "json_usuarios_auto", resultado: "error", detalle: traducirError(err).mensaje });
  }
}

router.post("/usuarios", async (req, res) => {
  const { username, password, rol } = req.body || {};
  const out = await operar(req, res, "crear_usuario", async (db) => {
    if (!username || String(password || "").length < 8) throw errorPublico("Usuario obligatorio y contraseña de 8 caracteres como mínimo.");
    if (rol === "Web") throw errorPublico("El rol Web es técnico y no se asigna a personas.");
    return (await db.query("SELECT fn_crear_usuario($1, $2, $3) AS id", [String(username).trim(), String(password), rol])).rows[0];
  }, { detalle: `nuevo_usuario=${String(username || "").slice(0, 30)} rol=${rol}` });
  if (!out) return;
  await regenerarJson(req);
  res.status(201).json(out);
});

router.patch("/usuarios/:id", async (req, res) => {
  const id = parseInt(req.params.id, 10);
  const { activo, rol } = req.body || {};
  const out = await operar(req, res, "modificar_usuario", async (db) => {
    if (typeof activo === "boolean") await db.query("SELECT fn_cambiar_activo($1, $2)", [id, activo]);
    if (rol) {
      if (rol === "Web") throw errorPublico("El rol Web es técnico y no se asigna a personas.");
      await db.query("SELECT fn_cambiar_rol($1, $2)", [id, rol]);
    }
    return { id, activo, rol };
  }, { detalle: `id_usuario=${id} activo=${activo} rol=${rol || "-"}` });
  if (!out) return;
  await regenerarJson(req);
  res.json(out);
});

router.post("/usuarios/exportar-json", async (req, res) => {
  const out = await operar(req, res, "exportar_usuarios_json", async (db) => ({ usuarios: await exportarUsuariosJson(db) }),
    { detalle: (o) => `usuarios=${o.usuarios}` });
  if (out) res.json({ ok: true, ...out });
});

// Exportación del contrato de datos (PSP + Python) con una sola instantánea
router.post("/exportar-contrato", async (req, res) => {
  const out = await operar(req, res, "exportar_contrato_csv", async (db) => {
    await db.query("SELECT fn_exigir_permiso('consultar_pedidos')");
    return { ficheros: await exportarContrato(db) };
  }, { instantanea: true, detalle: (o) => o.ficheros.map((f) => `${f.fichero}=${f.filas}`).join(" ") });
  if (out) res.json({ ok: true, ...out });
});

module.exports = router;
