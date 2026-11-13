package speake.psp;

import java.io.PrintStream;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;

// Proceso hijo 1: comprueba que el pedido está bien antes de seguir
public final class ValidadorPedidoCustom {

    static final Set<String> COLORES = Set.of(
        "Negro", "Blanco", "Azul eléctrico", "Rojo", "Verde", "Amarillo", "Naranja", "Gris");

    private ValidadorPedidoCustom() { }

    public static void main(String[] args) throws Exception {
        PrintStream out = Csv.salida();
        PrintStream err = Csv.error();
        List<String> lineas = Csv.leerTodo(Csv.entrada());

        // Sin cabecera y al menos una línea no hay pedido
        if (lineas.size() < 2) {
            err.println("ERROR: el pedido no tiene líneas");
            System.exit(4);
        }

        List<String> cabecera = Csv.separar(lineas.get(0));
        // Miramos que estén todas las columnas obligatorias
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
        // Revisamos fila a fila: talla, cantidad y colores
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
                err.println("ERROR: fila " + (n + 1) + ": cantidad «" + fila.get(11) + "» no es un entero positivo");
                errores++;
            }
            for (int i = 3; i <= 8; i++) {
                if (!COLORES.contains(fila.get(i))) {
                    err.println("ERROR: fila " + (n + 1) + ": " + Csv.COLUMNAS.get(i) + " «" + fila.get(i)
                        + "» no es un color del catálogo");
                    errores++;
                }
            }
            normalizado.add(String.join(",", fila));
        }

        // Si hay errores no devolvemos nada y salimos con código 3
        if (errores > 0) {
            System.exit(3);
        }
        normalizado.forEach(out::println);
        System.exit(0);
    }

    private static int entero(String s) {
        try {
            return Integer.parseInt(s);
        } catch (NumberFormatException e) {
            return -1;
        }
    }
}
