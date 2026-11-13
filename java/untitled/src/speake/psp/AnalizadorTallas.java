package speake.psp;

import java.io.PrintStream;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;

// Proceso hijo 2: cuenta cuántos pares hay de cada talla
public final class AnalizadorTallas {

    private AnalizadorTallas() { }

    public static void main(String[] args) throws Exception {
        PrintStream out = Csv.salida();
        PrintStream err = Csv.error();

        // Solo para probar el timeout: hace esperar al proceso
        if (args.length == 2 && args[0].equals("--retardo-ms")) {
            Thread.sleep(Long.parseLong(args[1]));
        }

        List<String> lineas = Csv.leerTodo(Csv.entrada());
        if (lineas.size() < 2) {
            err.println("ERROR: no hay líneas que analizar");
            System.exit(5);
        }

        // TreeMap para que las tallas salgan ordenadas
        Map<Integer, Integer> porTalla = new TreeMap<>();
        int total = 0;
        for (String l : lineas.subList(1, lineas.size())) {
            List<String> f = Csv.separar(l);
            if (f.size() != Csv.COLUMNAS.size()) {
                err.println("ERROR: línea con formato incorrecto: " + l);
                System.exit(5);
            }
            int talla = Integer.parseInt(f.get(10));
            int pares = Integer.parseInt(f.get(11));
            porTalla.merge(talla, pares, Integer::sum);
            total += pares;
        }

        // Escribimos el resumen como clave=valor para el siguiente proceso
        List<String> primera = Csv.separar(lineas.get(1));
        out.println("REFERENCIA=" + primera.get(0));
        out.println("CLIENTE=" + primera.get(1));
        out.println("MODELO=" + primera.get(2));
        out.println("COLORES=" + String.join(" / ", primera.subList(3, 9)));
        out.println("TEXTO=" + primera.get(9));
        porTalla.forEach((talla, pares) -> out.println("TALLA." + talla + "=" + pares));
        out.println("TOTAL_PARES=" + total);
        System.exit(0);
    }
}
