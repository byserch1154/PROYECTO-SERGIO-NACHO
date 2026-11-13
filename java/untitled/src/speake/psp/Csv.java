package speake.psp;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.PrintStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;

// Cosas comunes a todos los procesos: las columnas del pedido y leer/escribir en UTF-8
public final class Csv {

    public static final List<String> COLUMNAS = List.of(
        "referencia", "cliente", "modelo", "color_cuerpo", "color_franja", "color_puntera",
        "color_talon", "color_suela", "color_cordones", "texto_suela", "talla", "cantidad");

    private Csv() { }

    public static BufferedReader entrada() {
        return new BufferedReader(new InputStreamReader(System.in, StandardCharsets.UTF_8));
    }

    public static PrintStream salida() {
        return new PrintStream(System.out, true, StandardCharsets.UTF_8);
    }

    public static PrintStream error() {
        return new PrintStream(System.err, true, StandardCharsets.UTF_8);
    }

    // Lee todo lo que llega por la entrada estándar, sin líneas vacías
    public static List<String> leerTodo(BufferedReader in) throws IOException {
        List<String> lineas = new ArrayList<>();
        String l;
        while ((l = in.readLine()) != null) {
            if (!l.isBlank()) {
                lineas.add(l.replace("﻿", ""));
            }
        }
        return lineas;
    }

    // Parte una línea del CSV por las comas
    public static List<String> separar(String linea) {
        List<String> campos = new ArrayList<>();
        for (String c : linea.split(",", -1)) {
            campos.add(c.trim());
        }
        return campos;
    }
}
