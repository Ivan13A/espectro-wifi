import 'package:material_ui/material_ui.dart';

import 'pantallas/pantalla_espectro.dart';
import 'tema.dart';

void main() {
  runApp(const AppEspectro());
}

class AppEspectro extends StatefulWidget {
  const AppEspectro({super.key});

  @override
  State<AppEspectro> createState() => _AppEspectroState();
}

class _AppEspectroState extends State<AppEspectro> {
  // Por defecto sigue al sistema. No se guarda al cerrar la app.
  ThemeMode modo = ThemeMode.system;

  /// Rota: automático → claro → oscuro → automático.
  void _rotarModo() => setState(() {
    modo = switch (modo) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    };
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Espectro Wi-Fi',
      debugShowCheckedModeBanner: false,
      theme: temaDeSemilla(semilla24, Brightness.light),
      darkTheme: temaDeSemilla(semilla24, Brightness.dark),
      themeMode: modo,
      home: PantallaEspectro(modoTema: modo, alRotarTema: _rotarModo),
    );
  }
}
