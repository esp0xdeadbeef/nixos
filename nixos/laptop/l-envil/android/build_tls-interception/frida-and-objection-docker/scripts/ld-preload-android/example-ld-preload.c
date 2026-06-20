#define _GNU_SOURCE
#include <unistd.h>
#include <fcntl.h>
#include <time.h>
#include <sys/types.h>
#include <sys/stat.h>

__attribute__((constructor))
void init(void) {
    int fd = open("/data/local/tmp/ld-prehook.txt",
                  O_WRONLY | O_CREAT | O_APPEND, 0644);

    if (fd >= 0) {
        time_t t = time(NULL);
        struct tm tm;
        localtime_r(&t, &tm);

        char buf[128];
        int len = strftime(buf, sizeof(buf),
                           "[%Y-%m-%d %H:%M:%S] preload hit\n",
                           &tm);

        if (len > 0) {
            write(fd, buf, len);
        }

        close(fd);
    }
}

