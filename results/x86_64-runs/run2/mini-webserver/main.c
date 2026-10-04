#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>

int main(void)
{
    int srv, opt = 1;
    struct sockaddr_in addr;
    static const char resp[] =
        "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 15\r\n\r\nHello from NLC\n";

    signal(SIGPIPE, SIG_IGN);

    srv = socket(AF_INET, SOCK_STREAM, 0);
    if (srv < 0) {
        perror("socket");
        return 1;
    }
    setsockopt(srv, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof opt);

    memset(&addr, 0, sizeof addr);
    addr.sin_family = AF_INET;
    addr.sin_port = htons(8123);
    addr.sin_addr.s_addr = inet_addr("127.0.0.1");

    if (bind(srv, (struct sockaddr *)&addr, sizeof addr) < 0) {
        perror("bind");
        return 1;
    }
    if (listen(srv, 16) < 0) {
        perror("listen");
        return 1;
    }

    printf("Listening on port 8123\n");
    fflush(stdout);

    for (;;) {
        char buf[4096];
        size_t total = 0;
        int c = accept(srv, NULL, NULL);
        if (c < 0) {
            continue;
        }
        while (total < sizeof buf - 1) {
            ssize_t n = recv(c, buf + total, sizeof buf - 1 - total, 0);
            if (n <= 0)
                break;
            total += (size_t)n;
            buf[total] = '\0';
            if (strstr(buf, "\r\n\r\n") || strstr(buf, "\n\n"))
                break;
        }
        {
            const char *p = resp;
            size_t left = sizeof resp - 1;
            while (left > 0) {
                ssize_t w = send(c, p, left, 0);
                if (w <= 0)
                    break;
                p += w;
                left -= (size_t)w;
            }
        }
        close(c);
    }
    return 0;
}
