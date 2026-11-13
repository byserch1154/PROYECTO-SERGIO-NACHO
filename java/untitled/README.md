# PSP · Procesador de pedidos Custom (Java)

Proyecto de IntelliJ (JDK 17). Se ejecuta con Run sobre `src/Main.java`. Lee el pedido exportado de la base de datos
y, para cada pedido, lanza tres procesos hijos con ProcessBuilder pasándose los datos por stdin y stdout:

```
ProcesadorPedidosCustom (padre)
 ├─► ValidadorPedidoCustom   comprueba columnas, tallas, cantidades y colores
 ├─► AnalizadorTallas        cuenta los pares por talla
 └─► GeneradorFichaTaller    genera salida/ficha_taller_SO0xx.txt
```

Cada paso queda apuntado en `salida/procesamiento.log` con la hora, el hilo, el pedido, el proceso y su código.

| Código | Proceso | Significado |
|---|---|---|
| 0 | todos | correcto |
| 2 / 3 / 4 | validador | faltan columnas / datos no válidos / pedido vacío |
| 5 | analizador | no se pudo analizar |
| 6 | generador | resumen incompleto |
| 1 / 2 | padre | algún pedido con error / fichero incorrecto |

Opciones: `--paralelo` (hasta 3 pedidos a la vez), `--timeout N` (segundos, 5 por defecto) y `--retardo-ms N`
(retrasa el analizador para probar el timeout). Los casos de prueba están en el README de la raíz.
