package speake.psp;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.io.PrintStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardOpenOption;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;

// Proceso padre: lee el pedido, lanza los 3 hijos en cadena y guarda las evidencias
public final class ProcesadorPedidosCustom {

    static final int TIMEOUT = -1;
    private static final Path SALIDA = Paths.get("salida");
    private static final DateTimeFormatter HORA = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss.SSS");
    private static PrintStream out;
    private static int timeoutSeg = 5;
    private static long retardoMs = 0;

    // Lo que devuelve cada hijo: su código de salida, lo que escribió y sus errores
    record Resultado(String proceso, int codigo, String stdout, String stderr) {
        boolean ok() {
            return codigo == 0;
        }
    }

    private ProcesadorPedidosCustom() { }

    public static void main(String[] args) throws Exception {
        out = Csv.salida();
        String fichero = "datos/ficha_fabricacion.csv";
        boolean paralelo = false;
        // Leemos los argumentos: fichero, --paralelo, --timeout y --retardo-ms
        for (int i = 0; i < args.length; i++) {
            switch (args[i]) {
                case "--paralelo" -> paralelo = true;
                case "--timeout" -> timeoutSeg = Integer.parseInt(args[++i]);
                case "--retardo-ms" -> retardoMs = Long.parseLong(args[++i]);
                default -> fichero = args[i];
            }
        }

        Path entrada = Paths.get(fichero);
        if (!Files.isRegularFile(entrada)) {
            out.println("ERROR: no existe el fichero " + entrada.toAbsolutePath());
            System.exit(2);
        }

        List<String> lineas;
        // El pedido puede venir en JSON o en CSV
        if (fichero.toLowerCase().endsWith(".json")) {
            try {
                lineas = JsonPedido.aFilasCsv(Files.readString(entrada, StandardCharsets.UTF_8));
            } catch (IllegalArgumentException e) {
                out.println("ERROR: JSON no válido: " + e.getMessage());
                System.exit(2);
                return;
            }
        } else {
            lineas = Files.readAllLines(entrada, StandardCharsets.UTF_8);
            lineas.removeIf(String::isBlank);
        }
        if (lineas.size() < 2) {
            out.println("ERROR: el fichero no tiene pedidos");
            System.exit(2);
        }

        String cabecera = lineas.get(0).replace("﻿", "");
        int colRef = Csv.separar(cabecera).indexOf("referencia");
        // Separamos las filas por pedido (SO003, SO005...)
        Map<String, List<String>> pedidos = new LinkedHashMap<>();
        for (String l : lineas.subList(1, lineas.size())) {
            String ref = colRef >= 0 ? Csv.separar(l).get(colRef) : "SIN_REF";
            pedidos.computeIfAbsent(ref, k -> new ArrayList<>()).add(l);
        }

        Files.createDirectories(SALIDA);
        out.println("Entrada: " + entrada + " · pedidos: " + pedidos.size()
            + " · modo: " + (paralelo ? "paralelo" : "secuencial") + " · timeout: " + timeoutSeg + " s");
        long inicio = System.currentTimeMillis();

        Map<String, String> estados = new LinkedHashMap<>();
        // En paralelo: hasta 3 pedidos a la vez, cada uno en un hilo
        if (paralelo) {
            ExecutorService pool = Executors.newFixedThreadPool(3);
            Map<String, Future<String>> tareas = new LinkedHashMap<>();
            for (Map.Entry<String, List<String>> p : pedidos.entrySet()) {
                String csv = cabecera + "\n" + String.join("\n", p.getValue()) + "\n";
                tareas.put(p.getKey(), pool.submit(() -> procesarPedido(p.getKey(), csv)));
            }
            for (Map.Entry<String, Future<String>> t : tareas.entrySet()) {
                estados.put(t.getKey(), t.getValue().get());
            }
            pool.shutdown();
        } else {
            // En secuencial: un pedido detrás de otro
            for (Map.Entry<String, List<String>> p : pedidos.entrySet()) {
                String csv = cabecera + "\n" + String.join("\n", p.getValue()) + "\n";
                estados.put(p.getKey(), procesarPedido(p.getKey(), csv));
            }
        }

        out.println();
        out.println("RESUMEN");
        estados.forEach((ref, estado) -> out.println("  " + ref + " -> " + estado));
        out.println("Tiempo total: " + (System.currentTimeMillis() - inicio) + " ms");
        out.println("Evidencias en " + SALIDA.toAbsolutePath());
        // 0 si todo fue bien, 1 si algún pedido falló
        boolean todoOk = estados.values().stream().allMatch("OK"::equals);
        System.exit(todoOk ? 0 : 1);
    }

    // Cadena validador → analizador → generador; si uno falla, no se lanza el siguiente
    static String procesarPedido(String ref, String csv) throws IOException, InterruptedException {
        Resultado val = ejecutarHijo("ValidadorPedidoCustom", csv);
        log(ref, val);
        if (!val.ok()) {
            return estado("VALIDACION", val);
        }
        Resultado ana = ejecutarHijo("AnalizadorTallas", val.stdout());
        log(ref, ana);
        if (!ana.ok()) {
            return estado("ANALISIS", ana);
        }
        Resultado gen = ejecutarHijo("GeneradorFichaTaller", ana.stdout());
        log(ref, gen);
        if (!gen.ok()) {
            return estado("FICHA", gen);
        }
        Files.writeString(SALIDA.resolve("ficha_taller_" + ref + ".txt"), gen.stdout(), StandardCharsets.UTF_8);
        return "OK";
    }

    private static String estado(String paso, Resultado r) {
        return r.codigo() == TIMEOUT ? "TIMEOUT_" + paso : "ERROR_" + paso + " (código " + r.codigo() + ")";
    }

    // Lanza un proceso hijo con ProcessBuilder y espera su resultado
    static Resultado ejecutarHijo(String clase, String entrada) throws IOException, InterruptedException {
        String java = Paths.get(System.getProperty("java.home"), "bin", "java").toString();
        List<String> comando = new ArrayList<>(List.of(java, "-Dfile.encoding=UTF-8",
            "-cp", System.getProperty("java.class.path"), "speake.psp." + clase));
        if (clase.equals("AnalizadorTallas") && retardoMs > 0) {
            comando.add("--retardo-ms");
            comando.add(String.valueOf(retardoMs));
        }
        // Arrancamos el hijo con el mismo Java y el mismo classpath
        Process p = new ProcessBuilder(comando).start();

        // stdout y stderr se leen a la vez en hilos aparte, así el hijo nunca se queda bloqueado
        CompletableFuture<String> salida = CompletableFuture.supplyAsync(() -> leer(p.getInputStream()));
        CompletableFuture<String> errores = CompletableFuture.supplyAsync(() -> leer(p.getErrorStream()));
        // Le pasamos el pedido por la entrada estándar y cerramos
        try (OutputStream os = p.getOutputStream()) {
            os.write(entrada.getBytes(StandardCharsets.UTF_8));
        } catch (IOException e) {
            errores.complete("el proceso cerró la entrada antes de tiempo");
        }

        // Si tarda demasiado lo paramos: primero por las buenas y luego a la fuerza
        if (!p.waitFor(timeoutSeg, TimeUnit.SECONDS)) {
            p.destroy();
            if (!p.waitFor(2, TimeUnit.SECONDS)) {
                p.destroyForcibly();
            }
            return new Resultado(clase, TIMEOUT, "", "superado el tiempo máximo de " + timeoutSeg + " s");
        }
        return new Resultado(clase, p.exitValue(), salida.join(), errores.join());
    }

    private static String leer(InputStream is) {
        try (InputStream in = is) {
            return new String(in.readAllBytes(), StandardCharsets.UTF_8);
        } catch (IOException e) {
            return "";
        }
    }

    // synchronized: en modo paralelo varios hilos escriben en el mismo log
    private static synchronized void log(String ref, Resultado r) throws IOException {
        String linea = LocalDateTime.now().format(HORA) + " | " + Thread.currentThread().getName() + " | " + ref
            + " | " + r.proceso() + " | salida=" + r.codigo();
        if (!r.stderr().isBlank()) {
            linea += " | " + r.stderr().trim().replace("\n", " / ");
        }
        out.println(linea);
        Files.writeString(SALIDA.resolve("procesamiento.log"), linea + System.lineSeparator(),
            StandardCharsets.UTF_8, StandardOpenOption.CREATE, StandardOpenOption.APPEND);
    }
}
