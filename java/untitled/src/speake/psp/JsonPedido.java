package speake.psp;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Lector del contrato JSON de un pedido Custom.
 * Convierte el JSON de ejemplo (referencia, cliente, modelo, colores y líneas)
 * a las mismas filas CSV que usa el resto del procesador.
 *
 * Es un lector para el esquema fijo del proyecto, no un parser JSON genérico.
 * Si el contrato cambia, hay que ampliar este lector.
 */
final class JsonPedido {

    private static final Pattern LINEAS =
        Pattern.compile("\"lineas\"\\s*:\\s*\\[(.*?)\\]", Pattern.DOTALL);
    private static final Pattern OBJETO = Pattern.compile("\\{([^{}]*)\\}");
    private static final Pattern COLORES =
        Pattern.compile("\"colores\"\\s*:\\s*\\{([^{}]*)\\}", Pattern.DOTALL);

    private JsonPedido() { }

    static List<String> aLineas(Path ruta) throws IOException {
        String json = Files.readString(ruta, StandardCharsets.UTF_8);

        String referencia = requerido(json, "referencia");
        String cliente = requerido(json, "cliente");
        String modelo = requerido(json, "modelo");
        String textoSuela = texto(json, "texto_suela");

        Matcher mc = COLORES.matcher(json);
        if (!mc.find()) {
            throw new IllegalArgumentException("JSON sin objeto colores");
        }
        String colores = mc.group(1);
        String cuerpo = requerido(colores, "cuerpo");
        String franja = requerido(colores, "franja");
        String puntera = requerido(colores, "puntera");
        String talon = requerido(colores, "talon");
        String suela = requerido(colores, "suela");
        String cordones = requerido(colores, "cordones");

        Matcher ml = LINEAS.matcher(json);
        if (!ml.find()) {
            throw new IllegalArgumentException("JSON sin array lineas");
        }
        List<String> filas = new ArrayList<>();
        filas.add(String.join(",", Csv.COLUMNAS));

        Matcher mo = OBJETO.matcher(ml.group(1));
        while (mo.find()) {
            String objeto = mo.group(1);
            int talla = entero(objeto, "talla");
            int cantidad = entero(objeto, "cantidad");
            if (talla < 38 || talla > 46) {
                throw new IllegalArgumentException("talla fuera de 38-46: " + talla);
            }
            if (cantidad <= 0) {
                throw new IllegalArgumentException("cantidad no positiva: " + cantidad);
            }
            filas.add(String.join(",",
                referencia, cliente, modelo,
                cuerpo, franja, puntera, talon, suela, cordones,
                textoSuela, Integer.toString(talla), Integer.toString(cantidad)));
        }

        if (filas.size() == 1) {
            throw new IllegalArgumentException("JSON sin líneas de pedido");
        }
        return filas;
    }

    private static String requerido(String json, String clave) {
        String valor = texto(json, clave);
        if (valor.isBlank()) {
            throw new IllegalArgumentException("campo vacío en JSON: " + clave);
        }
        return valor;
    }

    /** Extrae un texto entre comillas y valida que no rompa el CSV. */
    private static String texto(String json, String clave) {
        Pattern p = Pattern.compile("\"" + Pattern.quote(clave)
            + "\"\\s*:\\s*\"((?:\\\\.|[^\"\\\\])*)\"");
        Matcher m = p.matcher(json);
        if (!m.find()) {
            throw new IllegalArgumentException("falta el campo JSON: " + clave);
        }
        String valor = desescapar(m.group(1));
        if (valor.contains(",") || valor.contains("\n") || valor.contains("\r")) {
            throw new IllegalArgumentException("el campo " + clave + " no puede llevar comas ni saltos de línea");
        }
        return valor;
    }

    private static int entero(String json, String clave) {
        Pattern p = Pattern.compile("\"" + Pattern.quote(clave)
            + "\"\\s*:\\s*\"?(-?\\d+)\"?");
        Matcher m = p.matcher(json);
        if (!m.find()) {
            throw new IllegalArgumentException("falta el número JSON: " + clave);
        }
        try {
            return Integer.parseInt(m.group(1));
        } catch (NumberFormatException e) {
            throw new IllegalArgumentException("número JSON no válido: " + clave);
        }
    }

    private static String desescapar(String s) {
        StringBuilder b = new StringBuilder();
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            if (c != '\\') {
                b.append(c);
                continue;
            }
            if (++i >= s.length()) {
                throw new IllegalArgumentException("escape incompleto en JSON");
            }
            switch (s.charAt(i)) {
                case '"' -> b.append('"');
                case '\\' -> b.append('\\');
                case 'n' -> b.append('\n');
                case 'r' -> b.append('\r');
                case 't' -> b.append('\t');
                default -> throw new IllegalArgumentException("escape JSON no soportado");
            }
        }
        return b.toString();
    }
}
