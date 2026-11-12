# Estado del Odoo de SPEAKE (09/11/2026)

Instancia: **Odoo 19 Community** en la máquina virtual Ubuntu del equipo, base de datos **Proyecto1**,
compañía **Speake**. Acceso remoto por Tailscale (las credenciales NO se guardan en el repositorio).

## Apps instaladas
Ventas · CRM · Fabricación · Inventario · Facturación · Contactos · Empleados (y otras de apoyo).

## Datos maestros
| Elemento | Contenido |
|---|---|
| Atributo | **Talla** 38–46 (crea variantes) |
| Productos estándar | SPEAKE COURT (89 €), PULSE (109 €), HIGH (99 €), RETRO (95 €), STREET (92 €), AERO (105 €) — 9 variantes cada uno |
| Productos Custom | Los mismos 6 modelos + « CUSTOM» (+15 €), rutas **Manufacture + Replenish on Order (MTO)** |
| Componentes | Corte, Suela, Cordones, Plantilla (×2) y Caja de cada modelo + Kit personalización (solo Custom) |
| Listas de materiales | 12 (una por producto) |
| Clientes | Los 6 de la base de datos: Ana García, Club Halcones, Pedro Ruiz, Peña Los Linces, Marta Sánchez, Escuela Deportiva Norte |

## Caso común: pedido SO003
| Bloque | Identificador | Contenido |
|---|---|---|
| Base de datos SPEAKE | **SO003** | Club Halcones · SPEAKE Pulse personalizado · 40 pares · 5.160 € |
| Odoo (CRM) | Oportunidad «Club Halcones · 40 pares Pulse Custom» | Etapa **Won** |
| Odoo (Ventas) | **S00007**, Referencia del cliente = **SO003** | 9 líneas (tallas 38–46: 2,3,4,6,8,7,5,3,2) a 129 € · base imponible **5.160 €** · total con IVA 21 % 6.243,60 € |
| Odoo (Fabricación) | WH/MO/00010 … WH/MO/00018 | 9 órdenes (una por talla, 40 pares) **generadas automáticamente por MTO con origen S00007** |
| Odoo (Inventario) | WH/OUT/00002 | Entrega en espera hasta terminar la fabricación |
| PSP (Java) | `exportaciones/ficha_SO003_odoo.csv` | Procesado OK; idéntico a la exportación de PostgreSQL |

Pasos que quedan para la demo (se hacen en directo): Fabricación → producir las 9 órdenes →
Inventario → validar WH/OUT/00002 → Ventas → crear y confirmar la factura de S00007.

El pedido S00005 (Club X, 40 pares Court) se conserva como primera prueba del flujo.
