# Fase 1 — Daemon USB (5 días)

Objetivo: CLI en macOS que habla con la Scarlett 6i6 vía USB.

## Tareas

### 1.0 Detectar y abrir dispositivo USB (día 1)
- [ ] Usar `ioreg -p IOUSB -w0 | grep -i scarlett`
- [ ] Escribir mini programa C que abre el device con IOKit
- [ ] Verificar USB ID 0x1235:0x8012
- [ ] Leer descriptor de la interfaz vendor-specific (class 255)

### 1.1 Comunicación USB básica (días 2-3)
- [ ] Implementar `usb_ctl_msg` usando IOKit (`USBSendControlRequest`)
- [ ] Probar comando simple: leer Sample Clock Source
- [ ] Probar comando de escritura: cambiar impedance del Input 1
- [ ] Verificar respuestas contra el hardware

Referencia: `mixer_scarlett.c` líneas de inicialización y las funciones
`snd_usb_ctl_msg`. En IOKit se usa `USBDeviceReadPipe` / `USBSendControlRequest`.

### 1.2 Puerto de mixer_scarlett.c (días 3-4)
- [ ] Copiar estructuras de hardware: `s6i6_info`, `s8i6_info`, etc. (~260 líneas)
- [ ] Copiar mapeo de wIndex/wValue/canales
- [ ] Copiar inicialización de sample rate
- [ ] Ignorar secciones `forte_*` (Focusrite Forte, ~400 líneas)
- [ ] Reemplazar callbacks ALSA por función que envía datos al socket

### 1.3 Daemon socket (día 5)
- [ ] Socket Unix en `/tmp/scarlett-6i6.sock`
- [ ] Protocolo: `GET <port>` / `SET <port> <value>` / `GET_METERS` / `SAVE`
- [ ] Formato: JSON o binario simple
- [ ] Manejar múltiples conexiones (thread pool o dispatch)

### 1.4 Notificaciones USB (día 5)
- [ ] Implementar URB de notificación con IOKit (interrupt pipe)
- [ ] Enviar eventos por socket a los clientes conectados

## Archivos a crear
- `scarlett-daemon.c` — entry point, loop principal
- `usb-io.c` + `usb-io.h` — wrappers IOKit
- `scarlett-protocol.c` + `scarlett-protocol.h` — comandos USB específicos Scarlett
- `socket-server.c` + `socket-server.h` — servidor Unix socket
- `Makefile`

## Criterio de éxito
```bash
scarlett-daemon &
scarlett-client get impedance:1
# → Line
scarlett-client set impedance:1 hi-z
scarlett-client get impedance:1
# → Hi-Z
```
