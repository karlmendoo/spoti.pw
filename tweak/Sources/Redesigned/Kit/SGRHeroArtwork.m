#import "SGRHeroArtwork.h"
#import <QuartzCore/QuartzCore.h>
#import "SGRTokens.h"

@implementation SGRHeroArtwork {
    UIImageView *_placeholder;
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
    CGFloat side = floor(MAX(0, MIN(320, MIN(size.width - 2 * SGRSpace32,
        size.height - top - SGRSpace16))));
    _picture.frame = CGRectMake(round((size.width - side) / 2), top, side, side);
    _placeholder.frame = _picture.bounds;
}
@end
