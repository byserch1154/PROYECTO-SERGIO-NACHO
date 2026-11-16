# Matriz de permisos

✅ puede · ❌ no puede. Los permisos se comprueban **dentro de PostgreSQL**, no solo escondiendo botones en el panel.

| Operación | Administrador | Comercial | Almacén |
|---|:-:|:-:|:-:|
| Consultar pedidos | ✅ | ✅ | ✅ |
| Crear pedidos | ✅ | ✅ | ❌ |
| Editar pedidos (líneas, cliente, fecha) | ✅ | ✅ | ❌ |
| Confirmar pedidos | ✅ | ✅ | ❌ |
| Cancelar pedidos | ✅ | ✅ | ❌ |
| Marcar como entregado | ✅ | ❌ | ✅ |
| Eliminar pedidos | ✅ | ❌ | ❌ |
| Consultar stock | ✅ | ✅ | ✅ |
| Ver la auditoría | ✅ | ❌ | ❌ |
| Gestionar usuarios | ✅ | ❌ | ❌ |
| Exportar usuarios a JSON | ✅ | ❌ | ❌ |

## Por qué cada rol puede lo que puede
- **Comercial.** Es quien trata con el cliente, así que crea, cambia, confirma y cancela pedidos. No entrega, no ve
  la auditoría y no gestiona usuarios.
- **Almacén.** Prepara y entrega lo que ya está confirmado y necesita ver el stock. No puede crear ni cambiar pedidos,
  así no puede tocar lo que vendió el comercial.
- **Administrador.** Puede hacerlo todo, también gestionar usuarios y ver la auditoría. Se crea al cargar los datos.
- **La auditoría** solo la ve el administrador porque tiene la actividad de todos los usuarios.

## Usuarios de prueba (ficticios, guardados con bcrypt)
| Usuario | Rol | Contraseña de prueba |
|---|---|---|
| admin | Administrador | Admin#2026 |
| comercial1 | Comercial | Comercial#2026 |
| almacen1 | Almacén | Almacen#2026 |

## Roles de la aplicación y roles de PostgreSQL
- **Los de la aplicación** (Administrador, Comercial y Almacén) son datos guardados en las tablas `roles`, `permisos`
  y `usuarios`. Son los que usa el negocio.
- **Los de PostgreSQL** (`CREATE ROLE`, `GRANT`) deciden quién se puede conectar a la base. No los hemos usado para
  los perfiles del negocio porque el enunciado lo deja como opcional: el backend se conecta con una sola cuenta y en
  cada operación le dice a la base qué usuario de la aplicación la está haciendo.
