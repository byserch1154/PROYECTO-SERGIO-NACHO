/* =============================================================
   Conexión con Odoo por su API externa (JSON-RPC, endpoint /jsonrpc)
   -------------------------------------------------------------
   Odoo tiene su propia base de datos y sus propias reglas (precios,
   fabricación MTO, stock...). Por eso NO se escribe en sus tablas ni se
   usan triggers: se le pide a Odoo que cree el pedido, igual que si lo
   hiciera un usuario desde su pantalla.

   Datos de conexión en .env (si falta alguno, la integración está apagada):
     ODOO_URL, ODOO_DB, ODOO_USER, ODOO_PASSWORD (mejor una clave API)
   Productos y variantes de talla: los crea odoo/scripts/cargar_datos_odoo.py
============================================================= */
const cfg = require("./config");

let uid = null; // id del usuario de Odoo tras iniciar sesión

const activo = () => Boolean(cfg.odoo.url && cfg.odoo.db && cfg.odoo.user && cfg.odoo.password);

async function rpc(service, method, args) {
  let resp;
  try {
    resp = await fetch(cfg.odoo.url.replace(/\/+$/, "") + "/jsonrpc", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ jsonrpc: "2.0", method: "call", params: { service, method, args }, id: Date.now() }),
      signal: AbortSignal.timeout(cfg.odoo.timeoutMs),
    });
  } catch (err) {
    throw new Error("No hay conexión con Odoo (" + (err.name === "TimeoutError" ? "tiempo agotado" : err.message) + ")");
  }
  if (!resp.ok) throw new Error("Odoo respondió " + resp.status);
  const datos = await resp.json();
  if (datos.error) {
    const d = datos.error.data || {};
    throw new Error("Odoo: " + (d.message || datos.error.message));
  }
  return datos.result;
}

async function conectar() {
  if (uid) return uid;
  uid = await rpc("common", "authenticate", [cfg.odoo.db, cfg.odoo.user, cfg.odoo.password, {}]);
  if (!uid) throw new Error("Odoo: usuario o contraseña incorrectos");
  return uid;
}

// Llama a un método de un modelo de Odoo (search_read, create, action_confirm...)
async function llamar(modelo, metodo, args, kwargs = {}) {
  await conectar();
  try {
    return await rpc("object", "execute_kw", [cfg.odoo.db, uid, cfg.odoo.password, modelo, metodo, args, kwargs]);
  } catch (err) {
    uid = null; // por si la sesión dejó de valer; el siguiente intento vuelve a entrar
    throw err;
  }
}

async function buscarUno(modelo, dominio, campos = ["id"]) {
  const filas = await llamar(modelo, "search_read", [dominio], { fields: campos, limit: 1 });
  return filas[0] || null;
}

// Busca el cliente por email; si no existe lo crea
async function clienteOdoo(c) {
  const existente = await buscarUno("res.partner", [["email", "=", c.email]]);
  if (existente) return existente.id;
  return llamar("res.partner", "create", [{
    name: c.nombre,
    email: c.email,
    phone: c.telefono || false,
    is_company: c.tipo !== "particular",
    customer_rank: 1,
  }]);
}

// Variante del producto para una talla: "SPEAKE Pulse Custom" + talla 42
async function varianteOdoo(producto, talla) {
  const v = await buscarUno("product.product", [
    ["product_tmpl_id.name", "=ilike", producto], // sin distinguir mayúsculas
    ["product_template_attribute_value_ids.name", "=", String(talla)],
  ]);
  if (!v) {
    throw new Error(`En Odoo no existe «${producto}» talla ${talla} (ejecuta odoo/scripts/cargar_datos_odoo.py)`);
  }
  return v.id;
}

/* Crea en Odoo el pedido de venta de un pedido de SPEAKE.
   pedido = { referencia, cliente: {nombre, email, telefono, tipo},
              lineas: [{ modelo, talla, cantidad, precio, personalizacion, texto, colorCatalogo }] }
   Si ya se envió antes (misma Referencia del cliente) no se duplica. */
async function enviarPedido(pedido) {
  const ya = await buscarUno("sale.order", [["client_order_ref", "=", pedido.referencia]], ["id", "name"]);
  if (ya) return { id: ya.id, nombre: ya.name, nuevo: false };

  const partner = await clienteOdoo(pedido.cliente);
  const lineas = [];
  for (const l of pedido.lineas) {
    const producto = l.personalizacion ? l.modelo + " Custom" : l.modelo;
    let descripcion = `${producto} · Talla ${l.talla}`;
    if (l.personalizacion) descripcion += ` · Colores: ${l.personalizacion}`;
    else if (l.colorCatalogo) descripcion += ` · Color: ${l.colorCatalogo}`;
    if (l.texto) descripcion += ` · Texto: ${l.texto}`;
    lineas.push([0, 0, {
      product_id: await varianteOdoo(producto, l.talla),
      product_uom_qty: l.cantidad,
      price_unit: l.precio,
      name: descripcion,
    }]);
  }

  const id = await llamar("sale.order", "create", [{
    partner_id: partner,
    client_order_ref: pedido.referencia,
    origin: "Web SPEAKE " + pedido.referencia,
    order_line: lineas,
  }]);
  // Confirmar en Odoo genera las órdenes de fabricación (ruta MTO de los Custom)
  if (cfg.odoo.confirmar) await llamar("sale.order", "action_confirm", [[id]]);

  const so = await buscarUno("sale.order", [["id", "=", id]], ["name"]);
  return { id, nombre: so.name, nuevo: true };
}

// Prueba de conexión para el panel (sin datos sensibles)
async function comprobar() {
  if (!activo()) return { activo: false };
  try {
    await conectar();
    return { activo: true, conectado: true, url: cfg.odoo.url, db: cfg.odoo.db };
  } catch (err) {
    return { activo: true, conectado: false, url: cfg.odoo.url, db: cfg.odoo.db, error: err.message };
  }
}

module.exports = { activo, enviarPedido, comprobar };
