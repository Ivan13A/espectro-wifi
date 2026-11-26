// Incremento 6: guardar y compartir el reporte PDF por el canal propio
// "espectro/wifi" (MainActivity.kt). Sin paquetes externos (ni printing,
// ni path_provider, ni share_plus). Solo existe en la app de Android.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class PdfGuardado {
  const PdfGuardado({required this.uri, required this.enDescargas, this.ruta});

  /// content:// de MediaStore (API 29+) o de FileProvider (API < 29).
  final String uri;

  /// true si quedó en Descargas; false si quedó en la carpeta de la app
  /// (API < 29), y entonces se abre Compartir de una vez.
  final bool enDescargas;
  final String? ruta;
}

abstract final class ArchivosPdf {
  static const _canal = MethodChannel('espectro/wifi');

  static bool get disponible => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Build.MODEL, o null si no se pudo leer.
  static Future<String?> modeloCelular() async {
    if (!disponible) return null;
    try {
      return await _canal.invokeMethod<String>('modelo');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Lanza PlatformException si Android no pudo guardarlo.
  static Future<PdfGuardado> guardar(Uint8List bytes, String nombre) async {
    final r = await _canal.invokeMapMethod<String, Object?>(
      'guardarPdf',
      {'bytes': bytes, 'nombre': nombre},
    );
    final uri = r?['uri'] as String?;
    if (uri == null) {
      throw PlatformException(code: 'guardar', message: 'Android no devolvió la Uri');
    }
    return PdfGuardado(
      uri: uri,
      enDescargas: r?['descargas'] == true,
      ruta: r?['ruta'] as String?,
    );
  }

  static Future<void> compartir(String uri) =>
      _canal.invokeMethod<bool>('compartirPdf', {'uri': uri});
}
