#import "ANXSender.h"
#import "ANXCommon.h"
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#import <VideoToolbox/VideoToolbox.h>
#include <sys/socket.h>
#include <arpa/inet.h>

@interface ANXSender () <SCStreamOutput, SCStreamDelegate>
- (void)sendType:(ANXMessage)type data:(NSData *)data;
@end

static void encoded(void *ref, void *src, OSStatus st, VTEncodeInfoFlags flags, CMSampleBufferRef sb) {
    if (st != noErr || !sb) return;
    ANXSender *s = (__bridge ANXSender *)ref;
    CFArrayRef att = CMSampleBufferGetSampleAttachmentsArray(sb, false);
    BOOL key = !(att && CFArrayGetCount(att) &&
                 CFDictionaryContainsKey(CFArrayGetValueAtIndex(att, 0), kCMSampleAttachmentKey_NotSync));
    if (key) {
        CMFormatDescriptionRef fmt = CMSampleBufferGetFormatDescription(sb);
        NSMutableData *d = [NSMutableData data];
        for (size_t i = 0; i < 2; i++) {
            const uint8_t *ps; size_t len;
            CMVideoFormatDescriptionGetH264ParameterSetAtIndex(fmt, i, &ps, &len, NULL, NULL);
            uint16_t be = htons((uint16_t)len);
            [d appendBytes:&be length:2]; [d appendBytes:ps length:len];
        }
        [s sendType:ANXMessageParams data:d];
    }
    CMBlockBufferRef bb = CMSampleBufferGetDataBuffer(sb);
    size_t len = CMBlockBufferGetDataLength(bb);
    NSMutableData *frame = [NSMutableData dataWithLength:len];
    CMBlockBufferCopyDataBytes(bb, 0, len, frame.mutableBytes);
    [s sendType:ANXMessageFrame data:frame];
}

@implementation ANXSender {
    NSString *_ip, *_name;
    NSUUID *_senderID;
    int _fd;
    BOOL _alive, _ended, _replied;
    uint64_t _frames, _bytes, _dropped;
    BOOL _waitingForKeyframe;            // _net only: frames were skipped, so only a keyframe may go next
    volatile BOOL _wantKeyframe;         // set on _net, read on _capture: ask the encoder for one
    dispatch_queue_t _net, _capture;
    dispatch_source_t _ping;
    NSTimer *_statsTimer;
    CGVirtualDisplay *_display;
    SCStream *_stream;
    VTCompressionSessionRef _encoder;
}

- (instancetype)initWithAddress:(NSString *)ipv4 senderID:(NSUUID *)senderID senderName:(NSString *)name {
    if ((self = [super init])) {
        _ip = [ipv4 copy]; _senderID = senderID; _name = [name copy]; _fd = -1; _sizeScale = 1.0;
        _net = dispatch_queue_create("annex.send.net", DISPATCH_QUEUE_SERIAL);
        _capture = dispatch_queue_create("annex.send.capture", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)emit:(ANXSenderState)state detail:(NSString *)detail {
    void (^cb)(ANXSenderState, NSString *) = self.onStateChange;
    if (cb) cb(state, detail);
}

#pragma mark - Handshake

- (void)start {
    [self emit:ANXSenderStateConnecting detail:_ip];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{ [self handshake]; });
}

- (void)handshake {
    int fd = ANXConnect(_ip, ANXPort, 2500);
    if (fd < 0) { [self finishOnMain:ANXSenderStateEnded detail:[NSString stringWithFormat:@"Can't reach %@", _ip]]; return; }

    NSMutableData *req = [NSMutableData data];
    uint32_t magic = htonl(ANXMagic); [req appendBytes:&magic length:4];
    uuid_t uuid; [_senderID getUUIDBytes:uuid]; [req appendBytes:uuid length:16];
    NSData *name = [_name dataUsingEncoding:NSUTF8StringEncoding];
    uint16_t nl = htons((uint16_t)MIN(name.length, 255)); [req appendBytes:&nl length:2];
    [req appendBytes:name.bytes length:MIN(name.length, 255)];

    struct timeval wait = { .tv_sec = 120 };   // time for a person to click Allow on the other Mac
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &wait, sizeof wait);
    uint32_t reply[5];
    if (!ANXWriteAll(fd, req.bytes, req.length)) { close(fd); [self finishOnMain:ANXSenderStateEnded detail:@"Connection dropped"]; return; }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 2), dispatch_get_main_queue(), ^{
        if (!self->_replied && !self->_ended) [self emit:ANXSenderStateAwaitingApproval detail:@""];
    });
    BOOL ok = ANXReadAll(fd, reply, sizeof reply) && ntohl(reply[0]) == ANXMagic;
    _replied = YES;
    if (!ok) { close(fd); [self finishOnMain:ANXSenderStateEnded detail:@"No answer from the other Mac"]; return; }
    uint32_t status = ntohl(reply[1]);
    if (status != ANXReplyAccepted) {
        close(fd);
        [self finishOnMain:ANXSenderStateDeclined
                    detail:status == ANXReplyDeclined ? @"The other Mac declined" : @"The other Mac isn't accepting right now"];
        return;
    }
    _receiverWidth = (int)ntohl(reply[2]); _receiverHeight = (int)ntohl(reply[3]);
    struct timeval tv = { .tv_sec = 4 };
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof tv);
    _viaCable = ANXSocketIsCable(fd);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_ended) { close(fd); return; }
        int sndbuf = 4 << 20;
        setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &sndbuf, sizeof sndbuf);
        self->_fd = fd; self->_alive = YES;
        [self beginStreaming];
    });
}

- (void)finishOnMain:(ANXSenderState)state detail:(NSString *)detail {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_ended) return;
        [self stop];
        [self emit:state detail:detail];
    });
}

#pragma mark - Streaming

- (void)beginStreaming {
    int w = _pointsWide, h;
    if (w > 0) h = (int)lround((double)w * _receiverHeight / MAX(_receiverWidth, 1));
    else { w = (int)lround(_receiverWidth * _sizeScale); h = (int)lround(_receiverHeight * _sizeScale); }
    if (w > 2048) { h = h * 2048 / w; w = 2048; }   // H.264 hardware limit is 4096 px wide
    w &= ~1; h &= ~1;
    _displayWidth = w; _displayHeight = h;
    int pw = w * 2, ph = h * 2;
    ANXLog(@"Streaming to %@ over %@ at %d×%d", _ip, _viaCable ? @"cable" : @"Wi-Fi", w, h);

    CGVirtualDisplayDescriptor *d = [CGVirtualDisplayDescriptor new];
    d.queue = dispatch_get_main_queue(); d.name = @"Annex Display";
    d.maxPixelsWide = pw; d.maxPixelsHigh = ph;
    d.sizeInMillimeters = CGSizeMake(w * 0.17, h * 0.17);   // ~150 dpi at 2x, keeps macOS scaling sane
    d.vendorID = 0xA4E; d.productID = 0x2; d.serialNum = 1;
    _display = [[CGVirtualDisplay alloc] initWithDescriptor:d];
    CGVirtualDisplaySettings *set = [CGVirtualDisplaySettings new];
    set.hiDPI = 1;
    set.modes = @[[[CGVirtualDisplayMode alloc] initWithWidth:w height:h refreshRate:60]];
    if (![_display applySettings:set]) { [self fail:@"Couldn't create the virtual display"]; return; }

    NSDictionary *spec = @{(id)kVTVideoEncoderSpecification_EnableLowLatencyRateControl: @YES};
    if (VTCompressionSessionCreate(NULL, pw, ph, kCMVideoCodecType_H264, (__bridge CFDictionaryRef)spec,
                                   NULL, NULL, encoded, (__bridge void *)self, &_encoder)) {
        [self fail:@"Couldn't start the video encoder"]; return;
    }
    VTSessionSetProperty(_encoder, kVTCompressionPropertyKey_RealTime, kCFBooleanTrue);
    VTSessionSetProperty(_encoder, kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse);
    VTSessionSetProperty(_encoder, kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_High_AutoLevel);
    VTSessionSetProperty(_encoder, kVTCompressionPropertyKey_AverageBitRate,
                         (__bridge CFTypeRef)@(_viaCable ? 50000000 : 20000000));
    VTSessionSetProperty(_encoder, kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, (__bridge CFTypeRef)@2);
    VTSessionSetProperty(_encoder, kVTCompressionPropertyKey_ExpectedFrameRate, (__bridge CFTypeRef)@60);

    _ping = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _net);
    dispatch_source_set_timer(_ping, DISPATCH_TIME_NOW, NSEC_PER_SEC, NSEC_PER_SEC / 10);
    __weak ANXSender *ws = self;
    dispatch_source_set_event_handler(_ping, ^{ [ws pingNow]; });
    dispatch_resume(_ping);

    int fd = _fd;
    [NSThread detachNewThreadWithBlock:^{ [ws readPongs:fd]; }];
    _statsTimer = [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *t) { [ws sampleStats]; }];

    [self startCapture:10];
}

- (void)placeDisplay {
    if (!_display) return;
    CGDirectDisplayID vid = _display.displayID;
    CGRect main = CGDisplayBounds(CGMainDisplayID());
    double dx = _hasPlacement ? _offsetX : main.size.width, dy = _hasPlacement ? _offsetY : 0;   // default: right, top-aligned
    CGDisplayConfigRef cfg;
    if (CGBeginDisplayConfiguration(&cfg) != kCGErrorSuccess) return;
    CGConfigureDisplayOrigin(cfg, vid, (int32_t)lround(main.origin.x + dx), (int32_t)lround(main.origin.y + dy));
    CGCompleteDisplayConfiguration(cfg, kCGConfigureForSession);
}

- (void)applyPlacement {
    [self placeDisplay];
}

- (void)startCapture:(int)retries {
    [SCShareableContent getShareableContentWithCompletionHandler:^(SCShareableContent *c, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self->_ended) return;
            if (err) { [self fail:@"Screen Recording permission is off for Annex"]; return; }
            SCDisplay *target = nil;
            for (SCDisplay *disp in c.displays) if (disp.displayID == self->_display.displayID) target = disp;
            if (!target) {
                if (retries <= 0) { [self fail:@"The virtual display never appeared"]; return; }
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 4), dispatch_get_main_queue(),
                               ^{ [self startCapture:retries - 1]; });
                return;
            }
            [self placeDisplay];
            SCContentFilter *f = [[SCContentFilter alloc] initWithDisplay:target excludingWindows:@[]];
            SCStreamConfiguration *cfg = [SCStreamConfiguration new];
            cfg.width = (size_t)self->_displayWidth * 2; cfg.height = (size_t)self->_displayHeight * 2;
            cfg.minimumFrameInterval = CMTimeMake(1, 60);
            cfg.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange;
            cfg.showsCursor = YES;
            cfg.queueDepth = 4;
            self->_stream = [[SCStream alloc] initWithFilter:f configuration:cfg delegate:self];
            [self->_stream addStreamOutput:self type:SCStreamOutputTypeScreen sampleHandlerQueue:self->_capture error:nil];
            [self->_stream startCaptureWithCompletionHandler:^(NSError *e) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (e) [self fail:[NSString stringWithFormat:@"Screen capture failed: %@", e.localizedDescription]];
                    else [self emit:ANXSenderStateStreaming detail:@""];
                });
            }];
        });
    }];
}

// Runs on _capture.
- (void)stream:(SCStream *)stream didOutputSampleBuffer:(CMSampleBufferRef)sb ofType:(SCStreamOutputType)type {
    if (type != SCStreamOutputTypeScreen || !_encoder) return;
    CFArrayRef att = CMSampleBufferGetSampleAttachmentsArray(sb, false);
    if (!att || !CFArrayGetCount(att)) return;
    NSDictionary *info = (__bridge NSDictionary *)CFArrayGetValueAtIndex(att, 0);
    if ([info[SCStreamFrameInfoStatus] integerValue] != SCFrameStatusComplete) return;
    CVPixelBufferRef pb = CMSampleBufferGetImageBuffer(sb);
    NSDictionary *opts = nil;
    if (_wantKeyframe) { _wantKeyframe = NO; opts = @{(id)kVTEncodeFrameOptionKey_ForceKeyFrame: @YES}; }
    if (pb) VTCompressionSessionEncodeFrame(_encoder, pb, CMSampleBufferGetPresentationTimeStamp(sb),
                                            kCMTimeInvalid, (__bridge CFDictionaryRef)opts, NULL, NULL);
}

- (void)stream:(SCStream *)stream didStopWithError:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self fail:[NSString stringWithFormat:@"Screen capture stopped: %@", error.localizedDescription]];
    });
}

#pragma mark - Network

- (void)sendType:(ANXMessage)type data:(NSData *)data {
    dispatch_sync(_net, ^{
        if (!self->_alive) return;
        if (type == ANXMessageFrame && [self shouldSkipFrame:data]) return;
        uint64_t t0 = ANXNowNanos();
        if (!ANXSendMessage(self->_fd, type, data.bytes, (uint32_t)data.length)) {
            [self linkDown:[NSString stringWithFormat:@"sending %@ (%lu bytes) failed after %.1f s: %d (%s)",
                            type == ANXMessageFrame ? @"a frame" : @"stream settings", (unsigned long)data.length,
                            (ANXNowNanos() - t0) / 1e9, errno, strerror(errno)]];
            return;
        }
        if (type == ANXMessageFrame) { self->_frames++; self->_bytes += data.length; }
    });
}

// Runs on _net. Video must never block the link: if the socket still holds more than ~1 MB that the
// other Mac hasn't taken yet, skip this frame instead of waiting, so pings keep flowing and the
// display catches up the moment the link does. After skipping, only a fresh keyframe may follow.
- (BOOL)shouldSkipFrame:(NSData *)frame {
    int unsent = 0; socklen_t len = sizeof unsent;
    getsockopt(_fd, SOL_SOCKET, SO_NWRITE, &unsent, &len);
    BOOL key = frame.length >= 5 && [self frameIsKey:frame];
    if (unsent > (1 << 20)) {
        if (!_waitingForKeyframe) ANXLog(@"Sender: link backed up (%d KB unsent), skipping frames", unsent / 1024);
        _waitingForKeyframe = YES; _wantKeyframe = YES; _dropped++;
        return YES;
    }
    if (_waitingForKeyframe) {
        if (!key) { _wantKeyframe = YES; _dropped++; return YES; }
        ANXLog(@"Sender: link caught up after skipping %llu frames", _dropped);
        _waitingForKeyframe = NO; _dropped = 0;
    }
    return NO;
}

// An AVCC frame is a keyframe when it contains an IDR slice (NAL type 5).
- (BOOL)frameIsKey:(NSData *)frame {
    const uint8_t *p = frame.bytes; size_t n = frame.length, off = 0;
    while (off + 5 <= n) {
        uint32_t len; memcpy(&len, p + off, 4); len = ntohl(len);
        if ((p[off + 4] & 0x1F) == 5) return YES;
        if (len == 0 || off + 4 + len > n) break;
        off += 4 + len;
    }
    return NO;
}

// Runs on _net.
- (void)pingNow {
    if (!_alive) return;
    uint64_t ts = ANXNowNanos();
    if (!ANXSendMessage(_fd, ANXMessagePing, &ts, sizeof ts))
        [self linkDown:[NSString stringWithFormat:@"sending a ping failed: %d (%s)", errno, strerror(errno)]];
}

// Runs on its own thread until the socket closes or goes quiet for 4 s.
- (void)readPongs:(int)fd {
    NSString *why = nil;
    for (;;) {
        uint8_t hdr[5];
        errno = 0;
        if (!ANXReadAll(fd, hdr, 5)) {
            why = errno == 0 ? @"the receiver closed the connection"
                : (errno == EAGAIN || errno == EWOULDBLOCK) ? @"no reply from the receiver for 4 s"
                : [NSString stringWithFormat:@"read error %d (%s)", errno, strerror(errno)];
            break;
        }
        uint32_t len; memcpy(&len, hdr, 4); len = ntohl(len) - 1;
        if (len > 1024) { why = [NSString stringWithFormat:@"bad reply length %u", len]; break; }
        uint8_t buf[1024];
        if (len && !ANXReadAll(fd, buf, len)) { why = @"reply cut off"; break; }
        if (hdr[4] == ANXMessagePong && len == 8) {
            uint64_t ts; memcpy(&ts, buf, 8);
            double ms = (ANXNowNanos() - ts) / 1e6;
            dispatch_async(_net, ^{ self->_latencyMs = ms; });
        }
    }
    dispatch_async(_net, ^{ if (self->_alive) [self linkDown:why ?: @"reply loop ended"]; });
}

// Runs on _net.
- (void)linkDown:(NSString *)why {
    _alive = NO;
    ANXLog(@"Sender: link down: %@", why);
    dispatch_async(dispatch_get_main_queue(), ^{ [self fail:@"Lost connection to the other Mac"]; });
}

- (void)sampleStats {
    __block uint64_t frames, bytes; __block double latency;
    dispatch_sync(_net, ^{
        frames = self->_frames; bytes = self->_bytes; latency = self->_latencyMs;
        self->_frames = 0; self->_bytes = 0;
    });
    [self willChangeValueForKey:@"fps"];
    _fps = frames; _mbps = bytes * 8 / 1e6; _latencyMs = latency;
    [self didChangeValueForKey:@"fps"];
}

#pragma mark - Teardown

- (void)fail:(NSString *)reason {
    if (_ended) return;
    ANXLog(@"Stopped: %@", reason);
    [self stop];
    [self emit:ANXSenderStateEnded detail:reason];
}

- (void)stop {
    if (_ended) return;
    _ended = YES;
    dispatch_sync(_net, ^{ self->_alive = NO; });
    [_statsTimer invalidate];
    if (_ping) dispatch_source_cancel(_ping);
    [_stream stopCaptureWithCompletionHandler:nil];
    _stream = nil;
    dispatch_sync(_capture, ^{
        if (self->_encoder) {
            VTCompressionSessionInvalidate(self->_encoder);
            CFRelease(self->_encoder);
            self->_encoder = NULL;
        }
    });
    _display = nil;   // releasing it removes the display; macOS moves its windows back
    if (_fd >= 0) { shutdown(_fd, SHUT_RDWR); close(_fd); _fd = -1; }
    _fps = 0; _mbps = 0;
}
@end
