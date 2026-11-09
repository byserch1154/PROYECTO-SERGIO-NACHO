/* =============================================================
   SPEAKE · Sneaker Factory · Servidor Express
   -------------------------------------------------------------
   http://localhost:3000/            -> web corporativa (lenguaje-de-marcas)
   http://localhost:3000/gestion/    -> panel de gestión (login por rol)
   http://localhost:3000/api/...     -> API REST conectada a PostgreSQL
   Arranque:  npm install  &&  npm start
============================================================= */
const express = require("express");
const cfg = require("./config");
const { pool } = require("./db");

const app = express();
app.disable("x-powered-by");
app.use(express.json({ limit: "100kb" }));

// Cabeceras básicas de seguridad
app.use((req, res, next) => {
  res.setHeader("X-Content-Type-Options", "nosniff");
  res.setHeader("X-Frame-Options", "DENY");
  res.setHeader("Referrer-Policy", "same-origin");
  next();
});

app.get("/api/salud", async (req, res) => {
  try {
    await pool.query("SELECT 1");
    res.json({ ok: true, bd: "conectada", hora: new Date().toISOString() });
  } catch (err) {
    res.status(503).json({ ok: false, bd: "sin conexión", error: err.code || err.message });
  }
});

app.use("/api", require("./routes/publico"));
app.use("/api", require("./routes/gestion"));
app.use("/api", (req, res) => res.status(404).json({ error: "Ruta de API no encontrada" }));

app.use("/gestion", express.static(cfg.panelDir));
app.use("/", express.static(cfg.webDir, { extensions: ["html"] }));

// JSON mal formado u otros errores de Express
app.use((err, req, res, next) => {
  if (err.type === "entity.parse.failed") return res.status(400).json({ error: "JSON mal formado" });
  console.error(err);
  res.status(500).json({ error: "Error interno" });
});

if (require.main === module) {
  app.listen(cfg.puerto, () => {
    console.log(`SPEAKE backend escuchando en http://localhost:${cfg.puerto}`);
    console.log(`  Web:     http://localhost:${cfg.puerto}/`);
    console.log(`  Gestión: http://localhost:${cfg.puerto}/gestion/`);
    console.log(`  Web servida desde: ${cfg.webDir}`);
  });
}

module.exports = app;
