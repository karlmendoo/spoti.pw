// A centered release cover on the page's artwork-derived field. Decorative only: Spotify owns
// navigation, scrolling, artwork loading and the height of the header around it.
#import <UIKit/UIKit.h>

@interface SGRHeroArtwork : UIView
@property (nonatomic, weak) UIView *topObstruction;
@property (nonatomic, readonly) UIImageView *picture;
@property (nonatomic) CGFloat topInset;
- (void)showImage:(UIImage *)image animated:(BOOL)animated;
@end
