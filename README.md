# Espectro Wi-Fi

App Android del examen final de Comunicaciones Inalámbricas (UFPSO). Muestra
cómo se ocupan las bandas de 2.4 GHz y 5 GHz: canales, anchos de banda,
solapamientos e interferencia, con puntos de acceso simulados y redes reales.

## Qué hace

- Espectro de 2.4 GHz y 5 GHz con los canales permitidos en Colombia
  (Res. ANE 105/2020) y la forma real de cada señal (DSSS y OFDM).
- Animación del espectro en vivo y cascada, con anchos de 20/40/80/160 MHz.
- APs simulados: agregar, editar, quitar, cambiar canal, ancho y potencia, y
  activar o desactivar canales.
- Análisis de solapamiento e interferencia por par de APs (quién oye a quién,
  SIR y gravedad).
- Escaneo real de las redes Wi-Fi con el WifiManager de Android.
- Reporte del análisis en PDF.
- "Sugerir canal": propone el mejor canal y ancho para un AP según el análisis.

## Tecnologías

- Flutter (Dart).
- Kotlin para el canal nativo del escaneo Wi-Fi.
- Paquete `pdf` para el reporte, con la fuente Noto Sans (licencia OFL).

## Cómo correrla

Con un celular Android conectado por USB y la depuración USB activa:

```
cd app_espectro_wifi
flutter pub get
flutter run
```

## Cómo generar el APK

```
cd app_espectro_wifi
flutter build apk --release
```

El APK queda en `app_espectro_wifi/build/app/outputs/flutter-apk/app-release.apk`.
