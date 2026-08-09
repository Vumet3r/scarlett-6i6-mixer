# Especificaciones GUI — Port desde alsa-scarlett-gui

## Archivos de alsa-scarlett-gui y su equivalente

| Archivo C (Linux) | Líneas | Acción en macOS |
|---|---|---|
| `alsa.c` | 1808 | Reemplazar: socket daemon en vez de ALSA |
| `alsa.h` | 461 | Reusar: struct alsa_card, alsa_elem |
| `scarlett2.h` | 54 | Reusar (ioctl defs) |
| `window-routing.c` | 2304 | Reescribir: SwiftUI RoutingView |
| `window-mixer.c` | 1538 | Reescribir: SwiftUI MixerView |
| `window-dsp.c` | 2164 | Reescribir: SwiftUI DSPView |
| `window-levels.c` | 448 | Reescribir: SwiftUI MetersView |
| `iface-mixer.c` | 1590 | Portar lógica (C puro, no GTK) |
| `stereo-link.c` | 2373 | Portar lógica (C puro) |
| `config-io.c` | 2100 | Portar lógica (C puro) |
| `gtkdial.c` | 1924 | Reemplazar: SwiftUI Knob |
| `glow.c` | ~300 | Reimplementar: efecto glow en Metal/CoreImage |
| `hardware.c` | ~200 | Reusar: definiciones de hardware |
| 20+ archivos pequeños | ~10k | Reusar: lógica de negocio pura |

## Protocolo cliente-daemon

### Comandos
```
GET <path>             → valor
SET <path> <valor>     → ok/error
GET_METERS             → [nivel1, nivel2, ...]
SAVE                   → ok
LIST                   → lista de controles disponibles
```

### Paths
```
/input/<n>/impedance
/input/<n>/pad
/input/<n>/gain
/output/<n>/volume
/output/<n>/mute
/master/volume
/master/mute
/clock/source
/clock/samplerate
/routing/matrix/<src>/<dst>
/meters
```

### Formato respuesta
```json
{"ok": true, "value": ...}
{"ok": false, "error": "mensaje"}
```

## Vistas SwiftUI propuestas
- `ContentView` — contenedor principal con tabs
- `MixerView` — faders por canal, mute/solo
- `RoutingView` — matriz de routing
- `DSPView` — panel de efectos
- `MetersView` — barras de nivel
- `SettingsView` — clock source, sample rate

## CoreImage / Metal
- El efecto glow de `glow.c` se puede reimplementar con `CIFilter` o shader Metal
- Alternativa: `NSView` con `CGShading` para mínimo esfuerzo
