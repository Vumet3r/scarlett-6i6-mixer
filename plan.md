# Scarlett macOS Port — Visión general

Portar el controlador de la Focusrite Scarlett 6i6 de Linux a macOS
eliminando la dependencia de ALSA y GTK4.

## Arquitectura actual (Linux)
```
kernel driver (mixer_scarlett.c) ←→ USB ←→ Scarlett 6i6
       ↓ (expone controles ALSA)
alsa-scarlett-gui (GTK4, 35k líneas)
```

## Arquitectura objetivo (macOS)
```
scarlett-daemon (C/IOKit) ←→ USB ←→ Scarlett 6i6
       ↓ (Unix socket)
scarlett-app (SwiftUI)
```

O bien app monolítica que habla USB directamente.

## Fases
1. **Daemon USB** — Acceso IOKit, comunicación USB, protocolo socket
2. **GUI nativa** — SwiftUI reemplazando GTK4, lógica C pura se reutiliza
3. **Features 6i6** — Impedancia, pad, gain, routing, meters

## Estimación
20 días hábiles (~1 mes).

## Código existente
- `fcp.c` — Focusrite Control Protocol driver (Linux kernel, 1129 líneas)
- `mixer_scarlett.c` — Driver 1ª generación (1456 líneas)
- `alsa-scarlett-gui/` — GUI completa en GTK4 + C (~35k líneas)
- `scarlett-gen2/` — Driver kernel para 2ª gen+

Para detalle, ver carpeta de cada fase.
