#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>

int main(void) {
    signal(SIGPIPE, SIG_IGN);

    int listen_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (listen_fd < 0) {
        perror("socket");
        return 1;
    }

    int opt = 1;
    if (setsockopt(listen_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt)) < 0) {
        perror("setsockopt");
        return 1;
    }

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(8123);
    addr.sin_addr.s_addr = inet_addr("127.0.0.1");

    if (bind(listen_fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        perror("bind");
        return 1;
    }

    if (listen(listen_fd, 16) < 0) {
        perror("listen");
        return 1;
    }

    printf("Listening on port 8123\n");
    fflush(stdout);

    /* Content-Length must match the actual body size: the declared length is
       15, so the body is "Hello from NLC\n" (15 bytes). The previous version
       sent only 14 body bytes, so curl aborted with rc=18 (partial file). */
    const char response[] =
        "HTTP/1.1 200 OK\r\n"
        "Content-Type: text/plain\r\n"
        "Content-Length: 15\r\n"
        "\r\n"
        "Hello from NLC\n";

    for (;;) {
        int conn_fd = accept(listen_fd, NULL, NULL);
        if (conn_fd < 0) {
            continue;
        }

        char buf[4096];
        ssize_t n = recv(conn_fd, buf, sizeof(buf) - 1, 0);
        if (n > 0) {
            buf[n] = '\0';
            if (strncmp(buf, "GET ", 4) == 0) {
                size_t total = 0;
                size_t len = sizeof(response) - 1;
                while (total < len) {
                    ssize_t sent = send(conn_fd, response + total, len - total, 0);
                    if (sent <= 0) {
                        break;
                    }
                    total += (size_t)sent;
                }
            }
        }

        close(conn_fd);
    }

    return 0;
}
