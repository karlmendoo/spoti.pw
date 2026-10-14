#import "SGRHeroArtwork.h"
#import <QuartzCore/QuartzCore.h>
#import "SGRTokens.h"

@implementation SGRHeroArtwork {
    UIImageView *_placeholder;
    __weak UIWindow *_insetWindow;
    __weak UIView *_insetObstruction;
    CGFloat _insetWidth, _insetSafeTop, _reservedTop;
    BOOL _obstructionMeasured;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.userInteractionEnabled = NO;
    self.accessibilityElementsHidden = YES;
    _topInset = SGRSpace32 + SGRSpace24;
    _picture = [UIImageView new];
    _picture.contentMode = UIViewContentModeScaleAspectFit;
    _picture.clipsToBounds = YES;
    _picture.layer.cornerRadius = SGRRadiusArtwork;
    _picture.layer.cornerCurve = kCACornerCurveContinuous;
    _picture.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
    [self addSubview:_picture];
    _placeholder = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"music.note"
        withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:40 weight:UIImageSymbolWeightLight]]];
    _placeholder.contentMode = UIViewContentModeCenter;
    _placeholder.tintColor = SGRTertiary();
    [_picture addSubview:_placeholder];
    return self;
}

- (void)setTopInset:(CGFloat)topInset {
    if (fabs(topInset - _topInset) < 0.5) return;
    _topInset = MAX(0, topInset);
    [self setNeedsLayout];
}

- (void)showImage:(UIImage *)image animated:(BOOL)animated {
    if (_picture.image == image) return;
    // Never snapshot a scrolling hero or add another blur. UIKit composites just the cover.
    if (animated && self.window && _picture.image && !SGRReduceMotion()) {
        [UIView transitionWithView:_picture duration:SGRCrossfade
            options:UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionBeginFromCurrentState
            animations:^{ self->_picture.image = image; } completion:nil];
    } else {
        _picture.image = image;
    }
    _placeholder.hidden = image != nil;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    CGFloat top = MIN(_topInset, MAX(SGRSpace16, size.height * 0.25));
    UIWindow *window = self.window;
    UIView *obstruction = self.topObstruction;
    // Measure the expanded header once per window geometry, not while its plane scrolls.
    // Recomputing this coordinate every frame would pin the cover during collapse.
    BOOL changed = window != _insetWindow || fabs(window.bounds.size.width - _insetWidth) > 0.5
        || fabs(window.safeAreaInsets.top - _insetSafeTop) > 0.5 || obstruction != _insetObstruction
        || (!_obstructionMeasured && obstruction.window == window && obstruction.bounds.size.height >= 20);
    if (window && size.height >= 120 && changed) {
        CGFloat safeTop = [self convertPoint:CGPointMake(0, window.safeAreaInsets.top + SGRGlassCircleSize + SGRSpace16)
            fromView:window].y;
        _reservedTop = MAX(0, safeTop);
        _obstructionMeasured = obstruction.window == window && obstruction.bounds.size.height >= 20;
        if (_obstructionMeasured) {
            _reservedTop = MAX(_reservedTop, CGRectGetMaxY([self convertRect:obstruction.bounds fromView:obstruction]) + SGRSpace16);
        }
        _insetWindow = window;
        _insetWidth = window.bounds.size.width;
        _insetSafeTop = window.safeAreaInsets.top;
        _insetObstruction = obstruction;
    }
    top = MAX(top, _reservedTop);
    CGFloat side = floor(MAX(0, MIN(320, MIN(size.width - 2 * SGRSpace32,
        size.height - top - SGRSpace16))));
    _picture.frame = CGRectMake(round((size.width - side) / 2), top, side, side);
    _placeholder.frame = _picture.bounds;
}

- (void)setTopObstruction:(UIView *)topObstruction {
    if (_topObstruction == topObstruction) return;
    _topObstruction = topObstruction;
    [self setNeedsLayout];
}
@end
