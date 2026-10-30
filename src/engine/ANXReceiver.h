// Lets another Mac use this Mac's screen: listens, asks the user once, then shows the stream full screen.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ANXReceiver : NSObject
/// When NO, incoming requests are refused with "not accepting".
@property BOOL enabled;

/// Called on the main queue for every new sender; return YES to allow. May show UI.
@property(copy, nullable) BOOL (^shouldAccept)(NSString *senderID, NSString *senderName);
/// Called on the main queue when a stream starts (active = YES) or ends.
@property(copy, nullable) void (^onActiveChange)(BOOL active, NSString *senderName, BOOL viaCable);

@property(readonly) double fps, mbps;
@property(readonly, getter=isActive) BOOL active;

/// Binds the listening port. Returns NO if it is already in use.
- (BOOL)startListening;
/// Ends the current stream and refuses new ones for `seconds` (Esc does this with 30 s).
- (void)pauseFor:(NSTimeInterval)seconds;
@end

NS_ASSUME_NONNULL_END
