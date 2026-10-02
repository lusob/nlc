#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <errno.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>

int main(void) {
    signal(SIGPIPE, SIG_IGN);

    int srv = socket(AF_INET, SOCK_STREAM, 0);
    if (srv < 0) {
        perror("socket");
        return 1;
    }

    int opt = 1;
    if (setsockopt(srv, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt)) < 0) {
        perror("setsockopt");
        return 1;
    }

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(8123);
    addr.sin_addr.s_addr = inet_addr("127.0.0.1");

    if (bind(srv, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        perror("bind");
        return 1;
    }
    if (listen(srv, 16) < 0) {
        perror("listen");
        return 1;
    }

    printf("Listening on port 8123\n");
    fflush(stdout);

    static const char resp[] =
        "HTTP/1.1 200 OK\r\n"
        "Content-Type: text/plain\r\n"
        "Content-Length: 15\r\n"
        "\r\n"
        "Hello from NLC\n";

    for (;;) {
        int c = accept(srv, NULL, NULL);
        if (c < 0) {
            continue;
        }

        char buf[4096];
        size_t total = 0;
        while (total < sizeof(buf) - 1) {
            ssize_t n = read(c, buf + total, sizeof(buf) - 1 - total);
            if (n <= 0) break;
            total += (size_t)n;
            buf[total] = '\0';
            if (strstr(buf, "\r\n\r\n") || strstr(buf, "\n\n")) break;
        }

        size_t len = sizeof(resp) - 1;
        size_t sent = 0;
        while (sent < len) {
            ssize_t n = write(c, resp + sent, len - sent);
            if (n <= 0) break;
            sent += (size_t)n;
        }
        close(c);
    }

    return 0;
}
