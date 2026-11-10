# PSP · Procesador de pedidos Custom (Java)

Proyecto de IntelliJ. Se ejecuta con **Run** sobre `src/Main.java` (JDK 17).
Lee `datos/ficha_fabricacion.csv` (exportado desde la base de datos SPEAKE) y, para cada pedido,
lanza tres procesos hijos con `ProcessBuilder`, pasándose los datos por stdin/stdout:

```
ProcesadorPedidosCustom (padre)
   ├─► ValidadorPedidoCustom   comprueba columnas, tallas, cantidades y colores
   ├─► AnalizadorTallas        cuenta los pares por talla
   └─► GeneradorFichaTaller    genera salida/ficha_taller_SO003.txt
```

Para probar otro fichero: Run → Edit Configurations → Program arguments, por ejemplo
`datos/pedido_erroneo.csv`.

| Código | Proceso | Significado |
|---|---|---|
| 0 | todos | correcto |
| 2 / 3 / 4 | validador | faltan columnas / datos no válidos / pedido vacío |
| 5 | analizador | no se pudo analizar |
| 6 | generador | resumen incompleto |
| 1 / 2 | padre | algún pedido con error / fichero incorrecto |

## Estado
| Parte | Estado |
|---|---|
| Leer el CSV y separarlo por pedido | hecho |
| Lanzar los hijos con ProcessBuilder, stdout y stderr por separado | hecho |
| Validador | hecho |
| Log `salida/procesamiento.log` | hecho |
| Analizador: sumar pares por talla | **pendiente** |
| Ficha: líneas por talla y fecha | **pendiente** |
| Timeout de los hijos (`waitFor`, `destroy`) | **pendiente** |
| Varios pedidos en paralelo (`ExecutorService`) | **pendiente** |
| Entrada JSON (`datos/pedido_SO003.json`) | **pendiente** |

Cada parte pendiente está marcada con `TODO` en el código.

## Pruebas que debe pasar al terminar
| Prueba | Entrada | Resultado esperado |
|---|---|---|
| P1 | `datos/ficha_fabricacion.csv` | 3 fichas con sus tallas, padre = 0 |
| P2 | `datos/pedido_erroneo.csv` | validador = 3 con 4 errores, padre = 1 |
| P3 | `datos/pedido_sin_columnas.csv` | validador = 2, padre = 1 |
| P4 | `datos/no_existe.csv` | mensaje de error, padre = 2 |
| P5 | analizador con `--retardo-ms 8000` y timeout de 3 s | TIMEOUT, padre = 1 |
| P6 | `datos/pedido_SO003.json` | misma ficha que en P1 |
