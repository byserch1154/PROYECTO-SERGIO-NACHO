-- =====================================================================
-- 05_exportar_csv.sql  ·  Exportación a CSV (UTF-8, cabeceras, coma)
-- Ejecutar con psql (usa \copy, que escribe en la carpeta de TU máquina):
--   mkdir export
--   psql -d sneaker_factory -f 05_exportar_csv.sql
-- Re-ejecutar este script = nueva exportación (lo que lee Python cada 60 s).
-- =====================================================================
\encoding UTF8

-- Para PSP: ficha de fabricación del pedido Custom
\copy (SELECT * FROM v_ficha_fabricacion) TO 'export/ficha_fabricacion.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

-- Para Python (contrato acordado con Ampliación de Python)
\copy (SELECT * FROM v_export_clientes      ORDER BY 1) TO 'export/clientes.csv'      WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy (SELECT * FROM v_export_modelos       ORDER BY 1) TO 'export/modelos.csv'       WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy (SELECT * FROM v_export_pedidos       ORDER BY 1) TO 'export/pedidos.csv'       WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy (SELECT * FROM v_export_lineas_pedido ORDER BY 1) TO 'export/lineas_pedido.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy (SELECT * FROM v_export_stock         ORDER BY 1,2) TO 'export/stock.csv'       WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
