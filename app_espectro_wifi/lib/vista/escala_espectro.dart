// Conversión entre frecuencia/potencia y píxeles. Todo el dibujo pasa por aquí,
// así lo que se ve coincide con lo que calcula el modelo.
import '../modelo/canales.dart';

/// Rango de frecuencias que se muestra por banda: el de la norma más un margen,
/// para que se vean los bordes de la banda.
Rango rangoVista(Banda b) => switch (b) {
      Banda.ghz24 => const Rango(2390, 2495),
      Banda.ghz5 => const Rango(5140, 5860),
      Banda.ghz6 => const Rango(5915, 7135),
    };

/// Ancho mínimo de la ventana con zoom máximo.
double anchoMinimoVista(Banda b) => b == Banda.ghz24 ? 20 : 40;

/// Tramo de frecuencias visible (zoom horizontal). La escala es siempre lineal:
/// el zoom no comprime ni estira partes de la banda, solo elige qué se ve.
class VentanaFrecuencia {
  const VentanaFrecuencia(this.inicioMHz, this.finMHz);

  factory VentanaFrecuencia.completa(Banda b) {
    final r = rangoVista(b);
    return VentanaFrecuencia(r.inicioMHz, r.finMHz);
  }

  final double inicioMHz;
  final double finMHz;

  double get anchoMHz => finMHz - inicioMHz;

  bool contiene(double desde, double hasta) => desde >= inicioMHz && hasta <= finMHz;

  /// Ventana tras un pellizco que empezó en esta ventana. [factor] es la escala
  /// horizontal acumulada del gesto; [fFoco] la frecuencia que estaba bajo los
  /// dedos al empezar; [fraccionFoco] dónde están ahora los dedos (0 = borde
  /// izquierdo, 1 = derecho). La frecuencia del foco se queda bajo los dedos,
  /// así que con un dedo (factor 1) el gesto es un desplazamiento.
  VentanaFrecuencia pellizcar({
    required double factor,
    required double fFoco,
    required double fraccionFoco,
    required Rango limite,
    required double anchoMinMHz,
  }) {
    final total = limite.finMHz - limite.inicioMHz;
    final ancho = (anchoMHz / factor).clamp(anchoMinMHz, total);
    final inicio = fFoco - fraccionFoco * ancho;
    return VentanaFrecuencia(inicio, inicio + ancho)._dentroDe(limite);
  }

  /// Misma ventana, desplazada para que [fMHz] quede en el centro.
  VentanaFrecuencia centrarEn(double fMHz, Rango limite) =>
      VentanaFrecuencia(fMHz - anchoMHz / 2, fMHz + anchoMHz / 2)._dentroDe(limite);

  VentanaFrecuencia _dentroDe(Rango limite) {
    var ini = inicioMHz, fin = finMHz;
    if (ini < limite.inicioMHz) {
      fin += limite.inicioMHz - ini;
      ini = limite.inicioMHz;
    }
    if (fin > limite.finMHz) {
      ini -= fin - limite.finMHz;
      fin = limite.finMHz;
    }
    return VentanaFrecuencia(ini < limite.inicioMHz ? limite.inicioMHz : ini, fin);
  }

  @override
  bool operator ==(Object other) =>
      other is VentanaFrecuencia &&
      other.inicioMHz == inicioMHz &&
      other.finMHz == finMHz;

  @override
  int get hashCode => Object.hash(inicioMHz, finMHz);
}

class EscalaEspectro {
  const EscalaEspectro({
    required this.fMinMHz,
    required this.fMaxMHz,
    required this.xIzq,
    required this.xDer,
    required this.yBase,
    required this.yTope,
  });

  final double fMinMHz;
  final double fMaxMHz;
  final double xIzq;
  final double xDer;

  /// y del eje de frecuencia (potencia relativa 0).
  final double yBase;

  /// y de la potencia relativa 1.
  final double yTope;

  double get pxPorMHz => (xDer - xIzq) / (fMaxMHz - fMinMHz);

  double x(double fMHz) => xIzq + (fMHz - fMinMHz) * pxPorMHz;

  double f(double x) => fMinMHz + (x - xIzq) / pxPorMHz;

  /// y para una potencia relativa 0..1 (lineal).
  double y(double relativa) => yBase - relativa * (yBase - yTope);

  /// y para una potencia en dBm (para los incrementos 4 y 5: RSSI real).
  double yDbm(double dbm, {double minDbm = -95, double maxDbm = -20}) =>
      y(((dbm - minDbm) / (maxDbm - minDbm)).clamp(0.0, 1.0));
}
