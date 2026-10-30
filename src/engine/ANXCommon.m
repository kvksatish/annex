#import "ANXCommon.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <arpa/inet.h>
#include <ifaddrs.h>
#include <fcntl.h>
#include <poll.h>
#include <unistd.h>
#include <time.h>
#import <IOKit/ps/IOPowerSources.h>
#import <IOKit/ps/IOPSKeys.h>

static ANXLogSink gSink;

void ANXSetLogSink(ANXLogSink sink) { gSink = [sink copy]; }

void ANXLog(NSString *format, ...) {
    va_list ap; va_start(ap, format);
    NSString *line = [[NSString alloc] initWithFormat:format arguments:ap];
    va_end(ap);
    NSLog(@"%@", line);
    ANXLogSink sink = gSink;
    if (sink) dispatch_async(dispatch_get_main_queue(), ^{ sink(line); });
}

uint64_t ANXNowNanos(void) { return clock_gettime_nsec_np(CLOCK_UPTIME_RAW); }

BOOL ANXWriteAll(int fd, const void *buf, size_t n) {
    const uint8_t *p = buf;
    while (n) { ssize_t w = write(fd, p, n); if (w <= 0) return NO; p += w; n -= (size_t)w; }
    return YES;
}

BOOL ANXReadAll(int fd, void *buf, size_t n) {
    uint8_t *p = buf;
    while (n) { ssize_t r = read(fd, p, n); if (r <= 0) return NO; p += r; n -= (size_t)r; }
    return YES;
}

BOOL ANXSendMessage(int fd, ANXMessage type, const void *payload, uint32_t len) {
    uint8_t hdr[5]; uint32_t be = htonl(len + 1);
    memcpy(hdr, &be, 4); hdr[4] = type;
    return ANXWriteAll(fd, hdr, 5) && (len == 0 || ANXWriteAll(fd, payload, len));
}

int ANXConnect(NSString *ipv4, uint16_t port, int timeoutMs) {
    struct sockaddr_in a = { .sin_family = AF_INET, .sin_port = htons(port) };
    if (inet_pton(AF_INET, ipv4.UTF8String, &a.sin_addr) != 1) return -1;
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return -1;
    int flags = fcntl(fd, F_GETFL);
    fcntl(fd, F_SETFL, flags | O_NONBLOCK);
    if (connect(fd, (struct sockaddr *)&a, sizeof a) != 0) {
        struct pollfd p = { .fd = fd, .events = POLLOUT };
        int err = 0; socklen_t el = sizeof err;
        if (errno != EINPROGRESS || poll(&p, 1, timeoutMs) != 1 ||
            getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &el) || err) { close(fd); return -1; }
    }
    fcntl(fd, F_SETFL, flags);
    int one = 1;
    setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one);
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof one);
    return fd;
}

// Thunderbolt/USB-C "IP over cable" links show up as bridge interfaces.
static BOOL onBridge(struct in_addr addr, BOOL sameSubnet) {
    struct ifaddrs *ifs = NULL;
    if (getifaddrs(&ifs) != 0) return NO;
    BOOL hit = NO;
    for (struct ifaddrs *i = ifs; i && !hit; i = i->ifa_next) {
        if (!i->ifa_addr || i->ifa_addr->sa_family != AF_INET || strncmp(i->ifa_name, "bridge", 6) != 0) continue;
        in_addr_t mine = ((struct sockaddr_in *)i->ifa_addr)->sin_addr.s_addr;
        in_addr_t mask = i->ifa_netmask ? ((struct sockaddr_in *)i->ifa_netmask)->sin_addr.s_addr : 0xFFFFFFFF;
        hit = sameSubnet ? (mine & mask) == (addr.s_addr & mask) : mine == addr.s_addr;
    }
    freeifaddrs(ifs);
    return hit;
}

BOOL ANXSocketIsCable(int fd) {
    struct sockaddr_in local; socklen_t len = sizeof local;
    if (getsockname(fd, (struct sockaddr *)&local, &len) != 0) return NO;
    return onBridge(local.sin_addr, NO);
}

BOOL ANXAddressIsCable(NSString *ipv4) {
    struct in_addr a;
    if (inet_pton(AF_INET, ipv4.UTF8String, &a) != 1) return NO;
    return onBridge(a, YES);
}

NSArray<NSString *> *ANXCableAddresses(void) {
    NSMutableArray *out = [NSMutableArray array];
    struct ifaddrs *ifs = NULL;
    if (getifaddrs(&ifs) != 0) return out;
    for (struct ifaddrs *i = ifs; i; i = i->ifa_next) {
        if (!i->ifa_addr || i->ifa_addr->sa_family != AF_INET || strncmp(i->ifa_name, "bridge", 6) != 0) continue;
        char buf[INET_ADDRSTRLEN];
        inet_ntop(AF_INET, &((struct sockaddr_in *)i->ifa_addr)->sin_addr, buf, sizeof buf);
        [out addObject:@(buf)];
    }
    freeifaddrs(ifs);
    return out;
}

BOOL ANXIsLaptop(void) {
    CFTypeRef info = IOPSCopyPowerSourcesInfo();
    if (!info) return NO;
    CFArrayRef list = IOPSCopyPowerSourcesList(info);
    BOOL battery = NO;
    for (CFIndex i = 0; list && i < CFArrayGetCount(list) && !battery; i++) {
        NSDictionary *d = (__bridge NSDictionary *)IOPSGetPowerSourceDescription(info, CFArrayGetValueAtIndex(list, i));
        battery = [d[@kIOPSTypeKey] isEqual:@kIOPSInternalBatteryType];
    }
    if (list) CFRelease(list);
    CFRelease(info);
    return battery;
}

int ANXExternalPowerWatts(void) {
    CFDictionaryRef d = IOPSCopyExternalPowerAdapterDetails();
    if (!d) return 0;
    NSNumber *w = ((__bridge NSDictionary *)d)[@kIOPSPowerAdapterWattsKey];
    CFRelease(d);
    return w.intValue;
}
