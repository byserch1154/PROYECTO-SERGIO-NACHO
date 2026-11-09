/* =============================================================
   Pruebas de extremo a extremo de la API (node --test)
   Requisitos: servidor arrancado (npm start) sobre una base recién
   cargada con 01_esquema + 02_datos + 07_web_backend.
   Ejecutar:   npm test
   Cubre las pruebas A-J del enunciado de Acceso a Datos (versión web).
============================================================= */
const test = require("node:test");
const assert = require("node:assert");
const fs = require("fs");
const path = require("path");

const BASE = process.env.API || "http://localhost:3000/api";
const TXT = path.join(__dirname, "..", "logs", "actividad_sneaker.txt");
const JSONF = path.join(__dirname, "..", "data", "usuarios_sneaker.json");

async function api(ruta, { metodo = "GET", token, body } = {}) {
  const r = await fetch(BASE + ruta, {
    method: metodo,
    headers: { "Content-Type": "application/json", ...(token ? { Authorization: "Bearer " + token } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  const tipo = r.headers.get("content-type") || "";
  return { status: r.status, datos: tipo.includes("json") ? await r.json() : await r.text() };
}
const login = async (u, p) => (await api("/login", { metodo: "POST", body: { usuario: u, password: p } })).datos.token;
const lineasTxt = () => (fs.existsSync(TXT) ? fs.readFileSync(TXT, "utf8").trim().split("\n").length : 0);

let admin, comercial, almacen;

test("login por rol y rechazo de credenciales", async () => {
  admin = await login("admin", "Admin#2026");
  comercial = await login("comercial1", "Comercial#2026");
  almacen = await login("almacen1", "Almacen#2026");
  assert.ok(admin && comercial && almacen);
  const mal = await api("/login", { metodo: "POST", body: { usuario: "admin", password: "mal" } });
  assert.strictEqual(mal.status, 401);
  const web = await api("/login", { metodo: "POST", body: { usuario: "web_publica", password: "x" } });
  assert.strictEqual(web.status, 401);
});

test("A · solicitud Custom desde la web: cabecera, líneas, total, confirmación, stock y log", async () => {
  const antes = (await api("/modelos/pulse/stock")).datos.stock;
  const r = await api("/solicitudes", { metodo: "POST", body: {
    nombre: "Club Prueba", email: "prueba@example.com", tipo_cliente: "club", modelo: "pulse",
    tallas: [{ talla: 40, cantidad: 3 }, { talla: 42, cantidad: 2 }],
    colores: { cuerpo: "Rojo", franja: "Blanco", puntera: "Rojo", talon: "Blanco", suela: "Negro", cordones: "Blanco" },
    texto_suela: "test" } });
  assert.strictEqual(r.status, 201, JSON.stringify(r.datos));
  assert.strictEqual(r.datos.estado, "pendiente");
  assert.strictEqual(r.datos.tipo, "custom");
  assert.strictEqual(r.datos.total, 5 * (109 + 15 + 5)); // calculado por el trigger
  const ref = r.datos.referencia;

  const det = await api("/pedidos/" + ref, { token: comercial });
  assert.strictEqual(det.datos.lineas.length, 2);
  const conf = await api(`/pedidos/${ref}/estado`, { metodo: "PATCH", token: comercial, body: { estado: "confirmado" } });
  assert.strictEqual(conf.status, 200);
  const despues = (await api("/modelos/pulse/stock")).datos.stock;
  const s = (l, t) => l.find((x) => x.talla === t).stock_disponible;
  assert.strictEqual(s(despues, 40), s(antes, 40) - 3);
  assert.strictEqual(s(despues, 42), s(antes, 42) - 2);

  const aud = await api("/auditoria?limite=20", { token: admin });
  const ev = aud.datos.filas.find((e) => e.tabla === "pedidos" && e.resumen.includes("confirmado") && e.usuario === "comercial1");
  assert.ok(ev && ev.fecha, "evento de confirmación con usuario y fecha");
  const alta = aud.datos.filas.find((e) => e.tabla === "pedidos" && e.operacion === "INSERT" && e.usuario === "web_publica");
  assert.ok(alta, "el alta queda auditada con el usuario técnico web_publica");

  // C · cancelar un confirmado devuelve el stock
  const canc = await api(`/pedidos/${ref}/estado`, { metodo: "PATCH", token: comercial, body: { estado: "cancelado" } });
  assert.strictEqual(canc.status, 200);
  const fin = (await api("/modelos/pulse/stock")).datos.stock;
  assert.strictEqual(s(fin, 40), s(antes, 40));
});

test("B · confirmar sin stock suficiente: rechazo sin cambios parciales", async () => {
  const antes = (await api("/modelos/aero/stock")).datos.stock;
  const r = await api("/pedidos", { metodo: "POST", token: comercial, body: { id_cliente: 1, lineas: [
    { modelo: "aero", talla: 40, cantidad: 1 }, { modelo: "aero", talla: 38, cantidad: 5 } ] } }); // talla 38 tiene 0
  assert.strictEqual(r.status, 201);
  const conf = await api(`/pedidos/${r.datos.referencia}/estado`, { metodo: "PATCH", token: comercial, body: { estado: "confirmado" } });
  assert.strictEqual(conf.status, 409);
  assert.match(conf.datos.error, /Stock insuficiente/);
  const despues = (await api("/modelos/aero/stock")).datos.stock;
  assert.deepStrictEqual(despues, antes); // ni siquiera la talla 40 se ha descontado
  const det = await api("/pedidos/" + r.datos.referencia, { token: comercial });
  assert.strictEqual(det.datos.estado, "pendiente");
});

test("permisos aplicados en la BD aunque se llame a la API directamente", async () => {
  const r = await api("/pedidos", { metodo: "POST", token: almacen, body: { id_cliente: 1, lineas: [{ modelo: "court", talla: 40, cantidad: 1 }] } });
  assert.strictEqual(r.status, 403);
  const aud = await api("/auditoria", { token: comercial });
  assert.strictEqual(aud.status, 403);
  const js = await api("/usuarios/exportar-json", { metodo: "POST", token: comercial });
  assert.strictEqual(js.status, 403);
  const sinToken = await api("/pedidos");
  assert.strictEqual(sinToken.status, 401);
});

test("E/F/G · consultas con filtros, sin coincidencias, limpiar y TXT al instante", async () => {
  const n0 = lineasTxt();
  const todos = await api("/pedidos", { token: comercial });
  const filtrado = await api("/pedidos?cliente=halcones&estado=confirmado", { token: comercial });
  const vacio = await api("/pedidos?cliente=zzzz_no_existe", { token: comercial });
  assert.ok(todos.datos.filas.length > filtrado.datos.filas.length);
  assert.ok(filtrado.datos.filas.every((p) => p.estado === "confirmado" && /halcones/i.test(p.cliente)));
  assert.strictEqual(vacio.datos.filas.length, 0);
  const limpio = await api("/pedidos?limpiar=1", { token: comercial });
  assert.strictEqual(limpio.datos.filas.length, todos.datos.filas.length);
  assert.strictEqual(lineasTxt(), n0 + 4); // una línea por consulta, visible ya en disco
  const ultimas = fs.readFileSync(TXT, "utf8").trim().split("\n").slice(-4);
  assert.match(ultimas[2], /resultado=vacio .*filas=0/);
  assert.ok(!fs.readFileSync(TXT, "utf8").includes("Admin#2026"), "el TXT no contiene contraseñas");
});

test("H/J · indicadores coherentes y CSV filtrado igual a la tabla", async () => {
  const ind = await api("/indicadores", { token: comercial });
  const i = ind.datos.indicadores;
  const estados = i.pedidos_pendiente + i.pedidos_confirmado + i.pedidos_entregado + i.pedidos_cancelado;
  assert.strictEqual(estados, i.pedidos_totales);
  const tabla = await api("/pedidos?estado=confirmado", { token: comercial });
  const csv = await api("/pedidos/export.csv?estado=confirmado", { token: comercial });
  const filas = csv.datos.replace(/^﻿/, "").trim().split("\n");
  assert.strictEqual(filas[0], "referencia,fecha,cliente,estado,tipo,pares,total");
  assert.strictEqual(filas.length - 1, tabla.datos.filas.length);
});

test("I · crear y desactivar usuario actualiza usuarios_sneaker.json", async () => {
  const nombre = "prueba" + Date.now() % 100000;
  const c = await api("/usuarios", { metodo: "POST", token: admin, body: { username: nombre, password: "Prueba#2026", rol: "Comercial" } });
  assert.strictEqual(c.status, 201);
  let lista = JSON.parse(fs.readFileSync(JSONF, "utf8"));
  const u = lista.find((x) => x.username === nombre);
  assert.ok(u && u.activo === true);
  assert.ok(!JSON.stringify(lista).includes("password"), "sin contraseñas ni hashes");
  await api("/usuarios/" + u.id_usuario, { metodo: "PATCH", token: admin, body: { activo: false } });
  lista = JSON.parse(fs.readFileSync(JSONF, "utf8"));
  assert.strictEqual(lista.find((x) => x.username === nombre).activo, false);
  assert.ok(lista.find((x) => x.username === "admin"), "no se pierden los demás usuarios");
  const dup = await api("/usuarios", { metodo: "POST", token: admin, body: { username: nombre, password: "Prueba#2026", rol: "Comercial" } });
  assert.strictEqual(dup.status, 409);
});

test("validación de la web: datos incorrectos no crean nada", async () => {
  const r = await api("/solicitudes", { metodo: "POST", body: { nombre: "X", email: "mal", modelo: "court", tallas: [{ talla: 50, cantidad: 1 }] } });
  assert.strictEqual(r.status, 400);
});

test("exportación del contrato CSV para PSP y Python", async () => {
  const r = await api("/exportar-contrato", { metodo: "POST", token: comercial });
  assert.strictEqual(r.status, 200);
  assert.strictEqual(r.datos.ficheros.length, 7);
  const ficha = fs.readFileSync(path.join(__dirname, "..", "data", "export", "ficha_fabricacion.csv"), "utf8");
  assert.match(ficha, /^referencia,cliente,modelo,/);
  assert.match(ficha, /SO003,Club Halcones/);
});
