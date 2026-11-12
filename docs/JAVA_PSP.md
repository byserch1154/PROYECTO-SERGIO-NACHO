# Java y PSP: procesador de pedidos Custom

Documento de apoyo del Proyecto Intermodular de 2.º DAM.

Estado: 12 de noviembre de 2026.

Código: `java/untitled/`.

Documento general: [MEMORIA_TECNICA.md](MEMORIA_TECNICA.md).

## 1. Qué resuelve

El subsistema PSP recibe una copia de un pedido Custom exportada desde PostgreSQL u Odoo y prepara información auxiliar para taller. No sustituye a Ventas, Fabricación ni Inventario de Odoo. Trabaja con ficheros CSV o JSON y no se conecta a la base de datos.

El PDF del proyecto pide una aplicación Java de consola con un proceso coordinador que lance procesos hijos con `ProcessBuilder`, comunicación por stdin/stdout y control de errores. Este módulo implementa esa arquitectura con tres hijos.

## 2. Relación con los requisitos del PDF

| Requisito | Implementación |
|---|---|
| Aplicación Java de consola | `Main` arranca `ProcesadorPedidosCustom` |
| Proceso coordinador | `ProcesadorPedidosCustom` agrupa por referencia y encadena hijos |
| Lanzar hijos con `ProcessBuilder` | `ejecutarHijo` crea una JVM por proceso |
| Validar la estructura | `ValidadorPedidoCustom` |
| Resumir cantidades por talla | `AnalizadorTallas` |
| Preparar una ficha para taller | `GeneradorFichaTaller` |
| Comunicación por stdin/stdout | El padre escribe la entrada y lee la salida de cada hijo |
| stdout y stderr separados | El padre lee cada flujo en un `CompletableFuture` distinto |
| Códigos de salida | 0, 1, 2, 3, 4, 5, 6 |
| Tiempo de espera y finalización | `waitFor`, `destroy`, `destroyForcibly` |
| Evidencias | `salida/procesamiento.log` y `salida/ficha_taller_*.txt` |
| Sin Swing ni JDBC | No hay interfaz de escritorio ni conexión a PostgreSQL |

El PDF permite integrar los bloques mediante CSV/JSON y procedimientos documentados. No exige que la web o Express lancen Java. La ejecución del padre es manual, desde IntelliJ o consola.

## 3. Arquitectura

```text
Main
  └─ ProcesadorPedidosCustom (padre)
       ├─ ValidadorPedidoCustom   (proceso hijo)
       ├─ AnalizadorTallas        (proceso hijo)
       └─ GeneradorFichaTaller    (proceso hijo)
```

Cada hijo es una JVM independiente. El padre no llama a un método del hijo: construye un comando con el ejecutable de Java, el classpath actual y la clase principal del hijo.

```java
String java = Paths.get(System.getProperty("java.home"), "bin", "java").toString();
List<String> comando = new ArrayList<>(List.of(
    java, "-Dfile.encoding=UTF-8",
    "-cp", System.getProperty("java.class.path"),
    "speake.psp." + clase));
ProcessBuilder pb = new ProcessBuilder(comando);
Process p = pb.start();
```

Por eso los `.class` deben existir antes de arrancar el padre. El padre no compila fuentes. IntelliJ compila al pulsar Run; desde consola hay que ejecutar `javac` primero.

## 4. Ejecución

### Desde IntelliJ

1. Abrir `java/untitled` como proyecto.
2. Ejecutar `src/Main.java`.
3. Para cambiar de entrada, editar **Program arguments**.

Ejemplos:

```text
datos/ficha_fabricacion.csv
datos/pedido_SO003.json
datos/pedido_SO003.json --timeout-ms 3000 --retardo-ms 8000
```

### Desde consola

```bash
cd java/untitled
javac -encoding UTF-8 -d out $(find src -name "*.java")
java -cp out Main datos/ficha_fabricacion.csv
```

No uses `java src/Main.java` para la demo. Ese modo no garantiza que los hijos encuentren todas las clases en el classpath.

### Opciones

| Opción | Efecto |
|---|---|
| `--timeout-ms N` | Tiempo máximo de cada hijo. Por defecto, 3000 ms. |
| `--retardo-ms N` | Retardo artificial del analizador para probar P5. |
| Primer argumento sin guiones | Fichero de entrada. Por defecto, `datos/ficha_fabricacion.csv`. |

El padre solo pasa `--retardo-ms` al analizador. No hace falta en una ejecución normal.

## 5. Entrada CSV

Cabecera obligatoria, en este orden:

```text
referencia,cliente,modelo,color_cuerpo,color_franja,color_puntera,
color_talon,color_suela,color_cordones,texto_suela,talla,cantidad
```

| Columna | Uso |
|---|---|
| `referencia` | Agrupa las líneas por pedido, por ejemplo SO003 |
| `cliente` | Nombre del cliente o club |
| `modelo` | Modelo de zapatilla |
| `color_*` | Seis colores del producto Custom |
| `texto_suela` | Texto personalizado; puede estar vacío |
| `talla` | Número entero entre 38 y 46 |
| `cantidad` | Entero positivo de pares |

El fichero puede contener varios pedidos. El padre agrupa las filas por `referencia` y procesa cada grupo por separado.

## 6. Entrada JSON

`pedido_SO003.json` usa este contrato:

```json
{
  "referencia": "SO003",
  "cliente": "Club Halcones",
  "modelo": "SPEAKE Pulse",
  "texto_suela": "HALCONES",
  "colores": {
    "cuerpo": "Negro",
    "franja": "Azul eléctrico",
    "puntera": "Negro",
    "talon": "Gris",
    "suela": "Blanco",
    "cordones": "Azul eléctrico"
  },
  "lineas": [
    {"talla": 38, "cantidad": 2}
  ]
}
```

`JsonPedido` convierte ese JSON a las mismas filas CSV. Los procesos hijos no saben si el origen era CSV o JSON.

El lector es específico para este contrato. No es un parser JSON genérico: no admite comas ni saltos de línea dentro de los textos, y no interpreta estructuras distintas. Si cambia el contrato, hay que ampliar `JsonPedido`.

## 7. Flujo de un pedido

1. El padre comprueba que el fichero existe.
2. Lee el CSV o convierte el JSON.
3. Agrupa las filas por `referencia`.
4. Lanza el validador y le envía el CSV del pedido por stdin.
5. Si el validador termina con 0, lanza el analizador con la salida normalizada del validador.
6. Si el analizador termina con 0, lanza el generador con el resumen del analizador.
7. Si el generador termina con 0, guarda la ficha.
8. Si un hijo falla o agota el tiempo, registra el estado y no lanza el siguiente para ese pedido.

El padre sigue con el siguiente pedido después de un fallo. Al final devuelve 1 si algún pedido falló.

## 8. Responsabilidad de cada clase

### `Main`

Punto de entrada. Delega en `ProcesadorPedidosCustom.main(args)`.

### `ProcesadorPedidosCustom`

- Lee la entrada.
- Agrupa por referencia.
- Construye el CSV de cada pedido.
- Lanza los hijos.
- Escribe en stdin y lee stdout y stderr.
- Controla el timeout.
- Escribe el log y las fichas.
- Devuelve el código global.

### `ValidadorPedidoCustom`

Entrada: CSV de un pedido.

Comprueba:

- que la cabecera tiene todas las columnas;
- que la talla está entre 38 y 46;
- que la cantidad es un entero positivo;
- que los seis colores pertenecen al catálogo.

Si todo es correcto, escribe por stdout el pedido normalizado en el orden de `Csv.COLUMNAS`.

Códigos: 0 correcto, 2 faltan columnas, 3 datos no válidos, 4 pedido vacío.

### `AnalizadorTallas`

Entrada: CSV normalizado del validador.

Recorre las filas, suma la cantidad de cada talla y calcula el total de pares. Escribe un resumen `clave=valor`:

```text
REFERENCIA=SO003
CLIENTE=Club Halcones
MODELO=SPEAKE Pulse
TALLA.38=2
...
TOTAL_PARES=40
```

Código: 0 correcto, 5 no se pudo analizar.

Acepta `--retardo-ms N` para las pruebas de timeout. El padre solo lo pasa cuando se indica esa opción.

### `GeneradorFichaTaller`

Entrada: resumen del analizador.

Comprueba que existen `REFERENCIA`, `CLIENTE`, `MODELO` y `TOTAL_PARES`. Genera una ficha con una línea por talla y la fecha de generación.

Código: 0 correcto, 6 resumen incompleto.

### `Csv`

Utilidades comunes:

- lista de columnas;
- lectura de stdin en UTF-8;
- salida y error en UTF-8;
- separación por comas.

No soporta comas dentro de campos. El contrato de datos evita ese caso.

### `JsonPedido`

Convierte el contrato JSON a filas CSV. Valida campos obligatorios, tallas, cantidades y que los textos no rompan el CSV.

## 9. Comunicación y timeout

El padre escribe la entrada del hijo en `p.getOutputStream()`, que es el stdin del proceso. Después lee `p.getInputStream()` y `p.getErrorStream()` en dos hilos para evitar que el hijo se bloquee si llena un buffer.

El padre aplica el mismo timeout a todos los hijos:

```java
boolean termino = p.waitFor(timeoutMs, TimeUnit.MILLISECONDS);
if (!termino) {
    p.destroy();
    if (!p.waitFor(1, TimeUnit.SECONDS)) {
        p.destroyForcibly();
        p.waitFor();
    }
    return new Resultado(clase, -1, salida.join(), errores.join(), true);
}
```

Si un hijo agota el tiempo:

- el padre intenta terminar el hijo con `destroy()`;
- si sigue vivo, usa `destroyForcibly()`;
- el padre marca el resultado como `TIMEOUT`;
- el padre no lanza el siguiente hijo de ese pedido;
- el código global termina en 1.

## 10. Códigos de salida

| Código | Proceso | Significado |
|---|---|---|
| 0 | todos | correcto |
| 1 | padre | algún pedido falló o agotó el tiempo |
| 2 | padre | fichero inexistente, sin pedidos o argumento inválido |
| 2 | validador | faltan columnas |
| 3 | validador | datos no válidos |
| 4 | validador | pedido vacío |
| 5 | analizador | no se pudo analizar |
| 6 | generador | resumen incompleto |

## 11. Salidas

### Ficha

Ruta: `salida/ficha_taller_<referencia>.txt`.

Ejemplo de SO003:

```text
==============================================
 SPEAKE · FICHA AUXILIAR DE TALLER
 (la orden de fabricación oficial está en Odoo)
==============================================
 Pedido : SO003
 Cliente: Club Halcones
 Modelo : SPEAKE Pulse
 Pares  : 40
----------------------------------------------
 Talla 38 : 2 pares
 ...
 Talla 46 : 2 pares
 Fecha  : 2026-11-12T...
==============================================
```

### Log

Ruta: `salida/procesamiento.log`.

Formato normal:

```text
2026-11-12T... | SO003 | ValidadorPedidoCustom salida=0
```

Formato de timeout:

```text
2026-11-12T... | SO003 | AnalizadorTallas TIMEOUT
```

El log incluye la hora, el pedido, el proceso, el código o `TIMEOUT` y el stderr si existe. No incluye PID ni duración.

`salida/` está ignorado por Git. Las fichas se regeneran al ejecutar `Main`.

## 12. Pruebas

| Caso | Entrada | Resultado comprobado |
|---|---|---|
| P1 | `datos/ficha_fabricacion.csv` | 3 fichas, padre 0; SO003=40, SO005=12, SO006=1 |
| P2 | `datos/pedido_erroneo.csv` | validador 3 con 4 errores, padre 1 |
| P3 | `datos/pedido_sin_columnas.csv` | validador 2, padre 1 |
| P4 | `datos/no_existe.csv` | mensaje de error, padre 2 |
| P5 | `datos/pedido_SO003.json --timeout-ms 3000 --retardo-ms 8000` | TIMEOUT, padre 1 |
| P6 | `datos/pedido_SO003.json` | misma ficha que P1, salvo la fecha |

Comandos usados:

```bash
cd java/untitled
javac --release 17 -encoding UTF-8 -d /tmp/psp-classes $(find src -name "*.java")
java -cp /tmp/psp-classes Main datos/ficha_fabricacion.csv
java -cp /tmp/psp-classes Main datos/pedido_erroneo.csv
java -cp /tmp/psp-classes Main datos/pedido_sin_columnas.csv
java -cp /tmp/psp-classes Main no_existe.csv
java -cp /tmp/psp-classes Main datos/pedido_SO003.json
java -cp /tmp/psp-classes Main datos/pedido_SO003.json --timeout-ms 3000 --retardo-ms 8000
```

La compilación con `--release 17` terminó correctamente. Ejecutamos las pruebas con Java 21 sobre clases compatibles con Java 17.

## 13. Límites actuales

- El paralelismo con `ExecutorService` sigue como `TODO`. El PDF lo plantea como ampliación, no como requisito del flujo principal.
- El programa no genera `informe_procesamiento.csv` ni un resumen global aparte de la ficha y el log.
- El log no guarda PID ni duración. Corregimos la memoria para que no afirme que los guarda.
- No existe `pruebas.bat`. Lanzamos las pruebas P1-P6 a mano desde IntelliJ o consola.
- `JsonPedido` solo cubre el contrato documentado.
- No hay lanzador desde Express ni desde la web. El PDF no lo exige: la demo ejecuta la aplicación PSP y muestra cómo el padre lanza los hijos.

## 14. Defensa en cuatro frases

1. `Main` arranca el proceso padre `ProcesadorPedidosCustom`.
2. El padre agrupa el pedido y lanza tres JVM independientes con `ProcessBuilder`.
3. Cada hijo recibe datos por stdin, devuelve resultados por stdout y errores por stderr; el padre controla el código de salida.
4. Si un hijo falla o supera el timeout, el padre no continúa con ese pedido y deja la evidencia en el log y en la ficha.
