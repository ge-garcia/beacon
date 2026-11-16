/* POSIX serial operations use the platform's native termios layout. */
#include <errno.h>
#include <fcntl.h>
#include <stddef.h>
#include <termios.h>
#include <unistd.h>

int beacon_serial_open(const char *path)
{
    int fd = open(path, O_RDWR | O_NOCTTY | O_NONBLOCK);
    struct termios settings;
    if (fd < 0) return -1;
    if (tcgetattr(fd, &settings) < 0) goto fail;
    cfmakeraw(&settings);
    settings.c_cflag &= ~(CSIZE | PARENB | CSTOPB | CRTSCTS);
    settings.c_cflag |= CS8 | CLOCAL | CREAD;
    settings.c_cc[VMIN] = 0;
    settings.c_cc[VTIME] = 0;
    if (cfsetispeed(&settings, B115200) < 0 ||
        cfsetospeed(&settings, B115200) < 0 ||
        tcsetattr(fd, TCSANOW, &settings) < 0) goto fail;
    return fd;
fail:
    close(fd);
    return -1;
}

/* Return one byte, -2 when no byte is ready, or -1 on a device error. */
int beacon_serial_read(int fd)
{
    unsigned char byte;
    ssize_t n = read(fd, &byte, 1);
    if (n == 1) return byte;
    if (n == 0 || (n < 0 && (errno == EAGAIN || errno == EINTR))) return -2;
    return -1;
}

/* Each write makes progress or returns. Ada owns the overall deadline. */
int beacon_serial_write(int fd, const unsigned char *data, int count)
{
    ssize_t n = write(fd, data, (size_t)count);
    if (n >= 0) return (int)n;
    if (errno == EAGAIN || errno == EINTR) return 0;
    return -1;
}

void beacon_serial_close(int fd)
{
    close(fd);
}
