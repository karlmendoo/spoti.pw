// Real cached media and the production player layer inside the recorded Spotify cover hierarchy.
#import <AVFoundation/AVFoundation.h>
#import "Redesigned/Player/SGRAnimatedCover.h"
#import "Redesigned/Player/Player.h"
#import "Shared/LockScreenArtwork/SGArtworkFile.h"
#import "Shared/LockScreenArtwork/LockScreenArtwork.h"

void SGRHarnessSetAnimation(NSString *identifier);
void SGRHarnessSetTrack(NSString *uri, NSString *imageURI, BOOL paused);
static NSUInteger checks, failures;
static void check(BOOL ok, NSString *message) {
    checks++; if (!ok) failures++;
    NSLog(@"[harness] animated cover: %@ -- %@", message, ok ? @"PASS" : @"FAIL");
}
static void later(double delay, dispatch_block_t block) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, delay * NSEC_PER_SEC), dispatch_get_main_queue(), block);
}
static SGRAnimatedCover *findCover(UIView *view) {
    if ([view isKindOfClass:SGRAnimatedCover.class]) return (id)view;
    for (UIView *child in view.subviews) { SGRAnimatedCover *found = findCover(child); if (found) return found; }
    return nil;
}
static AVPlayerLayer *videoLayer(SGRAnimatedCover *cover) {
    for (CALayer *layer in cover.layer.sublayers) if ([layer isKindOfClass:AVPlayerLayer.class]) return (id)layer;
    return nil;
}
static NSURL *cache(NSString *name) {
    NSString *root = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
    NSURL *dir = [NSURL fileURLWithPath:[root stringByAppendingPathComponent:@"spoti.pw/LockArtwork"]];
    [NSFileManager.defaultManager createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return [dir URLByAppendingPathComponent:[name stringByAppendingPathExtension:@"mp4"]];
}
static BOOL fixture(void) {
    NSURL *url = cache(@"harness-motion");
    [NSFileManager.defaultManager removeItemAtURL:url error:nil];
    AVAssetWriter *writer = [AVAssetWriter assetWriterWithURL:url fileType:AVFileTypeMPEG4 error:nil];
    AVAssetWriterInput *input = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:
        @{AVVideoCodecKey: AVVideoCodecTypeH264, AVVideoWidthKey: @320, AVVideoHeightKey: @320}];
    AVAssetWriterInputPixelBufferAdaptor *adaptor = [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:input
        sourcePixelBufferAttributes:@{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA), (id)kCVPixelBufferWidthKey: @320, (id)kCVPixelBufferHeightKey: @320}];
    [writer addInput:input]; [writer startWriting]; [writer startSessionAtSourceTime:kCMTimeZero];
    for (int frame = 0; frame < 45; frame++) {
        CVPixelBufferRef buffer = NULL;
        CVPixelBufferPoolCreatePixelBuffer(NULL, adaptor.pixelBufferPool, &buffer);
        if (!buffer) return NO;
        CVPixelBufferLockBaseAddress(buffer, 0);
        uint8_t *bytes = CVPixelBufferGetBaseAddress(buffer);
        size_t stride = CVPixelBufferGetBytesPerRow(buffer);
        for (int y = 0; y < 320; y++) for (int x = 0; x < 320; x++) {
            uint8_t *p = bytes + y * stride + x * 4;
            p[0] = 140; p[1] = (x + frame * 6) % 256; p[2] = 240; p[3] = 255;
        }
        CVPixelBufferUnlockBaseAddress(buffer, 0);
        while (!input.readyForMoreMediaData && writer.status == AVAssetWriterStatusWriting) usleep(1000);
        BOOL wrote = [adaptor appendPixelBuffer:buffer withPresentationTime:CMTimeMake(frame, 30)];
        CVPixelBufferRelease(buffer);
        if (!wrote) return NO;
    }
    [input markAsFinished];
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    [writer finishWritingWithCompletionHandler:^{ dispatch_semaphore_signal(done); }];
    dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
    [@"invalid media" writeToURL:cache(@"harness-broken") atomically:YES encoding:NSUTF8StringEncoding error:nil];
    return writer.status == AVAssetWriterStatusCompleted;
}
static void track(NSString *name, NSString *clip) {
    SGRHarnessSetAnimation(clip);
    SGRHarnessSetTrack([@"spotify:track:" stringByAppendingString:name], nil, NO);
}
static void exercise(UIWindow *window, SGRAnimatedCover *cover) {
    AVPlayerLayer *layer = videoLayer(cover);
    AVQueuePlayer *player = (id)layer.player;
    CGRect original = [cover convertRect:cover.bounds toView:window];
    UIView *container = cover.superview;
    check(layer.readyForDisplay && layer.opacity == 1 && player.rate > 0, @"first frame revealed over the still");
    check(player.muted && player.volume == 0 && ![player.currentItem.asset tracksWithMediaType:AVMediaTypeAudio].count,
        @"muted video-only playback");
    check(CGRectEqualToRect(cover.frame, container.bounds) && container.clipsToBounds && container.layer.cornerRadius > 0
        && !cover.userInteractionEnabled && cover.accessibilityElementsHidden, @"existing bounds, corners and touches preserved");
    later(3, ^{
        AVPlayerLooper *looper = [cover valueForKey:@"looper"];
        check(looper.loopCount >= 1 && layer.player == player && layer.readyForDisplay, @"loop keeps one player and a displayed frame");
        container.alpha = 0; [cover refreshVisibility];
        check(player.rate == 0, @"covered artwork pauses");
        container.alpha = 1; [cover refreshVisibility];
        check(layer.player == player && player.rate > 0, @"visibility resumes the same player");
        CGPoint center = container.center;
        container.center = CGPointMake(center.x + window.bounds.size.width * 2, center.y); [cover refreshVisibility];
        check(player.rate == 0, @"offscreen artwork pauses");
        container.center = center; [cover refreshVisibility];
        [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationWillResignActiveNotification object:nil];
        check(player.rate == 0, @"background notification pauses immediately");
        [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
        check(player.rate > 0 && layer.player == player, @"foreground resumes without recreation");
        UIViewController *modal = [UIViewController new];
        modal.modalPresentationStyle = UIModalPresentationFullScreen;
        modal.view.backgroundColor = UIColor.blackColor;
        [window.rootViewController presentViewController:modal animated:NO completion:^{
            [cover refreshVisibility];
            check(player.rate == 0, @"fullscreen presentation suspends the underlying cover");
            [modal dismissViewControllerAnimated:NO completion:^{
                [cover refreshVisibility];
                check(player.rate > 0 && layer.player == player, @"fullscreen dismissal resumes");
                [cover removeFromSuperview];
                check(player.rate == 0, @"dismissed player pauses");
                [container addSubview:cover]; [cover refreshVisibility];
                check(layer.player == player && player.rate > 0 && CGRectEqualToRect(original, [cover convertRect:cover.bounds toView:window]),
                    @"reattachment preserves geometry and player");
                SGRPlayerToggleLyrics();
                check(player.rate == 0, @"lyrics suspends the large animation");
                SGRPlayerToggleLyrics();
                later(1, ^{
                    track(@"obsolete", @"harness-motion");
                    track(@"broken-obsolete", @"harness-broken");
                    track(@"latest", @"harness-motion");
                    check(player.rate == 0 && layer.opacity == 0, @"rapid skips immediately expose static fallback");
                    later(2, ^{
                        check([[cover valueForKey:@"uri"] isEqualToString:@"spotify:track:latest"] && layer.player != player && layer.player.rate > 0,
                            @"only the latest track's completion plays");
                        track(@"invalid", @"harness-broken");
                        later(2, ^{
                            check(!layer.player && layer.opacity == 0, @"invalid media silently keeps the static cover");
                            [NSUserDefaults.standardUserDefaults setBool:NO forKey:SGKeyLockScreenArtwork];
                            track(@"disabled", @"harness-motion");
                            later(1, ^{
                                check(!layer.player && layer.opacity == 0, @"existing artwork preference disables cover animation");
                                [NSUserDefaults.standardUserDefaults setBool:YES forKey:SGKeyLockScreenArtwork];
                                SGArtworkFetchRequest *cancelled = SGArtworkFetchShared(@"harness-motion", @"https://example.invalid/clip.mp4",
                                    ^(NSURL *file, NSString *note) { check(NO, @"cancelled cache subscriber was called"); });
                                SGArtworkFetchShared(@"harness-motion", @"https://example.invalid/clip.mp4", ^(NSURL *file, NSString *note) {
                                    check(file != nil, @"cancelling one surface preserves the other cache subscriber");
                                    NSLog(@"[harness] animated cover checks: %lu of %lu -- %@", (unsigned long)(checks - failures),
                                        (unsigned long)checks, failures ? @"FAIL" : @"PASS");
                                });
                                [cancelled cancel];
                            });
                        });
                    });
                });
            }];
        }];
    });
}
static void awaitVideo(UIWindow *window, SGRAnimatedCover *cover, NSUInteger attempt) {
    [cover refreshVisibility];
    AVPlayerLayer *layer = videoLayer(cover);
    if (layer.readyForDisplay && layer.player.rate > 0) { exercise(window, cover); return; }
    if (attempt >= 40) { NSLog(@"[harness] animated cover checks: video never ready -- FAIL"); return; }
    later(0.25, ^{ awaitVideo(window, cover, attempt + 1); });
}
void SGRRunAnimatedCoverChecks(UIWindow *window) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        BOOL written = fixture();
        dispatch_async(dispatch_get_main_queue(), ^{
            check(written, @"H.264 fixture written off main");
            SGRAnimatedCover *cover = findCover(window);
            check(cover != nil, @"production overlay attached to the recorded Spotify cover");
            if (!cover || !written) { NSLog(@"[harness] animated cover checks: setup -- FAIL"); return; }
            track(@"animated", @"harness-motion");
            check(!videoLayer(cover).player && videoLayer(cover).opacity == 0, @"static artwork remains while resolving");
            awaitVideo(window, cover, 0);
        });
    });
}
