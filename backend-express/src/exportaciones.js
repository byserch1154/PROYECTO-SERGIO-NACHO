/* =============================================================
   Exportaciones a ficheros: CSV (UTF-8 con cabecera) y JSON de usuarios
   -------------------------------------------------------------
   Escritura SEGURA: se escribe un fichero temporal y después se renombra
   (rename es atómico en el mismo disco). Así PSP / Python nunca leen un
   fichero a medio escribir y, si hay un error, el anterior sigue intacto.
============================================================= */
const fs = require("fs");
const path = require("path");
const { exportDir, usuariosJson } = require("./config");

function escribirSeguro(destino, contenido) {
  fs.mkdirSync(path.dirname(destino), { recursive: true });
  const tmp = destino + ".tmp-" + process.pid + "-" + Date.now();
  fs.writeFileSync(tmp, contenido, { encoding: "utf8" });
  fs.renameSync(tmp, destino);
}

const celdaCsv = (v) => {
  if (v === null || v === undefined) return "";
  const s = v instanceof Date ? v.toISOString() : String(v);
  return /[",\n\r]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
};

function aCsv(campos, filas) {
  const lineas = [campos.join(",")];
  for (const f of filas) lineas.push(campos.map((c) => celdaCsv(f[c])).join(","));
  return lineas.join("\n") + "\n";
}

// Mismas vistas y columnas que bd/05_exportar_csv.sql (contrato con PSP y Python)
const CONTRATO = [
  ["ficha_fabricacion.csv", "SELECT * FROM v_ficha_fabricacion"],
  ["clientes.csv", "SELECT * FROM v_export_clientes ORDER BY 1"],
  ["modelos.csv", "SELECT * FROM v_export_modelos ORDER BY 1"],
  ["pedidos.csv", "SELECT * FROM v_export_pedidos ORDER BY 1"],
  ["lineas_pedido.csv", "SELECT * FROM v_export_lineas_pedido ORDER BY 1"],
  ["stock.csv", "SELECT * FROM v_export_stock ORDER BY 1, 2"],
  ["reconciliacion_sql.csv", "SELECT * FROM v_reconciliacion"],   // cifras de control para Python
];

// Lee TODAS las vistas dentro de la misma transacción REPEATABLE READ (instantánea coherente)
async function exportarContrato(cliente) {
  const resultados = [];
  for (const [fichero, sql] of CONTRATO) {
    const r = await cliente.query(sql);
    resultados.push([fichero, aCsv(r.fields.map((f) => f.name), r.rows), r.rowCount]);
  }
  // Solo se escriben si TODAS las consultas han ido bien
  for (const [fichero, csv] of resultados) escribirSeguro(path.join(exportDir, fichero), csv);
  return resultados.map(([fichero, , filas]) => ({ fichero, filas }));
}

// usuarios_sneaker.json: lista estable de objetos, SIN contraseñas ni hashes
async function exportarUsuariosJson(cliente) {
  const r = await cliente.query("SELECT * FROM fn_listar_usuarios()");
  const usuarios = r.rows.map((u) => ({
    id_usuario: u.id_usuario,
    username: u.username,
    rol: u.rol,
    activo: u.activo,
    fecha_creacion: new Date(u.fecha_creacion).toISOString(),
  }));
  const texto = JSON.stringify(usuarios, null, 2) + "\n";
  JSON.parse(texto); // comprobación: el JSON se puede volver a leer
  escribirSeguro(usuariosJson, texto);
  return usuarios.length;
}

module.exports = { aCsv, escribirSeguro, exportarContrato, exportarUsuariosJson };
