#import <AVFoundation/AVFoundation.h>
#import "Core/SGCore.h"
#import "SGArtworkFile.h"

static const unsigned long long kCap = 120 * 1024 * 1024;   // an Apple Music cover is about 8 MB
// A clip this close to the shape asked for is handed over untouched rather than re-encoded.
static const CGFloat kAspectSlack = 0.02;

static dispatch_queue_t queue(void) {
    static dispatch_queue_t shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = dispatch_queue_create("com.spotifyglass.lockartwork", DISPATCH_QUEUE_SERIAL); });
    return shared;
}

static NSURL *directory(void) {
    NSString *caches = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
    NSURL *url = [NSURL fileURLWithPath:[caches stringByAppendingPathComponent:@"spoti.pw/LockArtwork"]];
    [NSFileManager.defaultManager createDirectoryAtURL:url withIntermediateDirectories:YES attributes:nil error:nil];
    return url;
}

static NSURL *fileFor(NSString *name) {
    return [directory() URLByAppendingPathComponent:name];
}

// Kept alive by its use, so the file the lock screen is playing is the last one to go.
static void touch(NSURL *file) {
    [NSFileManager.defaultManager setAttributes:@{NSFileModificationDate: NSDate.date} ofItemAtPath:file.path error:nil];
}

static void prune(void) {
    NSFileManager *files = NSFileManager.defaultManager;
    NSArray<NSURLResourceKey> *wanted = @[NSURLContentModificationDateKey, NSURLFileSizeKey];
    NSArray<NSURL *> *kept = [files contentsOfDirectoryAtURL:directory() includingPropertiesForKeys:wanted options:0 error:nil];
    unsigned long long total = 0;
    for (NSURL *file in kept) total += [[file resourceValuesForKeys:wanted error:nil][NSURLFileSizeKey] unsignedLongLongValue];
    if (total <= kCap) return;
    NSArray<NSURL *> *oldest = [kept sortedArrayUsingComparator:^NSComparisonResult(NSURL *a, NSURL *b) {
        NSDate *left = [a resourceValuesForKeys:wanted error:nil][NSURLContentModificationDateKey];
        NSDate *right = [b resourceValuesForKeys:wanted error:nil][NSURLContentModificationDateKey];
        return [left ?: NSDate.distantPast compare:right ?: NSDate.distantPast];
    }];
    for (NSURL *file in oldest) {
        if (total <= kCap) break;
        total -= [[file resourceValuesForKeys:wanted error:nil][NSURLFileSizeKey] unsignedLongLongValue];
        [files removeItemAtURL:file error:nil];
    }
    SGLog(@"lock artwork: cache pruned to %llu KB", total / 1024);
}

@interface SGArtworkFetchRequest ()
@property (atomic) BOOL cancelled;
@property (nonatomic, copy) NSString *key;
@property (nonatomic, copy) void (^completion)(NSURL *, NSString *);
@end
@interface SGArtworkDownload : NSObject
@property (nonatomic, strong) NSURLSessionDownloadTask *task;
@property (nonatomic, strong) NSMutableArray<SGArtworkFetchRequest *> *subscribers;
@end
@implementation SGArtworkDownload
@end
static NSMutableDictionary<NSString *, SGArtworkDownload *> *sg_downloads; // main thread
static SGArtworkFetchRequest *sg_legacy;

@implementation SGArtworkFetchRequest
- (void)cancel {
    self.cancelled = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        self.completion = nil;
        if (!self.key) return;
        SGArtworkDownload *download = sg_downloads[self.key];
        [download.subscribers removeObject:self];
        if (download && !download.subscribers.count) {
            [download.task cancel];
            download.task = nil;
            [sg_downloads removeObjectForKey:self.key];
        }
    });
}
@end

void SGArtworkCancelFetch(void) { [sg_legacy cancel]; sg_legacy = nil; }
void SGArtworkFetch(NSString *identifier, NSString *address, void (^done)(NSURL *, NSString *)) {
    SGArtworkCancelFetch();
    sg_legacy = SGArtworkFetchShared(identifier, address, done);
}

SGArtworkFetchRequest *SGArtworkFetchShared(NSString *identifier, NSString *address, void (^done)(NSURL *, NSString *)) {
    SGArtworkFetchRequest *subscriber = [SGArtworkFetchRequest new];
    subscriber.completion = done;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (subscriber.cancelled) return;
        NSURL *remote = address.length ? [NSURL URLWithString:address] : nil;
        if (!identifier.length || ![identifier isEqualToString:identifier.lastPathComponent]
            || ![@[@"https", @"http"] containsObject:remote.scheme.lowercaseString]) {
            if (subscriber.completion) subscriber.completion(nil, @"no address");
            subscriber.completion = nil;
            return;
        }
        NSURL *local = fileFor([identifier stringByAppendingPathExtension:@"mp4"]);
        if ([NSFileManager.defaultManager fileExistsAtPath:local.path]) {
            dispatch_async(queue(), ^{ touch(local); });
            if (subscriber.completion) subscriber.completion(local, @"cached");
            subscriber.completion = nil;
            return;
        }
        if (!sg_downloads) sg_downloads = [NSMutableDictionary dictionary];
        NSString *key = [NSString stringWithFormat:@"%@\n%@", identifier, address];
        subscriber.key = key;
        SGArtworkDownload *download = sg_downloads[key];
        if (download) { [download.subscribers addObject:subscriber]; return; }
        download = [SGArtworkDownload new];
        download.subscribers = [NSMutableArray arrayWithObject:subscriber];
        sg_downloads[key] = download;
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:remote];
        request.allowsConstrainedNetworkAccess = NO;
        download.task = [NSURLSession.sharedSession downloadTaskWithRequest:request completionHandler:^(NSURL *temporary, NSURLResponse *response, NSError *error) {
            // NSURLSession removes its temporary file when this callback returns. Move it before
            // handing work to the cache queue, otherwise a perfectly good download can disappear.
            NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? [(NSHTTPURLResponse *)response statusCode] : 0;
            NSURL *staged = fileFor([NSUUID.UUID.UUIDString stringByAppendingPathExtension:@"download"]);
            unsigned long long size = temporary ? [[NSFileManager.defaultManager attributesOfItemAtPath:temporary.path error:nil][NSFileSize] unsignedLongLongValue] : 0;
            BOOL kept = temporary && !error && status >= 200 && status < 300 && size > 0 && size <= kCap
                && [NSFileManager.defaultManager moveItemAtURL:temporary toURL:staged error:nil];
            dispatch_async(queue(), ^{
                BOOL moved = NO;
                if (kept) {
                    if ([NSFileManager.defaultManager fileExistsAtPath:local.path]) {
                        moved = YES;
                        [NSFileManager.defaultManager removeItemAtURL:staged error:nil];
                    } else moved = [NSFileManager.defaultManager moveItemAtURL:staged toURL:local error:nil];
                    if (moved) { touch(local); prune(); }
                }
                if (!moved) [NSFileManager.defaultManager removeItemAtURL:staged error:nil];
                dispatch_async(dispatch_get_main_queue(), ^{
                    // A cancelled download may have a new request under the same key already.
                    download.task = nil;
                    if (sg_downloads[key] != download) return;
                    [sg_downloads removeObjectForKey:key];
                    NSArray *subscribers = [download.subscribers copy];
                    [download.subscribers removeAllObjects];
                    for (SGArtworkFetchRequest *waiting in subscribers) {
                        if (!waiting.cancelled && waiting.completion) waiting.completion(moved ? local : nil, moved ? @"downloaded" : @"download failed");
                        waiting.completion = nil;
                    }
                });
            });
        }];
        [download.task resume];
    });
    return subscriber;
}

// The size the clip is played at, its rotation applied, and the transform that puts its top left at
// the origin.
static CGSize shownSize(AVAssetTrack *track, CGAffineTransform *upright) {
    CGRect shown = CGRectApplyAffineTransform(CGRectMake(0, 0, track.naturalSize.width, track.naturalSize.height),
                                              track.preferredTransform);
    *upright = CGAffineTransformConcat(track.preferredTransform,
                                       CGAffineTransformMakeTranslation(-CGRectGetMinX(shown), -CGRectGetMinY(shown)));
    return CGSizeMake(fabs(shown.size.width), fabs(shown.size.height));
}

// H.264 wants even sides.
static CGFloat even(CGFloat value) {
    return 2 * floor(value / 2);
}

static void crop(AVURLAsset *asset, AVAssetTrack *track, NSURL *into, CGFloat aspect, void (^done)(NSURL *cropped, NSString *note)) {
    CGAffineTransform upright;
    CGSize shown = shownSize(track, &upright);
    if (shown.width < 2 || shown.height < 2) {
        done(nil, @"no picture");
        return;
    }
    if (fabs(shown.width / shown.height - aspect) < kAspectSlack) {
        done(asset.URL, @"already the right shape");
        return;
    }
    CGSize render = shown.width / shown.height > aspect ? CGSizeMake(even(shown.height * aspect), even(shown.height))
                                                        : CGSizeMake(even(shown.width), even(shown.width / aspect));
    AVMutableVideoCompositionLayerInstruction *layer = [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:track];
    [layer setTransform:CGAffineTransformConcat(upright, CGAffineTransformMakeTranslation((render.width - shown.width) / 2,
                                                                                          (render.height - shown.height) / 2))
                 atTime:kCMTimeZero];
    AVMutableVideoCompositionInstruction *instruction = [AVMutableVideoCompositionInstruction videoCompositionInstruction];
    instruction.timeRange = track.timeRange;
    instruction.layerInstructions = @[layer];
    AVMutableVideoComposition *composition = [AVMutableVideoComposition videoComposition];
    composition.renderSize = render;
    composition.frameDuration = CMTimeMake(1, track.nominalFrameRate > 1 ? (int32_t)lround(track.nominalFrameRate) : 30);
    composition.instructions = @[instruction];

    AVAssetExportSession *export = [AVAssetExportSession exportSessionWithAsset:asset presetName:AVAssetExportPresetHighestQuality];
    if (!export) {
        done(nil, @"no exporter");
        return;
    }
    export.outputURL = into;
    export.outputFileType = AVFileTypeMPEG4;
    export.videoComposition = composition;
    [export exportAsynchronouslyWithCompletionHandler:^{
        BOOL ok = export.status == AVAssetExportSessionStatusCompleted;
        dispatch_async(queue(), ^{
            if (ok) prune();
            done(ok ? into : nil, ok ? [NSString stringWithFormat:@"cropped to %.0fx%.0f", render.width, render.height]
                                     : [NSString stringWithFormat:@"crop failed: %@", export.error.localizedDescription]);
        });
    }];
}

void SGArtworkCrop(NSURL *file, NSString *identifier, CGFloat aspect, void (^done)(NSURL *cropped, NSString *note)) {
    NSURL *into = fileFor([NSString stringWithFormat:@"%@-%.2f.mp4", identifier, aspect]);
    if ([NSFileManager.defaultManager fileExistsAtPath:into.path]) {
        dispatch_async(queue(), ^{ touch(into); });
        done(into, @"cropped already");
        return;
    }
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:file options:nil];
    [asset loadTracksWithMediaType:AVMediaTypeVideo completionHandler:^(NSArray<AVAssetTrack *> *tracks, NSError *error) {
        dispatch_async(queue(), ^{
            if (!tracks.count) {
                done(nil, [NSString stringWithFormat:@"no video track: %@", error.localizedDescription]);
                return;
            }
            crop(asset, tracks.firstObject, into, aspect, done);
        });
    }];
}

void SGArtworkFirstFrame(NSURL *file, void (^done)(CGImageRef frame)) {
    AVAssetImageGenerator *generator = [AVAssetImageGenerator assetImageGeneratorWithAsset:[AVURLAsset URLAssetWithURL:file options:nil]];
    generator.appliesPreferredTrackTransform = YES;
    generator.requestedTimeToleranceBefore = kCMTimeZero;
    generator.requestedTimeToleranceAfter = kCMTimeZero;
    [generator generateCGImageAsynchronouslyForTime:kCMTimeZero completionHandler:^(CGImageRef frame, CMTime actual, NSError *error) {
        done(frame);
    }];
}
