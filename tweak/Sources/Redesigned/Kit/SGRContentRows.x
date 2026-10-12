// Search results and queue rows use the same Encore content identifiers as the entity pages.
// Match the recorded identifiers, not a controller guessed from its name. Unknown cells stay stock.
#import "Core/SGCore.h"
#import "SGRContentStyle.h"

static char kPartsKey;
@interface SGRContentRowParts : NSObject
@property (nonatomic, weak) UIView *title;
@property (nonatomic, weak) UIView *subtitle;
@property (nonatomic) CFTimeInterval scanned;
@end
@implementation SGRContentRowParts
@end

// A bounded walk of a single short row, never a carousel or a page. No ancestor/window traversal.
static UIView *findRowPart(UIView *root, NSString *identifier, NSUInteger depth, NSUInteger *budget) {
    if (!root || !*budget || depth > 6) return nil;
    (*budget)--;
    if ([root.accessibilityIdentifier isEqualToString:identifier]) return root;
    if ([root isKindOfClass:UIScrollView.class]) return nil;
    for (UIView *sub in root.subviews) {
        UIView *found = findRowPart(sub, identifier, depth + 1, budget);
        if (found) return found;
    }
    return nil;
}

static void styleContentRow(UIView *cell) {
    CGSize size = cell.bounds.size;
    if (size.width < 250 || size.height < 44 || size.height > 100 || !cell.window) return;
    SGRContentRowParts *parts = objc_getAssociatedObject(cell, &kPartsKey);
    if (parts.title && [parts.title isDescendantOfView:cell]) {
        SGRStyleText(parts.title, SGRTextPrimary, nil);
        if ([parts.subtitle isDescendantOfView:cell]) SGRStyleText(parts.subtitle, SGRTextSecondary, SGRSecondary());
        return;
    }
    CFTimeInterval now = CACurrentMediaTime();
    if (parts && now - parts.scanned < 0.25) return;
    if (!parts) {
        parts = [SGRContentRowParts new];
        objc_setAssociatedObject(cell, &kPartsKey, parts, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    parts.scanned = now;
    NSUInteger budget = 40;
    UIView *title = findRowPart(cell, @"Track.Row.Content.Title", 0, &budget);
    if (!title) {
        budget = 40;
        title = findRowPart(cell, @"EncoreConsumerMobile.View.Granular.Title", 0, &budget);
    }
    if (!title) return;
    SGRStyleText(title, SGRTextPrimary, nil);
    budget = 40;
    UIView *subtitle = findRowPart(cell, @"Track.Row.Content.Subtitle", 0, &budget);
    if (!subtitle) {
        budget = 40;
        subtitle = findRowPart(cell, @"EncoreConsumerMobile.View.Granular.Subtitle", 0, &budget);
    }
    SGRStyleText(subtitle, SGRTextSecondary, SGRSecondary());
    parts.title = title;
    parts.subtitle = subtitle;
}

%hook UICollectionViewCell
- (void)layoutSubviews {
    %orig;
    styleContentRow((UIView *)self);
}
- (void)prepareForReuse {
    %orig;
    // A search result can be reused as a category/empty state without a track title.
    objc_setAssociatedObject(self, &kPartsKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
%end

%hook UITableViewCell
- (void)layoutSubviews {
    %orig;
    styleContentRow((UIView *)self);
}
- (void)prepareForReuse {
    %orig;
    objc_setAssociatedObject(self, &kPartsKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
}
