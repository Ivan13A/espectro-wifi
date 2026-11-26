// Incremento 5: tarjeta "Escaneo real" sobre la lista de APs. Botón Escanear,
// hora del último escaneo, aviso del límite de Android, problemas de permisos,
// ubicación o Wi-Fi con su solución, filtro de RSSI mínimo y redes que no se
// dibujan (6 GHz, fuera de la rejilla...).
//
// Requisito del examen que cubre: validación en laboratorio (detectar las redes
// reales, su banda y canal, y compararlas con la simulación).
import 'package:material_ui/material_ui.dart';

import '../modelo/canales.dart';
import '../modelo/lista_aps.dart';
import '../servicios/escaner_wifi.dart';

String _hora(DateTime t) =>
    [t.hour, t.minute, t.second].map((v) => v.toString().padLeft(2, '0')).join(':');

class PanelEscaneo extends StatelessWidget {
  const PanelEscaneo({super.key, required this.modelo, required this.banda});

  final ModeloAps modelo;
  final Banda banda;

  static const _opcionesRssi = <double>[-100, -90, -85, -80, -75, -70, -65];

  @override
  Widget build(BuildContext context) {
    final esc = ControladorEscaneo.de(modelo);
    return ListenableBuilder(
      listenable: Listenable.merge([esc, modelo]),
      builder: (context, _) {
        final tema = Theme.of(context).textTheme;
        final aviso = tema.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.error,
        );
        final conv = esc.conversion;
        final hijos = <Widget>[
          Row(children: [
            const Icon(Icons.wifi_find, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text('Escaneo real', style: tema.titleSmall)),
            if (esc.horaUltimo != null)
              Tooltip(
                message: 'Quitar las redes escaneadas',
                child: TextButton(
                  onPressed: esc.ocupado ? null : esc.limpiar,
                  child: const Text('Limpiar'),
                ),
              ),
            FilledButton.icon(
              onPressed: esc.disponible && !esc.ocupado ? esc.escanear : null,
              icon: esc.ocupado
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.radar, size: 18),
              label: Text(esc.ocupado ? 'Escaneando…' : 'Escanear'),
            ),
          ]),
        ];

        if (!esc.disponible) {
          hijos.add(Text(
            'El escaneo real solo funciona en la app de Android: el navegador no '
            'tiene acceso al Wi-Fi del equipo. Aquí puedes trabajar con APs simulados.',
            style: tema.bodySmall,
          ));
          return _tarjeta(hijos);
        }

        // Hora y resumen.
        final hora = esc.horaUltimo;
        hijos.add(Text(
          hora == null
              ? 'Aún no has escaneado. Las redes reales aparecen en la lista como '
                  'APs de solo lectura, sobre el mismo espectro que los simulados.'
              : 'Último escaneo: ${_hora(hora)} · ${conv.totalBssid} BSSID → '
                  '${conv.totalEquipos} equipos · ${esc.escaneadosEn(banda)} en ${banda.nombre}',
          style: tema.bodySmall,
        ));

        // Límite de Android.
        final resultados = esc.horaResultados;
        final deCuando = resultados == null ? '' : ' (vistos a las ${_hora(resultados)})';
        if (esc.estado == EstadoEscaneo.limitado) {
          hijos.add(Text(
            'Android rechazó el escaneo por el límite de frecuencia (4 escaneos cada '
            '2 minutos con la app abierta). Se muestran los resultados guardados$deCuando. '
            'Espera un momento y vuelve a escanear.',
            style: aviso,
          ));
        } else if (esc.estado == EstadoEscaneo.sinRespuesta) {
          hijos.add(Text(
            'Android no avisó a tiempo que terminó el escaneo. Se muestran los '
            'resultados guardados$deCuando.',
            style: aviso,
          ));
        } else if (esc.estado == EstadoEscaneo.aceptado && conv.totalBssid == 0) {
          hijos.add(Text(
            'Android no devolvió redes. Revisa que la ubicación del celular esté '
            'encendida y vuelve a escanear.',
            style: aviso,
          ));
        }

        // Problemas con su solución.
        final p = esc.problema;
        if (p != null) hijos.add(_problema(context, esc, p));

        // Solo redes reales: apaga los simulados de la banda sin borrarlos.
        // Deshabilitado sin redes escaneadas (salvo que ya esté activo, para poder quitarlo).
        final hayReales = modelo.aps.any((a) => a.escaneado && a.banda == banda);
        final soloReales = modelo.soloReales(banda);
        final puede = hayReales || soloReales;
        hijos.add(Tooltip(
          message: puede ? 'Apaga los APs simulados de ${banda.nombre} sin borrarlos' : 'Escanea primero',
          child: SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text('Solo redes reales', style: tema.bodyMedium),
            value: soloReales,
            onChanged: puede ? (v) => modelo.fijarSoloReales(banda, v) : null,
          ),
        ));

        // Filtro de RSSI.
        hijos.add(Row(children: [
          Text('RSSI mínimo:', style: tema.bodySmall),
          const SizedBox(width: 8),
          DropdownButton<double>(
            value: esc.rssiMinimo,
            isDense: true,
            items: [
              for (final v in _opcionesRssi)
                DropdownMenuItem(
                  value: v,
                  child: Text(v <= -100 ? 'Todas' : '${v.round()} dBm'),
                ),
            ],
            onChanged: (v) {
              if (v != null) esc.cambiarRssiMinimo(v);
            },
          ),
        ]));
        hijos.add(SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text('Mostrar antiguas', style: tema.bodyMedium),
          value: esc.mostrarAntiguas,
          onChanged: esc.cambiarMostrarAntiguas,
        ));
        if (conv.ocultas > 0) {
          hijos.add(Text(
            conv.ocultas == 1
                ? 'Se ocultó 1 equipo (antiguas o débiles).'
                : 'Se ocultaron ${conv.ocultas} equipos (antiguas o débiles).',
            style: tema.bodySmall,
          ));
        }

        // Redes que no se dibujan.
        if (conv.noDibujadas.isNotEmpty) {
          hijos.add(Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('No dibujadas (${conv.noDibujadas.length})', style: tema.labelMedium),
          ));
          for (final r in conv.noDibujadas) {
            hijos.add(Text('• ${r.titulo}: ${r.motivo}', style: tema.bodySmall));
          }
        }

        if (hora != null) {
          hijos.add(Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Las redes escaneadas son de solo lectura: su nivel es el RSSI medido. '
              'Usa "Duplicar como simulado" para editarlas.',
              style: tema.bodySmall?.copyWith(fontStyle: FontStyle.italic),
            ),
          ));
        }
        return _tarjeta(hijos);
      },
    );
  }

  Widget _tarjeta(List<Widget> hijos) => Card(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: hijos),
        ),
      );

  Widget _problema(BuildContext context, ControladorEscaneo esc, ProblemaEscaneo p) {
    final tema = Theme.of(context).textTheme;
    final (String texto, String? boton, VoidCallback? accion) = switch (p) {
      ProblemaEscaneo.noDisponible => (
          'Esta plataforma no permite escanear redes Wi-Fi.',
          null,
          null,
        ),
      ProblemaEscaneo.sinPermisos => (
          'Para leer las redes Wi-Fi, Android exige "Ubicación precisa" y, desde '
              'Android 13, "Dispositivos cercanos" (las redes cercanas revelan dónde '
              'estás). La app no guarda ni envía tu ubicación. Si eliges "Ubicación '
              'aproximada", Android no entrega las redes.',
          'Dar permisos',
          esc.pedirPermisos,
        ),
      ProblemaEscaneo.permisosNegados => (
          'Negaste los permisos y Android ya no deja pedirlos desde la app. Abre '
              'Ajustes → Permisos y activa Ubicación (precisa, "mientras se usa la '
              'app") y Dispositivos cercanos. Luego vuelve y pulsa Escanear.',
          'Abrir ajustes',
          esc.abrirAjustesApp,
        ),
      ProblemaEscaneo.ubicacionApagada => (
          'La ubicación del celular está apagada. Con ella apagada Android entrega '
              'la lista de redes vacía, aunque la app tenga permisos. Enciéndela y '
              'vuelve a escanear.',
          'Activar ubicación',
          esc.abrirAjustesUbicacion,
        ),
      ProblemaEscaneo.wifiApagado => (
          'El Wi-Fi está apagado. Enciéndelo (no hace falta conectarse a ninguna red) '
              'y vuelve a escanear.',
          'Abrir Wi-Fi',
          esc.abrirAjustesWifi,
        ),
      ProblemaEscaneo.error => (
          'No se pudo escanear${esc.detalleError == null ? '' : ': ${esc.detalleError}'}.',
          null,
          null,
        ),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          texto,
          style: tema.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.error,
          ),
        ),
        if (boton != null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: accion, child: Text(boton)),
          ),
      ]),
    );
  }
}
