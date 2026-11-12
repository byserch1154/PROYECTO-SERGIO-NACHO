package speake.psp;

import java.io.PrintStream;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * PROCESO HIJO 3 · GeneradorFichaTaller
 * stdin : resumen clave=valor del AnalizadorTallas
 * stdout: ficha auxiliar para el taller (la orden de fabricación oficial está en Odoo)
 * Códigos de salida: 0 = OK, 6 = resumen incompleto.
 */
public final class GeneradorFichaTaller {

    private GeneradorFichaTaller() { }

    public static void main(String[] args) throws Exception {
        PrintStream out = Csv.salida();
        PrintStream err = Csv.error();

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

        out.println("==============================================");
        out.println(" SPEAKE · FICHA AUXILIAR DE TALLER");
        out.println(" (la orden de fabricación oficial está en Odoo)");
        out.println("==============================================");
        out.println(" Pedido : " + datos.get("REFERENCIA"));
        out.println(" Cliente: " + datos.get("CLIENTE"));
        out.println(" Modelo : " + datos.get("MODELO"));
        out.println(" Pares  : " + datos.get("TOTAL_PARES"));
        out.println("----------------------------------------------");
        datos.forEach((clave, valor) -> {
            if (clave.startsWith("TALLA.")) {
                out.println(" Talla " + clave.substring("TALLA.".length()) + " : " + valor + " pares");
            }
        });
        out.println(" Fecha  : " + LocalDateTime.now().format(DateTimeFormatter.ISO_LOCAL_DATE_TIME));
        out.println("==============================================");
        System.exit(0);
    }
}
