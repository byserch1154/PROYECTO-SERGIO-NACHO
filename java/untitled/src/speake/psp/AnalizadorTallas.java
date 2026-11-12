package speake.psp;

import java.io.PrintStream;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;

/**
 * PROCESO HIJO 2 · AnalizadorTallas
 * stdin : pedido normalizado (salida del validador)
 * stdout: resumen clave=valor, por ejemplo:
 *           REFERENCIA=SO003
 *           CLIENTE=Club Halcones
 *           MODELO=SPEAKE Pulse
 *           TALLA.38=2
 *           TOTAL_PARES=40
 * Códigos de salida: 0 = OK, 5 = no se pudo analizar.
 * Argumento opcional --retardo-ms N: espera N ms para probar el timeout del padre.
 */
public final class AnalizadorTallas {

    private AnalizadorTallas() { }

    public static void main(String[] args) throws Exception {
        PrintStream out = Csv.salida();
        PrintStream err = Csv.error();

        if (args.length == 2 && args[0].equals("--retardo-ms")) {
            try {
                Thread.sleep(Long.parseLong(args[1]));
            } catch (NumberFormatException e) {
                err.println("ERROR: --retardo-ms necesita un número de milisegundos");
                System.exit(5);
            }
        }

        List<String> lineas = Csv.leerTodo(Csv.entrada());
        if (lineas.size() < 2) {
            err.println("ERROR: no hay líneas que analizar");
            System.exit(5);
        }

        List<String> primera = Csv.separar(lineas.get(1));
        if (primera.size() < Csv.COLUMNAS.size()) {
            err.println("ERROR: la primera fila no tiene todas las columnas");
            System.exit(5);
        }
        Map<Integer, Integer> porTalla = new TreeMap<>();
        int total = 0;

        int colTalla = Csv.COLUMNAS.indexOf("talla");
        int colCantidad = Csv.COLUMNAS.indexOf("cantidad");
        for (int n = 1; n < lineas.size(); n++) {
            List<String> fila = Csv.separar(lineas.get(n));
            if (fila.size() < Csv.COLUMNAS.size()) {
                err.println("ERROR: fila " + (n + 1) + ": faltan columnas");
                System.exit(5);
            }
            try {
                int talla = Integer.parseInt(fila.get(colTalla));
                int cantidad = Integer.parseInt(fila.get(colCantidad));
                if (talla < 38 || talla > 46) {
                    err.println("ERROR: fila " + (n + 1) + ": talla «" + talla + "» fuera de 38-46");
                    System.exit(5);
                }
                if (cantidad <= 0) {
                    err.println("ERROR: fila " + (n + 1) + ": cantidad «" + cantidad
                        + "» debe ser positiva");
                    System.exit(5);
                }
                porTalla.merge(talla, cantidad, Integer::sum);
                total += cantidad;
            } catch (NumberFormatException e) {
                err.println("ERROR: fila " + (n + 1) + ": talla o cantidad no son números");
                System.exit(5);
            }
        }

        out.println("REFERENCIA=" + primera.get(0));
        out.println("CLIENTE=" + primera.get(1));
        out.println("MODELO=" + primera.get(2));
        porTalla.forEach((talla, pares) -> out.println("TALLA." + talla + "=" + pares));
        out.println("TOTAL_PARES=" + total);
        System.exit(0);
    }
}
