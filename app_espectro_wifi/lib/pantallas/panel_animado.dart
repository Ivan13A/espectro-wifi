// Incremento 3: panel de simulación animada. Arriba el espectro en vivo (cada
// emisor "respira" con sus ráfagas) y abajo la cascada (frecuencia × tiempo).
// Cambiar el ancho de canal anima la transición del emisor de demostración.
//
// Todo es SIMULADO: Android no entrega la ocupación en el tiempo de las redes
// reales, así que esto es un modelo y no una medición.
import 'dart:math' as math;

import 'package:flutter/scheduler.dart' show Ticker;
import 'package:material_ui/material_ui.dart';

import '../modelo/canales.dart';
import '../modelo/lista_aps.dart';
import '../modelo/punto_acceso.dart';
import '../modelo/simulacion.dart';
import '../vista/escala_espectro.dart';
import '../vista/pintor_animado.dart';
import '../vista/pintor_espectro.dart';
import 'panel_aps.dart';

String _num(double v) => v == v.roundToDouble()
    ? v.toInt().toString()
    : v.toStringAsFixed(1).replaceAll('.', ',');

class PanelAnimado extends StatefulWidget {
  const PanelAnimado({
    super.key,
    required this.banda,
    required this.modelo,
    required this.pasos,
    required this.indicePaso,
    required this.alCambiarPaso,
  });

  final Banda banda;

  /// Lista de APs: los que transmiten en [banda] son los emisores. El
  /// seleccionado es el que siguen los chips de ancho.
  final ModeloAps modelo;

  /// Anchos que puede tomar el emisor animado, en el orden de los chips.
  final List<PasoAncho> pasos;

  /// Ancho elegido (índice en [pasos]); lo manda la pantalla.
  final int indicePaso;
  final ValueChanged<int> alCambiarPaso;

  @override
  State<PanelAnimado> createState() => _PanelAnimadoState();
}

class _PanelAnimadoState extends State<PanelAnimado>
    with SingleTickerProviderStateMixin {
  /// Segundos de pantalla que tarda la cascada en recorrer una ventana de tiempo.
  static const _segundosPorVentana = 6.0;

  /// Segundos entre un ancho y el siguiente en "Reproducir anchos".
  static const _segundosPorPaso = 4.0;

  /// Alturas mínimas de los dibujos (dp): nunca se achican más que esto.
  // Alto fijo de los dibujos (fracción del alto disponible, con mínimo): no se
  // encogen; lo demás (explicación, escaneo, APs y análisis) se desplaza debajo.
  static const _altoMinEspectro = 200.0;
  static const _altoMinCascada = 140.0;
  static const _fraccionEspectro = 0.40;
  static const _fraccionCascada = 0.25;

  late final SimulacionEspectro sim;
  late final Ticker _ticker;
  final cuadro = ValueNotifier<int>(0);
  Duration _ultimo = Duration.zero;

  bool reproduciendo = true;
  double ventanaMs = 20;
  double velocidad = 1;
  bool secuencia = false;
  double _tSecuencia = 0;
  bool _cambioPropio = false;
  int? _indiceAnterior;

  // Zoom horizontal compartido por el espectro y la cascada.
  late VentanaFrecuencia ventana = VentanaFrecuencia.completa(widget.banda);
  double _ancho = 0;
  VentanaFrecuencia? _ventanaInicial;
  double _fFoco = 0;

  @override
  void initState() {
    super.initState();
    sim = SimulacionEspectro(
      banda: widget.banda,
      demos: _demos(),
      paso: widget.pasos[widget.indicePaso],
    );
    _idAnimado = widget.modelo.seleccionado(widget.banda)?.id;
    widget.modelo.addListener(_alCambiarLista);
    _ajustarRitmo();
    _ticker = createTicker(_tick)..start();
  }

  @override
  void dispose() {
    widget.modelo.removeListener(_alCambiarLista);
    _ticker.dispose();
    cuadro.dispose();
    super.dispose();
  }

  /// Emisores = APs de la banda que transmiten (encendidos y sin canales
  /// desactivados). El seleccionado es el "animado".
  List<EmisorDemo> _demos() {
    final sel = widget.modelo.seleccionado(widget.banda);
    return [
      for (final ap in widget.modelo.transmitiendoEn(widget.banda))
        emisorDeAp(ap, animado: ap.id == sel?.id),
    ];
  }

  /// Id del AP animado (seleccionado) la última vez que cambió la lista.
  String? _idAnimado;

  /// true entre el cambio de AP seleccionado y el siguiente build: el cambio
  /// de [PanelAnimado.indicePaso] que llega en ese cuadro no es una transición.
  bool _cambioDeAp = false;

  void _alCambiarLista() {
    final id = widget.modelo.seleccionado(widget.banda)?.id;
    if (id != _idAnimado) {
      _idAnimado = id;
      _indiceAnterior = null;
      _cambioDeAp = true;
      secuencia = false;
    }
    sim.sincronizar(_demos());
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(PanelAnimado old) {
    super.didUpdateWidget(old);
    if (old.indicePaso != widget.indicePaso) {
      // Si el cambio no lo hizo la secuencia, el usuario tomó el control.
      if (!_cambioPropio) secuencia = false;
      _cambioPropio = false;
      // Si el ancho cambió porque se eligió otro AP, no hay transición que contar.
      _indiceAnterior = _cambioDeAp ? null : old.indicePaso;
      sim.irA(widget.pasos[widget.indicePaso]);
    }
  }

  void _ajustarRitmo() =>
      sim.msPorSegundo = ventanaMs / _segundosPorVentana * velocidad;

  void _tick(Duration t) {
    final dt = ((t - _ultimo).inMicroseconds / 1e6).clamp(0.0, 0.1).toDouble();
    _ultimo = t;
    if (secuencia) {
      _tSecuencia += dt;
      if (_tSecuencia >= _segundosPorPaso) {
        _tSecuencia = 0;
        _cambioPropio = true;
        widget.alCambiarPaso((widget.indicePaso + 1) % widget.pasos.length);
      }
    }
    sim.avanzar(dt, correr: reproduciendo);
    cuadro.value++;
  }

  void _alternarSecuencia() {
    if (widget.modelo.seleccionado(widget.banda) == null) return;
    setState(() {
      secuencia = !secuencia;
      // Al arrancar, el primer cambio es inmediato.
      _tSecuencia = _segundosPorPaso;
    });
  }

  // --- Zoom (mismo comportamiento que el espectro estático) --------------------

  Rango get _limite => rangoVista(widget.banda);

  void _inicioPellizco(ScaleStartDetails d) {
    _ventanaInicial = ventana;
    final e = EscalaEspectro(
      fMinMHz: ventana.inicioMHz,
      fMaxMHz: ventana.finMHz,
      xIzq: 0,
      xDer: _ancho,
      yBase: 0,
      yTope: 0,
    );
    _fFoco = e.f(d.localFocalPoint.dx);
  }

  void _pellizco(ScaleUpdateDetails d) {
    final base = _ventanaInicial;
    if (base == null || _ancho <= 0) return;
    setState(() {
      ventana = base.pellizcar(
        factor: d.horizontalScale,
        fFoco: _fFoco,
        fraccionFoco: d.localFocalPoint.dx / _ancho,
        limite: _limite,
        anchoMinMHz: anchoMinimoVista(widget.banda),
      );
    });
  }

  void _vistaCompleta() =>
      setState(() => ventana = VentanaFrecuencia.completa(widget.banda));

  /// Dedos sobre el espectro y la cascada. Con dos o más se bloquea el
  /// desplazamiento vertical, para que el pellizco no compita con él.
  int _dedos = 0;

  void _dedo(int delta) {
    final antes = _dedos >= 2;
    _dedos = (_dedos + delta).clamp(0, 10);
    if ((_dedos >= 2) != antes) setState(() {});
  }

  // --- Interfaz -----------------------------------------------------------------

  /// Vertical: una sola fila de 48 dp con pausa, "Reproducir anchos" (ícono
  /// con tooltip), la etiqueta "SIMULACIÓN ×N" (al tocarla abre la
  /// explicación) y "Opciones". Cabe en 360 dp: la etiqueta se achica antes
  /// de cortarse.
  Widget _filaVertical() {
    const oscuro = Color(0xFF1B1B1B);
    return SizedBox(
      height: 48,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            IconButton(
              tooltip: reproduciendo ? 'Pausar' : 'Reanudar',
              icon: Icon(reproduciendo ? Icons.pause : Icons.play_arrow),
              onPressed: () => setState(() => reproduciendo = !reproduciendo),
            ),
            IconButton(
              tooltip: secuencia ? 'Detener anchos' : 'Reproducir anchos',
              icon: Icon(secuencia ? Icons.stop : Icons.play_circle_outline),
              onPressed: _alternarSecuencia,
            ),
            Expanded(
              child: Tooltip(
                message: 'Qué es esta simulación',
                child: Material(
                  color: const Color(0xFFFFC107),
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: _mostrarInfoSimulacion,
                    child: SizedBox(
                      height: 48,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              'SIMULACIÓN ×${sim.lentitud.round()}',
                              maxLines: 1,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: oscuro,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            TextButton.icon(
              onPressed: _abrirOpciones,
              style: const ButtonStyle(
                minimumSize: WidgetStatePropertyAll(Size(0, 48)),
                padding: WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
              icon: const Icon(Icons.tune),
              label: const Text('Opciones'),
            ),
          ],
        ),
      ),
    );
  }

  /// Horizontal (igual que antes): pausa, "Reproducir anchos" y opciones.
  Widget _controles() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            tooltip: reproduciendo ? 'Pausar' : 'Reanudar',
            icon: Icon(reproduciendo ? Icons.pause : Icons.play_arrow),
            onPressed: () => setState(() => reproduciendo = !reproduciendo),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: OutlinedButton.icon(
              onPressed: _alternarSecuencia,
              icon: Icon(secuencia ? Icons.stop : Icons.play_circle_outline),
              label: Text(
                secuencia ? 'Detener anchos' : 'Reproducir anchos',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: _abrirOpciones,
            icon: const Icon(Icons.tune),
            label: const Text('Opciones'),
          ),
        ],
      ),
    );
  }

  /// Ventana de tiempo, velocidad y potencia constante, en un panel inferior.
  void _abrirOpciones() {
    const velocidades = [(0.5, '×0,5'), (1.0, '×1'), (2.0, '×2')];
    const ventanas = [(20.0, '20 ms · ráfagas'), (400.0, '400 ms · beacons')];
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setHoja) {
          void cambiar(void Function() f) {
            setState(f);
            setHoja(() {});
          }

          final tema = Theme.of(ctx).textTheme;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ventana de tiempo de la cascada',
                    style: tema.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final (v, etiqueta) in ventanas)
                        ChoiceChip(
                          label: Text(etiqueta),
                          selected: ventanaMs == v,
                          onSelected: (_) => cambiar(() {
                            ventanaMs = v;
                            _ajustarRitmo();
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('Velocidad de la reproducción', style: tema.titleSmall),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final (v, etiqueta) in velocidades)
                        ChoiceChip(
                          label: Text(etiqueta),
                          selected: velocidad == v,
                          onSelected: (_) => cambiar(() {
                            velocidad = v;
                            _ajustarRitmo();
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Potencia total constante'),
                    subtitle: const Text(
                      'Más ancho de canal = menos potencia por MHz (−3 dB al duplicar).',
                    ),
                    value: sim.potenciaConstante,
                    onChanged: (v) => cambiar(() => sim.potenciaConstante = v),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String get _textoCompleto =>
      'Esta animación es un modelo, no una medición: Android no entrega la '
      'ocupación en el tiempo de las redes reales. Las ráfagas, los beacons y la '
      'interferencia salen de una simulación.\n\nCámara lenta ×${sim.lentitud.round()}: '
      '1 s en pantalla = ${_num(sim.msPorSegundo)} ms reales.';

  /// Una línea; al tocarla muestra el texto completo.
  void _mostrarInfoSimulacion() => showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Simulación'),
      content: Text(_textoCompleto),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    ),
  );

  Widget _aviso() {
    return Material(
      color: const Color(0xFFFFC107),
      child: InkWell(
        onTap: _mostrarInfoSimulacion,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'SIMULACIÓN · cámara lenta ×${sim.lentitud.round()}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1B1B1B),
                  ),
                ),
              ),
              const Icon(
                Icons.info_outline,
                size: 16,
                color: Color(0xFF1B1B1B),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Un elemento por emisor; tocarlo selecciona ese AP (el que siguen los chips).
  Widget _leyenda() {
    final estilo = Theme.of(context).textTheme.bodySmall;
    return Wrap(
      spacing: 12,
      runSpacing: 2,
      children: [
        for (final em in sim.emisores)
          InkWell(
            onTap: () {
              final ap = widget.modelo.porId(em.demo.id);
              if (ap != null) widget.modelo.seleccionar(ap);
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: ColoresEspectro.deCanal(em.demo.colorIndice),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '${em.demo.nombre} · canal ${em.demo.primario} · '
                  '${em.canalDestino.anchoMHz} MHz',
                  style: em.demo.animado
                      ? estilo?.copyWith(fontWeight: FontWeight.bold)
                      : estilo,
                ),
              ],
            ),
          ),
      ],
    );
  }

  String _explicacion() {
    final sel = widget.modelo.seleccionado(widget.banda);
    if (sel == null) {
      return 'No hay puntos de acceso en ${widget.banda.nombre}. Agrega uno con "+ AP".';
    }
    final demo = emisorDeAp(sel, animado: true);
    final actual = widget.pasos[widget.indicePaso];
    final antes = _indiceAnterior;
    if (antes == null || antes == widget.indicePaso) {
      return describirOcupacion(
        banda: widget.banda,
        emisor: demo,
        paso: actual,
      );
    }
    return describirTransicion(
      banda: widget.banda,
      emisor: demo,
      de: widget.pasos[antes],
      a: actual,
      potenciaConstante: sim.potenciaConstante,
    );
  }

  @override
  Widget build(BuildContext context) {
    _cambioDeAp = false;
    final tema = Theme.of(context).textTheme;
    return Column(
      children: [
        if (MediaQuery.orientationOf(context) == Orientation.landscape) ...[
          _aviso(),
          _controles(),
        ] else
          _filaVertical(),
        // Fijos arriba: la franja SIMULACIÓN y los botones. Todo lo demás va
        // en un solo scroll vertical.
        Expanded(
          child: LayoutBuilder(
            builder: (context, cons) {
              _ancho = cons.maxWidth;
              final altoEspectro = math.max(
                _altoMinEspectro,
                cons.maxHeight * _fraccionEspectro,
              );
              final altoCascada = math.max(
                _altoMinCascada,
                cons.maxHeight * _fraccionCascada,
              );
              return SingleChildScrollView(
                // Con dos dedos sobre los dibujos no se desplaza: es un pellizco.
                physics: _dedos >= 2
                    ? const NeverScrollableScrollPhysics()
                    : null,
                child: Column(
                  children: [
                    Listener(
                      onPointerDown: (_) => _dedo(1),
                      onPointerUp: (_) => _dedo(-1),
                      onPointerCancel: (_) => _dedo(-1),
                      child: GestureDetector(
                        onDoubleTap: _vistaCompleta,
                        onScaleStart: _inicioPellizco,
                        onScaleUpdate: _pellizco,
                        onScaleEnd: (_) => _ventanaInicial = null,
                        child: Column(
                          children: [
                            SizedBox(
                              height: altoEspectro,
                              width: double.infinity,
                              child: CustomPaint(
                                painter: PintorEspectroEnVivo(
                                  sim: sim,
                                  ventana: ventana,
                                  repaint: cuadro,
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            SizedBox(
                              height: altoCascada,
                              width: double.infinity,
                              child: CustomPaint(
                                painter: PintorCascada(
                                  sim: sim,
                                  ventana: ventana,
                                  ventanaMs: ventanaMs,
                                  repaint: cuadro,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                      child: SizedBox(
                        width: double.infinity,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _leyenda(),
                            const SizedBox(height: 4),
                            Text(_explicacion(), style: tema.bodySmall),
                            const SizedBox(height: 4),
                            Text(
                              'Cada rectángulo de la cascada es una ráfaga: su ancho es el espectro '
                              'que ocupa y su alto, lo que dura. Blanco = beacon (solo el canal '
                              'primario); rojo = dos emisores a la vez. Pellizca para acercar; '
                              'doble toque para ver toda la banda. Los chips de ancho y '
                              '"Reproducir anchos" mandan sobre el AP seleccionado (en negrita).',
                              style: tema.bodySmall?.copyWith(
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    PanelAps(modelo: widget.modelo, banda: widget.banda),
                    const SizedBox(height: 16),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
