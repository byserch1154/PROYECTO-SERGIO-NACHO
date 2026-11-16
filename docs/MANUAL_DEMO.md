# Manual de demostración

Guion para enseñar el caso completo en unos 15 minutos.

**Antes de empezar:** base `SPEAKE` cargada en PostgreSQL, `npm start` en `backend-express`, la máquina virtual de
Odoo encendida (y Tailscale conectado), pgAdmin abierto, `java/untitled` abierto en IntelliJ y una consola en
`python/sneaker-data-lab` con el dashboard arrancado (`py -m streamlit run app_dashboard.py`).

| # | Qué hacer | Dónde | Qué se ve |
|---|---|---|---|
| 1 | Presentar SPEAKE y el problema | presentación | Catálogo + pedidos Custom para clubes |
| 2 | Recorrer el catálogo y una ficha de producto con sus colores | `localhost:3000` | Web responsive (F12, vista móvil) |
| 3 | Diseñar una zapatilla en Personaliza y enviar el pedido con su reparto por tallas | `personaliza.html` → `contacto.html` | Mensaje con la referencia SO0xx |
| 4 | Abrir la tabla `pedidos` | pgAdmin | El SO0xx está pendiente, con el total calculado por los triggers |
| 5 | Ejecutar `04_pruebas.sql` y `12_pruebas_web_odoo.sql` | pgAdmin | Todas las pruebas superadas (terminan en ROLLBACK) |
| 6 | Entrar como `comercial1` y confirmar el SO0xx | `/gestion/` | Baja el stock, queda auditado y la columna Odoo pone «enviado» |
| 7 | Entrar como `almacen1` e intentar confirmar otro | `/gestion/` | No tiene esa opción y PostgreSQL lo rechazaría |
| 8 | Ventas → el pedido con la referencia del cliente SO0xx | Odoo | Mismo pedido, con el 21 % de IVA |
| 9 | Fabricación → órdenes con el origen de ese pedido | Odoo | Los Custom se fabrican bajo pedido (MTO) |
| 10 | Enseñar SO024 (S00005): entrega validada y factura pagada | Odoo | Flujo completo CRM → venta → fabricación → entrega → factura |
| 11 | Pulsar «Exportar CSV PSP/Python» y copiar los CSV | panel | Ficheros en `backend-express/data/export/` |
| 12 | Run sobre `Main` | IntelliJ | Padre + 3 hijos, códigos de salida, `salida/ficha_taller_SO0xx.txt` |
| 13 | Run con `datos/pedido_erroneo.csv` y con `--retardo-ms 8000 --timeout 3` | IntelliJ | Error de validación y TIMEOUT controlados |
| 14 | Mirar el dashboard | navegador | En el siguiente ciclo de 60 s cambian los KPIs con el pedido nuevo |
| 15 | Cierre: pruebas, dificultades y mejoras | presentación | Trazabilidad del mismo SO0xx de principio a fin |

**Si algo falla en directo:**
- Sin Odoo: se enseñan las capturas del apartado 6 de la memoria y se sigue con Java y Python usando los CSV de `datos/`
  y de `entrada_acc/`.
- Sin backend: la web se ve abriendo los HTML, y Java y Python funcionan con los CSV que ya traen.
