/* =============================================================
   Acceso a PostgreSQL con el driver "pg" (equivalente a JDBC en Node)
   -------------------------------------------------------------
   · Todas las consultas son PARAMETRIZADAS ($1, $2...): los valores del
     usuario nunca se concatenan en el SQL (equivale a PreparedStatement).
   · comoUsuario(id, fn) abre una TRANSACCIÓN, propaga la identidad con
       SELECT set_config('app.id_usuario', $1, true)
     (true = solo vive hasta COMMIT/ROLLBACK, seguro con el pool) y
     ejecuta fn. Si algo falla => ROLLBACK de todo (datos + auditoría).
   · La conexión siempre se devuelve al pool (finally = cierre de recursos).
============================================================= */
const { Pool } = require("pg");

const pool = new Pool({ max: 10, idleTimeoutMillis: 30000 });

// Las fechas DATE se devuelven como texto 'YYYY-MM-DD' (sin desfases de zona horaria)
require("pg").types.setTypeParser(1082, (v) => v);

async function comoUsuario(idUsuario, fn, { instantanea = false } = {}) {
  const cliente = await pool.connect();
  try {
    // instantanea = REPEATABLE READ: todas las lecturas ven la misma foto de los datos
    await cliente.query(instantanea ? "BEGIN ISOLATION LEVEL REPEATABLE READ" : "BEGIN");
    await cliente.query("SELECT set_config('app.id_usuario', $1, true)", [String(idUsuario)]);
    const resultado = await fn(cliente);
    await cliente.query("COMMIT");
    return resultado;
  } catch (err) {
    try { await cliente.query("ROLLBACK"); } catch (_) { /* conexión rota */ }
    throw err;
  } finally {
    cliente.release();
  }
}

// Consultas sin identidad (login y catálogo público)
const consulta = (sql, params) => pool.query(sql, params);

module.exports = { pool, comoUsuario, consulta };
