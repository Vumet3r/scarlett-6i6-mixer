# Fase 2 — GUI macOS nativa (10 días)

Objetivo: App SwiftUI que se conecta al daemon y permite controlar la Scarlett.

## Estrategia: Opción B (recomendada)
Reescribir la GUI en SwiftUI manteniendo la lógica C pura:
- Lógica de routing/mixer (C, ~15k líneas) se compila igual en macOS
- Solo reemplazar:
  - GTK4 → SwiftUI/Cocoa
  - ALSA → socket daemon
  - inotify → FSEvents / IOKit notification

## Tareas

### 2.0 Cliente socket (días 1-2)
- [ ] Escribir `libscarlett-client.c/h` — wrapper C del protocolo daemon
- [ ] Bridge Swift → C (modulemap o wrapper ObjC)
- [ ] Probar conexión desde Swift playground

### 2.1 Mixer básico (días 3-5)
- [ ] Ventana principal con faders (niveles de canal)
- [ ] Mute / Solo buttons
- [ ] Master volume slider
- [ ] Conectar cada control al comando SET del daemon
- [ ] Polling de meters (timer cada 100ms)

### 2.2 Routing grid (días 5-7)
- [ ] Matriz routing: fuentes → destinos (Matrix Mixer)
- [ ] Selectores de fuente por canal de salida
- [ ] Mostrar nombres de canal desde hardware definitions

### 2.3 DSP (días 8-9)
- [ ] Panel de efectos si aplica
- [ ] Save/Load presets (guardar estado local)

### 2.4 Niveles (meters) (días 9-10)
- [ ] Barras de nivel en tiempo real
- [ ] Peak hold
- [ ] Efecto glow (portar de `glow.c`)

## Archivos a crear
- `scarlett-app/` — proyecto Xcode SwiftUI
- `libscarlett-client/` — cliente C para el socket
- `scarlett-app/Bridge/` — headers de bridging

## Criterio de éxito
- App lanzable desde Finder
- Muestra niveles en tiempo real
- Se puede cambiar impedance, gain, volumen, routing
- Persiste configuración al cerrar

## Especificaciones de componentes
Ver `SPECS.md` de esta fase.
