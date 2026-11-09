/* =============================================================
   Registro externo actividad_sneaker.txt (modo APPEND, UTF-8)
   -------------------------------------------------------------
   · Una línea por evento, nunca se sobrescribe lo anterior.
   · appendFileSync escribe y cierra el fichero en cada llamada: el
     contenido queda en disco al instante (sin esperar a cerrar Node).
   · NO se guardan contraseñas, hashes, tokens, emails ni SQL.
   · Diferencia con log_eventos: este TXT registra también intentos
     rechazados y errores; log_eventos solo cambios confirmados (COMMIT).
     Por eso el resultado "correcto" se escribe DESPUÉS del COMMIT.
============================================================= */
const fs = require("fs");
const path = require("path");
const { logDir } = require("./config");

fs.mkdirSync(logDir, { recursive: true });
const FICHERO = path.join(logDir, "actividad_sneaker.txt");

const limpiar = (v) => String(v ?? "").replace(/[\r\n|]+/g, " ").trim();

function registrar({ usuario = "anonimo", rol = "-", accion, resultado, detalle = "" }) {
  const linea = [
    new Date().toISOString(),
    "usuario=" + limpiar(usuario),
    "rol=" + limpiar(rol),
    "accion=" + limpiar(accion),
    "resultado=" + limpiar(resultado),     // correcto | rechazado | error | vacio
    limpiar(detalle),
  ].join(" | ");
  fs.appendFileSync(FICHERO, linea + "\n", { encoding: "utf8" });
}

// Describe los filtros sin datos sensibles (solo qué campos y valores de catálogo)
function describirFiltros(f) {
  const partes = Object.entries(f).filter(([, v]) => v !== null && v !== undefined && v !== "");
  return partes.length ? "filtros=" + partes.map(([k, v]) => `${k}:${k === "cliente" ? "[texto]" : v}`).join(",") : "filtros=ninguno";
}

module.exports = { registrar, describirFiltros, FICHERO };
