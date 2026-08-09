// SPDX-License-Identifier: GPL-2.0
#include "usb-io.h"
#include "socket-server.h"

#include <stdio.h>
#include <stdlib.h>
#include <signal.h>
#include <unistd.h>
#include <string.h>
#include <stdint.h>
#include <pthread.h>
#include <time.h>

#define SCARLETT_VID 0x1235
#define SCARLETT_PID 0x8012

static volatile sig_atomic_t keep_running = 1;
static scarlett_device_t *g_dev = NULL;
static pthread_mutex_t    g_dev_lock = PTHREAD_MUTEX_INITIALIZER;
static volatile int       g_usb_failures = 0;

static void handle_signal(int sig) { (void)sig; keep_running = 0; }

/* ---- Device lifecycle (watchdog-managed) ---- */

static void device_try_open(void)
{
	if (g_dev) return;
	g_dev = scarlett_usb_open(SCARLETT_VID, SCARLETT_PID);
	if (g_dev) {
		printf("scarlett-daemon: device opened (watchdog)\n");
		if (scarlett_usb_start_interrupt(g_dev, NULL) != 0)
			printf("scarlett-daemon: interrupt monitoring unavailable\n");
		g_usb_failures = 0;
	}
}

static void device_reset(void)
{
	if (!g_dev) return;
	scarlett_usb_stop_interrupt();
	scarlett_usb_close(g_dev);
	g_dev = NULL;
}

static void *watchdog_main(void *arg)
{
	int last_log = 0;
	(void)arg;
	while (keep_running) {
		usleep(1000000);
		pthread_mutex_lock(&g_dev_lock);
		if (!g_dev) {
			device_try_open();
			if (!g_dev && (int)time(NULL) - last_log > 10) {
				printf("scarlett-daemon: device absent, retrying every 1s\n");
				last_log = (int)time(NULL);
			}
		} else if (g_usb_failures >= 5) {
			printf("scarlett-daemon: %d consecutive USB failures — resetting device\n",
				g_usb_failures);
			device_reset();
			device_try_open();
		}
		pthread_mutex_unlock(&g_dev_lock);
	}
	return NULL;
}

/* ---- USB helpers ---- */

static int usb_ctl_cur(uint8_t dir, uint16_t wVal, uint16_t wIdx, void *data, uint16_t len)
{
	scarlett_usb_control_request_t req = {
		.bmRequestType = dir, // 0xA1=IN, 0x21=OUT
		.bRequest      = 0x01,
		.wValue        = wVal,
		.wIndex        = wIdx,
		.wLength       = len,
		.data          = data,
	};
	return scarlett_usb_control_transfer(g_dev, &req);
}

static int usb_read_cur(uint16_t wVal, uint16_t wIdx, void *data, uint16_t len)
	{ return usb_ctl_cur(0xA1, wVal, wIdx, data, len); }

static int usb_write_cur(uint16_t wVal, uint16_t wIdx, void *data, uint16_t len)
	{ return usb_ctl_cur(0x21, wVal, wIdx, data, len); }

static int usb_read_mem(uint16_t wVal, uint16_t wIdx, void *data, uint16_t len)
{
	scarlett_usb_control_request_t req = {
		.bmRequestType = 0xA1,
		.bRequest      = 0x03,
		.wValue        = wVal,
		.wIndex        = wIdx,
		.wLength       = len,
		.data          = data,
	};
	return scarlett_usb_control_transfer(g_dev, &req);
}

static int usb_write_mem(uint16_t wVal, uint16_t wIdx, void *data, uint16_t len)
{
	scarlett_usb_control_request_t req = {
		.bmRequestType = 0x21,
		.bRequest      = 0x03,
		.wValue        = wVal,
		.wIndex        = wIdx,
		.wLength       = len,
		.data          = data,
	};
	return scarlett_usb_control_transfer(g_dev, &req);
}

/* ---- value parsers / formatters ---- */

static const char *str_onoff(int v) { return v ? "On" : "Off"; }
static const char *str_line_hi(int v) { return v ? "Hi-Z" : "Line"; }
static const char *str_lo_hi(int v) { return v ? "Hi" : "Lo"; }

/* ---- GET commands ---- */

static int cmd_get_clock(char *r, size_t rs)
{
	uint8_t d = 0;
	if (usb_read_cur(0x0100, 0x2800, &d, 1)) goto e;
	const char *s[] = {"Internal", "S/PDIF", "ADAT"};
	snprintf(r, rs, "OK %s", d < 3 ? s[d] : "?");
	return 0; e: snprintf(r, rs, "ERR ctl"); return -1;
}

static int cmd_get_rate(char *r, size_t rs)
{
	uint8_t d[4] = {0};
	if (usb_read_cur(0x0100, 0x2900, d, 4)) goto e;
	uint32_t rate = (uint32_t)d[0] | ((uint32_t)d[1] << 8)
		| ((uint32_t)d[2] << 16) | ((uint32_t)d[3] << 24);
	snprintf(r, rs, "OK %u Hz", rate);
	return 0; e: snprintf(r, rs, "ERR ctl"); return -1;
}

static int cmd_get_sync(char *r, size_t rs)
{
	uint8_t d = 0;
	if (usb_read_mem(0x0002, 0x3c00, &d, 1)) goto e;
	snprintf(r, rs, "OK %s", d ? "Locked" : "Unlocked");
	return 0; e: snprintf(r, rs, "ERR ctl"); return -1;
}

static int cmd_get_impedance(char *r, size_t rs, int ch)
{
	uint8_t d[2] = {0};
	if (usb_read_cur(0x0900 | ch, 0x0100, d, 2)) goto e;
	snprintf(r, rs, "OK %s", str_line_hi(d[0]));
	return 0; e: snprintf(r, rs, "ERR ctl"); return -1;
}

static int cmd_get_pad(char *r, size_t rs, int ch)
{
	uint8_t d[2] = {0};
	if (usb_read_cur(0x0b00 | ch, 0x0100, d, 2)) goto e;
	snprintf(r, rs, "OK %s", str_onoff(d[0]));
	return 0; e: snprintf(r, rs, "ERR ctl"); return -1;
}

static int cmd_get_gain(char *r, size_t rs, int ch)
{
	uint8_t d[2] = {0};
	if (usb_read_cur(0x0800 | ch, 0x0100, d, 2)) goto e;
	snprintf(r, rs, "OK %s", str_lo_hi(d[0]));
	return 0; e: snprintf(r, rs, "ERR ctl"); return -1;
}

static int cmd_get_volume(char *r, size_t rs, int bus)
{
	uint8_t d[2] = {0};
	if (usb_read_cur(0x0200 | bus, 0x0a00, d, 2)) goto e;
	int dB = (int)d[0] - 128;
	snprintf(r, rs, "OK %d dB", dB);
	return 0; e: snprintf(r, rs, "ERR ctl"); return -1;
}

static int cmd_get_mute(char *r, size_t rs, int bus)
{
	uint8_t d[2] = {0};
	if (usb_read_cur(0x0100 | bus, 0x0a00, d, 2)) goto e;
	snprintf(r, rs, "OK %s", d[0] ? "Muted" : "Unmuted");
	return 0; e: snprintf(r, rs, "ERR ctl"); return -1;
}

static int cmd_set_clock(char *r, size_t rs, const char *val)
{
	uint8_t d[1] = {0};
	if      (!strcmp(val, "internal")) d[0] = 0;
	else if (!strcmp(val, "spdif"))    d[0] = 1;
	else if (!strcmp(val, "adat"))     d[0] = 2;
	else return snprintf(r, rs, "ERR val: %s (internal|spdif|adat)", val), -1;
	if (usb_write_cur(0x0100, 0x2800, d, 1)) goto e;
	return snprintf(r, rs, "OK %s", val), 0; e: snprintf(r, rs, "ERR ctl"); return -1;
}

static int cmd_set_rate(char *r, size_t rs, uint32_t rate)
{
	if (rate != 44100 && rate != 48000 && rate != 88200 && rate != 96000)
		return snprintf(r, rs, "ERR rate: 44100|48000|88200|96000"), -1;
	uint8_t d[4] = { (uint8_t)(rate & 0xff), (uint8_t)((rate >> 8) & 0xff),
		(uint8_t)((rate >> 16) & 0xff), (uint8_t)((rate >> 24) & 0xff) };
	if (usb_write_cur(0x0100, 0x2900, d, 4)) goto e;
	return snprintf(r, rs, "OK %u", rate), 0; e: snprintf(r, rs, "ERR ctl"); return -1;
}

static int cmd_get_meters(char *r, size_t rs)
{
	uint8_t d[36] = {0};
	if (usb_read_mem(0x0000, 0x3c00, d, sizeof(d))) goto e;
	char buf[256]; int pos = 0;
	pos += snprintf(buf + pos, sizeof(buf) - pos, "OK");
	for (int i = 0; i < 18 && pos < (int)sizeof(buf) - 8; i++)
		pos += snprintf(buf + pos, sizeof(buf) - pos, " %d",
			(int)d[i*2] | ((int)d[i*2+1] << 8));
	snprintf(r, rs, "%s", buf);
	return 0; e: snprintf(r, rs, "ERR ctl"); return -1;
}

static int cmd_get_matrix_mux(char *r, size_t rs, int ch)
{
	uint8_t d[2] = {0};
	if (usb_read_cur(0x0600 | ch, 0x3200, d, 2)) goto e;
	snprintf(r, rs, "OK src=%d", (int)d[0]);
	return 0; e: snprintf(r, rs, "ERR ctl"); return -1;
}

static int cmd_get_output_mux(char *r, size_t rs, int bus)
{
	uint8_t d[2] = {0};
	if (usb_read_cur(0x0000 | bus, 0x3300, d, 2)) goto e;
	snprintf(r, rs, "OK src=%d", (int)d[0]);
	return 0; e: snprintf(r, rs, "ERR ctl"); return -1;
}

static int cmd_get_capture_mux(char *r, size_t rs, int ch)
{
	uint8_t d[2] = {0};
	if (usb_read_cur(0x0000 | ch, 0x3400, d, 2)) goto e;
	snprintf(r, rs, "OK src=%d", (int)d[0]);
	return 0; e: snprintf(r, rs, "ERR ctl"); return -1;
}

static int cmd_get_matrix_gain(char *r, size_t rs, int node)
{
	uint8_t d[2] = {0};
	if (usb_read_cur(0x0000 | node, 0x3c00, d, 2)) goto e;
	int dB = (int)d[0] - 128;
	snprintf(r, rs, "OK %d dB", dB);
	return 0; e: snprintf(r, rs, "ERR ctl"); return -1;
}

/* ---- SET commands (whitelist) ---- */

static int cmd_set_impedance(char *r, size_t rs, int ch, const char *val)
{
	uint8_t d[2] = {0};
	if      (!strcmp(val, "line"))  d[0] = 0;
	else if (!strcmp(val, "hi-z")) d[0] = 1;
	else return snprintf(r, rs, "ERR val: %s (line|hi-z)", val), -1;
	if (usb_write_cur(0x0900 | ch, 0x0100, d, 2)) goto e;
	return snprintf(r, rs, "OK %s", val), 0; e: snprintf(r, rs, "ERR ctl"); return -1;
}

static int cmd_set_pad(char *r, size_t rs, int ch, const char *val)
{
	uint8_t d[2] = {0};
	if      (!strcmp(val, "off")) d[0] = 0;
	else if (!strcmp(val, "on"))  d[0] = 1;
	else return snprintf(r, rs, "ERR val: %s (on|off)", val), -1;
	if (usb_write_cur(0x0b00 | ch, 0x0100, d, 2)) goto e;
	return snprintf(r, rs, "OK %s", val), 0; e: snprintf(r, rs, "ERR ctl"); return -1;
}

static int cmd_set_gain(char *r, size_t rs, int ch, const char *val)
{
	uint8_t d[2] = {0};
	if      (!strcmp(val, "lo")) d[0] = 0;
	else if (!strcmp(val, "hi")) d[0] = 1;
	else return snprintf(r, rs, "ERR val: %s (lo|hi)", val), -1;
	if (usb_write_cur(0x0800 | ch, 0x0100, d, 2)) goto e;
	return snprintf(r, rs, "OK %s", val), 0; e: snprintf(r, rs, "ERR ctl"); return -1;
}

static int cmd_set_volume(char *r, size_t rs, int bus, int dB)
{
	if (dB < -128 || dB > 0) return snprintf(r, rs, "ERR dB: -128..0"), -1;
	uint8_t d[2] = {0};
	d[0] = (uint8_t)(dB + 128);
	if (usb_write_cur(0x0200 | bus, 0x0a00, d, 2)) goto e;
	return snprintf(r, rs, "OK %d dB", dB), 0; e: snprintf(r, rs, "ERR ctl"); return -1;
}

static int cmd_set_mute(char *r, size_t rs, int bus, const char *val)
{
	uint8_t d[2] = {0};
	if      (!strcmp(val, "off")) d[0] = 0;
	else if (!strcmp(val, "on"))  d[0] = 1;
	else return snprintf(r, rs, "ERR val: %s (on|off)", val), -1;
	if (usb_write_cur(0x0100 | bus, 0x0a00, d, 2)) goto e;
	return snprintf(r, rs, "OK %s", val), 0; e: snprintf(r, rs, "ERR ctl"); return -1;
}

static int cmd_set_matrix_mux(char *r, size_t rs, int ch, int src)
{
	uint8_t d[2] = {0};
	d[0] = (uint8_t)src;
	if (usb_write_cur(0x0600 | ch, 0x3200, d, 2)) goto e;
	return snprintf(r, rs, "OK src=%d", src), 0; e: snprintf(r, rs, "ERR ctl"); return -1;
}

static int cmd_set_output_mux(char *r, size_t rs, int bus, int src)
{
	uint8_t d[2] = {0};
	d[0] = (uint8_t)src;
	if (usb_write_cur(0x0000 | bus, 0x3300, d, 2)) goto e;
	return snprintf(r, rs, "OK src=%d", src), 0; e: snprintf(r, rs, "ERR ctl"); return -1;
}

static int cmd_set_capture_mux(char *r, size_t rs, int ch, int src)
{
	uint8_t d[2] = {0};
	d[0] = (uint8_t)src;
	if (usb_write_cur(0x0000 | ch, 0x3400, d, 2)) goto e;
	return snprintf(r, rs, "OK src=%d", src), 0; e: snprintf(r, rs, "ERR ctl"); return -1;
}

static int cmd_set_matrix_gain(char *r, size_t rs, int node, int dB)
{
	if (dB < -128 || dB > 0) return snprintf(r, rs, "ERR dB: -128..0"), -1;
	uint8_t d[2] = {0};
	d[0] = (uint8_t)(dB + 128);
	if (usb_write_cur(0x0000 | node, 0x3c00, d, 2)) goto e;
	return snprintf(r, rs, "OK %d dB", dB), 0; e: snprintf(r, rs, "ERR ctl"); return -1;
}

/* ---- command router ---- */

static void scarlett_response(const char *cmd, char *r, size_t rs)
{
	if (!g_dev) { snprintf(r, rs, "ERR no device"); return; }

	if (strncmp(cmd, "GET ", 4) == 0) {
		const char *a = cmd + 4;
		if      (strcmp(a, "clock") == 0)        cmd_get_clock(r, rs);
		else if (strcmp(a, "rate") == 0)         cmd_get_rate(r, rs);
		else if (strcmp(a, "sync") == 0)         cmd_get_sync(r, rs);
		else if (strcmp(a, "meters") == 0)       cmd_get_meters(r, rs);
		else if (strncmp(a, "volume:", 7) == 0)   cmd_get_volume(r, rs, atoi(a+7));
		else if (strncmp(a, "mute:", 5) == 0)     cmd_get_mute(r, rs, atoi(a+5));
		else if (strcmp(a, "volume") == 0)        cmd_get_volume(r, rs, 0);
		else if (strcmp(a, "mute") == 0)          cmd_get_mute(r, rs, 0);
		else if (strncmp(a, "impedance:", 10) == 0) cmd_get_impedance(r, rs, atoi(a+10));
		else if (strncmp(a, "pad:", 4) == 0)       cmd_get_pad(r, rs, atoi(a+4));
		else if (strncmp(a, "gain:", 5) == 0)      cmd_get_gain(r, rs, atoi(a+5));
		else if (strncmp(a, "matrix:", 7) == 0) {
			int mi = atoi(a+7);
			char *dot = strchr(a+7, '.');
			if (dot) cmd_get_matrix_gain(r, rs, mi * 8 | (atoi(dot+1) & 7));
			else     cmd_get_matrix_mux(r, rs, mi);
		}
		else if (strncmp(a, "output:", 7) == 0)    cmd_get_output_mux(r, rs, atoi(a+7));
		else if (strncmp(a, "capture:", 8) == 0)   cmd_get_capture_mux(r, rs, atoi(a+8));
		else snprintf(r, rs, "ERR unknown GET: %s", a);
		return;
	}

	if (strncmp(cmd, "SET ", 4) == 0) {
		const char *a = cmd + 4;
		if (strcmp(a, "save") == 0) { uint8_t v = 0xa5; if (usb_write_mem(0x005a, 0x3c00, &v, 1)) { snprintf(r, rs, "ERR save"); return; } snprintf(r, rs, "OK saved"); return; }
		char key[64] = {0}, val[64] = {0};
		if (sscanf(a, "%63s %63s", key, val) < 2)
			{ snprintf(r, rs, "ERR usage: SET <key> <val>"); return; }

		if      (strncmp(key, "impedance:", 10) == 0) cmd_set_impedance(r, rs, atoi(key+10), val);
		else if (strncmp(key, "pad:", 4) == 0)        cmd_set_pad(r, rs, atoi(key+4), val);
		else if (strncmp(key, "gain:", 5) == 0)       cmd_set_gain(r, rs, atoi(key+5), val);
		else if (strncmp(key, "volume:", 7) == 0)     cmd_set_volume(r, rs, atoi(key+7), atoi(val));
		else if (strcmp(key, "volume") == 0)           cmd_set_volume(r, rs, 0, atoi(val));
		else if (strncmp(key, "mute:", 5) == 0)       cmd_set_mute(r, rs, atoi(key+5), val);
		else if (strcmp(key, "mute") == 0)             cmd_set_mute(r, rs, 0, val);
		else if (strcmp(key, "clock") == 0)            cmd_set_clock(r, rs, val);
		else if (strcmp(key, "rate") == 0)             cmd_set_rate(r, rs, (uint32_t)atoi(val));
		else if (strncmp(key, "matrix:", 7) == 0) {
			int mi = atoi(key+7);
			char *dot = strchr(key+7, '.');
			if (dot) cmd_set_matrix_gain(r, rs, mi * 8 | (atoi(dot+1) & 7), atoi(val));
			else     cmd_set_matrix_mux(r, rs, mi, atoi(val));
		}
		else if (strncmp(key, "output:", 7) == 0)     cmd_set_output_mux(r, rs, atoi(key+7), atoi(val));
		else if (strncmp(key, "capture:", 8) == 0)    cmd_set_capture_mux(r, rs, atoi(key+8), atoi(val));
		else snprintf(r, rs, "ERR unknown SET: %s", key);
		return;
	}

	if (strcmp(cmd, "DUMP") == 0) {
		/* Read all known values — best-effort */
		char buf[1024]; int pos = 0;
		uint8_t d[4];
		pos += snprintf(buf+pos, sizeof(buf)-pos, "OK");
		if (!usb_read_cur(0x0100, 0x2800, d, 1)) {
			const char *s[] = {"Internal", "S/PDIF", "ADAT"};
			pos += snprintf(buf+pos, sizeof(buf)-pos, " clock=%s",
				d[0] < 3 ? s[d[0]] : "?");
		}
		if (!usb_read_cur(0x0100, 0x2900, d, 4))
			pos += snprintf(buf+pos, sizeof(buf)-pos, " rate=%u",
				(uint32_t)d[0]|((uint32_t)d[1]<<8)|((uint32_t)d[2]<<16)|((uint32_t)d[3]<<24));
		if (!usb_read_mem(0x0002, 0x3c00, d, 1))
			pos += snprintf(buf+pos, sizeof(buf)-pos, " sync=%s",
				d[0] ? "Locked" : "Unlocked");
		if (!usb_read_cur(0x0200, 0x0a00, d, 2))
			pos += snprintf(buf+pos, sizeof(buf)-pos, " vol=%ddB", (int)d[0]-128);
		if (!usb_read_cur(0x0100, 0x0a00, d, 2))
			pos += snprintf(buf+pos, sizeof(buf)-pos, " mute=%d", d[0]);
		for (int ch = 1; ch <= 2; ch++) {
			if (!usb_read_cur(0x0900|ch, 0x0100, d, 2))
				pos += snprintf(buf+pos, sizeof(buf)-pos, " imp%d=%s", ch, str_line_hi(d[0]));
			if (!usb_read_cur(0x0b00|ch, 0x0100, d, 2))
				pos += snprintf(buf+pos, sizeof(buf)-pos, " pad%d=%s", ch, str_onoff(d[0]));
		}
		for (int ch = 3; ch <= 4; ch++)
			if (!usb_read_cur(0x0800|ch, 0x0100, d, 2))
				pos += snprintf(buf+pos, sizeof(buf)-pos, " gain%d=%s", ch, str_lo_hi(d[0]));
		snprintf(r, rs, "%s", buf);
		return;
	}

	if (strcmp(cmd, "LIST") == 0) {
		snprintf(r, rs, "OK clock rate sync meters "
			"volume volume:N mute mute:N "
			"impedance:N pad:N gain:N "
			"matrix:N matrix:N.M output:N capture:N "
			"set: clock rate save");
		return;
	}

	snprintf(r, rs, "ERR unknown: %s", cmd);
}

static void cmd_handler(const char *cmd, char *r, size_t rs)
{
	pthread_mutex_lock(&g_dev_lock);
	scarlett_response(cmd, r, rs);
	/* Count USB-level failures to trigger a device reset in the watchdog.
	 * "ERR no device" also counts: it means we have no handle yet. */
	if (!strncmp(r, "ERR ctl", 7) || !strncmp(r, "ERR no device", 13)
		|| !strncmp(r, "ERR save", 8)) {
		if (g_usb_failures < 1000) g_usb_failures++;
	} else {
		g_usb_failures = 0;
	}
	pthread_mutex_unlock(&g_dev_lock);
}

/* ---- main ---- */

int main(void)
{
	struct sigaction sa;
	pthread_t wd;
	printf("scarlett-daemon v0.2.0\n");

	signal(SIGPIPE, SIG_IGN);

	/* Best-effort open; the watchdog keeps retrying / resetting. */
	g_dev = scarlett_usb_open(SCARLETT_VID, SCARLETT_PID);
	if (g_dev) printf("scarlett-daemon: device opened\n");
	else printf("scarlett-daemon: device not found — watchdog will retry\n");

	pthread_create(&wd, NULL, watchdog_main, NULL);

	sa.sa_handler = handle_signal;
	sigemptyset(&sa.sa_mask);
	sa.sa_flags = 0;
	sigaction(SIGINT, &sa, NULL);
	sigaction(SIGTERM, &sa, NULL);

	socket_server_start("/tmp/scarlett-6i6.sock", cmd_handler);

	keep_running = 0;
	pthread_join(wd, NULL);
	if (g_dev) {
		scarlett_usb_stop_interrupt();
		scarlett_usb_close(g_dev);
		g_dev = NULL;
	}
	printf("scarlett-daemon: shutdown complete\n");
	return 0;
}
