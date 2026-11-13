package speake.psp;

import java.util.ArrayList;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

// Convierte el pedido en JSON a las mismas filas que el CSV, así el resto no cambia
public final class JsonPedido {

    private static final Pattern LINEA = Pattern.compile(
        "\\{\\s*\"talla\"\\s*:\\s*(-?\\d+)\\s*,\\s*\"cantidad\"\\s*:\\s*(-?\\d+)\\s*}");

    private JsonPedido() { }

    public static List<String> aFilasCsv(String json) {
        String referencia = texto(json, "referencia");
        if (referencia.isEmpty() || !json.trim().endsWith("}")) {
            throw new IllegalArgumentException("JSON incompleto o sin referencia");
        }
        // Estos datos son iguales en todas las filas del pedido
        String comun = String.join(",", referencia, texto(json, "cliente"), texto(json, "modelo"),
            texto(json, "cuerpo"), texto(json, "franja"), texto(json, "puntera"),
            texto(json, "talon"), texto(json, "suela"), texto(json, "cordones"), texto(json, "texto_suela"));

        List<String> filas = new ArrayList<>();
        filas.add(String.join(",", Csv.COLUMNAS));
        // Una fila por cada talla que encontremos
        Matcher m = LINEA.matcher(json);
        while (m.find()) {
            filas.add(comun + "," + m.group(1) + "," + m.group(2));
        }
        if (filas.size() == 1) {
            throw new IllegalArgumentException("el JSON no tiene líneas de tallas");
        }
        return filas;
    }

    private static String texto(String json, String clave) {
        Matcher m = Pattern.compile("\"" + clave + "\"\\s*:\\s*\"([^\"]*)\"").matcher(json);
        return m.find() ? m.group(1) : "";
    }
}
