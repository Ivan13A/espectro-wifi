// Incremento 5: escaneo real de redes Wi-Fi por el canal de plataforma
// "espectro/wifi" (MainActivity.kt, WifiManager). Sin paquetes externos.
//
// ControladorEscaneo guarda el último escaneo, el filtro de RSSI y los
// problemas (permisos, ubicación, Wi-Fi, límite de Android) y mete los APs en
// ModeloAps con reemplazarEscaneados(). Hay uno por ModeloAps
// (ControladorEscaneo.de), así las dos pestañas ven el mismo escaneo.
//
// En el navegador (y en cualquier plataforma que no sea Android) el escaneo
// no existe: el controlador lo dice y no llama al canal.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../modelo/canales.dart';
import '../modelo/lista_aps.dart';
import '../modelo/redes_escaneadas.dart';

enum ProblemaEscaneo {
  /// Navegador u otra plataforma: no hay acceso al Wi-Fi del equipo.
  noDisponible,

  /// Faltan permisos y se pueden pedir.
  sinPermisos,

  /// Se negaron y Android ya no muestra el diálogo: toca ir a Ajustes.
  permisosNegados,

  /// La ubicación del celular está apagada: Android devuelve la lista vacía.
  ubicacionApagada,
  wifiApagado,
  error,
}

enum EstadoEscaneo {
  /// Android hizo un escaneo nuevo.
  aceptado,

  /// Android rechazó el escaneo (límite de frecuencia): resultados guardados.
  limitado,

  /// Android no avisó a tiempo: resultados guardados.
  sinRespuesta,
}

class ControladorEscaneo extends ChangeNotifier {
  ControladorEscaneo._(this.modelo);

  static final _porModelo = Expando<ControladorEscaneo>();

  /// El controlador de [modelo] (se crea la primera vez).
  static ControladorEscaneo de(ModeloAps modelo) =>
      _porModelo[modelo] ??= ControladorEscaneo._(modelo);

  static const _canal = MethodChannel('espectro/wifi');

  final ModeloAps modelo;

  /// Solo la app de Android puede escanear.
  bool get disponible => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool ocupado = false;
  ProblemaEscaneo? problema;
  String? detalleError;

  EstadoEscaneo? estado;

  /// Cuándo se pulsó "Escanear" por última vez con respuesta de Android.
  DateTime? horaUltimo;

  /// Cuándo vio Android las redes más recientes (puede ser antes de
  /// [horaUltimo] si el escaneo fue rechazado).
  DateTime? horaResultados;

  double rssiMinimo = rssiMinimoPorDefecto;

  List<RedEscaneada> _redes = const [];
  ResultadoConversion conversion = ResultadoConversion.vacio;

  int escaneadosEn(Banda banda) => [
        for (final a in conversion.aps)
          if (a.banda == banda) a,
      ].length;

  // --- Acciones ------------------------------------------------------------------

  Future<void> escanear() async {
    if (ocupado) return;
    if (!disponible) {
      problema = ProblemaEscaneo.noDisponible;
      notifyListeners();
      return;
    }
    ocupado = true;
    detalleError = null;
    notifyListeners();
    try {
      var r = await _canal.invokeMapMethod<String, Object?>('escanear');
      // Faltan permisos que aún se pueden pedir: se piden y se reintenta.
      if (r?['problema'] == 'sinPermisos') {
        final est = await _canal.invokeMapMethod<String, Object?>('pedirPermisos');
        final p = est?['problema'];
        r = p == null ? await _canal.invokeMapMethod<String, Object?>('escanear') : est;
      }
      _procesar(r ?? const {});
    } on MissingPluginException {
      problema = ProblemaEscaneo.noDisponible;
    } on PlatformException catch (e) {
      problema = ProblemaEscaneo.error;
      detalleError = e.message ?? e.code;
    } finally {
      ocupado = false;
      notifyListeners();
    }
  }

  void _procesar(Map<String, Object?> r) {
    final p = r['problema'] as String?;
    if (p != null) {
      problema = ProblemaEscaneo.values.where((v) => v.name == p).firstOrNull ??
          ProblemaEscaneo.error;
      return;
    }
    problema = null;
    estado = EstadoEscaneo.values.where((v) => v.name == r['estado']).firstOrNull ??
        EstadoEscaneo.aceptado;
    final lista = (r['redes'] as List<Object?>?) ?? const [];
    _redes = [
      for (final m in lista)
        if (m is Map) RedEscaneada.desdeMapa(m),
    ];
    final ahora = DateTime.now();
    horaUltimo = ahora;
    final edades = [for (final red in _redes) ?red.edadMs];
    horaResultados = edades.isEmpty
        ? null
        : ahora.subtract(Duration(milliseconds: edades.reduce((a, b) => a < b ? a : b)));
    _aplicar();
  }

  /// Convierte las redes guardadas con el filtro actual y las pone en la lista.
  void _aplicar() {
    final colores = <Banda, Set<int>>{};
    for (final a in modelo.aps) {
      if (!a.escaneado) colores.putIfAbsent(a.banda, () => <int>{}).add(a.colorIndice);
    }
    conversion = convertirRedes(
      _redes,
      rssiMinimo: rssiMinimo,
      coloresOcupados: colores,
      horaEscaneo: horaUltimo,
      mostrarAntiguas: mostrarAntiguas,
    );
    modelo.reemplazarEscaneados(conversion.aps);
  }

  /// Si se muestran también las redes vistas hace más de 60 s al escanear.
  bool mostrarAntiguas = false;

  void cambiarMostrarAntiguas(bool v) {
    if (v == mostrarAntiguas) return;
    mostrarAntiguas = v;
    if (horaUltimo != null) _aplicar();
    notifyListeners();
  }

  void cambiarRssiMinimo(double v) {
    if (v == rssiMinimo) return;
    rssiMinimo = v;
    if (horaUltimo != null) _aplicar();
    notifyListeners();
  }

  /// Quita los APs escaneados de la lista (los simulados quedan).
  void limpiar() {
    _redes = const [];
    conversion = ResultadoConversion.vacio;
    estado = null;
    horaUltimo = null;
    horaResultados = null;
    modelo.limpiarEscaneados();
    notifyListeners();
  }

  Future<void> pedirPermisos() async {
    if (!disponible) return;
    try {
      final est = await _canal.invokeMapMethod<String, Object?>('pedirPermisos');
      final p = est?['problema'] as String?;
      problema = p == null
          ? null
          : ProblemaEscaneo.values.where((v) => v.name == p).firstOrNull;
      notifyListeners();
      if (problema == null) await escanear();
    } on PlatformException catch (e) {
      problema = ProblemaEscaneo.error;
      detalleError = e.message ?? e.code;
      notifyListeners();
    }
  }

  Future<void> abrirAjustesApp() => _abrir('abrirAjustesApp');
  Future<void> abrirAjustesUbicacion() => _abrir('abrirAjustesUbicacion');
  Future<void> abrirAjustesWifi() => _abrir('abrirAjustesWifi');

  Future<void> _abrir(String metodo) async {
    if (!disponible) return;
    try {
      await _canal.invokeMethod<bool>(metodo);
    } on PlatformException {
      // Si no se puede abrir, el mensaje en pantalla ya dice qué hacer.
    }
  }
}
