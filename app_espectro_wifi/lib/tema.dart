// Tema de la app: claro y oscuro con ColorScheme.fromSeed (Material 3) y una
// semilla distinta por banda. Solo es apariencia: el dibujo del espectro y la
// cascada tienen sus propios colores oscuros y no dependen de este tema.
import 'package:material_ui/material_ui.dart';

import 'modelo/canales.dart';

/// Semilla de la vista de 2.4 GHz (azul).
const semilla24 = Color(0xFF185FA5);

/// Semilla de la vista de 5 GHz (verde azulado).
const semilla5 = Color(0xFF0F6E56);

Color semillaDe(Banda banda) => banda == Banda.ghz24 ? semilla24 : semilla5;

ThemeData temaDeSemilla(Color semilla, Brightness brillo) => ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: semilla, brightness: brillo),
  useMaterial3: true,
);

final _cacheTemas = <(Banda, Brightness), ThemeData>{};

/// Tema de la vista de [banda] en el [brillo] dado (se calcula una sola vez).
ThemeData temaBanda(Banda banda, Brightness brillo) => _cacheTemas.putIfAbsent(
  (banda, brillo),
  () => temaDeSemilla(semillaDe(banda), brillo),
);

/// Envuelve [hijo] con el tema de [banda], en el brillo del tema actual, y le
/// da su fondo (así el color de la banda llega hasta el borde de la vista).
class TemaDeBanda extends StatelessWidget {
  const TemaDeBanda({super.key, required this.banda, required this.hijo});

  final Banda banda;
  final Widget hijo;

  @override
  Widget build(BuildContext context) {
    final tema = temaBanda(banda, Theme.of(context).brightness);
    return Theme(
      data: tema,
      child: Material(color: tema.colorScheme.surface, child: hijo),
    );
  }
}
