/* Traduce los errores de PostgreSQL a mensajes comprensibles + código HTTP.
   Los permisos y reglas se comprueban EN LA BASE DE DATOS (triggers y
   funciones); aquí solo se presenta el mensaje al usuario. */
function traducirError(err) {
  const codigo = err && err.code;
  const msg = (err && err.message) || "Error desconocido";
  switch (codigo) {
    case "42501": return { http: 403, resultado: "rechazado", mensaje: msg };            // permiso denegado
    case "28000": return { http: 401, resultado: "rechazado", mensaje: "Sesión no válida: vuelve a iniciar sesión." };
    case "23514": return { http: 409, resultado: "rechazado", mensaje: msg.startsWith("Stock") ? msg : "Dato no válido: " + msg };
    case "23503": return { http: 400, resultado: "rechazado", mensaje: "Referencia inexistente (cliente, modelo o pedido)." };
    case "23505": return { http: 409, resultado: "rechazado", mensaje: "Ya existe un registro con esos datos." };
    case "22P02":
    case "22007":
    case "22008": return { http: 400, resultado: "rechazado", mensaje: "Formato de dato incorrecto." };
    case "P0001": return { http: 400, resultado: "rechazado", mensaje: msg };            // RAISE EXCEPTION de los triggers
    case "ECONNREFUSED":
    case "57P01":
    case "08006": return { http: 503, resultado: "error", mensaje: "No hay conexión con la base de datos." };
    default:
      if (err && err.publico) return { http: err.http || 400, resultado: "rechazado", mensaje: msg };
      return { http: 500, resultado: "error", mensaje: "Error interno: " + msg };
  }
}

// Error de validación propio (antes de llegar a la BD)
function errorPublico(mensaje, http = 400) {
  const e = new Error(mensaje);
  e.publico = true;
  e.http = http;
  return e;
}

module.exports = { traducirError, errorPublico };
