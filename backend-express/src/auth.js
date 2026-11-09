/* =============================================================
   Autenticación del panel de gestión
   -------------------------------------------------------------
   · La contraseña se comprueba EN PostgreSQL con fn_login() (bcrypt +
     sal, pgcrypto). Node nunca ve ni guarda el hash.
   · Tras el login se genera un token aleatorio (crypto.randomBytes) que el
     navegador envía en la cabecera Authorization: Bearer <token>.
   · El token solo identifica la sesión. Los PERMISOS se comprueban en la
     base de datos en cada operación (fn_exigir_permiso), así que aunque
     alguien manipule la interfaz o llame a la API a mano, no puede hacer
     nada que su rol no tenga permitido.
============================================================= */
const crypto = require("crypto");
const { consulta } = require("./db");
const { sesionMinutos } = require("./config");

const sesiones = new Map(); // token -> { id, usuario, rol, caduca }

async function login(username, password) {
  const r = await consulta(
    `SELECT u.id_usuario, u.username, r.nombre AS rol
       FROM usuarios u JOIN roles r USING (id_rol)
      WHERE u.id_usuario = fn_login($1, $2) AND r.nombre <> 'Web'`,
    [username, password]
  );
  if (!r.rows.length) return null;
  const u = r.rows[0];
  const token = crypto.randomBytes(32).toString("hex");
  sesiones.set(token, { id: u.id_usuario, usuario: u.username, rol: u.rol, caduca: Date.now() + sesionMinutos * 60000 });
  return { token, usuario: u.username, rol: u.rol, id: u.id_usuario };
}

function logout(token) { sesiones.delete(token); }

// Middleware: exige una sesión válida
function requiereSesion(req, res, next) {
  const cab = req.headers.authorization || "";
  const token = cab.startsWith("Bearer ") ? cab.slice(7) : null;
  const s = token && sesiones.get(token);
  if (!s || s.caduca < Date.now()) {
    if (token) sesiones.delete(token);
    return res.status(401).json({ error: "Inicia sesión para continuar." });
  }
  s.caduca = Date.now() + sesionMinutos * 60000; // renovación por actividad
  req.sesion = s;
  req.token = token;
  next();
}

// Permisos del rol (solo para pintar la interfaz; la BD vuelve a comprobarlos)
async function permisosDe(idUsuario) {
  const r = await consulta(
    `SELECT p.operacion, p.permitido FROM usuarios u JOIN permisos p USING (id_rol)
      WHERE u.id_usuario = $1 ORDER BY p.operacion`, [idUsuario]);
  return Object.fromEntries(r.rows.map((x) => [x.operacion, x.permitido]));
}

module.exports = { login, logout, requiereSesion, permisosDe };
