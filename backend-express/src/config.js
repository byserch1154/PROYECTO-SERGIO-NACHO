// Configuración leída de .env (nunca hay credenciales en el código)
const path = require("path");
require("dotenv").config({ path: path.join(__dirname, "..", ".env") });

const raiz = path.join(__dirname, "..");
const ruta = (v, porDefecto) => path.resolve(raiz, process.env[v] || porDefecto);

module.exports = {
  puerto: Number(process.env.PORT || 3000),
  webDir: ruta("WEB_DIR", "../lenguaje-de-marcas"),
  panelDir: path.join(raiz, "panel"),
  logDir: ruta("LOG_DIR", "./logs"),
  exportDir: ruta("EXPORT_DIR", "./data/export"),
  usuariosJson: ruta("USUARIOS_JSON", "./data/usuarios_sneaker.json"),
  sesionMinutos: Number(process.env.SESION_MINUTOS || 120),
  // pg lee PGHOST, PGPORT, PGDATABASE, PGUSER y PGPASSWORD del entorno
};
