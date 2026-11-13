# 02 · Matriz de permisos por rol y operación

✅ permitido · ❌ denegado. La comprobación se hace **en PostgreSQL** (funciones `fn_exigir_permiso`
y triggers `BEFORE`), no solo ocultando botones en el panel.

| Operación | Administrador | Comercial | Almacén |
|---|:-:|:-:|:-:|
| consultar_pedidos | ✅ | ✅ | ✅ |
| crear_pedido | ✅ | ✅ | ❌ |
| editar_pedido (líneas, cliente, fecha) | ✅ | ✅ | ❌ |
| confirmar_pedido | ✅ | ✅ | ❌ |
| cancelar_pedido | ✅ | ✅ | ❌ |
| entregar_pedido | ✅ | ❌ | ✅ |
| eliminar_pedido (físico) | ✅ | ❌ | ❌ |
| consultar_stock | ✅ | ✅ | ✅ |
| ver_auditoria | ✅ | ❌ | ❌ |
| gestionar_usuarios | ✅ | ❌ | ❌ |
| exportar_usuarios | ✅ | ❌ | ❌ |

## Justificación por responsabilidad de empresa
- **Comercial**: lleva la relación con el cliente, por eso crea, edita, confirma y cancela pedidos. No entrega (no gestiona el almacén) ni ve la auditoría ni gestiona usuarios.
- **Almacén**: prepara y entrega lo ya confirmado, y necesita ver el stock. No crea ni cambia pedidos: así no puede alterar lo que vendió el comercial.
- **Administrador**: acceso completo, incluida la gestión de usuarios, roles y auditoría. Existe desde la carga inicial (`02_datos.sql`).
- **Auditoría** solo para el Administrador: contiene la actividad de todos los usuarios.

## Usuarios de prueba (ficticios, guardados con bcrypt)
| Usuario | Rol | Contraseña de prueba |
|---|---|---|
| admin | Administrador | Admin#2026 |
| comercial1 | Comercial | Comercial#2026 |
| almacen1 | Almacén | Almacen#2026 |

## Roles de la aplicación vs. roles de PostgreSQL
- **Roles funcionales de la app** (`roles`, `permisos`, `usuarios`): los que ve el negocio (Administrador, Comercial, Almacén). Son datos en tablas.
- **Roles/privilegios de PostgreSQL** (`CREATE ROLE`, `GRANT/REVOKE`): quién puede conectarse a la base y a qué tablas. No se han usado para los perfiles de negocio (es opcional en el enunciado). El backend se conecta con una sola cuenta de base de datos y la identidad del usuario funcional viaja en cada transacción.
