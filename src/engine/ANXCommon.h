// Annex engine: wire protocol, logging, socket helpers, and the private virtual-display API.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Protocol (v2)
// 1. Sender → receiver request: u32 magic | 16-byte sender id | u16 name length | name (UTF-8)
// 2. Receiver → sender reply:   u32 magic | u32 status | u32 width-pt | u32 height-pt | u32 scale
// 3. Then length-framed messages both ways: u32 big-endian length | u8 type | payload
//      sender → receiver: params (u16 len + SPS, u16 len + PPS), frame (AVCC), ping (u64 timestamp)
//      receiver → sender: pong (the ping's u64 timestamp, echoed)
// All integers are big-endian.

static const uint16_t ANXPort = 47979;
static const uint32_t ANXMagic = 0x414E5832;   // "ANX2"
static NSString *const ANXServiceType = @"_annex._tcp.";

typedef NS_ENUM(uint8_t, ANXMessage) {
    ANXMessageParams = 0,
    ANXMessageFrame = 1,
    ANXMessagePing = 2,
    ANXMessagePong = 3,
};

typedef NS_ENUM(uint32_t, ANXReply) {
    ANXReplyDeclined = 0,
    ANXReplyAccepted = 1,
    ANXReplyNotAccepting = 2,   // "Let other Macs use this screen" is off, or the user pressed Esc
};

#pragma mark - Logging (forwarded to the app's activity log)

typedef void (^ANXLogSink)(NSString *line);
void ANXSetLogSink(ANXLogSink sink);
void ANXLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);

#pragma mark - Sockets

/// Connects with a timeout; returns a blocking socket (TCP_NODELAY, no SIGPIPE) or -1.
int ANXConnect(NSString *ipv4, uint16_t port, int timeoutMs);
/// YES when this socket's local address is on a Thunderbolt/USB-C bridge (a cable link).
BOOL ANXSocketIsCable(int fd);
/// YES when the address is on the same subnet as one of this Mac's cable bridges.
BOOL ANXAddressIsCable(NSString *ipv4);
/// This Mac's own IPv4 addresses on cable bridges (advertised so the other Mac can pick the cable).
NSArray<NSString *> *ANXCableAddresses(void);
/// YES on MacBooks (has an internal battery).
BOOL ANXIsLaptop(void);
BOOL ANXWriteAll(int fd, const void *buf, size_t n);
BOOL ANXReadAll(int fd, void *buf, size_t n);
BOOL ANXSendMessage(int fd, ANXMessage type, const void *_Nullable payload, uint32_t len);
uint64_t ANXNowNanos(void);

NS_ASSUME_NONNULL_END

#pragma mark - Private CoreGraphics virtual display API (also used by DeskPad and BetterDisplay)

NS_ASSUME_NONNULL_BEGIN

@interface CGVirtualDisplayDescriptor : NSObject
@property(retain) dispatch_queue_t queue;
@property(retain) NSString *name;
@property unsigned int maxPixelsWide, maxPixelsHigh, vendorID, productID, serialNum;
@property CGSize sizeInMillimeters;
@end
@interface CGVirtualDisplayMode : NSObject
- (instancetype)initWithWidth:(unsigned)w height:(unsigned)h refreshRate:(double)r;
@end
@interface CGVirtualDisplaySettings : NSObject
@property(retain) NSArray *modes;
@property unsigned int hiDPI;
@end
@interface CGVirtualDisplay : NSObject
- (instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)d;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)s;
@property(readonly) CGDirectDisplayID displayID;
@end

NS_ASSUME_NONNULL_END
