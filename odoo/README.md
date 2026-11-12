# Odoo · núcleo de gestión de SPEAKE (Sistemas de Gestión Empresarial)

Odoo es el **sistema central** del negocio: el comercial registra la oportunidad y el pedido de venta, y a partir de él se
encadenan fabricación, inventario/entrega y facturación. La web, la base de datos y PSP **no sustituyen** a Odoo: solo
muestran, guardan una copia o procesan una exportación del mismo pedido (`SO003`).

```
CRM (oportunidad) ─► Ventas (presupuesto → pedido SO003) ─► Fabricación (OF por MTO)
                     ─► Inventario (consumo de componentes, entrega) ─► Facturación
```

Contenido de esta carpeta:
| Fichero | Para qué |
|---|---|
| `README.md` | Guía de instalación, configuración y demostración (este documento) |
| `ESTADO_ODOO.md` | **Estado real** de la instancia del equipo: apps, productos, clientes y el pedido S00007 ↔ SO003 |
| `exportaciones/ficha_SO003_odoo.csv` | Pedido exportado de Odoo en el formato que procesa PSP |
| `scripts/cargar_datos_odoo.py` | Carga por XML-RPC productos con tallas, componentes, listas de materiales, rutas, clientes, oportunidad y el pedido SO003 |
| `scripts/exportar_pedido_odoo.py` | Exporta un pedido de Odoo al CSV que procesa PSP (Java) |
| `importacion/*.csv` | Alternativa manual: contactos, productos y componentes para *Importar* desde la interfaz |
| `evidencias/` | Carpeta para capturas (crear al hacer la demo) |

> **Instancia del equipo:** Odoo **19** Community, base `Proyecto1`, compañía *Speake*, accesible por Tailscale.
> Ya contiene los 12 productos, el CRM, la ruta MTO y el pedido común (ver `ESTADO_ODOO.md`). Los scripts sirven para
> reconstruir esa configuración en una instancia nueva (solo librería estándar de Python).

---

## 1. Entorno: máquina virtual Ubuntu + Odoo Community (17, 18 o 19)

VM recomendada: Ubuntu Server 22.04/24.04, 2 CPU, 4 GB RAM, 25 GB disco, red en **adaptador puente** (para entrar desde
el navegador del anfitrión).

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y postgresql wget gnupg
# Repositorio oficial de Odoo (Community). El equipo usa la 19.0; cambiar 19.0 por la versión deseada
wget -q -O - https://nightly.odoo.com/odoo.key | sudo gpg --dearmor -o /usr/share/keyrings/odoo-archive-keyring.gpg
echo 'deb [signed-by=/usr/share/keyrings/odoo-archive-keyring.gpg] https://nightly.odoo.com/19.0/nightly/deb/ ./' \
  | sudo tee /etc/apt/sources.list.d/odoo.list
sudo apt update && sudo apt install -y odoo
sudo systemctl enable --now odoo
sudo systemctl status odoo          # debe aparecer "active (running)"
ip a                                # IP de la VM -> http://IP:8069
```
Incidencias habituales (documentarlas en la memoria si os pasan):
- *No se ve la página desde el anfitrión*: red en NAT → cambiar a adaptador puente o redirigir el puerto 8069.
- *Error de PostgreSQL al crear la base*: comprobar `sudo systemctl status postgresql`.
- *Informes PDF en blanco*: instalar `wkhtmltopdf` (paquete del repositorio de Odoo/Ubuntu).

Crear la base de datos en `http://IP:8069/web/database/manager`: nombre **speake**, idioma **Español**, país **España**,
**sin** datos de demostración. Apuntad la contraseña maestra fuera del repositorio.

## 2. Aplicaciones a instalar
Ajustes → Aplicaciones: **CRM**, **Ventas**, **Fabricación**, **Inventario**, **Facturación** (y **Empleados** si se
quieren roles por departamento).

Ajustes generales:
- *Ventas → Variantes de producto*: **activar** (necesario para las tallas).
- *Inventario → Rutas multipaso*: **activar** (para ver/usar la ruta MTO).
- *Fabricación → Órdenes de trabajo*: opcional.

## 3. Empresa, usuarios y roles
Ajustes → Compañías: **SPEAKE · Sneaker Factory S.L.** (datos ficticios), logo de la web (`lenguaje-de-marcas/img/logo.jpeg`).

| Usuario (ficticio) | Rol de negocio | Permisos en Odoo |
|---|---|---|
| `admin` | Administración | Administrador de ajustes, Facturación: administrador |
| `comercial1` | Comercial | CRM: usuario (solo sus documentos), Ventas: usuario (solo sus documentos) |
| `produccion1` | Producción | Fabricación: usuario, Inventario: usuario |
| `almacen1` | Almacén | Inventario: usuario (entregas y recepciones) |

Los nombres coinciden con los usuarios de la base de datos del proyecto (`admin`, `comercial1`, `almacen1`). Las
contraseñas de demostración **no** se guardan en el repositorio.

Cómo crearlos: Ajustes → Usuarios y compañías → Usuarios → **Nuevo** → nombre y correo ficticios → en *Derechos de
acceso* elegir para cada aplicación el nivel de la tabla → Guardar → *Cambiar contraseña*. Comprobación del rol:
iniciar sesión como `almacen1` y verificar que **no** puede confirmar un presupuesto de Ventas.

> Estado en la instancia del equipo: existen `Administrator`, `Nacho` y `Sergio`; **falta crear** los tres perfiles
> de la tabla (comercial, producción y almacén) antes de la demo.

## 4. Datos maestros (script o importación manual)

### Opción A · Script (recomendada)
Desde el ordenador anfitrión, con Python 3:
```bat
cd odoo\scripts
set ODOO_PASSWORD=la_contraseña_de_admin
python cargar_datos_odoo.py --url http://IP_DE_LA_VM:8069 --db speake --user admin
```
Crea:
- Atributo **Talla** (38–46) con creación de variantes.
- **12 productos almacenables**: los 6 modelos de la web (`SPEAKE Court`, `Pulse`, `High`, `Retro`, `Street`, `Aero`)
  y su versión **Custom** (+15 €), cada uno con 9 variantes de talla. Mismos nombres y precios que PostgreSQL y la web.
- **5 componentes** (corte, suela, cordones, plantilla y kit de personalización) con coste.
- **Listas de materiales**: 1 de cada componente por par; las Custom añaden el kit de personalización.
- **Rutas**: estándar → *Fabricar*; Custom → *Fabricar* + *MTO (bajo pedido)*.
- **6 clientes** ficticios (los mismos de la base de datos).
- **Oportunidad CRM** «Club Halcones · 40 pares Pulse Custom» y el **presupuesto** con 9 líneas (una por talla), con *Referencia del cliente* = **SO003**.

Añadiendo `--confirmar` también confirma el pedido. El script no duplica nada si se ejecuta dos veces.

### Opción B · Importación manual
Contactos → ⚙ → Importar → `importacion/contactos.csv`; Inventario → Productos → Importar →
`importacion/productos.csv` y `importacion/componentes.csv`. Después, en cada producto: pestaña *Atributos y variantes*
→ Talla 38–46; pestaña *Inventario* → rutas; y crear la lista de materiales en Fabricación → Productos → Listas de materiales.

## 5. Caso de uso común: pedido Custom SO003 (guion de demostración)
1. **Web**: el club envía la solicitud desde `contacto.html` (o ya existe en la BD como SO003).
2. **CRM** (`comercial1`): Pipeline → oportunidad *Club Halcones · 40 pares Pulse Custom* → mover a *Propuesta*.
3. **Ventas**: desde la oportunidad, *Nueva cotización* (en la instancia del equipo: **S00007**, Referencia del cliente SO003). Comprobar 9 líneas:
   tallas 38–46 → 2, 3, 4, 6, 8, 7, 5, 3, 2 pares = **40 pares** a 129 € (109 + 15 Custom + 5 texto) = **5.160 €**,
   igual que en PostgreSQL. Imprimir el presupuesto (PDF) → *Confirmar*.
4. **Fabricación** (`produccion1`): al confirmar, la ruta MTO genera **órdenes de fabricación** con origen S00007 (WH/MO/00010–00018 en la instancia del equipo)
   (Fabricación → Órdenes). Revisar componentes, *Comprobar disponibilidad*, *Producir todo* → *Hecho*.
   - Si faltan componentes: Inventario → Ajuste de inventario (stock inicial ficticio de componentes) y documentarlo.
5. **Inventario / entrega** (`almacen1`): Inventario → Entregas → la entrega de S00007 (WH/OUT/00002) → *Validar*. Ver *Movimientos de stock*.
6. **Facturación** (`admin`): en S00007 → *Crear factura* → *Confirmar* → registrar pago (simulado).
7. **Trazabilidad**: en S00007 los botones inteligentes muestran Fabricación, Entrega y Factura del mismo pedido.
8. **Exportar para PSP**:
   ```bat
   python exportar_pedido_odoo.py --url https://<máquina>.ts.net --db Proyecto1 --user <usuario> --pedido SO003
   ```
   Después, en IntelliJ (`java\untitled`), Run sobre `Main` con el argument
   `..\..\odoo\exportaciones\ficha_SO003_odoo.csv`.
   La ficha de taller generada por PSP lleva la referencia **SO003** del pedido de Odoo.

## 6. Correspondencia de datos entre bloques
| Dato | Web | PostgreSQL | Odoo | PSP |
|---|---|---|---|---|
| Pedido | referencia que muestra el formulario (SO0xx) | `pedidos.referencia` (SO003) | `sale.order.name` = S00007 y *Referencia del cliente* = SO003 | columna `referencia` |
| Cliente | nombre/email del formulario | `clientes` | `res.partner` (mismo email) | `cliente` |
| Modelo | `court`, `pulse`… | `modelos.nombre` | `product.template` (+ «Custom») | `modelo` |
| Talla | selector 38–46 | `lineas_pedido.talla` | variante del atributo Talla | `talla` |
| Personalización | 6 colores + texto | `color_*`, `texto_suela` | descripción de la línea | `color_*`, `texto_suela` |
| Estado | «solicitud registrada» | pendiente / confirmado / entregado / cancelado | presupuesto / pedido / entregado / facturado | código de salida + log |

## 7. Evidencias para la memoria (checklist)
- [ ] `systemctl status odoo` y pantalla de inicio con la base *speake*.
- [ ] Ajustes de la compañía y lista de usuarios con sus permisos.
- [ ] Producto *SPEAKE Pulse Custom*: variantes de talla, rutas (Fabricar + MTO) y lista de materiales.
- [ ] Oportunidad en el pipeline CRM.
- [ ] Presupuesto S00007 (ref. SO003) en PDF y pedido confirmado.
- [ ] Órdenes de fabricación con origen S00007 y componentes consumidos.
- [ ] Entrega validada y movimientos de stock.
- [ ] Factura confirmada.
- [ ] Exportación CSV de SO003 y resultado de PSP.
- [ ] Copia de seguridad: Gestor de bases de datos → *Backup* (zip) guardado fuera del repositorio.

## 8. Conexión automática con la web
Además de los scripts, el backend Express envía a Odoo cada pedido que se confirma en el panel
(ver `backend-express/README.md`, apartado «Integración con Odoo»). Se hace por la API externa,
nunca escribiendo en la base de datos de Odoo ni con triggers sobre ella.

| En SPEAKE | En Odoo |
|---|---|
| Pedido SO0xx confirmado en el panel | Pedido de venta S000xx, Referencia del cliente = SO0xx |
| Cliente (por correo) | Contacto (se busca por correo; si no existe se crea) |
| Línea con color de catálogo | Producto «SPEAKE Pulse» de esa talla, «Color: …» en la descripción |
| Línea personalizada | Producto «SPEAKE Pulse Custom» de esa talla (ruta MTO → orden de fabricación) |
| Importe sin IVA | Importe con IVA 21 % (lo añade Odoo) |

## 9. Ampliaciones posibles
- Campos propios en la línea de venta para los 6 colores (módulo personalizado) en lugar de la descripción.
- Informes de fabricación por talla con la vista pivote de Fabricación.
