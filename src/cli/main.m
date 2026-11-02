// annex: the bare engine as a command-line tool. Run one side on each Mac.
//   annex recv            this Mac becomes a display; it shows whatever a sender streams to it
//   annex send <ipv4>     this Mac gets a new display that is streamed to that receiver
#import <Cocoa/Cocoa.h>
#import "ANXCommon.h"
#import "ANXSender.h"
#import "ANXReceiver.h"
#include <signal.h>

static int usage(void) {
    fprintf(stderr, "usage:\n  annex recv          use this Mac's screen as a display\n"
                    "  annex send <ipv4>   extend this Mac onto the receiver at that address\n");
    return 1;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        signal(SIGPIPE, SIG_IGN);
        setvbuf(stdout, NULL, _IOLBF, 0);
        ANXSetLogSink(^(NSString *line) { printf("%s\n", line.UTF8String); });
        if (argc < 2) return usage();
        NSApplication *app = NSApplication.sharedApplication;
        app.activationPolicy = NSApplicationActivationPolicyAccessory;
        static id keep;

        if (!strcmp(argv[1], "recv")) {
            ANXReceiver *r = [ANXReceiver new];
            r.shouldAccept = ^BOOL(NSString *senderID, NSString *name) {
                printf("accepting %s\n", name.UTF8String);
                return YES;
            };
            keep = r;
            dispatch_async(dispatch_get_main_queue(), ^{ if (![r startListening]) exit(1); });
        } else if (!strcmp(argv[1], "send") && argc > 2) {
            ANXSender *s = [[ANXSender alloc] initWithAddress:@(argv[2]) senderID:[NSUUID UUID]
                                                   senderName:NSHost.currentHost.localizedName ?: @"Mac"];
            s.onStateChange = ^(ANXSenderState state, NSString *detail) {
                if (state == ANXSenderStateStreaming) printf("streaming\n");
                if (state == ANXSenderStateDeclined || state == ANXSenderStateEnded) {
                    fprintf(stderr, "%s\n", detail.UTF8String);
                    exit(1);
                }
            };
            keep = s;
            [NSTimer scheduledTimerWithTimeInterval:2 repeats:YES block:^(NSTimer *t) {
                if (s.fps > 0 || s.mbps > 0)
                    printf("%.0f fps  %.1f Mbps  %.1f ms  %s\n", s.fps, s.mbps, s.latencyMs, s.viaCable ? "cable" : "wi-fi");
            }];
            dispatch_async(dispatch_get_main_queue(), ^{ [s start]; });
        } else {
            return usage();
        }
        (void)keep;
        [app run];
    }
    return 0;
}
