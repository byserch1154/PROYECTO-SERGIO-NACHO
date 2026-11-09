-- =====================================================================
-- 08_exportar_reconciliacion.sql · Cifras SQL para conciliar con Python
-- Ejecutar con psql junto a 05_exportar_csv.sql (misma exportación):
--   psql -d sneaker_factory -f 08_exportar_reconciliacion.sql
-- Python (df12_reconciliacion) compara estas cifras con las calculadas
-- con pandas a partir de los CSV. Regla de ventas: confirmado + entregado.
-- =====================================================================
\encoding UTF8
\copy (SELECT * FROM v_reconciliacion) TO 'export/reconciliacion_sql.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
