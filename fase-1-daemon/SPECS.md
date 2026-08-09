# Especificaciones USB — Scarlett 6i6

## Identificación
- USB ID: `0x1235:0x8012`
- 2 interfaces USB:
  - Interface 0: Audio class-compliant (lo maneja macOS automáticamente)
  - Interface 1: Vendor-specific (class 255) — endpoint de control

## Control messages (URB)
Del driver Linux `mixer_scarlett.c`:

### bRequest values
- `0x01` = `UAC2_CS_CUR` (leer/escribir control)
- `0x03` = `UAC2_CS_MEM` (meters/sync, bmRequestType diferente)

### Formato general
```c
snd_usb_ctl_msg(dev, pipe, bRequest, bmRequestType, wValue, wIndex, &data, size);
```

### bmRequestType
- Dirección: `USB_DIR_OUT` (0x00) / `USB_DIR_IN` (0x80)
- Tipo: `USB_TYPE_CLASS` (0x20)
- Recipiente: `USB_RECIP_INTERFACE` (0x01)
- Compuesto: `USB_RECIP_INTERFACE | USB_TYPE_CLASS | USB_DIR_OUT` = `0x21`
             `USB_RECIP_INTERFACE | USB_TYPE_CLASS | USB_DIR_IN`  = `0xA1`

Para MEM: `USB_DIR_IN | USB_TYPE_VENDOR | USB_RECIP_OTHER` = `0xC1`

## Tabla de controles (6i6)

| Función | wIndex | wValue | Data | bRequest |
|---------|--------|--------|------|----------|
| Impedance (Line/Hi-Z) | 0x01 | 0x0901+ch | 2B | 0x01 |
| Pad (-10dB) | 0x01 | 0x0b01+ch | 2B | 0x01 |
| Gain switch (Lo/Hi) | 0x01 | 0x0801+ch | 2B | 0x01 |
| Master Volume | 0x0a | 0x0200+bus | 2B | 0x01 |
| Master Mute | 0x0a | 0x0100+bus | 2B | 0x01 |
| Clock Source | 0x28 | 0x0100 | 1B | 0x01 |
| Sample Rate | 0x29 | 0x0100 | 4B | 0x01 |
| Matrix Mux (routing) | 0x32 | 0x0600+ch | 2B | 0x01 |
| Output Mux | 0x33 | bus | 2B | 0x01 |
| Capture Mux | 0x34 | 0-18 | 2B | 0x01 |
| Matrix Mixer Gains | 0x3c | mixer-node | 2B | 0x01 |
| Level Meters | 0x3c (MEM) | 0x0000/1/3 | 2B*N | 0x03 |
| Sync Status | 0x3c (MEM) | 0x0002 | 1B | 0x03 |
| Save to hardware | 0x3c (MEM) | 0x005a | 0xa5 | 0x03 |

### Ejemplo: cambiar impedance del Input 1
```c
// wValue = (0x09 << 8) | channel
// wIndex = interface | (control_group << 8)
snd_usb_ctl_msg(dev, usb_sndctrlpipe(dev, 0),
    UAC2_CS_CUR,
    USB_RECIP_INTERFACE | USB_TYPE_CLASS | USB_DIR_OUT,
    0x0901,       // wValue: control 0x09, channel 1
    interface | (0x01 << 8),  // wIndex: interface, control group 0x01
    &value, 2);   // data: Line(0) / Hi-Z(1)
```

## Protocolo FCP (Focusrite Control Protocol, 2ª gen+)
`fcp.c` implementa el protocolo para Scarlett 2ª gen+ / Clarett / Vocaster.
Usa opcodes en lugar de URBs directos:

- `FCP_USB_REQ_STEP0` = 0 (init step 0)
- `FCP_USB_REQ_CMD_TX` = 2 (enviar comando)
- `FCP_USB_REQ_CMD_RX` = 3 (recibir respuesta)

Estructura de paquete FCP:
```c
struct fcp_usb_packet {
    __le32 opcode;
    __le16 size;
    __le16 seq;
    __le32 error;
    __le32 pad;
    u8 data[];
};
```

No aplica a la 6i6 (1ª gen), que usa URBs directos con wIndex/wValue.
Se documenta aquí por si se extiende el daemon a 2ª gen+.

## IOKit API (macOS)
```c
// Abrir dispositivo
IOServiceGetMatchingServices(kIOMasterPortDefault,
    IOServiceMatching("IOUSBHostDevice"), &iterator);

// Enviar control request
IOReturn err = USBDeviceSendControlRequest(device,
    &controlRequest, timeout_ms);

// Leer interrupt pipe (notificaciones)
IOReturn err = USBDeviceReadPipe(device, endpointRef,
    data, &length, timeout_ms);
```

Referencia: `IOUSBHostFamily` / `IOKitLib`.
