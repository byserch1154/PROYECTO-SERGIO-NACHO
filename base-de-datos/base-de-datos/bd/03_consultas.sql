-- =====================================================================
-- 03_consultas.sql · Consultas SQL de explotación (12)
-- Convención: "ventas" = pedidos CONFIRMADOS + ENTREGADOS (se excluyen
-- cancelados y pendientes). Un pedido con 3 líneas cuenta como 1 pedido.
-- =====================================================================
SELECT set_config('app.id_usuario', '1', false);   -- sesión como admin (para las funciones con permisos)

-- Q01 · Búsqueda por cliente (parcial, sin distinguir mayúsculas)
SELECT p.referencia, p.fecha, c.nombre, p.estado, p.total
  FROM pedidos p JOIN clientes c USING (id_cliente)
 WHERE c.nombre ILIKE '%halcones%'
 ORDER BY p.fecha;

-- Q02 · Pedidos por estado dentro de un periodo (septiembre-octubre 2026)
SELECT estado, count(*) AS pedidos, sum(total) AS importe
  FROM pedidos
 WHERE fecha BETWEEN '2026-09-01' AND '2026-10-31'
 GROUP BY estado ORDER BY estado;

-- Q03 · JOIN de 4 tablas: detalle del pedido SO003 (caso común, 40 pares)
SELECT p.referencia, c.nombre AS cliente, m.nombre AS modelo, l.talla, l.cantidad,
       l.precio_unitario, l.cantidad * l.precio_unitario AS importe_linea,
       l.color_cuerpo, l.texto_suela
  FROM pedidos p
  JOIN clientes c       USING (id_cliente)
  JOIN lineas_pedido l  USING (id_pedido)
  JOIN modelos m        USING (id_modelo)
 WHERE p.referencia = 'SO003'
 ORDER BY l.talla;

-- Q04 · Unidades por talla (utilidad: qué tallas fabricar más)
SELECT l.talla, sum(l.cantidad) AS pares
  FROM lineas_pedido l JOIN pedidos p USING (id_pedido)
 WHERE p.estado IN ('confirmado','entregado')
 GROUP BY l.talla ORDER BY l.talla;

-- Q05 · Ventas por modelo (pares e importe)
SELECT m.nombre, sum(l.cantidad) AS pares, sum(l.cantidad * l.precio_unitario) AS importe
  FROM lineas_pedido l
  JOIN pedidos p USING (id_pedido)
  JOIN modelos m USING (id_modelo)
 WHERE p.estado IN ('confirmado','entregado')
 GROUP BY m.nombre ORDER BY importe DESC;

-- Q06 · Pedidos (de venta) por cliente (COUNT DISTINCT: no cuenta líneas como pedidos)
SELECT c.nombre, count(DISTINCT p.id_pedido) AS pedidos, coalesce(sum(l.cantidad),0) AS pares
  FROM clientes c
  LEFT JOIN pedidos p ON p.id_cliente = c.id_cliente AND p.estado IN ('confirmado','entregado')
  LEFT JOIN lineas_pedido l ON l.id_pedido = p.id_pedido
 GROUP BY c.nombre ORDER BY pedidos DESC, c.nombre;

-- Q07 · HAVING: clientes que han comprado 10 pares o más (candidatos a trato de equipo)
SELECT c.nombre, c.tipo, sum(l.cantidad) AS pares
  FROM clientes c
  JOIN pedidos p USING (id_cliente)
  JOIN lineas_pedido l USING (id_pedido)
 WHERE p.estado IN ('confirmado','entregado')
 GROUP BY c.nombre, c.tipo
HAVING sum(l.cantidad) >= 10
 ORDER BY pares DESC;

-- Q08 · Subconsulta: modelos con menos stock total que la media (reposición)
SELECT m.nombre, sum(s.stock_disponible) AS stock_total
  FROM stock s JOIN modelos m USING (id_modelo)
 GROUP BY m.nombre
HAVING sum(s.stock_disponible) < (SELECT avg(t) FROM (SELECT sum(stock_disponible) t
                                                        FROM stock GROUP BY id_modelo) x)
 ORDER BY stock_total;

-- Q09 · Alertas de stock bajo (umbral configurable = 5)
SELECT * FROM fn_stock_bajo(5);

-- Q10 · Búsqueda combinada con filtros opcionales (NULL = sin filtro)
SELECT * FROM fn_buscar_pedidos(p_cliente => 'a', p_estado => 'confirmado', p_modelo => 'pulse');

-- Q11 · Panel de indicadores
SELECT * FROM fn_indicadores();

-- Q12 · Ficha de fabricación (entrada de PSP): pedidos custom confirmados
SELECT * FROM v_ficha_fabricacion LIMIT 12;