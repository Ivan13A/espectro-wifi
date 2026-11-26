// Incrementos 2 a 4: vista estática del espectro por banda, con selección de
// canal para ver sus solapamientos; (con "Animar") la simulación animada; y
// (con "APs") los puntos de acceso simulados sobre el espectro.
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../modelo/canales.dart';
import '../modelo/lista_aps.dart';
import '../modelo/punto_acceso.dart';
import '../modelo/simulacion.dart';
import '../tema.dart';
import '../vista/escala_espectro.dart';
import '../vista/pintor_espectro.dart';
import 'boton_reporte.dart';
import 'panel_animado.dart';
import 'panel_aps.dart';

String mhz(double v) => v == v.roundToDouble()
    ? v.toInt().toString()
    : v.toString().replaceAll('.', ',');

void _avisar(BuildContext context, String texto) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(texto)));
}

/// Cambia el ancho (y, si hace falta, el estándar) del AP seleccionado de
/// [banda] desde los chips de ancho.
///  - Al animar ([estricto] false): si el primario no tiene bloque de ese
///    ancho, el AP se mueve al canal válido más cercano y se avisa (así
///    "Reproducir anchos" nunca se atasca).
///  - En la vista de APs ([estricto] true): solo se cambia si la combinación
///    es válida con el mismo canal primario y no usa canales desactivados; si
///    no, se avisa y el AP queda igual.
void cambiarAnchoSeleccionado(
  BuildContext context,
  ModeloAps modelo,
  Banda banda,
  int ancho, {
  bool estricto = false,
}) {
  final sel = modelo.seleccionado(banda);
  if (sel == null) return;
  if (sel.escaneado) {
    _avisar(context, '${sel.nombre} es una red escaneada: no se puede cambiar.');
    return;
  }
  if (!estricto) {
    final nuevo = sel.conAncho(ancho, evitar: modelo.canalesDesactivados(banda));
    if (nuevo.canalPrimario != sel.canalPrimario) {
      _avisar(
        context,
        'El canal ${sel.canalPrimario} no forma un bloque de $ancho MHz: '
        '${sel.nombre} pasa al canal ${nuevo.canalPrimario}.',
      );
    }
    modelo.editar(nuevo);
    return;
  }

  final nuevo = sel.conAncho(ancho, moverPrimario: false);
  if (nuevo.anchoMHz == sel.anchoMHz && nuevo.estandar == sel.estandar) return;
  final error = validarAp(nuevo);
  if (error != null) {
    _avisar(
      context,
      '$error ${sel.nombre} no cambia; elige otro canal primario en el editor.',
    );
    return;
  }
  final nuevosOff = [
    for (final n in modelo.canalesBloqueados(nuevo))
      if (!modelo.canalesBloqueados(sel).contains(n)) n,
  ];
  if (nuevosOff.isNotEmpty) {
    _avisar(
      context,
      'Con $ancho MHz ${sel.nombre} usaría '
      '${nuevosOff.length == 1 ? 'el canal desactivado' : 'los canales desactivados'} '
      '${nuevosOff.join(', ')}. No cambia.',
    );
    return;
  }
  modelo.editar(nuevo);
}

/// Nota bajo el espectro cuando se ven los APs.
String notaAps(ModeloAps modelo, Banda banda) {
  final aps = modelo.de(banda);
  final tx = modelo.transmitiendoEn(banda).length;
  return '${aps.length} AP${aps.length == 1 ? '' : 's'} en ${banda.nombre}, $tx '
      'transmitiendo. Relleno = transmite; punteado = apagado o en un canal '
      'desactivado. La línea vertical gruesa marca el canal primario. Toca un AP '
      'para seleccionarlo.';
}

class PantallaEspectro extends StatefulWidget {
  const PantallaEspectro({
    super.key,
    this.modoTema = ThemeMode.system,
    this.alRotarTema,
  });

  /// Modo de tema actual y cómo rotarlo (automático → claro → oscuro).
  final ThemeMode modoTema;
  final VoidCallback? alRotarTema;

  @override
  State<PantallaEspectro> createState() => _PantallaEspectroState();
}

class _PantallaEspectroState extends State<PantallaEspectro> {
  /// Una sola lista para las dos bandas (y, en el incremento 5, para las
  /// redes escaneadas).
  final modelo = ModeloAps.conEjemplo();

  @override
  void dispose() {
    modelo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // En horizontal se quita el título para darle la altura al espectro.
    final horizontal =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: horizontal
              ? null
              : Text(
                  'Espectro Wi-Fi en Colombia',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
          // Vertical: barra compacta de 48 dp para dejarle alto al contenido.
          toolbarHeight: horizontal ? 0 : 48,
          actions: horizontal
              ? null
              : [
                  BotonReporte(modelo: modelo),
                  BotonTema(
                    modo: widget.modoTema,
                    alRotar: widget.alRotarTema,
                  ),
                ],
          // En horizontal no hay barra superior: los botones de reporte y
          // tema van junto a las pestañas.
          bottom: horizontal
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(kTextTabBarHeight),
                  child: Row(
                    children: [
                      const Expanded(
                        child: _PestanasBanda(alto: kTextTabBarHeight),
                      ),
                      BotonReporte(modelo: modelo),
                      BotonTema(
                        modo: widget.modoTema,
                        alRotar: widget.alRotarTema,
                      ),
                    ],
                  ),
                )
              : const _PestanasBanda(),
        ),
        // Sin deslizar entre pestañas: el gesto horizontal es del espectro.
        // SafeArea: en horizontal la barra de navegación o la cámara quedan a un lado.
        body: SafeArea(
          top: false,
          child: TabBarView(
            physics: const NeverScrollableScrollPhysics(),
            children: [
              TemaDeBanda(banda: Banda.ghz24, hijo: Vista24(modelo: modelo)),
              TemaDeBanda(banda: Banda.ghz5, hijo: Vista5(modelo: modelo)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Botón de la barra superior: rota automático → claro → oscuro. Muestra el
/// ícono del modo actual.
class BotonTema extends StatelessWidget {
  const BotonTema({super.key, required this.modo, this.alRotar});

  final ThemeMode modo;
  final VoidCallback? alRotar;

  @override
  Widget build(BuildContext context) {
    final (icono, tooltip) = switch (modo) {
      ThemeMode.system => (Icons.brightness_auto, 'Tema: automático'),
      ThemeMode.light => (Icons.light_mode, 'Tema: claro'),
      ThemeMode.dark => (Icons.dark_mode, 'Tema: oscuro'),
    };
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icono),
      onPressed: alRotar,
    );
  }
}

/// Pestañas de banda en vertical, con aspecto de botones: una píldora rellena
/// marca la banda elegida dentro de un contenedor redondeado. 48 dp de alto
/// (área táctil completa); la píldora visible mide 40 dp. Colores del
/// ColorScheme actual.
class _PestanasBanda extends StatelessWidget implements PreferredSizeWidget {
  const _PestanasBanda({this.alto = 48});

  final double alto;

  @override
  Size get preferredSize => Size.fromHeight(alto);

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final brillo = Theme.of(context).brightness;
    final e24 = temaBanda(Banda.ghz24, brillo).colorScheme;
    final e5 = temaBanda(Banda.ghz5, brillo).colorScheme;
    final animacion = DefaultTabController.of(context).animation!;
    Tab pestana(String texto) => Tab(
      height: alto,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi, size: 18),
          const SizedBox(width: 6),
          Text(texto),
        ],
      ),
    );
    return Container(
      height: alto,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: esquema.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(alto / 2),
      ),
      // La píldora toma el color de la banda activa y se mezcla con el de la
      // otra mientras la pestaña se desliza.
      child: AnimatedBuilder(
        animation: animacion,
        builder: (context, _) {
          final t = animacion.value.clamp(0.0, 1.0);
          return TabBar(
            indicatorSize: TabBarIndicatorSize.tab,
            indicatorPadding: const EdgeInsets.all(4),
            indicator: BoxDecoration(
              color: Color.lerp(e24.primaryContainer, e5.primaryContainer, t),
              borderRadius: BorderRadius.circular(20),
            ),
            dividerColor: Colors.transparent,
            labelColor: Color.lerp(
              e24.onPrimaryContainer,
              e5.onPrimaryContainer,
              t,
            ),
            unselectedLabelColor: esquema.onSurfaceVariant,
            tabs: [pestana('2.4 GHz'), pestana('5 GHz')],
          );
        },
      ),
    );
  }
}

// --- 2.4 GHz -----------------------------------------------------------------

/// Opciones de ancho en 2.4 GHz: 22 (DSSS), 20 (OFDM) y 40 (HT40).
enum Opcion24 {
  dsss22('22 MHz (802.11b)', 'b', '802.11b'),
  ofdm20('20 MHz (802.11g/n)', 'g/n', '802.11g/n'),
  ht40('40 MHz (802.11n)', 'n', '802.11n');

  const Opcion24(this.etiqueta, this.estandar, this.estandarCompleto);
  final String etiqueta;

  /// Estándar corto (segmento) y completo (tooltip).
  final String estandar;
  final String estandarCompleto;
}

class Vista24 extends StatefulWidget {
  const Vista24({super.key, required this.modelo});

  final ModeloAps modelo;

  @override
  State<Vista24> createState() => _Vista24State();
}

class _Vista24State extends State<Vista24> {
  Opcion24 opcion = Opcion24.dsss22;
  bool animar = false;
  bool verAps = false;

  static const _anchos = {
    Opcion24.dsss22: 22,
    Opcion24.ofdm20: 20,
    Opcion24.ht40: 40,
  };

  static Opcion24 _opcionDe(PuntoAcceso ap) => ap.paso.dsss
      ? Opcion24.dsss22
      : ap.anchoMHz == 40
      ? Opcion24.ht40
      : Opcion24.ofdm20;

  List<Canal> get canales => switch (opcion) {
    Opcion24.dsss22 => CatalogoCanales.canales24(Modo24.dsss22),
    Opcion24.ofdm20 => CatalogoCanales.canales24(Modo24.ofdm20),
    Opcion24.ht40 => CatalogoCanales.canales24de40(),
  };

  /// Solo catálogo: el chip elige el ancho del catálogo. Al animar o con
  /// "APs", el chip cambia el AP seleccionado (con "APs", en modo estricto).
  void _elegir(int i) {
    final o = Opcion24.values[i];
    if (animar) {
      setState(() => opcion = o);
      cambiarAnchoSeleccionado(context, widget.modelo, Banda.ghz24, _anchos[o]!);
    } else if (verAps) {
      cambiarAnchoSeleccionado(
        context,
        widget.modelo,
        Banda.ghz24,
        _anchos[o]!,
        estricto: true,
      );
    } else {
      setState(() => opcion = o);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.modelo,
      builder: (context, _) {
        final modelo = widget.modelo;
        final lista = canales;
        final libres = canalesSinSolapamiento(lista);
        final sel = modelo.seleccionado(Banda.ghz24);
        // Al animar o con "APs", los chips muestran el ancho y estándar del
        // AP seleccionado; sin AP no hay nada que mostrar y se esconden.
        final conAps = animar || verAps;
        final elegido = conAps && sel != null ? _opcionDe(sel) : opcion;
        return Column(
          children: [
            _BarraOpciones(
              etiquetas: [for (final o in Opcion24.values) o.etiqueta],
              anchos: [for (final o in Opcion24.values) '${_anchos[o]} MHz'],
              estandares: [for (final o in Opcion24.values) o.estandar],
              estandaresCompletos: [
                for (final o in Opcion24.values) o.estandarCompleto,
              ],
              mostrarAnchos: !conAps || sel != null,
              elegido: elegido.index,
              alElegir: _elegir,
              animar: animar,
              alAnimar: (v) => setState(() => animar = v),
              verAps: verAps,
              alVerAps: (v) => setState(() => verAps = v),
            ),
            Expanded(
              child: animar
                  ? PanelAnimado(
                      banda: Banda.ghz24,
                      modelo: modelo,
                      pasos: PasosAncho.ghz24,
                      indicePaso: elegido.index,
                      alCambiarPaso: _elegir,
                    )
                  : PanelEspectro(
                      idVista: verAps ? 'aps' : opcion,
                      banda: Banda.ghz24,
                      // Con los APs, el catálogo es solo la referencia de
                      // los canales de 20 MHz (número arriba y marca en el eje).
                      canales: verAps
                          ? CatalogoCanales.canales24(Modo24.ofdm20)
                          : lista,
                      soloNumeros: verAps,
                      resaltados: verAps
                          ? const <int>{}
                          : {for (final c in libres) c.numero},
                      nota: verAps
                          ? notaAps(modelo, Banda.ghz24)
                          : nota24(opcion, libres),
                      aps: verAps ? modelo.de(Banda.ghz24) : const [],
                      apsSinTransmitir: _sinTransmitir(modelo, Banda.ghz24),
                      apSeleccionado: sel?.id,
                      alTocarAp: modelo.seleccionar,
                      abajo: verAps
                          ? PanelAps(modelo: modelo, banda: Banda.ghz24)
                          : null,
                    ),
            ),
          ],
        );
      },
    );
  }
}

Set<String> _sinTransmitir(ModeloAps modelo, Banda banda) => {
  for (final ap in modelo.de(banda))
    if (!modelo.transmite(ap)) ap.id,
};

/// Texto del conjunto sin solapamiento en 2.4 GHz. Los números y rangos salen
/// del modelo; solo las aclaraciones regulatorias son texto fijo.
String nota24(Opcion24 opcion, List<Canal> libres) {
  final numeros = libres.map((c) => c.numero).join(' / ');
  final tocan = [
    for (var i = 0; i + 1 < libres.length; i++)
      if (libres[i].finMHz == libres[i + 1].inicioMHz) libres[i].finMHz,
  ];
  switch (opcion) {
    case Opcion24.dsss22:
      final hueco = libres.length > 1
          ? libres[1].inicioMHz - libres[0].finMHz
          : 0.0;
      return 'Sin solaparse (22 MHz): $numeros. Entre sus lóbulos principales '
          'quedan ${mhz(hueco)} MHz libres.';
    case Opcion24.ofdm20:
      final bordes = tocan.map(mhz).join(', ');
      return 'Sin solaparse (20 MHz): $numeros. Ojo: se tocan en el borde '
          '($bordes MHz) y la máscara espectral deja algo de fuga al canal vecino. '
          'Además, muchos equipos con región de EE. UU. no usan los canales 12 y 13; '
          'por eso en América se recomienda 1 / 6 / 11.';
    case Opcion24.ht40:
      final bloques = libres
          .map((c) => '${c.numero} (${mhz(c.inicioMHz)}–${mhz(c.finMHz)} MHz)')
          .join(' y ');
      final borde = tocan.isEmpty
          ? ''
          : ', que se tocan en ${tocan.map(mhz).join(', ')} MHz pero no se pisan';
      return 'Con 40 MHz caben ${libres.length} bloques sin solaparse: $bloques$borde. '
          'En EE. UU. (canales 1-11) solo cabe uno, porque el bloque 11 necesita el '
          'canal 13. Aun así, 40 MHz en 2.4 GHz ocupa casi toda la banda.';
  }
}

// --- 5 GHz -------------------------------------------------------------------

class Vista5 extends StatefulWidget {
  const Vista5({super.key, required this.modelo});

  final ModeloAps modelo;

  @override
  State<Vista5> createState() => _Vista5State();
}

class _Vista5State extends State<Vista5> {
  int ancho = 20;
  bool animar = false;
  bool verAps = false;

  void _elegir(int i) {
    final w = CatalogoCanales.anchos5[i];
    if (animar) {
      setState(() => ancho = w);
      cambiarAnchoSeleccionado(context, widget.modelo, Banda.ghz5, w);
    } else if (verAps) {
      cambiarAnchoSeleccionado(
        context,
        widget.modelo,
        Banda.ghz5,
        w,
        estricto: true,
      );
    } else {
      setState(() => ancho = w);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.modelo,
      builder: (context, _) {
        final modelo = widget.modelo;
        final lista = CatalogoCanales.canales5(ancho);
        final sinBloque = CatalogoCanales.canales5SinBloque(ancho);
        final sel = modelo.seleccionado(Banda.ghz5);
        final conAps = animar || verAps;
        final elegido =
            conAps &&
                sel != null &&
                CatalogoCanales.anchos5.contains(sel.anchoMHz)
            ? sel.anchoMHz
            : ancho;
        return Column(
          children: [
            _BarraOpciones(
              etiquetas: [for (final w in CatalogoCanales.anchos5) '$w MHz'],
              anchos: [for (final w in CatalogoCanales.anchos5) '$w MHz'],
              estandares: [
                for (final w in CatalogoCanales.anchos5) estandares5(w).$1,
              ],
              estandaresCompletos: [
                for (final w in CatalogoCanales.anchos5) estandares5(w).$2,
              ],
              mostrarAnchos: !conAps || sel != null,
              elegido: CatalogoCanales.anchos5.indexOf(elegido),
              alElegir: _elegir,
              animar: animar,
              alAnimar: (v) => setState(() => animar = v),
              verAps: verAps,
              alVerAps: (v) => setState(() => verAps = v),
            ),
            Expanded(
              child: animar
                  ? PanelAnimado(
                      banda: Banda.ghz5,
                      modelo: modelo,
                      pasos: PasosAncho.ghz5,
                      indicePaso: CatalogoCanales.anchos5.indexOf(elegido),
                      alCambiarPaso: _elegir,
                    )
                  : PanelEspectro(
                      idVista: verAps ? 'aps' : ancho,
                      banda: Banda.ghz5,
                      canales: verAps ? CatalogoCanales.canales5(20) : lista,
                      soloNumeros: verAps,
                      resaltados: verAps
                          ? const <int>{}
                          : {
                              for (final c in canalesSinSolapamiento(lista))
                                c.numero,
                            },
                      sinBloque: verAps ? const [] : sinBloque,
                      nota: verAps
                          ? notaAps(modelo, Banda.ghz5)
                          : nota5(ancho, lista, sinBloque),
                      aps: verAps ? modelo.de(Banda.ghz5) : const [],
                      apsSinTransmitir: _sinTransmitir(modelo, Banda.ghz5),
                      apSeleccionado: sel?.id,
                      alTocarAp: modelo.seleccionar,
                      abajo: verAps
                          ? PanelAps(modelo: modelo, banda: Banda.ghz5)
                          : null,
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// Estándares de cada ancho en 5 GHz (corto, completo), según Estandar.anchosEn.
(String, String) estandares5(int ancho) => switch (ancho) {
  20 => ('a/n/ac', '802.11a/n/ac'),
  40 => ('n/ac', '802.11n/ac'),
  _ => ('ac', '802.11ac'),
};

String nota5(int ancho, List<Canal> canales, List<int> sinBloque) {
  final unidad = ancho == 20 ? 'canales' : 'bloques';
  var s =
      '${canales.length} $unidad de $ancho MHz; ninguno se solapa con otro '
      'del mismo ancho.';
  if (sinBloque.length == 1) {
    s +=
        ' El canal ${sinBloque.first} no forma un bloque de $ancho MHz (en gris).';
  } else if (sinBloque.isNotEmpty) {
    s +=
        ' Los canales ${sinBloque.join(', ')} no forman un bloque de $ancho MHz '
        '(en gris).';
  }
  return '$s Entre 5350 y 5470 MHz no hay canales: esa franja no está en las '
      'bandas de uso libre (Res. ANE 105/2020).';
}

// --- Panel común: espectro + información + tabla ---------------------------

class PanelEspectro extends StatefulWidget {
  const PanelEspectro({
    super.key,
    required this.idVista,
    required this.banda,
    required this.canales,
    required this.resaltados,
    required this.nota,
    this.sinBloque = const [],
    this.aps = const [],
    this.apsSinTransmitir = const {},
    this.apSeleccionado,
    this.alTocarAp,
    this.abajo,
    this.soloNumeros = false,
  });

  /// Identifica la opción de ancho. Si cambia, se quita la selección (el canal
  /// ya no existe con ese ancho) pero se conserva el zoom, para comparar anchos
  /// en la misma zona del espectro.
  final Object idVista;
  final Banda banda;
  final List<Canal> canales;
  final Set<int> resaltados;
  final String nota;
  final List<int> sinBloque;

  /// APs dibujados encima del catálogo (vacío si no se ven).
  final List<PuntoAcceso> aps;
  final Set<String> apsSinTransmitir;
  final String? apSeleccionado;

  /// Al tocar un AP en el espectro; si se toca fuera de los APs, se elige canal.
  final ValueChanged<PuntoAcceso>? alTocarAp;

  /// Si no es null, reemplaza la tabla de canales.
  final Widget? abajo;

  /// Los canales se dibujan solo como referencia: número arriba y marca en
  /// el eje, sin formas (vista de APs).
  final bool soloNumeros;

  @override
  State<PanelEspectro> createState() => _PanelEspectroState();
}

class _PanelEspectroState extends State<PanelEspectro> {
  /// En vertical la figura ocupa esta fracción del alto disponible, con un
  /// mínimo; no se encoge, el resto de la página se desplaza.
  static const fraccionVertical = 0.45;
  static const altoMinVertical = 220.0;

  late VentanaFrecuencia ventana = VentanaFrecuencia.completa(widget.banda);
  int? seleccionado;
  Size _lienzo = Size.zero;

  // Estado del pellizco en curso.
  VentanaFrecuencia? _ventanaInicial;
  double _fFoco = 0;

  @override
  void didUpdateWidget(PanelEspectro old) {
    super.didUpdateWidget(old);
    if (old.idVista != widget.idVista) seleccionado = null;
  }

  Rango get _limite => rangoVista(widget.banda);
  EscalaEspectro get _escala => PintorEspectro.escalaPara(_lienzo, ventana);
  bool get _conZoom => ventana != VentanaFrecuencia.completa(widget.banda);

  Canal? get _canalSel => seleccionado == null
      ? null
      : widget.canales.where((c) => c.numero == seleccionado).firstOrNull;

  void _alternar(int? numero) =>
      setState(() => seleccionado = numero == seleccionado ? null : numero);

  void _tocarEspectro(TapUpDetails d) {
    final f = _escala.f(d.localPosition.dx);
    final alTocarAp = widget.alTocarAp;
    if (widget.aps.isNotEmpty && alTocarAp != null) {
      final ap = PintorEspectro.apEn(widget.aps, f);
      if (ap != null) {
        alTocarAp(ap);
        return;
      }
    }
    _alternar(PintorEspectro.canalEn(widget.canales, f)?.numero);
  }

  void _inicioPellizco(ScaleStartDetails d) {
    _ventanaInicial = ventana;
    _fFoco = _escala.f(d.localFocalPoint.dx);
  }

  /// Solo se usa la escala horizontal: el eje vertical no cambia con el zoom.
  void _pellizco(ScaleUpdateDetails d) {
    final base = _ventanaInicial;
    if (base == null || _lienzo.width <= 0) return;
    setState(() {
      ventana = base.pellizcar(
        factor: d.horizontalScale,
        fFoco: _fFoco,
        fraccionFoco: d.localFocalPoint.dx / _lienzo.width,
        limite: _limite,
        anchoMinMHz: anchoMinimoVista(widget.banda),
      );
    });
  }

  void _vistaCompleta() =>
      setState(() => ventana = VentanaFrecuencia.completa(widget.banda));

  /// Al elegir en la tabla, si el canal no se ve completo con el zoom actual,
  /// la ventana se desplaza hasta él.
  void _tocarFila(Canal c) {
    _alternar(c.numero);
    if (!ventana.contiene(c.inicioMHz, c.finMHz)) {
      setState(
        () => ventana = ventana.centrarEn(c.centroMHz.toDouble(), _limite),
      );
    }
  }

  Widget _espectro() => LayoutBuilder(
    builder: (context, cons) {
      _lienzo = Size(cons.maxWidth, cons.maxHeight);
      return GestureDetector(
        onTapUp: _tocarEspectro,
        onDoubleTap: _vistaCompleta,
        onScaleStart: _inicioPellizco,
        onScaleUpdate: _pellizco,
        onScaleEnd: (_) => _ventanaInicial = null,
        child: CustomPaint(
          size: _lienzo,
          painter: PintorEspectro(
            banda: widget.banda,
            ventana: ventana,
            canales: widget.canales,
            resaltados: widget.resaltados,
            sinBloque: widget.sinBloque,
            seleccionado: seleccionado,
            aps: widget.aps,
            apsSinTransmitir: widget.apsSinTransmitir,
            apSeleccionado: widget.apSeleccionado,
            soloNumeros: widget.soloNumeros,
          ),
        ),
      );
    },
  );

  /// Alto de la pista "desliza hacia abajo" que asoma bajo el espectro en horizontal.
  static const altoPista = 28.0;

  /// Dedos apoyados sobre el espectro. Con dos o más se bloquea el
  /// desplazamiento vertical de la pantalla, para que el pellizco no compita
  /// con él. Con un dedo, el arrastre vertical desplaza la pantalla y el
  /// horizontal mueve el zoom (el pellizco gana solo si el movimiento es horizontal).
  int _dedos = 0;

  void _dedo(int delta) {
    final antes = _dedos >= 2;
    _dedos = (_dedos + delta).clamp(0, 10);
    if ((_dedos >= 2) != antes) setState(() {});
  }

  Widget _espectroConDedos() => Listener(
    onPointerDown: (_) => _dedo(1),
    onPointerUp: (_) => _dedo(-1),
    onPointerCancel: (_) => _dedo(-1),
    child: _espectro(),
  );

  @override
  Widget build(BuildContext context) {
    final info = _Informacion(
      canal: _canalSel,
      canales: widget.canales,
      nota: widget.nota,
      conZoom: _conZoom,
    );
    // Un solo scroll vertical en las dos orientaciones: arriba la figura con
    // alto fijo y, al deslizar, la explicación y la lista de APs (con el
    // escaneo y el análisis) o la tabla. Solo quedan fijos los controles de
    // arriba (pestañas y chips). En horizontal la figura toma casi todo el
    // alto visible y asoma la pista "desliza hacia abajo".
    final horizontal = MediaQuery.orientationOf(context) == Orientation.landscape;
    return LayoutBuilder(
      builder: (context, cons) {
        final alto = horizontal
            ? (cons.maxHeight - altoPista).clamp(200.0, double.infinity).toDouble()
            : math.max(altoMinVertical, cons.maxHeight * fraccionVertical);
        final tema = Theme.of(context).textTheme;
        return SingleChildScrollView(
          // Con dos dedos sobre la figura no se desplaza: es un pellizco.
          physics: _dedos >= 2 ? const NeverScrollableScrollPhysics() : null,
          child: Column(
            children: [
              SizedBox(height: alto, child: _espectroConDedos()),
              if (horizontal)
                SizedBox(
                  height: altoPista,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.keyboard_arrow_down, size: 18),
                      const SizedBox(width: 4),
                      Text(
                        widget.abajo != null
                            ? 'Desliza hacia abajo: explicación y puntos de acceso'
                            : 'Desliza hacia abajo: explicación y tabla de canales',
                        style: tema.bodySmall,
                      ),
                    ],
                  ),
                ),
              info,
              const Divider(height: 1),
              widget.abajo ??
                  TablaCanales(
                    canales: widget.canales,
                    seleccionado: _canalSel,
                    alTocar: _tocarFila,
                    incrustada: true,
                  ),
            ],
          ),
        );
      },
    );
  }
}

/// Debajo del espectro: la nota de la banda o el detalle del canal tocado.
class _Informacion extends StatelessWidget {
  const _Informacion({
    required this.canal,
    required this.canales,
    required this.nota,
    required this.conZoom,
  });

  final Canal? canal;
  final List<Canal> canales;
  final String nota;
  final bool conZoom;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final c = canal;
    final List<Widget> hijos;
    if (c == null) {
      final ayuda = [
        'Toca un canal para ver con cuáles se solapa.',
        conZoom
            ? 'Doble toque para ver toda la banda.'
            : 'Pellizca para acercar; con zoom, arrastra para desplazarte.',
        'Eje vertical: potencia relativa (lineal); horizontal: frecuencia en MHz.',
      ].join(' ');
      hijos = [
        Text(nota, style: tema.bodySmall),
        const SizedBox(height: 4),
        Text(
          ayuda,
          style: tema.bodySmall?.copyWith(fontStyle: FontStyle.italic),
        ),
      ];
    } else {
      final solapes = [
        for (final o in canales)
          if (o.numero != c.numero && c.solapaCon(o)) o,
      ];
      final une = c.subcanales.length > 1
          ? ' · une ${c.subcanales.join(', ')}'
          : '';
      hijos = [
        Text(
          'Canal ${c.numero} · centro ${c.centroMHz} MHz · ocupa '
          '${mhz(c.inicioMHz)}–${mhz(c.finMHz)} MHz (${c.anchoMHz} MHz)$une',
          style: tema.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          solapes.isEmpty
              ? 'No se solapa con ningún otro canal de este ancho.'
              : 'Se solapa con: ${solapes.map((o) => '${o.numero} (${mhz(c.solapamientoMHz(o))} MHz)').join(', ')}',
          style: tema.bodySmall?.copyWith(
            color: solapes.isEmpty ? null : Theme.of(context).colorScheme.error,
          ),
        ),
      ];
    }
    // Sin alto máximo ni scroll propio: va dentro del scroll de la página.
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: hijos,
        ),
      ),
    );
  }
}

/// Controles fijos de arriba: anchos de canal, "Animar" y "APs".
///  - Vertical: SegmentedButton a todo el ancho (ancho arriba, estándar corto
///    abajo, nombre completo en el tooltip) y debajo una fila con "Animar" y
///    "APs" alternables, del mismo ancho. Todo con 48 dp de alto.
///  - Horizontal: los chips de siempre en un Wrap.
class _BarraOpciones extends StatelessWidget {
  const _BarraOpciones({
    required this.etiquetas,
    required this.anchos,
    required this.estandares,
    required this.estandaresCompletos,
    required this.elegido,
    required this.alElegir,
    required this.animar,
    required this.alAnimar,
    required this.verAps,
    required this.alVerAps,
    this.mostrarAnchos = true,
  });

  /// Texto de los chips en horizontal, p. ej. "22 MHz (802.11b)".
  final List<String> etiquetas;

  /// Por segmento (vertical): "40 MHz", estándar corto ("n") y completo ("802.11n").
  final List<String> anchos;
  final List<String> estandares;
  final List<String> estandaresCompletos;

  final int elegido;
  final ValueChanged<int> alElegir;

  /// false cuando los anchos deberían reflejar un AP y no hay ninguno.
  final bool mostrarAnchos;

  /// Interruptor de la simulación animada (incremento 3).
  final bool animar;
  final ValueChanged<bool> alAnimar;

  /// Interruptor de los APs en la vista estática (incremento 4). Al animar
  /// los APs siempre se ven, así que queda marcado y sin efecto.
  final bool verAps;
  final ValueChanged<bool> alVerAps;

  static const altoTactil = 48.0;

  void _sinAp(BuildContext context) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            'Toca un AP en el espectro o en la lista para cambiar su ancho.',
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.orientationOf(context) == Orientation.landscape) {
      return _chips();
    }
    final colores = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              // Sin AP seleccionado se ve normal pero sin selección; al
              // tocarlo solo avisa y no cambia nada.
              emptySelectionAllowed: !mostrarAnchos,
              selected: mostrarAnchos ? {elegido} : const <int>{},
              onSelectionChanged: (s) {
                if (!mostrarAnchos) {
                  _sinAp(context);
                } else if (s.isNotEmpty) {
                  alElegir(s.first);
                }
              },
              style: const ButtonStyle(
                minimumSize: WidgetStatePropertyAll(Size(0, altoTactil)),
                padding: WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                ),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.standard,
              ),
              segments: [
                for (var i = 0; i < anchos.length; i++)
                  ButtonSegment<int>(
                    value: i,
                    tooltip: '${anchos[i]} · ${estandaresCompletos[i]}',
                    label: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          anchos[i],
                          maxLines: 1,
                          softWrap: false,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          estandares[i],
                          maxLines: 1,
                          softWrap: false,
                          style: TextStyle(
                            fontSize: 11,
                            color: colores.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: _Alternable(
                  texto: 'Animar',
                  icono: Icons.play_arrow,
                  activo: animar,
                  alTocar: () => alAnimar(!animar),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Alternable(
                  texto: 'APs',
                  icono: Icons.router,
                  activo: animar || verAps,
                  // Al animar los APs siempre se ven: se ve activo y, al
                  // tocarlo, solo lo explica.
                  alTocar: animar
                      ? () => ScaffoldMessenger.of(context)
                          ..hideCurrentSnackBar()
                          ..showSnackBar(
                            const SnackBar(
                              content: Text('Con Animar, los APs siempre se muestran.'),
                            ),
                          )
                      : () => alVerAps(!verAps),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Horizontal: igual que antes.
  Widget _chips() => Padding(
    padding: const EdgeInsets.all(8),
    child: Wrap(
      spacing: 8,
      children: [
        for (var i = 0; i < etiquetas.length && mostrarAnchos; i++)
          ChoiceChip(
            label: Text(etiquetas[i]),
            selected: i == elegido,
            onSelected: (_) => alElegir(i),
          ),
        FilterChip(
          label: const Text('Animar'),
          selected: animar,
          onSelected: alAnimar,
        ),
        FilterChip(
          label: const Text('APs'),
          selected: animar || verAps,
          onSelected: animar ? null : alVerAps,
        ),
      ],
    ),
  );
}

/// Botón alternable de 48 dp (Material 3): tonal cuando está activo y con
/// borde cuando no. [alTocar] null = deshabilitado.
class _Alternable extends StatelessWidget {
  const _Alternable({
    required this.texto,
    required this.icono,
    required this.activo,
    required this.alTocar,
  });

  final String texto;
  final IconData icono;
  final bool activo;
  final VoidCallback? alTocar;

  @override
  Widget build(BuildContext context) {
    const estilo = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(
        Size.fromHeight(_BarraOpciones.altoTactil),
      ),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    final icono = Icon(this.icono, size: 18);
    final etiqueta = Text(texto, maxLines: 1);
    return Semantics(
      toggled: activo,
      child: activo
          ? FilledButton.tonalIcon(
              onPressed: alTocar,
              style: estilo,
              icon: icono,
              label: etiqueta,
            )
          : OutlinedButton.icon(
              onPressed: alTocar,
              style: estilo,
              icon: icono,
              label: etiqueta,
            ),
    );
  }
}

/// Lista de canales con su centro, rango ocupado, sub-banda y con quién se solapa.
class TablaCanales extends StatelessWidget {
  const TablaCanales({
    super.key,
    required this.canales,
    required this.alTocar,
    this.seleccionado,
    this.incrustada = false,
  });

  final List<Canal> canales;
  final Canal? seleccionado;
  final ValueChanged<Canal> alTocar;

  /// Dentro de otro desplazamiento (horizontal): sin scroll propio y con su
  /// alto completo, así el arrastre vertical mueve la pantalla entera.
  final bool incrustada;

  @override
  Widget build(BuildContext context) {
    final sel = seleccionado;
    return ListView.separated(
      shrinkWrap: incrustada,
      physics: incrustada ? const NeverScrollableScrollPhysics() : null,
      itemCount: canales.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final c = canales[i];
        final solapa = [
          for (final o in canales)
            if (o.numero != c.numero && c.solapaCon(o)) o.numero,
        ];
        final sub = c.subcanales.length > 1
            ? ' · une ${c.subcanales.join(', ')}'
            : '';
        final esSel = sel != null && sel.numero == c.numero;
        final pisaSel = sel != null && !esSel && c.solapaCon(sel);
        return ListTile(
          dense: true,
          selected: esSel,
          onTap: () => alTocar(c),
          leading: CircleAvatar(
            backgroundColor: pisaSel ? Theme.of(context).colorScheme.error : null,
            foregroundColor: pisaSel ? Theme.of(context).colorScheme.onError : null,
            child: Text('${c.numero}'),
          ),
          title: Text('Centro ${c.centroMHz} MHz · ancho ${c.anchoMHz} MHz'),
          subtitle: Text(
            'Ocupa ${mhz(c.inicioMHz)}–${mhz(c.finMHz)} MHz · ${c.subbanda}$sub\n'
            '${solapa.isEmpty ? 'No se solapa con ningún otro' : 'Se solapa con: ${solapa.join(', ')}'}',
          ),
          isThreeLine: true,
        );
      },
    );
  }
}
