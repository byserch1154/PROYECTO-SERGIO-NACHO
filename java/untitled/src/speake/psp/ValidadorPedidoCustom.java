package speake.psp;

import java.io.PrintStream;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;

/**
 * PROCESO HIJO 1 · ValidadorPedidoCustom
 * stdin : CSV de un pedido (cabecera + filas)
 * stdout: el mismo pedido normalizado (columnas en el orden de Csv.COLUMNAS)
 * stderr: un mensaje por cada error encontrado
 * Códigos de salida: 0 = OK, 2 = faltan columnas, 3 = datos no válidos, 4 = pedido vacío.
 */
public final class ValidadorPedidoCustom {

    static final Set<String> COLORES = Set.of(
        "Negro", "Blanco", "Azul eléctrico", "Rojo", "Verde", "Amarillo", "Naranja", "Gris");

    private ValidadorPedidoCustom() { }

    public static void main(String[] args) throws Exception {
        PrintStream out = Csv.salida();
        PrintStream err = Csv.error();
        List<String> lineas = Csv.leerTodo(Csv.entrada());

        if (lineas.size() < 2) {
            err.println("ERROR: el pedido no tiene líneas");
            System.exit(4);
        }

        List<String> cabecera = Csv.separar(lineas.get(0));
        List<String> faltan = new ArrayList<>();
        for (String c : Csv.COLUMNAS) {
            if (!cabecera.contains(c)) {
                faltan.add(c);
            }
        }
        if (!faltan.isEmpty()) {
            err.println("ERROR: faltan columnas obligatorias: " + String.join(", ", faltan));
            System.exit(2);
        }

        List<String> normalizado = new ArrayList<>();
        normalizado.add(String.join(",", Csv.COLUMNAS));
        int errores = 0;
        for (int n = 1; n < lineas.size(); n++) {
            List<String> f = Csv.separar(lineas.get(n));
            List<String> fila = new ArrayList<>();
            for (String c : Csv.COLUMNAS) {
                int i = cabecera.indexOf(c);
                fila.add(i < f.size() ? f.get(i) : "");
            }

            int talla = entero(fila.get(10));
            if (talla < 38 || talla > 46) {
                err.println("ERROR: fila " + (n + 1) + ": talla «" + fila.get(10) + "» fuera de 38-46");
                errores++;
            }
            if (entero(fila.get(11)) <= 0) {
                err.println("ERROR: fila " + (n + 1) + ": cantidad «" + fila.get(11)
                    + "» debe ser un entero positivo");
                errores++;
            }
            for (int i = 3; i <= 8; i++) {
                if (!COLORES.contains(fila.get(i))) {
                    err.println("ERROR: fila " + (n + 1) + ": " + Csv.COLUMNAS.get(i) + " «"
                        + fila.get(i) + "» no es un color del catálogo");
                    errores++;
                }
            }
            normalizado.add(String.join(",", fila));
        }

        if (errores > 0) {
            System.exit(3);
        }
        normalizado.forEach(out::println);
        System.exit(0);
    }

    /** Convierte a entero; si no es un número devuelve -1. */
    private static int entero(String s) {
        try {
            return Integer.parseInt(s);
        } catch (NumberFormatException e) {
            return -1;
        }
    }
}
