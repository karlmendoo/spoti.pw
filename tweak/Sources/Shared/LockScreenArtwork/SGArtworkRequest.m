#import <AVFoundation/AVFoundation.h>
#import "Core/SGCore.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/Lyrics/Lyrics.h"
#import "LockScreenArtwork.h"
#import "SGCanvas.h"
#import "SGAppleArtwork.h"
#import "SGArtworkFile.h"
#import "SGArtworkRequest.h"

@interface SGArtworkRequest ()
@property (nonatomic) BOOL cancelled;
@property (nonatomic) BOOL tall;
@property (nonatomic, strong) SPTPlayerTrack *track;
@property (nonatomic, copy) NSArray<NSString *> *order;
@property (nonatomic, copy) void (^completion)(NSURL *, NSString *, NSString *);
@property (nonatomic, strong) SGArtworkFetchRequest *fetch;
@property (nonatomic, strong) NSURLSessionDataTask *canvaz;
@end

@implementation SGArtworkRequest
+ (instancetype)resolveTrack:(SPTPlayerTrack *)track tall:(BOOL)tall
    completion:(void (^)(NSURL *, NSString *, NSString *))completion {
    SGArtworkRequest *request = [self new];
    request.track = track;
    request.tall = tall;
    request.order = SGArtworkOrder();
    request.completion = completion;
    // Give the owner time to retain the request, even for a metadata/cache hit.
    dispatch_async(dispatch_get_main_queue(), ^{ [request walk:0]; });
    return request;
}
- (void)cancel {
    _cancelled = YES;
    [_fetch cancel];
    [_canvaz cancel];
    _completion = nil;
}
- (void)dealloc { [_fetch cancel]; [_canvaz cancel]; }
- (void)finish:(NSURL *)file identifier:(NSString *)identifier source:(NSString *)source {
    if (_cancelled) return;
    void (^done)(NSURL *, NSString *, NSString *) = _completion;
    _completion = nil;
    if (done) done(file, identifier, source);
}
- (void)accept:(SGCanvas *)canvas at:(NSUInteger)at {
    if (_cancelled) return;
    if (!canvas.video || !canvas.identifier.length || !canvas.address.length) { [self walk:at + 1]; return; }
    __weak SGArtworkRequest *weakSelf = self;
    _fetch = SGArtworkFetchShared(canvas.identifier, canvas.address, ^(NSURL *file, NSString *note) {
        SGArtworkRequest *request = weakSelf;
        if (!request || request.cancelled) return;
        if (!file) { [request walk:at + 1]; return; }
        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:file options:nil];
        [asset loadTracksWithMediaType:AVMediaTypeVideo completionHandler:^(NSArray<AVAssetTrack *> *tracks, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                SGArtworkRequest *current = weakSelf;
                if (!current || current.cancelled) return;
                if (!tracks.count || error || !CMTIMERANGE_IS_VALID(tracks.firstObject.timeRange)
                    || !isfinite(CMTimeGetSeconds(tracks.firstObject.timeRange.duration))
                    || CMTimeGetSeconds(tracks.firstObject.timeRange.duration) <= 0) {
                    [current walk:at + 1]; return;
                }
                [current finish:file identifier:canvas.identifier source:current.order[at]];
            });
        }];
    });
}
- (void)walk:(NSUInteger)at {
    if (_cancelled) return;
    if (at >= _order.count || !SGURIString(_track.URI).length) { [self finish:nil identifier:nil source:nil]; return; }
    NSDictionary *metadata = [_track respondsToSelector:@selector(metadata)] ? _track.metadata : nil;
    __weak SGArtworkRequest *weakSelf = self;
    if ([_order[at] isEqualToString:SGArtworkSourceApple]) {
        SGAppleArtworkFind(metadata[@"artist_name"] ?: _track.artistName, metadata[@"album_title"], _tall,
            ^(SGCanvas *canvas, NSString *note) { [weakSelf accept:canvas at:at]; });
        return;
    }
    SGCanvas *canvas = SGCanvasFromMetadata(metadata);
    if (canvas.video) { [self accept:canvas at:at]; return; }
    NSString *authorization = SGKaraokeSpotifyAuthorization();
    NSData *body = SGCanvazRequestBody(SGURIString(_track.URI));
    if (!authorization || !body) { [self walk:at + 1]; return; }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:
        [NSURL URLWithString:@"https://spclient.wg.spotify.com/canvaz-cache/v0/canvases"]];
    request.HTTPMethod = @"POST";
    request.HTTPBody = body;
    request.allowsConstrainedNetworkAccess = NO;
    [request setValue:authorization forHTTPHeaderField:@"Authorization"];
    [request setValue:@"application/x-protobuf" forHTTPHeaderField:@"Content-Type"];
    _canvaz = [NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        SGCanvas *found = !error && [(NSHTTPURLResponse *)response statusCode] == 200 ? SGCanvazFromBody(data) : nil;
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf accept:found at:at]; });
    }];
    [_canvaz resume];
}
@end
