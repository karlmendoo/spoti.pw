#import <UIKit/UIKit.h>
@class SPTPlayerTrack;

// A passive overlay inside Spotify's existing cover. One instance follows the visible cover cell.
@interface SGRAnimatedCover : UIView
- (void)setTrack:(SPTPlayerTrack *)track;
- (void)refreshVisibility;
@end
