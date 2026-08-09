// SPDX-License-Identifier: GPL-2.0
#include "usb-io.h"

#import <IOUSBHost/IOUSBHost.h>
#import <IOKit/IOKitLib.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>

struct scarlett_device {
	void             *hostDevice;   // IOUSBHostDevice *, bridged
};

scarlett_device_t *
scarlett_usb_open(uint16_t vid, uint16_t pid)
{
	@autoreleasepool {
		CFMutableDictionaryRef matching = IOServiceMatching("IOUSBHostDevice");
		if (!matching) {
			fprintf(stderr, "scarlett_usb_open: IOServiceMatching failed\n");
			return NULL;
		}

		io_iterator_t iter = 0;
		IOReturn ret = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iter);
		if (ret != kIOReturnSuccess || !iter) {
			fprintf(stderr, "scarlett_usb_open: no USB devices found\n");
			if (iter) IOObjectRelease(iter);
			return NULL;
		}

		io_service_t service = 0;
		while ((service = IOIteratorNext(iter))) {
			CFNumberRef vidRef = (CFNumberRef)IORegistryEntryCreateCFProperty(
				service, CFSTR("idVendor"), kCFAllocatorDefault, 0);
			CFNumberRef pidRef = (CFNumberRef)IORegistryEntryCreateCFProperty(
				service, CFSTR("idProduct"), kCFAllocatorDefault, 0);

			if (vidRef && pidRef) {
				int foundVid = 0, foundPid = 0;
				CFNumberGetValue(vidRef, kCFNumberIntType, &foundVid);
				CFNumberGetValue(pidRef, kCFNumberIntType, &foundPid);
				if (foundVid == vid && foundPid == pid)
					break;
			}

			if (vidRef) CFRelease(vidRef);
			if (pidRef) CFRelease(pidRef);
			IOObjectRelease(service);
			service = 0;
		}
		IOObjectRelease(iter);

		if (!service) {
			fprintf(stderr, "scarlett_usb_open: device not found (VID 0x%04x PID 0x%04x)\n",
				vid, pid);
			return NULL;
		}

		dispatch_queue_t queue = dispatch_queue_create("scarlett-usb",
			DISPATCH_QUEUE_SERIAL);
		NSError *error = nil;

		IOUSBHostDevice *device = [[IOUSBHostDevice alloc]
			initWithIOService:service
			options:IOUSBHostObjectInitOptionsDeviceSeize
			queue:queue
			error:&error
			interestHandler:nil];
		IOObjectRelease(service);

		if (!device) {
			fprintf(stderr, "scarlett_usb_open: IOUSBHostDevice init failed: %s\n"
				"Try: killall MIDIServer && scarlett-daemon\n",
				error ? [[error localizedDescription] UTF8String] : "unknown error");
			return NULL;
		}

		printf("scarlett_usb_open: device opened\n");
		/* Note: interrupt endpoint 0x84 is on interface 0 (AudioControl),
		 * which macOS does not expose as a separate IOUSBHostInterface.
		 * Interrupt notifications are not available on this hardware. */

		scarlett_device_t *dev = (scarlett_device_t *)calloc(1, sizeof(struct scarlett_device));
		if (!dev) {
			[device destroyWithOptions:IOUSBHostObjectDestroyOptionsDeviceSurrender];
			return NULL;
		}
		dev->hostDevice = (void *)CFBridgingRetain(device);
		return dev;
	}
}

void
scarlett_usb_close(scarlett_device_t *dev)
{
	if (!dev) return;

	IOUSBHostDevice *device = (__bridge IOUSBHostDevice *)dev->hostDevice;
	[device destroyWithOptions:IOUSBHostObjectDestroyOptionsDeviceSurrender];
	CFBridgingRelease(dev->hostDevice);
	free(dev);
}

int
scarlett_usb_control_transfer(
	scarlett_device_t              *dev,
	scarlett_usb_control_request_t *req)
{
	if (!dev || !req) return -1;

	@autoreleasepool {
		IOUSBHostDevice *device = (__bridge IOUSBHostDevice *)dev->hostDevice;

		IOUSBDeviceRequest usbReq;
		usbReq.bmRequestType = req->bmRequestType;
		usbReq.bRequest      = req->bRequest;
		usbReq.wValue        = req->wValue;
		usbReq.wIndex        = req->wIndex;
		usbReq.wLength       = req->wLength;

		NSMutableData *data = [NSMutableData dataWithLength:req->wLength];
		if (!data && req->wLength > 0) return -1;
		if (req->data && !(req->bmRequestType & 0x80))
			memcpy([data mutableBytes], req->data, req->wLength);

		NSUInteger bytesTransferred = 0;
		NSError *error = nil;

		BOOL ok = [device sendDeviceRequest:usbReq
		                              data:data
		                  bytesTransferred:&bytesTransferred
		                 completionTimeout:5.0
		                             error:&error];

		if (!ok) {
			fprintf(stderr, "scarlett_usb_control_transfer: %s"
				" (0x%x %d wVal=0x%04x wIdx=0x%04x len=%d)\n",
				error ? [[error localizedDescription] UTF8String] : "unknown",
				req->bmRequestType, req->bRequest, req->wValue,
				req->wIndex, req->wLength);
			return -1;
		}

		if ((req->bmRequestType & 0x80) && req->data && bytesTransferred > 0) {
			size_t copyLen = bytesTransferred < req->wLength
				? bytesTransferred : req->wLength;
			memcpy(req->data, [data bytes], copyLen);
		}

		return 0;
	}
}

/* ---- Interrupt endpoint — not available on this hardware ---- */
static pthread_t               g_intrThread = {0};
static volatile bool           g_intrRunning = false;
static scarlett_interrupt_callback_t g_intrCb = NULL;

static void *
interrupt_thread(void *arg)
{
	(void)arg;
	while (g_intrRunning) {
		/* No interrupt endpoint accessible; sleep and wait for stop */
		usleep(250000);
	}
	return NULL;
}

int
scarlett_usb_start_interrupt(
	scarlett_device_t              *dev,
	scarlett_interrupt_callback_t   callback)
{
	(void)dev;

	fprintf(stderr, "interrupt: Scarlett 6i6 interrupt endpoint not accessible on macOS\n");
	fprintf(stderr, "interrupt: notifications not available\n");

	/* Start a dummy thread so stop_interrupt can signal cleanly */
	g_intrCb       = callback;
	g_intrRunning  = true;

	int rc = pthread_create(&g_intrThread, NULL, interrupt_thread, NULL);
	if (rc != 0) {
		g_intrRunning = false;
		return -1;
	}
	pthread_detach(g_intrThread);
	return 0;
}

void
scarlett_usb_stop_interrupt(void)
{
	g_intrRunning = false;
	g_intrCb = NULL;
}
