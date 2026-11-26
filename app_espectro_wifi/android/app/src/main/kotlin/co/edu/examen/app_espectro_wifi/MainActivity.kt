package co.edu.examen.app_espectro_wifi

// Incremento 5: escaneo real de redes Wi-Fi con el WifiManager de Android,
// expuesto a Dart por un canal de plataforma propio ("espectro/wifi").
// Sin paquetes externos (wifi_scan y permission_handler no declaran soporte
// para AGP 9).
//
// Métodos del canal:
//  - estado: permisos, ubicación, Wi-Fi y el problema que impide escanear.
//  - pedirPermisos: pide los permisos que falten y devuelve el estado nuevo.
//  - escanear: startScan() y espera el broadcast SCAN_RESULTS_AVAILABLE_ACTION.
//    Si Android rechaza el escaneo por el límite (throttling: 4 escaneos cada
//    2 minutos con la app en primer plano), devuelve los resultados guardados
//    con estado "limitado".
//  - abrirAjustesUbicacion / abrirAjustesApp / abrirAjustesWifi.
//
// Incremento 6 (reporte PDF), por el mismo canal:
//  - modelo: Build.MODEL del celular.
//  - guardarPdf(bytes, nombre): desde API 29 lo guarda en Descargas con
//    MediaStore; antes, en getExternalFilesDir(Download) con Uri de
//    FileProvider (sin permiso de almacenamiento). Devuelve {uri, descargas}.
//  - compartirPdf(uri): ACTION_SEND con FLAG_GRANT_READ_URI_PERMISSION.

import android.Manifest
import android.content.BroadcastReceiver
import android.content.ClipData
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.location.LocationManager
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.MediaStore
import android.provider.Settings
import androidx.annotation.RequiresApi
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val nombreCanal = "espectro/wifi"
    private val codigoPermisos = 4501

    /// Si no llega el broadcast en este tiempo, se devuelve lo guardado.
    private val esperaMaximaMs = 12_000L

    private var resultadoPermisos: MethodChannel.Result? = null
    private var resultadoEscaneo: MethodChannel.Result? = null
    private var receptor: BroadcastReceiver? = null
    private var tiempoAgotado: Runnable? = null
    private val handler = Handler(Looper.getMainLooper())

    private val wifi: WifiManager by lazy {
        applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
    }

    private val preferencias by lazy { getSharedPreferences("escaneo_wifi", Context.MODE_PRIVATE) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, nombreCanal)
            .setMethodCallHandler { llamada, resultado ->
                when (llamada.method) {
                    "estado" -> resultado.success(estado())
                    "pedirPermisos" -> pedirPermisos(resultado)
                    "escanear" -> escanear(resultado)
                    "abrirAjustesUbicacion" -> abrir(Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS), resultado)
                    "abrirAjustesWifi" -> abrir(Intent(Settings.ACTION_WIFI_SETTINGS), resultado)
                    "abrirAjustesApp" -> abrir(
                        Intent(
                            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            Uri.fromParts("package", packageName, null),
                        ),
                        resultado,
                    )
                    "modelo" -> resultado.success(Build.MODEL)
                    "guardarPdf" -> guardarPdf(
                        llamada.argument<ByteArray>("bytes"),
                        llamada.argument<String>("nombre"),
                        resultado,
                    )
                    "compartirPdf" -> compartirPdf(llamada.argument<String>("uri"), resultado)
                    else -> resultado.notImplemented()
                }
            }
    }

    // --- Permisos y estado -------------------------------------------------------

    private fun permisosNecesarios(): List<String> {
        // COARSE va junto con FINE: desde Android 12 el diálogo los pide juntos.
        val lista = mutableListOf(
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_COARSE_LOCATION,
        )
        if (Build.VERSION.SDK_INT >= 33) lista.add(Manifest.permission.NEARBY_WIFI_DEVICES)
        return lista
    }

    private fun faltantes(): List<String> =
        permisosNecesarios().filter { checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }

    /// Negado "para siempre": ya se pidió y Android no deja volver a mostrar el
    /// diálogo (shouldShowRequestPermissionRationale es false después de negar).
    private fun negadoParaSiempre(falta: List<String>): Boolean {
        if (falta.isEmpty()) return false
        if (!preferencias.getBoolean("ya_pedido", false)) return false
        return falta.any { !shouldShowRequestPermissionRationale(it) }
    }

    private fun ubicacionEncendida(): Boolean {
        val lm = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        return if (Build.VERSION.SDK_INT >= 28) {
            lm.isLocationEnabled
        } else {
            @Suppress("DEPRECATION")
            Settings.Secure.getInt(contentResolver, Settings.Secure.LOCATION_MODE, 0) != 0
        }
    }

    @Suppress("DEPRECATION")
    private fun wifiUtilizable(): Boolean = wifi.isWifiEnabled || wifi.isScanAlwaysAvailable

    private fun problema(): String? {
        val falta = faltantes()
        return when {
            falta.isNotEmpty() -> if (negadoParaSiempre(falta)) "permisosNegados" else "sinPermisos"
            !ubicacionEncendida() -> "ubicacionApagada"
            !wifiUtilizable() -> "wifiApagado"
            else -> null
        }
    }

    private fun estado(): Map<String, Any?> = mapOf(
        "problema" to problema(),
        "faltan" to faltantes(),
        "ubicacion" to ubicacionEncendida(),
        "wifi" to wifi.isWifiEnabled,
        "sdk" to Build.VERSION.SDK_INT,
    )

    private fun pedirPermisos(resultado: MethodChannel.Result) {
        if (resultadoPermisos != null) {
            resultado.error("OCUPADO", "Ya se están pidiendo los permisos", null)
            return
        }
        val falta = faltantes()
        if (falta.isEmpty()) {
            resultado.success(estado())
            return
        }
        preferencias.edit().putBoolean("ya_pedido", true).apply()
        resultadoPermisos = resultado
        requestPermissions(falta.toTypedArray(), codigoPermisos)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != codigoPermisos) return
        resultadoPermisos?.success(estado())
        resultadoPermisos = null
    }

    private fun abrir(intent: Intent, resultado: MethodChannel.Result) {
        try {
            startActivity(intent)
            resultado.success(true)
        } catch (e: Exception) {
            resultado.success(false)
        }
    }

    // --- Reporte PDF (incremento 6) ------------------------------------------------

    /// Escribe el PDF en un hilo aparte y responde en el hilo principal.
    private fun guardarPdf(bytes: ByteArray?, nombre: String?, resultado: MethodChannel.Result) {
        if (bytes == null || bytes.isEmpty() || nombre.isNullOrBlank()) {
            resultado.error("argumentos", "Faltan los bytes o el nombre del PDF", null)
            return
        }
        Thread {
            try {
                val r = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    guardarEnDescargas(bytes, nombre)
                } else {
                    guardarEnCarpetaApp(bytes, nombre)
                }
                handler.post { resultado.success(r) }
            } catch (e: Exception) {
                handler.post { resultado.error("guardar", e.message ?: e.toString(), null) }
            }
        }.start()
    }

    /// API 29+: Descargas con MediaStore (sin permisos). IS_PENDING oculta el
    /// archivo hasta que termina de escribirse.
    @RequiresApi(Build.VERSION_CODES.Q)
    private fun guardarEnDescargas(bytes: ByteArray, nombre: String): Map<String, Any?> {
        val valores = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, nombre)
            put(MediaStore.MediaColumns.MIME_TYPE, "application/pdf")
            put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, valores)
            ?: throw IllegalStateException("MediaStore no creó el archivo")
        try {
            contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
                ?: throw IllegalStateException("No se pudo abrir el archivo")
            valores.clear()
            valores.put(MediaStore.MediaColumns.IS_PENDING, 0)
            contentResolver.update(uri, valores, null, null)
        } catch (e: Exception) {
            contentResolver.delete(uri, null, null)
            throw e
        }
        return mapOf("uri" to uri.toString(), "descargas" to true)
    }

    /// API < 29: carpeta de descargas propia de la app (Android/data/.../files/
    /// Download), con Uri de FileProvider para poder compartirlo.
    private fun guardarEnCarpetaApp(bytes: ByteArray, nombre: String): Map<String, Any?> {
        val carpeta = getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS) ?: filesDir
        carpeta.mkdirs()
        val archivo = java.io.File(carpeta, nombre)
        archivo.writeBytes(bytes)
        val uri = FileProvider.getUriForFile(this, "$packageName.archivos", archivo)
        return mapOf("uri" to uri.toString(), "descargas" to false, "ruta" to archivo.absolutePath)
    }

    private fun compartirPdf(uriTexto: String?, resultado: MethodChannel.Result) {
        if (uriTexto.isNullOrBlank()) {
            resultado.error("argumentos", "Falta la Uri del PDF", null)
            return
        }
        try {
            val uri = Uri.parse(uriTexto)
            val envio = Intent(Intent.ACTION_SEND).apply {
                type = "application/pdf"
                putExtra(Intent.EXTRA_STREAM, uri)
                putExtra(Intent.EXTRA_SUBJECT, "Reporte de análisis del espectro Wi-Fi")
                // ClipData además de EXTRA_STREAM: así el permiso de lectura
                // llega también a través del selector (createChooser).
                clipData = ClipData.newRawUri("Reporte PDF", uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            val selector = Intent.createChooser(envio, "Compartir reporte").apply {
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(selector)
            resultado.success(true)
        } catch (e: Exception) {
            resultado.error("compartir", e.message ?: e.toString(), null)
        }
    }

    // --- Escaneo -----------------------------------------------------------------

    private fun escanear(resultado: MethodChannel.Result) {
        if (resultadoEscaneo != null) {
            resultado.error("OCUPADO", "Ya hay un escaneo en curso", null)
            return
        }
        val p = problema()
        if (p != null) {
            resultado.success(mapOf("problema" to p))
            return
        }
        resultadoEscaneo = resultado

        val r = object : BroadcastReceiver() {
            override fun onReceive(contexto: Context, intent: Intent) {
                // false: Android no hizo un escaneo nuevo (límite u otra causa)
                // y lo que hay son los resultados anteriores.
                val nuevos = intent.getBooleanExtra(WifiManager.EXTRA_RESULTS_UPDATED, false)
                terminar(if (nuevos) "aceptado" else "limitado")
            }
        }
        receptor = r
        val filtro = IntentFilter(WifiManager.SCAN_RESULTS_AVAILABLE_ACTION)
        if (Build.VERSION.SDK_INT >= 33) {
            registerReceiver(r, filtro, Context.RECEIVER_EXPORTED)
        } else {
            registerReceiver(r, filtro)
        }

        // startScan() está "deprecado" desde Android 9, pero es la única forma
        // de pedir un escaneo; devuelve false cuando el límite lo rechaza.
        @Suppress("DEPRECATION")
        val iniciado = try {
            wifi.startScan()
        } catch (e: SecurityException) {
            false
        }
        if (!iniciado) {
            terminar("limitado")
            return
        }
        val t = Runnable { terminar("sinRespuesta") }
        tiempoAgotado = t
        handler.postDelayed(t, esperaMaximaMs)
    }

    private fun limpiarEscaneo() {
        tiempoAgotado?.let { handler.removeCallbacks(it) }
        tiempoAgotado = null
        receptor?.let {
            try {
                unregisterReceiver(it)
            } catch (e: IllegalArgumentException) {
            }
        }
        receptor = null
    }

    private fun terminar(estadoEscaneo: String) {
        val resultado = resultadoEscaneo ?: return
        resultadoEscaneo = null
        limpiarEscaneo()
        try {
            resultado.success(
                mapOf(
                    "estado" to estadoEscaneo,
                    "redes" to redes(),
                ),
            )
        } catch (e: SecurityException) {
            resultado.success(mapOf("problema" to "sinPermisos"))
        }
    }

    private fun redes(): List<Map<String, Any?>> {
        val ahoraUs = SystemClock.elapsedRealtimeNanos() / 1000
        return wifi.scanResults.map { r ->
            @Suppress("DEPRECATION")
            val ssid = (r.SSID ?: "").removeSurrounding("\"")
            mapOf(
                "ssid" to ssid,
                "bssid" to (r.BSSID ?: ""),
                "frecuencia" to r.frequency,
                // ScanResult.CHANNEL_WIDTH_*: 0=20, 1=40, 2=80, 3=160, 4=80+80, 5=320 MHz.
                "ancho" to r.channelWidth,
                "centro0" to r.centerFreq0,
                "centro1" to r.centerFreq1,
                "rssi" to r.level,
                // ScanResult.WIFI_STANDARD_*: 1=legacy, 4=n, 5=ac, 6=ax, 7=ad, 8=be.
                "estandar" to (if (Build.VERSION.SDK_INT >= 30) r.wifiStandard else null),
                // timestamp: microsegundos desde el arranque cuando se vio la red.
                "edadMs" to ((ahoraUs - r.timestamp) / 1000).coerceAtLeast(0),
            )
        }
    }

    override fun onDestroy() {
        limpiarEscaneo()
        resultadoEscaneo = null
        super.onDestroy()
    }
}
