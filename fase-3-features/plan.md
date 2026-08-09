# Fase 3 — Features específicas 6i6 (5 días)

Objetivo: Implementar todas las funciones de hardware de la Scarlett 6i6.

## Tareas

### 3.0 Impedance, Pad, Gain (día 1)
- [ ] Input impedance: Line(0) / Hi-Z(1) — wIndex 0x01, wValue 0x0901+ch
- [ ] Pad: -10dB on/off — wIndex 0x01, wValue 0x0b01+ch
- [ ] Gain switch: Lo(0) / Hi(1) — wIndex 0x01, wValue 0x0801+ch
- [ ] UI: botón toggle por input channel

### 3.1 Master Volume & Mute (día 1)
- [ ] Master volume — wIndex 0x0a, wValue 0x0200+bus
- [ ] Master mute — wIndex 0x0a, wValue 0x0100+bus

### 3.2 Clock & Sample Rate (día 2)
- [ ] Clock source: Internal / S/PDIF / ADAT — wIndex 0x28
- [ ] Sample rate: 44.1 / 48 / 88.2 / 96 kHz — wIndex 0x29
- [ ] Sync status polling — wIndex 0x3c MEM, wValue 0x0002

### 3.3 Routing Matrix (días 2-3)
- [ ] Matrix Mux — wIndex 0x32, wValue 0x0600+channel
- [ ] Output Mux — wIndex 0x33
- [ ] Capture Mux — wIndex 0x34
- [ ] Matrix Mixer Gains — wIndex 0x3c

### 3.4 Level Meters (días 3-4)
- [ ] Lectura periódica — wIndex 0x3c MEM, wValue 0x0000/1/3
- [ ] Mapping de canales físicos a slots del meter
- [ ] Peak hold y decay

### 3.5 Save to hardware (día 4)
- [ ] Comando save — wIndex 0x3c MEM, wValue 0x005a, data 0xa5
- [ ] Confirmar que persiste tras desconectar USB

### 3.6 Polishing (día 5)
- [ ] Edge cases: dispositivo desconectado, errores USB
- [ ] Reconnect automático al daemon
- [ ] Pruebas con la 6i6 física

## Criterio de éxito
Todas las funciones de la tabla USB (`SPECS.md` de fase 1) implementadas
y verificables desde la GUI.
