// Sends this Mac's new virtual display to one receiver. One instance = one connection attempt;
// the app creates a fresh one to reconnect.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, ANXSenderState) {
    ANXSenderStateConnecting,
    ANXSenderStateAwaitingApproval,
    ANXSenderStateStreaming,
    ANXSenderStateDeclined,      // the other Mac said no, or is not accepting right now
    ANXSenderStateEnded,         // link lost or failed; detail says why
};

@interface ANXSender : NSObject
- (instancetype)initWithAddress:(NSString *)ipv4 senderID:(NSUUID *)senderID senderName:(NSString *)name;

/// Size of the new display in points; 0 = match the receiver's screen.
@property int pointsWide;
/// Scale applied to the receiver's size when pointsWide is 0 (1.0 = match exactly).
@property double sizeScale;
/// Where the new display sits, as the offset of its top-left corner from the main display's
/// top-left corner, in points (macOS global coordinates, y grows downward). Ignored until hasPlacement.
@property double offsetX, offsetY;
@property BOOL hasPlacement;

/// Called on the main queue.
@property(copy, nullable) void (^onStateChange)(ANXSenderState state, NSString *detail);

@property(readonly) double fps, mbps, latencyMs;
@property(readonly) BOOL viaCable;
@property(readonly) int displayWidth, displayHeight;           // points actually used
@property(readonly) int receiverWidth, receiverHeight;         // receiver's screen, points

- (void)start;
- (void)stop;
/// Re-applies offsetX/offsetY to the live display (for dragging it around without reconnecting).
- (void)applyPlacement;
@end

NS_ASSUME_NONNULL_END
