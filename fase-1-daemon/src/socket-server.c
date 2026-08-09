// SPDX-License-Identifier: GPL-2.0
#include "socket-server.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>

#define BACKLOG 8
#define BUF_SZ  4096

static int                      listen_fd = -1;
static scarlett_command_handler_t cmd_handler;

static void
handle_client(int client_fd)
{
	char buf[BUF_SZ];
	char resp[BUF_SZ];
	ssize_t n;
	size_t rlen;

	n = read(client_fd, buf, sizeof(buf) - 1);
	if (n <= 0)
		goto out;
	buf[n] = '\0';

	/* Strip trailing newline / CR */
	while (n > 0 && (buf[n - 1] == '\n' || buf[n - 1] == '\r'))
		buf[--n] = '\0';

	resp[0] = '\0';
	if (cmd_handler)
		cmd_handler(buf, resp, sizeof(resp));

	/* Ensure response is newline-terminated */
	rlen = strlen(resp);
	if (rlen + 2 <= sizeof(resp)) {
		resp[rlen] = '\n';
		resp[rlen + 1] = '\0';
	}

	write(client_fd, resp, strlen(resp));

out:
	close(client_fd);
}

int
socket_server_start(
	const char                *path,
	scarlett_command_handler_t handler)
{
	struct sockaddr_un addr;
	int fd, rc;

	if (!path)
		path = "/tmp/scarlett-6i6.sock";

	cmd_handler = handler;

	fd = socket(AF_UNIX, SOCK_STREAM, 0);
	if (fd < 0) {
		perror("socket");
		return -1;
	}

	unlink(path);

	memset(&addr, 0, sizeof(addr));
	addr.sun_family = AF_UNIX;
	strncpy(addr.sun_path, path, sizeof(addr.sun_path) - 1);

	rc = bind(fd, (struct sockaddr *)&addr, sizeof(addr));
	if (rc < 0) {
		perror("bind");
		close(fd);
		return -1;
	}

	chmod(path, 0666);

	rc = listen(fd, BACKLOG);
	if (rc < 0) {
		perror("listen");
		close(fd);
		return -1;
	}

	listen_fd = fd;
	fprintf(stderr, "socket server listening on %s\n", path);

	/* Accept loop — non-blocking so server_stop() can signal us. */
	for (;;) {
		int client;

		client = accept(fd, NULL, NULL);
		if (client < 0) {
			if (errno == EINTR)
				break;
			if (errno == EAGAIN || errno == EWOULDBLOCK)
				continue;
			perror("accept");
			break;
		}
		handle_client(client);
	}

	socket_server_stop();
	return 0;
}

void
socket_server_stop(void)
{
	if (listen_fd >= 0) {
		close(listen_fd);
		listen_fd = -1;
	}
}
