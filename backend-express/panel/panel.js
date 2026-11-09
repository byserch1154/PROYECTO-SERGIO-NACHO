/* =============================================================
   Panel de gestión SPEAKE
   · Mostrar u ocultar botones según el rol es solo COMODIDAD: la API y
     PostgreSQL vuelven a comprobar el permiso en cada operación.
   · Todo el texto se inserta con textContent (sin innerHTML con datos)
     para evitar inyección de HTML.
============================================================= */
(function () {
  "use strict";
  const $ = (id) => document.getElementById(id);
  const TALLAS = [38, 39, 40, 41, 42, 43, 44, 45, 46];
  const COLORES = ["Negro", "Blanco", "Azul eléctrico", "Rojo", "Verde", "Amarillo", "Naranja", "Gris"];
  const PARTES = [["cuerpo", "Cuerpo"], ["franja", "Franja"], ["puntera", "Puntera"], ["talon", "Talón"], ["suela", "Suela"], ["cordones", "Cordones"]];
  const euros = (n) => Number(n || 0).toLocaleString("es-ES", { style: "currency", currency: "EUR" });

  let token = null;
  try { token = sessionStorage.getItem("speake_token"); } catch (_) { /* sin storage */ }
  let permisos = {};
  let pedidoAbierto = null;
  let odooActivo = false;

  // -------------------------------------------------- utilidades
  function mensaje(texto, tipo) {
    const m = $("msg");
    m.textContent = texto || "";
    m.className = "msg global " + (tipo || "");
  }

  async function api(ruta, opciones = {}) {
    const cab = { "Content-Type": "application/json" };
    if (token) cab.Authorization = "Bearer " + token;
    let resp;
    try {
      resp = await fetch("/api" + ruta, { ...opciones, headers: cab, body: opciones.body ? JSON.stringify(opciones.body) : undefined });
    } catch (e) {
      throw new Error("No se puede conectar con el servidor.");
    }
    if (resp.status === 401 && ruta !== "/login") { salir(true); throw new Error("La sesión ha caducado."); }
    const datos = (resp.headers.get("content-type") || "").includes("json") ? await resp.json() : await resp.text();
    if (!resp.ok) throw new Error((datos && datos.error) || "Error " + resp.status);
    return datos;
  }

  function celda(tr, texto, clase) {
    const td = document.createElement("td");
    if (clase) td.className = clase;
    td.textContent = texto == null ? "" : texto;
    tr.appendChild(td);
    return td;
  }

  function vaciar(tbody, columnas, texto) {
    tbody.textContent = "";
    if (texto) {
      const tr = document.createElement("tr");
      const td = celda(tr, texto);
      td.colSpan = columnas;
      td.className = "nota";
      tbody.appendChild(tr);
    }
  }

  function aplicarPermisos() {
    document.querySelectorAll("[data-permiso]").forEach((el) => {
      el.hidden = !permisos[el.dataset.permiso];
    });
    document.querySelectorAll("[data-permiso-bloque]").forEach((el) => {
      el.hidden = !permisos[el.dataset.permisoBloque];
    });
  }

  // -------------------------------------------------- sesión
  async function entrar(e) {
    e.preventDefault();
    $("login-msg").textContent = "";
    try {
      const r = await api("/login", { method: "POST", body: { usuario: $("l-usuario").value, password: $("l-pass").value } });
      token = r.token;
      try { sessionStorage.setItem("speake_token", token); } catch (_) {}
      $("l-pass").value = "";
      iniciarApp(r);
    } catch (err) {
      $("login-msg").textContent = err.message;
    }
  }

  function salir(caducada) {
    if (token && !caducada) api("/logout", { method: "POST" }).catch(() => {});
    token = null;
    try { sessionStorage.removeItem("speake_token"); } catch (_) {}
    $("vista-app").hidden = true;
    $("sesion-info").hidden = true;
    $("vista-login").hidden = false;
    if (caducada) $("login-msg").textContent = "La sesión ha caducado. Vuelve a entrar.";
  }

  async function iniciarApp(info) {
    permisos = info.permisos || {};
    $("quien").textContent = info.usuario + " · " + info.rol;
    $("vista-login").hidden = true;
    $("vista-app").hidden = false;
    $("sesion-info").hidden = false;
    aplicarPermisos();
    cambiarTab("pedidos");
    await cargarCatalogo();
    comprobarOdoo();
    if (permisos.consultar_pedidos) buscar(false);
    else mensaje("Tu rol no tiene permiso para consultar pedidos.", "err");
  }

  async function comprobarOdoo() {
    try {
      const o = await api("/odoo/estado");
      odooActivo = o.activo;
      $("info-odoo").textContent = !o.activo
        ? "Odoo: integración no configurada (los pedidos solo se guardan en SPEAKE)."
        : o.conectado
          ? "Odoo: conectado a " + o.db + ". Al confirmar un pedido se crea en Odoo."
          : "Odoo: sin conexión (" + o.error + "). Los pedidos confirmados se podrán reenviar después.";
    } catch (err) {
      $("info-odoo").textContent = "";
    }
  }

  // -------------------------------------------------- pestañas
  function cambiarTab(nombre) {
    document.querySelectorAll(".tabs button").forEach((b) => b.setAttribute("aria-selected", b.dataset.tab === nombre));
    document.querySelectorAll(".panel").forEach((p) => { p.hidden = p.id !== "tab-" + nombre; });
    mensaje("");
    if (nombre === "indicadores") cargarIndicadores();
    if (nombre === "usuarios") cargarUsuarios();
    if (nombre === "nuevo") cargarClientes();
  }

  // -------------------------------------------------- catálogo
  let modelos = [];
  async function cargarCatalogo() {
    const r = await api("/modelos");
    modelos = r.modelos;
    [$("f-modelo"), $("n-modelo")].forEach((sel, i) => {
      sel.textContent = "";
      if (i === 0) sel.appendChild(new Option("Todos", ""));
      modelos.forEach((m) => sel.appendChild(new Option(m.nombre, m.codigo)));
    });
  }

  // -------------------------------------------------- pedidos
  function filtros() {
    return { cliente: $("f-cliente").value.trim(), modelo: $("f-modelo").value, estado: $("f-estado").value, desde: $("f-desde").value, hasta: $("f-hasta").value };
  }
  const qs = (o) => new URLSearchParams(Object.entries(o).filter(([, v]) => v)).toString();

  async function buscar(limpiar) {
    const tbody = $("tabla-pedidos").querySelector("tbody");
    vaciar(tbody, 8, "Consultando…"); // nunca se muestran datos antiguos
    $("info-pedidos").textContent = "";
    try {
      const f = filtros();
      const r = await api("/pedidos?" + qs({ ...f, limpiar: limpiar ? "1" : "" }));
      vaciar(tbody, 8, r.filas.length ? "" : "No hay pedidos que coincidan con los filtros.");
      r.filas.forEach((p) => {
        const tr = document.createElement("tr");
        celda(tr, p.referencia);
        celda(tr, p.fecha);
        celda(tr, p.cliente);
        const td = celda(tr, "");
        const s = document.createElement("span");
        s.className = "estado estado-" + p.estado;
        s.textContent = p.estado;
        td.appendChild(s);
        celda(tr, p.tipo);
        celda(tr, p.pares, "num");
        celda(tr, euros(p.total), "num");
        celda(tr, textoOdoo(p.odoo), p.odoo && p.odoo.estado === "error" ? "odoo-error" : "");
        tr.addEventListener("click", () => abrirPedido(p.referencia));
        tbody.appendChild(tr);
      });
      const n = r.filas.length;
      $("info-pedidos").textContent = n + (n === 1 ? " pedido" : " pedidos") + " · consultado " + new Date(r.consultado).toLocaleTimeString("es-ES");
    } catch (err) {
      vaciar(tbody, 8, "");
      mensaje(err.message, "err");
    }
  }

  // Odoo: "S00012", "error" o "—" si aún no se ha enviado
  function textoOdoo(o) {
    if (!o) return "—";
    return o.estado === "enviado" ? o.pedido_odoo : "error";
  }

  async function abrirPedido(ref) {
    try {
      const p = await api("/pedidos/" + encodeURIComponent(ref));
      pedidoAbierto = p;
      $("d-titulo").textContent = p.referencia + " · " + p.cliente;
      $("d-resumen").textContent = "Fecha " + p.fecha + " · Estado " + p.estado + " · Tipo " + p.tipo + " · Total " + euros(p.total) +
        " · " + p.lineas.reduce((s, l) => s + l.cantidad, 0) + " pares";
      const tb = $("d-lineas").querySelector("tbody");
      vaciar(tb, 6, p.lineas.length ? "" : "Sin líneas");
      p.lineas.forEach((l) => {
        const tr = document.createElement("tr");
        celda(tr, l.modelo); celda(tr, l.talla, "num"); celda(tr, l.cantidad, "num");
        celda(tr, euros(l.precio_unitario), "num"); celda(tr, l.personalizacion || "—"); celda(tr, l.texto_suela || "");
        tb.appendChild(tr);
      });
      const o = p.odoo;
      $("d-odoo").textContent = !o ? "Odoo: todavía no enviado (se envía al confirmar)."
        : o.estado === "enviado" ? "Odoo: pedido de venta " + o.pedido_odoo + " (" + o.mensaje + ")."
        : "Odoo: no se pudo enviar · " + o.mensaje;
      $("d-odoo-btn").hidden = !(odooActivo && ["confirmado", "entregado"].includes(p.estado) && !(o && o.estado === "enviado"));
      // Solo se ofrecen las transiciones válidas (la BD también las valida)
      const validas = { pendiente: ["confirmado", "cancelado"], confirmado: ["entregado", "cancelado"] }[p.estado] || [];
      document.querySelectorAll("#detalle [data-estado]").forEach((b) => { b.disabled = !validas.includes(b.dataset.estado); });
      $("detalle").hidden = false;
      $("detalle").scrollIntoView({ behavior: "smooth", block: "nearest" });
    } catch (err) { mensaje(err.message, "err"); }
  }

  async function cambiarEstado(estado) {
    if (!pedidoAbierto) return;
    try {
      const r = await api("/pedidos/" + pedidoAbierto.referencia + "/estado", { method: "PATCH", body: { estado } });
      let texto = r.referencia + " ahora está " + r.estado + ". El stock y la auditoría los ha actualizado PostgreSQL.";
      if (r.odoo) {
        texto += r.odoo.estado === "enviado" ? " Enviado a Odoo como " + r.odoo.pedido_odoo + "."
          : " No se pudo enviar a Odoo: " + r.odoo.mensaje;
      }
      mensaje(texto, r.odoo && r.odoo.estado === "error" ? "err" : "ok");
      await abrirPedido(r.referencia);
      buscar(false);
    } catch (err) { mensaje(err.message, "err"); }
  }

  async function reenviarOdoo() {
    if (!pedidoAbierto) return;
    try {
      const r = await api("/pedidos/" + pedidoAbierto.referencia + "/odoo", { method: "POST" });
      mensaje(pedidoAbierto.referencia + " enviado a Odoo como " + r.pedido_odoo + ".", "ok");
    } catch (err) { mensaje(err.message, "err"); }
    await abrirPedido(pedidoAbierto.referencia);
    buscar(false);
  }

  async function descargarCsv() {
    try {
      const resp = await fetch("/api/pedidos/export.csv?" + qs(filtros()), { headers: { Authorization: "Bearer " + token } });
      if (!resp.ok) throw new Error((await resp.json()).error);
      const blob = await resp.blob();
      const a = document.createElement("a");
      a.href = URL.createObjectURL(blob);
      a.download = "pedidos_filtrados.csv";
      a.click();
      URL.revokeObjectURL(a.href);
      mensaje("CSV descargado con los mismos filtros que la tabla.", "ok");
    } catch (err) { mensaje(err.message, "err"); }
  }

  async function exportarContrato() {
    try {
      const r = await api("/exportar-contrato", { method: "POST" });
      mensaje("Exportados: " + r.ficheros.map((f) => f.fichero + " (" + f.filas + ")").join(", "), "ok");
    } catch (err) { mensaje(err.message, "err"); }
  }

  // -------------------------------------------------- nuevo pedido
  async function cargarClientes() {
    try {
      const r = await api("/clientes");
      const sel = $("n-cliente");
      sel.textContent = "";
      r.filas.forEach((c) => sel.appendChild(new Option(c.nombre + " (" + c.tipo + ")", c.id_cliente)));
    } catch (err) { mensaje(err.message, "err"); }
  }

  function construirNuevo() {
    const t = $("n-tallas");
    TALLAS.forEach((n) => {
      const d = document.createElement("div");
      const l = document.createElement("label");
      l.textContent = "T" + n; l.htmlFor = "n-t" + n;
      const i = document.createElement("input");
      i.type = "number"; i.min = "0"; i.max = "500"; i.id = "n-t" + n; i.dataset.talla = n; i.placeholder = "0";
      d.append(l, i); t.appendChild(d);
    });
    const c = $("n-colores");
    PARTES.forEach(([id, txt]) => {
      const d = document.createElement("div");
      const l = document.createElement("label");
      l.textContent = txt; l.htmlFor = "n-c-" + id;
      const s = document.createElement("select");
      s.id = "n-c-" + id;
      COLORES.forEach((co) => s.appendChild(new Option(co, co)));
      d.append(l, s); c.appendChild(d);
    });
    $("n-custom").addEventListener("change", (e) => { $("n-colores").hidden = !e.target.checked; $("n-texto-wrap").hidden = !e.target.checked; });
  }

  async function crearPedido(e) {
    e.preventDefault();
    const custom = $("n-custom").checked;
    const colores = custom ? Object.fromEntries(PARTES.map(([id]) => [id, $("n-c-" + id).value])) : null;
    const lineas = [...document.querySelectorAll("#n-tallas input")]
      .filter((i) => parseInt(i.value, 10) > 0)
      .map((i) => ({ modelo: $("n-modelo").value, talla: i.dataset.talla, cantidad: i.value, colores, texto_suela: custom ? $("n-texto").value : "" }));
    try {
      const r = await api("/pedidos", { method: "POST", body: { id_cliente: $("n-cliente").value, lineas } });
      mensaje("Pedido " + r.referencia + " creado (" + r.tipo + ", " + euros(r.total) + "). Queda pendiente de confirmar.", "ok");
      document.querySelectorAll("#n-tallas input").forEach((i) => { i.value = ""; });
    } catch (err) { mensaje(err.message, "err"); }
  }

  // -------------------------------------------------- indicadores
  async function cargarIndicadores() {
    try {
      const r = await api("/indicadores");
      const i = r.indicadores;
      const k = $("kpis");
      k.textContent = "";
      [["Pedidos totales", i.pedidos_totales], ["Pares solicitados", i.pares_solicitados], ["Pares vendidos", i.pares_vendidos],
       ["Ventas", euros(i.importe_ventas)], ["Pendientes", i.pedidos_pendiente], ["Confirmados", i.pedidos_confirmado],
       ["Entregados", i.pedidos_entregado], ["Cancelados", i.pedidos_cancelado]].forEach(([t, v]) => {
        const d = document.createElement("div"); d.className = "kpi";
        const s = document.createElement("span"); s.textContent = t;
        const st = document.createElement("strong"); st.textContent = v;
        d.append(s, st); k.appendChild(d);
      });
      $("regla-ventas").textContent = r.regla_ventas + ". «Pares solicitados» = pares de todos los pedidos no cancelados.";
      const tb = $("t-modelos").querySelector("tbody");
      vaciar(tb, 4);
      r.modelos.forEach((m) => { const tr = document.createElement("tr"); celda(tr, m.modelo); celda(tr, m.pedidos, "num"); celda(tr, m.pares, "num"); celda(tr, euros(m.importe), "num"); tb.appendChild(tr); });
      const max = Math.max(1, ...r.tallas.map((t) => t.pares));
      const b = $("barras-tallas");
      b.textContent = "";
      r.tallas.forEach((t) => {
        const f = document.createElement("div"); f.className = "barra-fila";
        const a = document.createElement("span"); a.textContent = t.talla;
        const barra = document.createElement("div"); barra.style.width = (100 * t.pares / max) + "%";
        const c = document.createElement("span"); c.textContent = t.pares;
        f.append(a, barra, c); b.appendChild(f);
      });
      if (permisos.consultar_stock) cargarStock();
    } catch (err) { mensaje(err.message, "err"); }
  }

  async function cargarStock(e) {
    if (e) e.preventDefault();
    const tb = $("t-stock").querySelector("tbody");
    try {
      const r = await api("/stock-bajo?umbral=" + encodeURIComponent($("s-umbral").value || 5));
      vaciar(tb, 3, r.filas.length ? "" : "Ninguna variante por debajo del umbral.");
      r.filas.forEach((s) => { const tr = document.createElement("tr"); celda(tr, s.modelo); celda(tr, s.talla, "num"); celda(tr, s.stock_disponible, "num"); tb.appendChild(tr); });
    } catch (err) { vaciar(tb, 3); mensaje(err.message, "err"); }
  }

  // -------------------------------------------------- auditoría
  async function cargarAuditoria() {
    const tb = $("t-auditoria").querySelector("tbody");
    try {
      const r = await api("/auditoria?limite=100");
      vaciar(tb, 7, r.filas.length ? "" : "Sin eventos.");
      r.filas.forEach((ev) => {
        const tr = document.createElement("tr");
        celda(tr, ev.id_evento); celda(tr, new Date(ev.fecha).toLocaleString("es-ES")); celda(tr, ev.tabla); celda(tr, ev.operacion);
        celda(tr, ev.id_registro); celda(tr, ev.usuario);
        const td = celda(tr, ev.resumen.length > 110 ? ev.resumen.slice(0, 110) + "…" : ev.resumen);
        td.title = ev.resumen; td.style.whiteSpace = "normal";
        tb.appendChild(tr);
      });
    } catch (err) { vaciar(tb, 7); mensaje(err.message, "err"); }
  }

  // -------------------------------------------------- usuarios
  async function cargarUsuarios() {
    const tb = $("t-usuarios").querySelector("tbody");
    try {
      const r = await api("/usuarios");
      vaciar(tb, 5);
      r.filas.forEach((u) => {
        const tr = document.createElement("tr");
        celda(tr, u.id_usuario); celda(tr, u.username); celda(tr, u.rol); celda(tr, u.activo ? "Sí" : "No");
        const td = celda(tr, "");
        if (u.rol !== "Web") {
          const b = document.createElement("button");
          b.type = "button"; b.className = "btn btn-sec"; b.style.marginTop = "0";
          b.textContent = u.activo ? "Desactivar" : "Activar";
          b.addEventListener("click", () => modificarUsuario(u.id_usuario, { activo: !u.activo }));
          const s = document.createElement("select");
          s.style.width = "auto"; s.style.marginLeft = "6px";
          ["Administrador", "Comercial", "Almacén"].forEach((x) => s.appendChild(new Option(x, x, false, x === u.rol)));
          s.addEventListener("change", () => modificarUsuario(u.id_usuario, { rol: s.value }));
          td.append(b, s);
        }
        tb.appendChild(tr);
      });
    } catch (err) { vaciar(tb, 5); mensaje(err.message, "err"); }
  }

  async function modificarUsuario(id, cambios) {
    try {
      await api("/usuarios/" + id, { method: "PATCH", body: cambios });
      mensaje("Usuario actualizado. usuarios_sneaker.json se ha regenerado automáticamente.", "ok");
    } catch (err) { mensaje(err.message, "err"); }
    cargarUsuarios();
  }

  async function crearUsuario(e) {
    e.preventDefault();
    try {
      await api("/usuarios", { method: "POST", body: { username: $("u-nombre").value, password: $("u-pass").value, rol: $("u-rol").value } });
      $("u-nombre").value = ""; $("u-pass").value = "";
      mensaje("Usuario creado. usuarios_sneaker.json actualizado.", "ok");
      cargarUsuarios();
    } catch (err) { mensaje(err.message, "err"); }
  }

  async function exportarJson() {
    try {
      const r = await api("/usuarios/exportar-json", { method: "POST" });
      mensaje("usuarios_sneaker.json exportado con " + r.usuarios + " usuarios (sin contraseñas).", "ok");
    } catch (err) { mensaje(err.message, "err"); }
  }

  // -------------------------------------------------- eventos
  $("form-login").addEventListener("submit", entrar);
  $("btn-logout").addEventListener("click", () => salir(false));
  document.querySelectorAll(".tabs button").forEach((b) => b.addEventListener("click", () => cambiarTab(b.dataset.tab)));
  $("form-filtros").addEventListener("submit", (e) => { e.preventDefault(); buscar(false); });
  $("btn-limpiar").addEventListener("click", () => { $("form-filtros").reset(); buscar(true); });
  $("btn-csv").addEventListener("click", descargarCsv);
  $("btn-contrato").addEventListener("click", exportarContrato);
  $("d-cerrar").addEventListener("click", () => { $("detalle").hidden = true; pedidoAbierto = null; });
  document.querySelectorAll("#detalle [data-estado]").forEach((b) => b.addEventListener("click", () => cambiarEstado(b.dataset.estado)));
  $("form-nuevo").addEventListener("submit", crearPedido);
  $("d-odoo-btn").addEventListener("click", reenviarOdoo);
  $("btn-indicadores").addEventListener("click", cargarIndicadores);
  $("form-stock").addEventListener("submit", cargarStock);
  $("btn-auditoria").addEventListener("click", cargarAuditoria);
  $("btn-usuarios").addEventListener("click", cargarUsuarios);
  $("btn-json").addEventListener("click", exportarJson);
  $("form-usuario").addEventListener("submit", crearUsuario);
  construirNuevo();

  // Sesión guardada en esta pestaña
  if (token) api("/me").then((r) => iniciarApp(r)).catch(() => salir(false));
})();
