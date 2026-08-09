// SPDX-License-Identifier: GPL-2.0
/**
 * socket-server.h — Unix-domain socket server for Scarlett daemon
 *
 * Listens on a local AF_UNIX socket, accepts text commands from
 * clients (e.g. "GET impedance:1", "SET impedance:1 hi-z"),
 * dispatches them through the registered handler, and sends the
 * text response back.
 */
#pragma once

#include <stddef.h>

/**
 * scarlett_command_handler_t — Callback invoked for each client command.
 *
 * @cmd:       null-terminated command string received from the client
 * @response:  buffer to write the response text into
 * @resp_size: size of the response buffer
 */
typedef void (*scarlett_command_handler_t)(
	const char *cmd,
	char       *response,
	size_t      resp_size);

/**
 * socket_server_start — Start the Unix-domain socket server.
 *
 * Creates and binds a stream socket at @path (mode 0666) and begins
 * accepting connections in a background dispatch source or thread.
 *
 * The default socket path is "/tmp/scarlett-6i6.sock".
 *
 * @handler: callback for processing client commands
 *
 * Return: 0 on success, -1 on error.
 */
int socket_server_start(
	const char                *path,
	scarlett_command_handler_t handler);

/**
 * socket_server_stop — Stop the server and close the listen socket.
 */
void socket_server_stop(void);
