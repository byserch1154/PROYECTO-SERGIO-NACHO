# Manual de demostración

Guion para enseñar el caso completo en unos 15 minutos.

**Antes de empezar:** base SPEAKE cargada, `npm start` en `backend-express`, la máquina virtual de Odoo encendida,
pgAdmin abierto, `java/untitled` abierto en IntelliJ y una consola en `python/sneaker-data-lab`.

| # | Qué hacer | Dónde | Qué se ve |
|---|---|---|---|
| 1 | Presentar SPEAKE y el problema | diapositiva | Catálogo + pedidos Custom para clubes |
| 2 | Recorrer el catálogo y una ficha de producto con sus colores | `localhost:3000` | Web responsive (F12, vista móvil) |
| 3 | Diseñar una zapatilla en Personaliza y enviar el pedido | `personaliza.html` → `contacto.html` | Mensaje con la referencia SO0xx |
| 4 | Abrir la tabla `pedidos` | pgAdmin | El SO0xx está pendiente, con total calculado por los triggers |
| 5 | Ejecutar `04_pruebas.sql` y `12_pruebas_web_odoo.sql` | pgAdmin | Todas las pruebas superadas (terminan en ROLLBACK) |
| 6 | Entrar como `comercial1` y confirmar el SO0xx | `/gestion/` | Baja el stock, queda auditado y la columna Odoo pone «enviado» |
| 7 | Entrar como `almacen1` e intentar confirmar otro | `/gestion/` | PostgreSQL lo rechaza: ese rol no puede |
| 8 | Ventas → el pedido con la referencia del cliente SO0xx | Odoo | Mismo pedido, con el 21 % de IVA |
| 9 | Fabricación → órdenes con origen S000xx | Odoo | Los Custom se fabrican bajo pedido (MTO) |
| 10 | Enseñar SO024 (S00005): entrega validada y factura pagada | Odoo | Flujo completo CRM → venta → fabricación → entrega → factura |
| 11 | Pulsar *Exportar CSV PSP/Python* y copiar los CSV | panel | Ficheros en `backend-express/data/export/` |
| 12 | Run sobre `Main` | IntelliJ | Padre + 3 hijos, códigos de salida, `salida/ficha_taller_SO0xx.txt` |
| 13 | Run con `datos/pedido_erroneo.csv` y con `--retardo-ms 8000 --timeout 3` | IntelliJ | Error de validación y TIMEOUT controlados |
| 14 | `py -m streamlit run app_dashboard.py` | consola | KPIs con el pedido nuevo; se recalcula cada 60 s |
| 15 | Cierre: el mismo SO0xx en web, base de datos, panel, Odoo, Java y Python | diapositiva | Trazabilidad de principio a fin |

**Si algo falla en directo:**
- Sin Odoo: se enseña el pedido en el panel con su estado de envío y se sigue con Java usando los CSV de `datos/`.
- Sin backend: la web se ve abriendo los HTML, y Java y Python funcionan con los CSV que ya traen.
