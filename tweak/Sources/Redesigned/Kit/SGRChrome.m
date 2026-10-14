#import "SGRChrome.h"
#import "SGRTokens.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

@interface SGRChromeEdge : UIView
@end
@implementation SGRChromeEdge
+ (Class)layerClass { return CAGradientLayer.class; }
@end

static char kEdgeKey;
static __weak UIView *sg_chromeHost;

void SGRProtectBottomChrome(UIView *host, CGRect miniPlayer) {
    if (!host) return;
    sg_chromeHost = host;
    SGRChromeEdge *edge = objc_getAssociatedObject(host, &kEdgeKey);
    if (!edge) {
        edge = [SGRChromeEdge new];
        edge.userInteractionEnabled = NO;
        edge.accessibilityElementsHidden = YES;
        edge.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        objc_setAssociatedObject(host, &kEdgeKey, edge, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (edge.superview != host) [host insertSubview:edge atIndex:0];
    CGFloat top = CGRectIsNull(miniPlayer) ? 0 : MIN(0, CGRectGetMinY(miniPlayer));
    top -= SGRSpace24;
    CGRect frame = CGRectMake(0, top, host.bounds.size.width, MAX(0, CGRectGetMaxY(host.bounds) - top));
    BOOL solid = SGRReduceTransparency() || SGRIncreaseContrast();
    CAGradientLayer *gradient = (CAGradientLayer *)edge.layer;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    edge.frame = frame;
    gradient.colors = @[(__bridge id)[UIColor colorWithWhite:0 alpha:0].CGColor,
        (__bridge id)[UIColor colorWithWhite:0 alpha:solid ? 1 : 0.84].CGColor,
        (__bridge id)[UIColor colorWithWhite:0 alpha:solid ? 1 : 0.96].CGColor];
    gradient.locations = @[@0, @(MIN(1, SGRSpace24 / MAX(1, frame.size.height))), @1];
    [CATransaction commit];
}

void SGRBottomChromeNeedsLayout(void) {
    [sg_chromeHost.superview setNeedsLayout];
}
