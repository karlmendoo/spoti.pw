// Both artwork surfaces use these existing providers, preferences and the one file cache.
#import <Foundation/Foundation.h>
@class SPTPlayerTrack;

@interface SGArtworkRequest : NSObject
// Main thread. A request may be cancelled at any stage; only a validated video is returned.
+ (instancetype)resolveTrack:(SPTPlayerTrack *)track tall:(BOOL)tall
    completion:(void (^)(NSURL *file, NSString *identifier, NSString *source))completion;
- (void)cancel;
@end
