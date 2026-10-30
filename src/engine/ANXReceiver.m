#import "ANXReceiver.h"
#import "ANXCommon.h"
#import <Cocoa/Cocoa.h>
#import <AVFoundation/AVFoundation.h>
#import <IOKit/pwr_mgt/IOPMLib.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <arpa/inet.h>

@interface ANXKeyWindow : NSWindow @end
@implementation ANXKeyWindow
- (BOOL)canBecomeKeyWindow { return YES; }
@end

@implementation ANXReceiver {
    NSWindow *_window;
    AVSampleBufferDisplayLayer *_layer;
    CMVideoFormatDescriptionRef _format;   // network thread only
    IOPMAssertionID _noSleep;
    BOOL _showing;
    volatile int _fd;
    volatile uint32_t _wPt, _hPt, _scale;
    NSDate *_pausedUntil;                  // main only
    uint64_t _frames, _bytes;              // main only
    NSTimer *_statsTimer;
}

- (instancetype)init {
    if ((self = [super init])) { _fd = -1; _enabled = YES; }
    return self;
}

- (BOOL)startListening {
    int ls = socket(AF_INET, SOCK_STREAM, 0);
    int one = 1; setsockopt(ls, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
    struct sockaddr_in a = { .sin_family = AF_INET, .sin_port = htons(ANXPort), .sin_addr.s_addr = INADDR_ANY };
    if (bind(ls, (struct sockaddr *)&a, sizeof a) || listen(ls, 2)) {
        ANXLog(@"Error: port %d is in use — is another copy of Annex running?", ANXPort);
        close(ls);
        return NO;
    }
    [self buildWindow];
    [self screenChanged];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(screenChanged)
                                               name:NSApplicationDidChangeScreenParametersNotification object:nil];
    [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *e) {
        if (e.keyCode == 53 && self->_showing) { [self pauseFor:30]; return nil; }   // Esc
        return e;
    }];
    __weak ANXReceiver *ws = self;
    _statsTimer = [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *t) { [ws sampleStats]; }];
    [NSThread detachNewThreadWithBlock:^{ [ws acceptLoop:ls]; }];
    ANXLog(@"Ready to be used as a display (port %d)", ANXPort);
    return YES;
}

- (void)pauseFor:(NSTimeInterval)seconds {
    _pausedUntil = [NSDate dateWithTimeIntervalSinceNow:seconds];
    int fd = _fd;
    if (fd >= 0) shutdown(fd, SHUT_RDWR);
    ANXLog(@"Screen handed back for %.0f s", seconds);
}

- (void)buildWindow {
    _window = [[ANXKeyWindow alloc] initWithContentRect:NSScreen.mainScreen.frame styleMask:NSWindowStyleMaskBorderless
                                                backing:NSBackingStoreBuffered defer:NO];
    _window.backgroundColor = NSColor.blackColor;
    _window.level = NSStatusWindowLevel + 1;   // above the menu bar, so the notch strip is used too
    _window.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorStationary;
    _window.releasedWhenClosed = NO;
    _layer = [AVSampleBufferDisplayLayer layer];
    _layer.videoGravity = AVLayerVideoGravityResize;
    _window.contentView.wantsLayer = YES;
    _layer.frame = _window.contentView.bounds;
    _layer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
    [_window.contentView.layer addSublayer:_layer];
}

- (void)screenChanged {
    NSScreen *s = NSScreen.mainScreen;
    _wPt = (uint32_t)s.frame.size.width; _hPt = (uint32_t)s.frame.size.height; _scale = (uint32_t)s.backingScaleFactor;
    [_window setFrame:s.frame display:NO];
}

#pragma mark - Network thread

- (void)acceptLoop:(int)ls {
    int one = 1;
    for (;;) {
        int fd = accept(ls, NULL, NULL);
        if (fd < 0) continue;
        setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one);
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof one);
        struct timeval tv = { .tv_sec = 5 };   // the sender pings every second; silence means it's gone
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof tv);
        [self serve:fd];
        close(fd);
    }
}

- (void)serve:(int)fd {
    uint32_t magic; uint8_t uuid[16]; uint16_t nl; char name[256] = {0};
    if (!ANXReadAll(fd, &magic, 4) || ntohl(magic) != ANXMagic || !ANXReadAll(fd, uuid, 16) ||
        !ANXReadAll(fd, &nl, 2) || (nl = ntohs(nl)) > 255 || !ANXReadAll(fd, name, nl)) return;
    NSString *senderID = [[NSUUID alloc] initWithUUIDBytes:uuid].UUIDString;
    NSString *senderName = [[NSString alloc] initWithBytes:name length:nl encoding:NSUTF8StringEncoding] ?: @"A Mac";

    __block ANXReply answer;
    dispatch_sync(dispatch_get_main_queue(), ^{
        BOOL paused = self->_pausedUntil && self->_pausedUntil.timeIntervalSinceNow > 0;
        if (!self.enabled || paused) answer = ANXReplyNotAccepting;
        else answer = (!self.shouldAccept || self.shouldAccept(senderID, senderName)) ? ANXReplyAccepted : ANXReplyDeclined;
    });
    uint32_t reply[5] = { htonl(ANXMagic), htonl(answer), htonl(_wPt), htonl(_hPt), htonl(_scale) };
    if (!ANXWriteAll(fd, reply, sizeof reply) || answer != ANXReplyAccepted) return;

    BOOL cable = ANXSocketIsCable(fd);
    ANXLog(@"%@ is using this screen (%@)", senderName, cable ? @"cable" : @"Wi-Fi");
    _fd = fd;
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_active = YES;
        if (self.onActiveChange) self.onActiveChange(YES, senderName, cable);
    });
    [self readFrom:fd];
    _fd = -1;
    if (_format) { CFRelease(_format); _format = NULL; }
    ANXLog(@"%@ stopped using this screen", senderName);
    dispatch_async(dispatch_get_main_queue(), ^{
        [self hide];
        self->_active = NO;
        if (self.onActiveChange) self.onActiveChange(NO, senderName, cable);
    });
}

- (void)readFrom:(int)fd {
    for (;;) {
        uint8_t hdr[5];
        if (!ANXReadAll(fd, hdr, 5)) return;
        uint32_t len; memcpy(&len, hdr, 4); len = ntohl(len) - 1;
        if (len > (64u << 20)) return;
        uint8_t *buf = len ? malloc(len) : NULL;
        if (len && !ANXReadAll(fd, buf, len)) { free(buf); return; }
        switch (hdr[4]) {
            case ANXMessageParams: [self setParams:buf length:len]; free(buf); break;
            case ANXMessageFrame: [self showFrame:buf length:len]; break;   // takes ownership of buf
            case ANXMessagePing:
                if (!ANXSendMessage(fd, ANXMessagePong, buf, len)) { free(buf); return; }
                free(buf); break;
            default: free(buf);
        }
    }
}

- (void)setParams:(uint8_t *)p length:(size_t)n {
    const uint8_t *sets[2]; size_t sizes[2]; size_t off = 0;
    for (int i = 0; i < 2; i++) {
        if (off + 2 > n) return;
        uint16_t l; memcpy(&l, p + off, 2); l = ntohs(l); off += 2;
        if (off + l > n) return;
        sets[i] = p + off; sizes[i] = l; off += l;
    }
    CMVideoFormatDescriptionRef fmt = NULL;
    if (CMVideoFormatDescriptionCreateFromH264ParameterSets(NULL, 2, sets, sizes, 4, &fmt) == noErr) {
        if (_format) CFRelease(_format);
        _format = fmt;
    }
}

- (void)showFrame:(uint8_t *)buf length:(size_t)len {
    if (!_format) { free(buf); return; }
    CMBlockBufferRef bb = NULL;
    CMBlockBufferCreateWithMemoryBlock(NULL, buf, len, kCFAllocatorMalloc, NULL, 0, len, 0, &bb);
    CMSampleBufferRef sb = NULL;
    CMSampleBufferCreateReady(NULL, bb, _format, 1, 0, NULL, 1, &len, &sb);
    CFRelease(bb);
    if (!sb) return;
    CFMutableDictionaryRef att = (CFMutableDictionaryRef)CFArrayGetValueAtIndex(
        CMSampleBufferGetSampleAttachmentsArray(sb, true), 0);
    CFDictionarySetValue(att, kCMSampleAttachmentKey_DisplayImmediately, kCFBooleanTrue);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self->_showing) [self show];
        if (self->_layer.status == AVQueuedSampleBufferRenderingStatusFailed) [self->_layer flush];
        [self->_layer enqueueSampleBuffer:sb];
        CFRelease(sb);
        self->_frames++; self->_bytes += len;
    });
}

#pragma mark - Main thread

- (void)sampleStats {
    [self willChangeValueForKey:@"fps"];
    _fps = _frames; _mbps = _bytes * 8 / 1e6;
    [self didChangeValueForKey:@"fps"];
    _frames = 0; _bytes = 0;
}

- (void)show {
    _showing = YES;
    [_window setFrame:NSScreen.mainScreen.frame display:NO];
    [_window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    [NSCursor setHiddenUntilMouseMoves:YES];
    IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep, kIOPMAssertionLevelOn,
                                CFSTR("Annex is showing another Mac's display"), &_noSleep);
}

- (void)hide {
    if (!_showing) return;
    _showing = NO;
    [_layer flushAndRemoveImage];
    [_window orderOut:nil];
    IOPMAssertionRelease(_noSleep);
}
@end
