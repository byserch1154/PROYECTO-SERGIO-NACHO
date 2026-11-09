/* =============================================================
   Pruebas de la integración con Odoo (node --test)
   -------------------------------------------------------------
   No necesitan la máquina virtual: levantan un Odoo SIMULADO que
   responde a /jsonrpc como el de verdad, y un backend propio en el
   puerto 3100 apuntando a él.
   Requisitos: base SPEAKE con 01 + 02 + 07 + 10_integracion_odoo.sql
   Ejecutar:   npm run test:odoo
============================================================= */
const test = require("node:test");
const assert = require("node:assert");
const http = require("http");

// ------------------------------------------------ Odoo simulado
const odooFalso = { pedidos: [], clientes: [], caido: false };

function responder(params) {
  if (params.service === "common") return 7; // uid
  const [, , , modelo, metodo, args, kw] = params.args;
  const dom = Array.isArray(args[0]) ? Object.fromEntries(args[0].filter(Array.isArray).map((d) => [d[0], d[2]])) : {};
  if (modelo === "res.partner" && metodo === "search_read") {
    return odooFalso.clientes.filter((c) => c.email === dom.email).slice(0, 1);
  }
  if (modelo === "res.partner" && metodo === "create") {
    odooFalso.clientes.push({ id: 100 + odooFalso.clientes.length, ...args[0] });
    return 100 + odooFalso.clientes.length - 1;
  }
  if (modelo === "product.product") {
    return dom["product_tmpl_id.name"].startsWith("SPEAKE") ? [{ id: 500 + Number(dom["product_template_attribute_value_ids.name"]) }] : [];
  }
  if (modelo === "sale.order" && metodo === "search_read") {
    return odooFalso.pedidos.filter((p) => p.client_order_ref === dom.client_order_ref || p.id === dom.id).slice(0, 1);
  }
  if (modelo === "sale.order" && metodo === "create") {
    const id = 900 + odooFalso.pedidos.length;
    odooFalso.pedidos.push({ id, name: "S" + String(id).padStart(5, "0"), state: "draft", ...args[0] });
    return id;
  }
  if (modelo === "sale.order" && metodo === "action_confirm") {
    odooFalso.pedidos.find((p) => p.id === args[0][0]).state = "sale";
    return true;
  }
  throw new Error("método no simulado: " + modelo + "." + metodo);
}

const servidorOdoo = http.createServer((req, res) => {
  let cuerpo = "";
  req.on("data", (c) => (cuerpo += c));
  req.on("end", () => {
    if (odooFalso.caido) { res.writeHead(503); return res.end(); }
    const { params, id } = JSON.parse(cuerpo);
    let salida;
    try { salida = { jsonrpc: "2.0", id, result: responder(params) }; }
    catch (e) { salida = { jsonrpc: "2.0", id, error: { message: "Odoo Server Error", data: { message: e.message } } }; }
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify(salida));
  });
});

// ------------------------------------------------ backend apuntando al Odoo simulado
let app, servidorApi, BASE;

test.before(async () => {
  await new Promise((ok) => servidorOdoo.listen(0, ok));
  Object.assign(process.env, {
    ODOO_URL: "http://127.0.0.1:" + servidorOdoo.address().port,
    ODOO_DB: "Proyecto1", ODOO_USER: "prueba@speake.local", ODOO_PASSWORD: "clave-de-prueba",
    ODOO_CONFIRMAR: "1", ODOO_TIMEOUT_MS: "3000",
  });
  app = require("../src/server");
  await new Promise((ok) => { servidorApi = app.listen(0, ok); });
  BASE = "http://127.0.0.1:" + servidorApi.address().port + "/api";
});

// Pedidos confirmados durante las pruebas: al final se cancelan para devolver el stock
const confirmados = [];

test.after(async () => {
  for (const ref of confirmados) {
    await api(`/pedidos/${ref}/estado`, { metodo: "PATCH", token: comercial, body: { estado: "cancelado" } });
  }
  servidorApi.close();
  servidorOdoo.close();
  await require("../src/db").pool.end();
});

async function api(ruta, { metodo = "GET", token, body } = {}) {
  const r = await fetch(BASE + ruta, {
    method: metodo,
    headers: { "Content-Type": "application/json", ...(token ? { Authorization: "Bearer " + token } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  return { status: r.status, datos: await r.json() };
}

async function pedidoWeb(email) {
  const r = await api("/solicitudes", { metodo: "POST", body: {
    nombre: "Club Odoo Prueba", email, tipo_cliente: "club", modelo: "pulse",
    tallas: [{ talla: 41, cantidad: 2 }, { talla: 43, cantidad: 1 }],
    colores: { cuerpo: "Negro", franja: "Azul eléctrico", puntera: "Negro", talon: "Gris", suela: "Blanco", cordones: "Negro" },
  } });
  assert.strictEqual(r.status, 201, JSON.stringify(r.datos));
  return r.datos.referencia;
}

let comercial, almacen;

test("O1 · el panel ve Odoo conectado", async () => {
  comercial = (await api("/login", { metodo: "POST", body: { usuario: "comercial1", password: "Comercial#2026" } })).datos.token;
  almacen = (await api("/login", { metodo: "POST", body: { usuario: "almacen1", password: "Almacen#2026" } })).datos.token;
  const e = await api("/odoo/estado", { token: comercial });
  assert.strictEqual(e.datos.activo, true);
  assert.strictEqual(e.datos.conectado, true);
  assert.ok(!JSON.stringify(e.datos).includes("clave-de-prueba"), "nunca se devuelve la contraseña");
});

test("O2 · confirmar un pedido web lo crea y confirma en Odoo", async () => {
  const ref = await pedidoWeb("odoo1@example.com");
  const r = await api(`/pedidos/${ref}/estado`, { metodo: "PATCH", token: comercial, body: { estado: "confirmado" } });
  confirmados.push(ref);
  assert.strictEqual(r.status, 200);
  assert.strictEqual(r.datos.odoo.estado, "enviado");
  const so = odooFalso.pedidos.find((p) => p.client_order_ref === ref);
  assert.ok(so, "pedido de venta con Referencia del cliente = " + ref);
  assert.strictEqual(so.state, "sale");
  assert.strictEqual(so.order_line.length, 2);
  assert.strictEqual(so.order_line[0][2].product_id, 541); // variante talla 41
  assert.match(so.order_line[0][2].name, /SPEAKE Pulse Custom · Talla 41 · Colores: Negro/);
  assert.strictEqual(odooFalso.clientes.filter((c) => c.email === "odoo1@example.com").length, 1);
  const lista = await api("/pedidos?cliente=Odoo", { token: comercial });
  assert.strictEqual(lista.datos.filas.find((p) => p.referencia === ref).odoo.pedido_odoo, so.name);
});

test("O3 · reenviar no duplica el pedido en Odoo", async () => {
  const ref = odooFalso.pedidos[0].client_order_ref;
  const antes = odooFalso.pedidos.length;
  const r = await api(`/pedidos/${ref}/odoo`, { metodo: "POST", token: comercial });
  assert.strictEqual(r.status, 200);
  assert.strictEqual(odooFalso.pedidos.length, antes);
  assert.match(r.datos.mensaje, /ya existía/);
});

test("O4 · con Odoo caído la confirmación se mantiene y luego se reenvía", async () => {
  const ref = await pedidoWeb("odoo2@example.com");
  odooFalso.caido = true;
  const r = await api(`/pedidos/${ref}/estado`, { metodo: "PATCH", token: comercial, body: { estado: "confirmado" } });
  confirmados.push(ref);
  assert.strictEqual(r.status, 200);
  assert.strictEqual(r.datos.estado, "confirmado");
  assert.strictEqual(r.datos.odoo.estado, "error");
  const det = await api("/pedidos/" + ref, { token: comercial });
  assert.strictEqual(det.datos.odoo.estado, "error");

  odooFalso.caido = false;
  const re = await api(`/pedidos/${ref}/odoo`, { metodo: "POST", token: comercial });
  assert.strictEqual(re.status, 200);
  assert.strictEqual((await api("/pedidos/" + ref, { token: comercial })).datos.odoo.estado, "enviado");
});

test("O5 · no se envían pedidos pendientes ni lo puede hacer almacén", async () => {
  const ref = await pedidoWeb("odoo3@example.com");
  const pendiente = await api(`/pedidos/${ref}/odoo`, { metodo: "POST", token: comercial });
  assert.strictEqual(pendiente.status, 400);
  assert.match(pendiente.datos.error, /solo se envían a Odoo los pedidos confirmados/);
  const sinPermiso = await api(`/pedidos/${ref}/odoo`, { metodo: "POST", token: almacen });
  assert.match(sinPermiso.datos.error, /permiso/i);
  assert.ok(!odooFalso.pedidos.some((p) => p.client_order_ref === ref));
});

test("O6 · un pedido con color de catálogo llega a Odoo como producto estándar con su color", async () => {
  const r = await api("/solicitudes", { metodo: "POST", body: {
    nombre: "Cliente Catálogo", email: "odoo-color@example.com", modelo: "pulse",
    color_catalogo: "pulse-negro-naranja", tallas: [{ talla: 42, cantidad: 2 }],
  } });
  assert.strictEqual(r.status, 201, JSON.stringify(r.datos));
  assert.strictEqual(r.datos.tipo, "estandar");
  assert.strictEqual(r.datos.total, 2 * 109); // precio base, sin los +15 de personalización
  const ref = r.datos.referencia;
  const conf = await api(`/pedidos/${ref}/estado`, { metodo: "PATCH", token: comercial, body: { estado: "confirmado" } });
  confirmados.push(ref);
  assert.strictEqual(conf.datos.odoo.estado, "enviado");
  const linea = odooFalso.pedidos.find((p) => p.client_order_ref === ref).order_line[0][2];
  assert.strictEqual(linea.name, "SPEAKE Pulse · Talla 42 · Color: Negro / Naranja");
  assert.strictEqual(linea.price_unit, 109);
});
