package speake.psp;

import java.io.PrintStream;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.LinkedHashMap;
import java.util.Map;

// Proceso hijo 3: con el resumen monta la ficha que se imprime para el taller
public final class GeneradorFichaTaller {

    private GeneradorFichaTaller() { }

    public static void main(String[] args) throws Exception {
        PrintStream out = Csv.salida();
        PrintStream err = Csv.error();

        // Leemos el resumen clave=valor que manda el analizador
        Map<String, String> datos = new LinkedHashMap<>();
        for (String l : Csv.leerTodo(Csv.entrada())) {
            int igual = l.indexOf('=');
            if (igual > 0) {
                datos.put(l.substring(0, igual), l.substring(igual + 1));
            }
        }
        for (String clave : new String[] {"REFERENCIA", "CLIENTE", "MODELO", "TOTAL_PARES"}) {
            if (!datos.containsKey(clave)) {
                err.println("ERROR: falta " + clave + " en el resumen");
                System.exit(6);
            }
        }

        // La talla con más pares sirve de referencia para el tamaño de las barras
        int maximo = 1;
        for (Map.Entry<String, String> d : datos.entrySet()) {
            if (d.getKey().startsWith("TALLA.")) {
                maximo = Math.max(maximo, Integer.parseInt(d.getValue()));
            }
        }

        // A partir de aquí se dibuja la ficha
        String linea = "=".repeat(50);
        out.println(linea);
        out.println(" SPEAKE · FICHA AUXILIAR DE TALLER");
        out.println(" (la orden de fabricación oficial está en Odoo)");
        out.println(linea);
        out.println(" Pedido   : " + datos.get("REFERENCIA"));
        out.println(" Cliente  : " + datos.get("CLIENTE"));
        out.println(" Modelo   : " + datos.get("MODELO"));
        out.println(" Colores  : " + datos.getOrDefault("COLORES", "-"));
        out.println(" Texto    : " + datos.getOrDefault("TEXTO", "-"));
        out.println("-".repeat(50));
        for (Map.Entry<String, String> d : datos.entrySet()) {
            if (d.getKey().startsWith("TALLA.")) {
                int pares = Integer.parseInt(d.getValue());
                String barra = "#".repeat(Math.max(1, pares * 20 / maximo));
                out.printf(" Talla %s : %3d pares  %s%n", d.getKey().substring(6), pares, barra);
            }
        }
        out.println("-".repeat(50));
        out.println(" Total    : " + datos.get("TOTAL_PARES") + " pares");
        out.println(" Generada : " + LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss")));
        out.println(linea);
        System.exit(0);
    }
}
