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
            Thread.sleep(Long.parseLong(args[1]));
        }

        List<String> lineas = Csv.leerTodo(Csv.entrada());
        if (lineas.size() < 2) {
            err.println("ERROR: no hay líneas que analizar");
            System.exit(5);
        }

        List<String> primera = Csv.separar(lineas.get(1));
        Map<Integer, Integer> porTalla = new TreeMap<>();
        int total = 0;

        // TODO: recorrer las filas (desde la 1) y sumar la cantidad (columna 11) de cada
        //   talla (columna 10) en «porTalla», y el total de pares en «total».
        //   Si una fila no tiene el formato esperado, mensaje por stderr y salir con 5.

        out.println("REFERENCIA=" + primera.get(0));
        out.println("CLIENTE=" + primera.get(1));
        out.println("MODELO=" + primera.get(2));
        porTalla.forEach((talla, pares) -> out.println("TALLA." + talla + "=" + pares));
        out.println("TOTAL_PARES=" + total);
        System.exit(0);
    }
}
