# PSP · Procesador de pedidos Custom (Java)

Documentación detallada: [docs/JAVA_PSP.md](../../docs/JAVA_PSP.md).

Proyecto de IntelliJ. Se ejecuta con **Run** sobre `src/Main.java` (JDK 17).
Lee `datos/ficha_fabricacion.csv` (exportado desde la base de datos SPEAKE) o `datos/pedido_SO003.json`
y, para cada pedido,
lanza tres procesos hijos con `ProcessBuilder`, pasándose los datos por stdin/stdout:

```
ProcesadorPedidosCustom (padre)
   ├─► ValidadorPedidoCustom   comprueba columnas, tallas, cantidades y colores
   ├─► AnalizadorTallas        cuenta los pares por talla
   └─► GeneradorFichaTaller    genera salida/ficha_taller_SO003.txt
```

Para probar otro fichero: Run → Edit Configurations → Program arguments, por ejemplo
`datos/pedido_erroneo.csv`.

El padre lanza una JVM nueva por cada hijo con el mismo classpath. Por eso hay que compilar todo
el proyecto antes de ejecutar; no sirve lanzar solo `java src/Main.java` sin las demás clases.

## Opciones

| Opción | Para qué sirve |
|---|---|
| `--timeout-ms N` | Tiempo máximo de cada hijo. Por defecto, 3000 ms. |
| `--retardo-ms N` | Retardo artificial del analizador. Solo se usa para probar P5. |

Ejemplos de Program arguments en IntelliJ:

```text
datos/ficha_fabricacion.csv
datos/pedido_SO003.json
datos/pedido_SO003.json --timeout-ms 3000 --retardo-ms 8000
```

El lector JSON convierte el contrato de `pedido_SO003.json` al mismo CSV interno. No es un parser
JSON genérico; si cambia el contrato, hay que ampliar `JsonPedido`.

| Código | Proceso | Significado |
|---|---|---|
| 0 | todos | correcto |
| 2 / 3 / 4 | validador | faltan columnas / datos no válidos / pedido vacío |
| 5 | analizador | no se pudo analizar |
| 6 | generador | resumen incompleto |
| 1 / 2 | padre | algún pedido con error / fichero incorrecto |

Si un hijo agota `--timeout-ms`, el padre lo marca como `TIMEOUT` y termina con código 1.

## Estado
| Parte | Estado |
|---|---|
| Leer el CSV y separarlo por pedido | hecho |
| Lanzar los hijos con ProcessBuilder, stdout y stderr por separado | hecho |
| Validador | hecho |
| Log `salida/procesamiento.log` | hecho |
| Analizador: sumar pares por talla | hecho |
| Ficha: líneas por talla y fecha | hecho |
| Timeout de los hijos (`waitFor`, `destroy`) | hecho |
| Varios pedidos en paralelo (`ExecutorService`) | pendiente, ampliación opcional |
| Entrada JSON (`datos/pedido_SO003.json`) | hecho |

El paralelismo sigue marcado con `TODO` en el código. No es necesario para el flujo principal.

## Pruebas que debe pasar al terminar
| Prueba | Entrada | Resultado esperado |
|---|---|---|
| P1 | `datos/ficha_fabricacion.csv` | 3 fichas con sus tallas, padre = 0 |
| P2 | `datos/pedido_erroneo.csv` | validador = 3 con 4 errores, padre = 1 |
| P3 | `datos/pedido_sin_columnas.csv` | validador = 2, padre = 1 |
| P4 | `datos/no_existe.csv` | mensaje de error, padre = 2 |
| P5 | `datos/pedido_SO003.json --timeout-ms 3000 --retardo-ms 8000` | TIMEOUT, padre = 1 |
| P6 | `datos/pedido_SO003.json` | misma ficha que en P1, salvo la fecha |
