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

static int g_output_mux_cache[6] = { 18, 19, 18, 19, 16, 17 };
static int g_capture_mux_cache[6] = { 12, 13, 14, 15, 16, 17 };
static int g_matrix_gain_cache[144];

static void handle_signal(int sig) { (void)sig; keep_running = 0; socket_server_stop(); }
static int usb_write_cur(uint16_t wVal, uint16_t wIdx, void *data, uint16_t len);

static void encode_scarlett_db(int dB, uint8_t d[2]);

/* ---- Device lifecycle (watchdog-managed) ---- */

static void enforce_safe_hardware_routing(void)
{
	/* 1. Feedback Protection: Lock capture mux strictly to physical hardware inputs (12..17) */
	for (int i = 0; i < 6; i++) {
		g_capture_mux_cache[i] = 12 + i;
		uint8_t d[2] = { (uint8_t)(12 + i), 0 };
		usb_write_cur(0x0000 | i, 0x3400, d, 2);
	}

	/* 2. Output routing: Mon L/R and HP 1/2 listen to Mix 1 (18, 19); SPDIF to SPDIF (16, 17) */
	int out_mux[6] = { 18, 19, 18, 19, 16, 17 };
	for (int i = 0; i < 6; i++) {
		g_output_mux_cache[i] = out_mux[i];
		uint8_t d[2] = { (uint8_t)out_mux[i], 0 };
		usb_write_cur(0x0000 | i, 0x3300, d, 2);
	}

	/* 3. Matrix input mux: 0..3=Analog 1..4 (12..15), 4..5=SPDIF (16..17), 6..7=DAW 1..2 (0..1) */
	int mat_mux[8] = { 12, 13, 14, 15, 16, 17, 0, 1 };
	for (int i = 0; i < 8; i++) {
		uint8_t d[2] = { (uint8_t)mat_mux[i], 0 };
		usb_write_cur(0x0600 | i, 0x3200, d, 2);
	}

	/* 4. Matrix gains: mute all by default (-128 dB) except Guitar (In 0) & DAW (In 6, 7) at -12 dB */
	for (int i = 0; i < 144; i++) {
		g_matrix_gain_cache[i] = -128;
	}
	// Node 0: Guitar (In 0) -> Mix 1 L (Mix 0)
	g_matrix_gain_cache[0] = -12;
	// Node 1: Guitar (In 0) -> Mix 1 R (Mix 1)
	g_matrix_gain_cache[1] = -12;
	// Node 48: DAW 1 (In 6) -> Mix 1 L (Mix 0)
	g_matrix_gain_cache[48] = -12;
	// Node 57: DAW 2 (In 7) -> Mix 1 R (Mix 1)
	g_matrix_gain_cache[57] = -12;

	for (int i = 0; i < 144; i++) {
		uint8_t d[2];
		encode_scarlett_db(g_matrix_gain_cache[i], d);
		usb_write_cur(0x0000 | i, 0x3c00, d, 2);
	}
}

static void device_try_open(void)
{
	if (g_dev) return;
	g_dev = scarlett_usb_open(SCARLETT_VID, SCARLETT_PID);
	if (g_dev) {
		printf("scarlett-daemon: device opened (watchdog)\n");
		enforce_safe_hardware_routing();
		if (scarlett_usb_start_interrupt(g_dev, NULL) != 0)
			printf("scarlett-daemon: interrupt monitoring unavailable\n");
		g_usb_failures = 0;
	}
}

static void device_reset(void)
{
	if (!g_dev) return;
	scarlett_usb_stop_interrupt();
	scarlett_usb_reset(g_dev);
	scarlett_usb_close(g_dev);
	g_dev = NULL;
	g_usb_failures = 0;
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

/* Scarlett Gen 1 volume/gain registers encode dB as signed 16-bit Q8.8 LE. */
static int decode_scarlett_db(const uint8_t d[2])
{
	int16_t raw = (int16_t)((uint16_t)d[0] | ((uint16_t)d[1] << 8));
	int dB = raw / 256;
	if (dB < -128) dB = -128;
	if (dB > 6) dB = 6;
	return dB;
}

static void encode_scarlett_db(int dB, uint8_t d[2])
{
	int16_t v = (int16_t)(dB * 256);
	d[0] = (uint8_t)(v & 0xff);
	d[1] = (uint8_t)((v >> 8) & 0xff);
}

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
	if (bus < 0 || bus > 6) return snprintf(r, rs, "ERR bus: 0..6"), -1;
	uint8_t d[2] = {0};
	if (usb_read_cur(0x0200 | bus, 0x0a00, d, 2)) goto e;
	int dB = decode_scarlett_db(d);
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
	uint8_t d_in[12] = {0};
	uint8_t d_daw[12] = {0};
	uint8_t d_mix[12] = {0};

	/* Read physical inputs (0x0000), DAW playback (0x0003), and Mix outputs (0x0001) */
	if (usb_read_mem(0x0000, 0x3c00, d_in, sizeof(d_in))) goto e;
	usb_read_mem(0x0003, 0x3c00, d_daw, sizeof(d_daw));
	usb_read_mem(0x0001, 0x3c00, d_mix, sizeof(d_mix));

	char buf[256]; int pos = 0;
	pos += snprintf(buf + pos, sizeof(buf) - pos, "OK");

	/* 0..5: Physical inputs (4 Analog + 2 S/PDIF) */
	for (int i = 0; i < 6; i++) {
		pos += snprintf(buf + pos, sizeof(buf) - pos, " %d",
			(int)d_in[i*2] | ((int)d_in[i*2+1] << 8));
	}
	/* 6..7: DAW 1 & 2 playback (Spotify / Mac Audio) */
	for (int i = 0; i < 2; i++) {
		pos += snprintf(buf + pos, sizeof(buf) - pos, " %d",
			(int)d_daw[i*2] | ((int)d_daw[i*2+1] << 8));
	}
	/* 8..9: Master Mix 1 L & R */
	for (int i = 0; i < 2; i++) {
		pos += snprintf(buf + pos, sizeof(buf) - pos, " %d",
			(int)d_mix[i*2] | ((int)d_mix[i*2+1] << 8));
	}

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
	if (bus >= 0 && bus < 6) {
		return snprintf(r, rs, "OK src=%d", g_output_mux_cache[bus]), 0;
	}
	snprintf(r, rs, "ERR bus: 0..5"); return -1;
}

static int cmd_get_capture_mux(char *r, size_t rs, int ch)
{
	if (ch >= 0 && ch < 6) {
		return snprintf(r, rs, "OK src=%d", g_capture_mux_cache[ch]), 0;
	}
	snprintf(r, rs, "ERR ch: 0..5"); return -1;
}

static int cmd_get_matrix_gain(char *r, size_t rs, int node)
{
	if (node >= 0 && node < 144) {
		return snprintf(r, rs, "OK %d dB", g_matrix_gain_cache[node]), 0;
	}
	snprintf(r, rs, "ERR node: 0..143"); return -1;
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
	if (bus < 0 || bus > 6) return snprintf(r, rs, "ERR bus: 0..6"), -1;
	if (dB < -128 || dB > 0) return snprintf(r, rs, "ERR dB: -128..0"), -1;
	uint8_t d[2];
	encode_scarlett_db(dB, d);
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
	/* Feedback Protection: Never allow matrix mux to route a mix output back into matrix inputs. */
	if (src >= 18 && src <= 23) {
		return snprintf(r, rs, "ERR feedback-protection: matrix loopback blocked for src=%d", src), -1;
	}
	uint8_t d[2] = {0};
	d[0] = (uint8_t)src;
	if (usb_write_cur(0x0600 | ch, 0x3200, d, 2)) goto e;
	return snprintf(r, rs, "OK src=%d", src), 0; e: snprintf(r, rs, "ERR ctl"); return -1;
}

static int cmd_set_output_mux(char *r, size_t rs, int bus, int src)
{
	if (bus < 0 || bus >= 6) return snprintf(r, rs, "ERR bus: 0..5"), -1;
	uint8_t d[2] = { (uint8_t)src, 0 };
	if (usb_write_cur(0x0000 | bus, 0x3300, d, 2)) goto e;
	g_output_mux_cache[bus] = src;
	return snprintf(r, rs, "OK src=%d", src), 0; e: snprintf(r, rs, "ERR ctl"); return -1;
}

static int cmd_set_capture_mux(char *r, size_t rs, int ch, int src)
{
	/* Feedback Protection: Never allow capture to route DAW/PCM or Mix outputs back into Mac inputs.
	 * This prevents infinite digital feedback loops with DAWs like GarageBand. */
	if (src < 12 || src > 17) {
		return snprintf(r, rs, "ERR feedback-protection: capture must be hardware input (12-17), blocked src=%d", src), -1;
	}
	if (ch < 0 || ch >= 6) return snprintf(r, rs, "ERR ch: 0..5"), -1;
	uint8_t d[2] = { (uint8_t)src, 0 };
	if (usb_write_cur(0x0000 | ch, 0x3400, d, 2)) goto e;
	g_capture_mux_cache[ch] = src;
	return snprintf(r, rs, "OK src=%d", src), 0; e: snprintf(r, rs, "ERR ctl"); return -1;
}

static int cmd_set_matrix_gain(char *r, size_t rs, int node, int dB)
{
	if (node < 0 || node >= 144) return snprintf(r, rs, "ERR node: 0..143"), -1;
	if (dB < -128 || dB > 6) return snprintf(r, rs, "ERR dB: -128..6"), -1;
	uint8_t d[2];
	encode_scarlett_db(dB, d);
	if (usb_write_cur(0x0000 | node, 0x3c00, d, 2)) goto e;
	g_matrix_gain_cache[node] = dB;
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
			if (dot) cmd_get_matrix_gain(r, rs, (atoi(dot+1) << 3) | (mi & 7));
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
			if (dot) cmd_set_matrix_gain(r, rs, (atoi(dot+1) << 3) | (mi & 7), atoi(val));
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
			pos += snprintf(buf+pos, sizeof(buf)-pos, " vol=%ddB", decode_scarlett_db(d));
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

	if (strncmp(cmd, "RAW_REQ ", 8) == 0) {
		unsigned int bmReq = 0, bReq = 0, wVal = 0, wIdx = 0, len = 0;
		char hexdata[128] = {0};
		int n = sscanf(cmd + 8, "%x %x %x %x %u %127s", &bmReq, &bReq, &wVal, &wIdx, &len, hexdata);
		if (n < 5) { snprintf(r, rs, "ERR usage: RAW_REQ bmReq bReq wVal wIdx len [hexdata]"); return; }
		uint8_t d[64] = {0};
		if (!(bmReq & 0x80) && hexdata[0]) {
			for (unsigned int i = 0; i < len && i < 32; i++) {
				unsigned int byte = 0;
				if (sscanf(hexdata + i*2, "%02x", &byte) == 1) d[i] = (uint8_t)byte;
			}
		}
		scarlett_usb_control_request_t req = {
			.bmRequestType = (uint8_t)bmReq,
			.bRequest      = (uint8_t)bReq,
			.wValue        = (uint16_t)wVal,
			.wIndex        = (uint16_t)wIdx,
			.wLength       = (uint16_t)len,
			.data          = d,
		};
		int ret = scarlett_usb_control_transfer(g_dev, &req);
		if (ret) { snprintf(r, rs, "ERR ret=%d", ret); return; }
		char buf[128] = {0}; int pos = 0;
		for (unsigned int i = 0; i < len; i++) pos += snprintf(buf+pos, sizeof(buf)-pos, "%02x ", d[i]);
		snprintf(r, rs, "OK %s", buf);
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
	if (g_dev) {
		printf("scarlett-daemon: device opened\n");
		enforce_safe_hardware_routing();
	} else {
		printf("scarlett-daemon: device not found — watchdog will retry\n");
	}

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
