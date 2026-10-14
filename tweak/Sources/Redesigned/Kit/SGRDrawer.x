// App's Mod Settings row is inserted above the drawer's collection. UIKit keeps the old
// initial offset when that extra inset arrives; reveal the row once without moving a scrolled list.
#import "Core/SGCore.h"

static char kDrawerInsetKey;

static void revealSettingsRow(UICollectionView *list) {
    if (![NSStringFromClass(list.class) containsString:@"SideDrawerListCollectionView"]) return;
    UIView *row = nil;
    for (UIView *sub in list.subviews) {
        if ([NSStringFromClass(sub.class) isEqualToString:@"SGModSettingsRow"]) { row = sub; break; }
    }
    if (!row || row.frame.origin.y >= 0 || row.bounds.size.height < 1) return;
    CGFloat inset = list.adjustedContentInset.top;
    NSNumber *previous = objc_getAssociatedObject(list, &kDrawerInsetKey);
    if (previous && fabs(previous.doubleValue - inset) < 0.5) return;
    CGFloat oldTop = previous ? -previous.doubleValue : -inset + row.bounds.size.height;
    CGPoint offset = list.contentOffset;
    if (!list.isDragging && !list.isDecelerating && fabs(offset.y - oldTop) <= 1) {
        [list setContentOffset:CGPointMake(offset.x, -inset) animated:NO];
    }
    objc_setAssociatedObject(list, &kDrawerInsetKey, @(inset), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%hook UICollectionView
- (void)layoutSubviews {
    %orig;
    if (self.window) revealSettingsRow((UICollectionView *)self);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
}
