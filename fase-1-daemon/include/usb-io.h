// SPDX-License-Identifier: GPL-2.0
/**
 * usb-io.h — IOKit USB wrapper for Focusrite Scarlett control
 *
 * Provides a minimal abstraction over IOKit USB host device
 * control- and interrupt-transfers.
 */
#pragma once

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * scarlett_device — Opaque handle to an open USB device.
 */
typedef struct scarlett_device scarlett_device_t;

/**
 * scarlett_usb_control_request — Raw USB control request parameters.
 *
 * Fields map directly to the USB setup packet as described in
 * USB 2.0 spec §9.3 (USB Device Framework).
 */
typedef struct scarlett_usb_control_request {
	uint8_t  bmRequestType;
	uint8_t  bRequest;
	uint16_t wValue;
	uint16_t wIndex;
	uint16_t wLength;
	void    *data;
} scarlett_usb_control_request_t;

/**
 * scarlett_usb_open — Find and open a Scarlett device by VID/PID.
 *
 * @vid: USB vendor ID  (e.g. 0x1235 for Focusrite)
 * @pid: USB product ID (e.g. 0x8012 for Scarlett 6i6)
 *
 * Return: device handle, or NULL on failure.
 */
scarlett_device_t *scarlett_usb_open(uint16_t vid, uint16_t pid);

/**
 * scarlett_usb_close — Close a previously opened device.
 *
 * @dev: device handle returned by scarlett_usb_open().
 */
void scarlett_usb_close(scarlett_device_t *dev);

/**
 * scarlett_usb_control_transfer — Perform a USB control transfer.
 *
 * Wraps IOKit's USBDeviceSendControlRequest (or equivalent).
 *
 * @dev:  device handle
 * @req:  control-request parameters (direction, type, recipient,
 *        bRequest, wValue, wIndex, data buffer + length)
 *
 * Return: 0 on success, -1 on error.
 */
int scarlett_usb_control_transfer(
	scarlett_device_t              *dev,
	scarlett_usb_control_request_t *req);

/**
 * scarlett_interrupt_callback_t — Called from a background thread when
 *                                  interrupt data arrives.
 */
typedef void (*scarlett_interrupt_callback_t)(
	const uint8_t *data,
	size_t         len);

/**
 * scarlett_usb_start_interrupt — Open the interrupt pipe and start a
 *                                background thread that reads notifications.
 *
 * The callback is invoked on the background thread for every received
 * interrupt packet.  Call scarlett_usb_stop_interrupt() to tear down.
 *
 * @dev:      device handle
 * @callback: function called with each packet; may be NULL (log only).
 *
 * Return: 0 on success, -1 on error.
 */
int scarlett_usb_start_interrupt(
	scarlett_device_t              *dev,
	scarlett_interrupt_callback_t   callback);

/**
 * scarlett_usb_stop_interrupt — Stop the background interrupt thread and
 *                               close the pipe.
 */
void scarlett_usb_stop_interrupt(void);

#ifdef __cplusplus
}
#endif
