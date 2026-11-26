// Incremento 5: conversión del escaneo real (agrupación, estándar, filtro de
// RSSI y redes no dibujadas).
import 'package:app_espectro_wifi/modelo/canales.dart';
import 'package:app_espectro_wifi/modelo/punto_acceso.dart';
import 'package:app_espectro_wifi/modelo/redes_escaneadas.dart';
import 'package:flutter_test/flutter_test.dart';

RedEscaneada red(
  String bssid,
  int frecuencia, {
  String ssid = 'Lab',
  int rssi = -50,
  int ancho = 0,
  int? centro0,
  int? estandar,
}) =>
    RedEscaneada(
      ssid: ssid,
      bssid: bssid,
      frecuenciaMHz: frecuencia,
      rssiDbm: rssi,
      codigoAncho: ancho,
      centro0MHz: centro0,
      codigoEstandar: estandar,
    );

void main() {
  test('dos BSSID del mismo radio se vuelven un AP con varios SSID', () {
    final r = convertirRedes([
      red('aa:bb:cc:dd:ee:10', 5180, ssid: 'Lab', ancho: 2, centro0: 5210, rssi: -50),
      red('aa:bb:cc:dd:ee:11', 5180, ssid: 'Invitados', ancho: 2, centro0: 5210, rssi: -52),
    ]);
    expect(r.totalBssid, 2);
    expect(r.aps, hasLength(1));
    final ap = r.aps.single;
    expect(ap.variosSsid, isTrue);
    expect(ap.ssids, ['Lab', 'Invitados']);
    expect(ap.bssids, hasLength(2));
    expect(ap.canalOcupado.centroMHz, 5210);
    expect(ap.canalOcupado.subcanales, [36, 40, 44, 48]);
  });

  test('ax en 2.4 GHz se dibuja como n (aprox.)', () {
    final ap = convertirRedes([red('aa:00:00:00:00:01', 2437, estandar: 6)]).aps.single;
    expect(ap.banda, Banda.ghz24);
    expect(ap.canalPrimario, 6);
    expect(ap.estandar, Estandar.n);
    expect(ap.estandarAprox, isTrue);
  });

  test('ax en 5 GHz se dibuja como ac (aprox.)', () {
    final ap = convertirRedes([red('aa:00:00:00:00:02', 5745, estandar: 6)]).aps.single;
    expect(ap.banda, Banda.ghz5);
    expect(ap.estandar, Estandar.ac);
    expect(ap.estandarAprox, isTrue);
  });

  test('el filtro de −85 dBm esconde las débiles y las cuenta', () {
    final r = convertirRedes([
      red('aa:00:00:00:00:03', 2412, rssi: -60),
      red('bb:00:00:00:00:04', 2462, rssi: -88),
      red('cc:00:00:00:00:05', 5200, rssi: -90),
    ]);
    expect(r.aps, hasLength(1));
    expect(r.ocultasPorRssi, 2);
  });

  test('las redes vistas hace más de 60 s se ocultan salvo "Mostrar antiguas"', () {
    final hora = DateTime(2026, 11, 25, 10, 0, 30);
    final redes = [
      const RedEscaneada(
          ssid: 'Nueva', bssid: 'aa:00:00:00:00:10', frecuenciaMHz: 2412, rssiDbm: -50, edadMs: 5000),
      const RedEscaneada(
          ssid: 'Justo', bssid: 'bb:00:00:00:00:11', frecuenciaMHz: 2437, rssiDbm: -50, edadMs: 60000),
      const RedEscaneada(
          ssid: 'Vieja', bssid: 'cc:00:00:00:00:12', frecuenciaMHz: 2462, rssiDbm: -50, edadMs: 61000),
    ];
    final r = convertirRedes(redes, horaEscaneo: hora);
    expect(r.aps.map((a) => a.nombre), unorderedEquals(['Nueva', 'Justo']));
    expect(r.ocultasPorAntiguedad, 1);
    expect(r.ocultas, 1);
    // Vista a las = hora del escaneo − edadMs.
    expect(r.aps.firstWhere((a) => a.nombre == 'Nueva').vistaEn, DateTime(2026, 11, 25, 10, 0, 25));

    final todas = convertirRedes(redes, horaEscaneo: hora, mostrarAntiguas: true);
    expect(todas.aps, hasLength(3));
    expect(todas.ocultasPorAntiguedad, 0);
  });

  test('160 MHz con CCFS0/CCFS1: el centro es centerFreq1', () {
    final ap = convertirRedes([
      RedEscaneada(
        ssid: 'MARIBEL_5G',
        bssid: 'aa:00:00:00:00:07',
        frecuenciaMHz: 5200,
        rssiDbm: -60,
        codigoAncho: 3,
        centro0MHz: 5210,
        centro1MHz: 5250,
      ),
    ]).aps.single;
    expect(ap.canalPrimario, 40);
    final c = ap.canalOcupado;
    expect(c.inicioMHz, 5170);
    expect(c.finMHz, 5330);
    expect(c.subcanales, [36, 40, 44, 48, 52, 56, 60, 64]);
    expect(ap.centro0Android, 5210);
    expect(ap.centro1Android, 5250);
  });

  test('una red de 6 GHz va a noDibujadas', () {
    final r = convertirRedes([red('aa:00:00:00:00:06', 5975, ssid: '', rssi: -55)]);
    expect(r.aps, isEmpty);
    expect(r.noDibujadas, hasLength(1));
    expect(r.noDibujadas.single.titulo, contains('(red oculta)'));
  });
}
