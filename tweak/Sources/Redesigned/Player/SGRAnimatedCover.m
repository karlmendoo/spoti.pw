#import <AVFoundation/AVFoundation.h>
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Shared/LockScreenArtwork/LockScreenArtwork.h"
#import "Shared/LockScreenArtwork/SGArtworkRequest.h"
#import "SGRAnimatedCover.h"
#import "Player.h"

static void *kFrameContext = &kFrameContext;

// UIKit can leave a dismissed/covered player in a window. Check clipping and presented controllers
// as well as attachment. This runs four times a second, never at display/ProMotion frequency.
static BOOL visible(UIView *cover) {
    UIWindow *window = cover.window;
    if (!window || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return NO;
    CGRect frame = [cover convertRect:cover.bounds toView:window];
    CGFloat full = frame.size.width * frame.size.height;
    if (full < 1) return NO;
    CGRect shown = CGRectIntersection(frame, window.bounds);
    for (UIView *view = cover; view; view = view.superview) {
        if (view.hidden || view.alpha < 0.01) return NO;
        if (view.clipsToBounds) shown = CGRectIntersection(shown, [view convertRect:view.bounds toView:window]);
    }
    if (CGRectIsNull(shown) || shown.size.width * shown.size.height < full * 0.8) return NO;
    NSMutableArray<UIViewController *> *controllers = [NSMutableArray array];
    if (window.rootViewController) [controllers addObject:window.rootViewController];
    for (NSUInteger at = 0; at < controllers.count && at < 64; at++) {
        UIViewController *controller = controllers[at];
        [controllers addObjectsFromArray:controller.childViewControllers];
        UIViewController *presented = controller.presentedViewController;
        if (!presented) continue;
        [controllers addObject:presented];
        UIView *pane = presented.viewIfLoaded;
        if (!pane.window || pane.hidden || pane.alpha < 0.01 || [cover isDescendantOfView:pane]) continue;
        CGRect obstruction = [pane convertRect:pane.bounds toView:window];
        if (CGRectContainsRect(obstruction, shown)) return NO;
    }
    return YES;
}

@implementation SGRAnimatedCover {
    AVPlayerLayer *_video;
    AVQueuePlayer *_player;
    AVPlayerLooper *_looper;
    SGArtworkRequest *_request;
    SPTPlayerTrack *_track;
    NSString *_signature;
    NSString *_uri;
    NSUInteger _generation;
    BOOL _loading;
    BOOL _revealed;
    NSTimer *_visibilityTimer;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.userInteractionEnabled = NO;
    self.accessibilityElementsHidden = YES;
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.backgroundColor = UIColor.clearColor;
    _video = [AVPlayerLayer playerLayerWithPlayer:nil];
    _video.videoGravity = AVLayerVideoGravityResizeAspectFill;
    _video.opacity = 0;
    [self.layer addSublayer:_video];
    [_video addObserver:self forKeyPath:@"readyForDisplay" options:0 context:kFrameContext];
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    for (NSString *name in @[UIApplicationDidBecomeActiveNotification, UIApplicationWillResignActiveNotification,
        UIApplicationDidEnterBackgroundNotification, UIAccessibilityReduceMotionStatusDidChangeNotification,
        NSUserDefaultsDidChangeNotification, AVPlayerItemFailedToPlayToEndTimeNotification]) {
        [center addObserver:self selector:@selector(changed:) name:name object:nil];
    }
    SGRObservePlayerTransition(self, ^(id owner) { [(SGRAnimatedCover *)owner refreshVisibility]; },
        ^(id owner) { [(SGRAnimatedCover *)owner refreshVisibility]; });
    return self;
}
- (void)dealloc {
    [_visibilityTimer invalidate];
    [_request cancel];
    [_player pause];
    [_looper disableLooping];
    [_video removeObserver:self forKeyPath:@"readyForDisplay" context:kFrameContext];
    [NSNotificationCenter.defaultCenter removeObserver:self];
}
- (void)changed:(NSNotification *)note {
    if (![NSThread isMainThread]) {
        __weak SGRAnimatedCover *weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf changed:note]; });
        return;
    }
    if ([note.name isEqualToString:AVPlayerItemFailedToPlayToEndTimeNotification]) {
        if ([_player.items containsObject:note.object]) { [self clearMedia]; _loading = YES; }
        return;
    }
    if ([note.name isEqualToString:UIApplicationWillResignActiveNotification]
        || [note.name isEqualToString:UIApplicationDidEnterBackgroundNotification]) { [_player pause]; return; }
    [self setTrack:_track];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _video.frame = self.bounds;
    [CATransaction commit];
    [self refreshVisibility];
}
- (void)didMoveToWindow {
    [super didMoveToWindow];
    [_visibilityTimer invalidate];
    _visibilityTimer = nil;
    if (self.window) {
        __weak SGRAnimatedCover *weakSelf = self;
        _visibilityTimer = [NSTimer scheduledTimerWithTimeInterval:0.25 repeats:YES block:^(NSTimer *timer) {
            SGRAnimatedCover *cover = weakSelf;
            if (cover) [cover setTrack:cover->_track];
        }];
        _visibilityTimer.tolerance = 0.05;
    }
    [self refreshVisibility];
}
- (void)clearMedia {
    ++_generation;
    [_request cancel];
    _request = nil;
    _loading = NO;
    [_player pause];
    [_looper disableLooping];
    _looper = nil;
    [_player removeAllItems];
    _video.player = nil;
    _player = nil;
    _revealed = NO;
    [_video removeAllAnimations];
    [CATransaction begin]; [CATransaction setDisableActions:YES]; _video.opacity = 0; [CATransaction commit];
}
- (void)setTrack:(SPTPlayerTrack *)track {
    _track = track;
    NSString *uri = SGURIString(track.URI);
    BOOL enabled = SGFlag(SGKeyLockScreenArtwork, YES) && !SGRReduceMotion();
    NSDictionary *metadata = [track respondsToSelector:@selector(metadata)] ? track.metadata : nil;
    NSString *signature = enabled && uri ? [NSString stringWithFormat:@"%@\n%@\n%@\n%@\n%@\n%@\n%@", uri,
        metadata[@"canvas.id"] ?: @"", metadata[@"canvas.url"] ?: @"", metadata[@"canvas.type"] ?: @"",
        metadata[@"artist_name"] ?: track.artistName ?: @"", metadata[@"album_title"] ?: @"", [SGArtworkOrder() componentsJoinedByString:@","]] : nil;
    BOOL same = signature == _signature || [signature isEqualToString:_signature];
    if (!same) {
        [self clearMedia]; // Expose Spotify's new high-resolution still immediately.
        _signature = signature;
        _uri = uri;
    }
    [self refreshVisibility];
}
- (void)refreshVisibility {
    BOOL shown = _signature && visible(self) && !SGRPlayerLyricsOpen() && !SGRPlayerIsTransitioning()
        && !SGRReduceMotion() && SGFlag(SGKeyLockScreenArtwork, YES);
    if (!shown) { [_player pause]; return; }
    if (!_loading && !_player) {
        _loading = YES; // Includes unavailable/failed results; do not retry at every visibility tick.
        NSUInteger generation = _generation;
        __weak SGRAnimatedCover *weakSelf = self;
        _request = [SGArtworkRequest resolveTrack:_track tall:NO completion:^(NSURL *file, NSString *identifier, NSString *source) {
            SGRAnimatedCover *cover = weakSelf;
            if (!cover || generation != cover->_generation || ![cover->_uri isEqualToString:SGURIString(SGPlayerState().track.URI)]) return;
            if (!file) return;
            [cover prepare:file generation:generation];
        }];
    }
    if (_player.status == AVPlayerStatusFailed || _looper.status == AVPlayerLooperStatusFailed
        || _player.currentItem.status == AVPlayerItemStatusFailed) { [self clearMedia]; _loading = YES; return; }
    if (_player) {
        if (_video.readyForDisplay && !_revealed) {
            _revealed = YES;
            // readyForDisplay, rather than item readiness, guarantees there is a picture to reveal.
            [CATransaction begin];
            [CATransaction setAnimationDuration:SGRCrossfade];
            [CATransaction setAnimationTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut]];
            _video.opacity = 1;
            [CATransaction commit];
        }
        if (_player.rate == 0) [_player play];
    }
}
- (void)prepare:(NSURL *)file generation:(NSUInteger)generation {
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:file options:nil];
    __weak SGRAnimatedCover *weakSelf = self;
    [asset loadTracksWithMediaType:AVMediaTypeVideo completionHandler:^(NSArray<AVAssetTrack *> *tracks, NSError *error) {
        // A video-only composition prevents an audio track from claiming Spotify's audio session.
        // No audio session configuration, decoding or per-frame image processing is performed here.
        AVMutableComposition *videoOnly = [AVMutableComposition composition];
        AVAssetTrack *video = tracks.firstObject;
        AVMutableCompositionTrack *lane = [videoOnly addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];
        NSError *insert = nil;
        BOOL ok = video && !error && [lane insertTimeRange:video.timeRange ofTrack:video atTime:kCMTimeZero error:&insert];
        if (ok) lane.preferredTransform = video.preferredTransform;
        dispatch_async(dispatch_get_main_queue(), ^{
            SGRAnimatedCover *cover = weakSelf;
            if (!cover || generation != cover->_generation || !ok) return;
            AVPlayerItem *item = [AVPlayerItem playerItemWithAsset:videoOnly];
            cover->_player = [AVQueuePlayer queuePlayerWithItems:@[]];
            cover->_player.muted = YES;
            cover->_player.volume = 0;
            cover->_player.preventsDisplaySleepDuringVideoPlayback = NO;
            cover->_player.automaticallyWaitsToMinimizeStalling = NO;
            cover->_looper = [AVPlayerLooper playerLooperWithPlayer:cover->_player templateItem:item];
            cover->_video.player = cover->_player;
            [cover refreshVisibility];
        });
    }];
}
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context != kFrameContext) { [super observeValueForKeyPath:keyPath ofObject:object change:change context:context]; return; }
    __weak SGRAnimatedCover *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf refreshVisibility]; });
}
@end
