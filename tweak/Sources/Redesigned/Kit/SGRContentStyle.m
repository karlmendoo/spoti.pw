#import "Core/SGCore.h"
#import "SGRContentStyle.h"

void SGRStyleText(UIView *root, SGRTextRole role, UIColor *color) {
    if (!root) return;
    UIFont *preferred = SGRType(role);
    SGForEachView(root, ^(UIView *view) {
        if (![view isKindOfClass:UILabel.class]) return;
        UILabel *label = (UILabel *)view;
        // Spotify measures a fixed slot. Use semantic type only up to the height it can contain;
        // its marquee, explicit badges, text links and truncation continue to work as before.
        CGFloat height = label.bounds.size.height;
        if (height < 8) return;
        CGFloat size = MIN(preferred.pointSize, preferred.pointSize * height / preferred.lineHeight);
        UIFont *font = [UIFont fontWithDescriptor:preferred.fontDescriptor size:floor(size)];
        if (![label.font isEqual:font]) label.font = font;
        NSAttributedString *original = label.attributedText;
        if (original.length) {
            __block BOOL changed = NO;
            [original enumerateAttribute:NSFontAttributeName inRange:NSMakeRange(0, original.length) options:0
                usingBlock:^(id value, NSRange range, BOOL *stop) { if (![value isEqual:font]) changed = YES; }];
            if (changed) {
                NSMutableAttributedString *text = [original mutableCopy];
                [text addAttribute:NSFontAttributeName value:font range:NSMakeRange(0, text.length)];
                label.attributedText = text;
            }
        }
        // nil preserves the track's selected/playing colour, including the user's accent.
        if (color && ![label.textColor isEqual:color]) label.textColor = color;
    });
}

void SGRStyleArtwork(UIView *artwork, CGFloat radius) {
    CGFloat side = MIN(artwork.bounds.size.width, artwork.bounds.size.height);
    if (side < 1 || artwork.layer.cornerRadius >= side / 2 - 0.5) return;
    artwork.layer.cornerRadius = radius;
    artwork.layer.cornerCurve = kCACornerCurveContinuous;
    artwork.clipsToBounds = YES;
}

void SGRStyleMediaLabels(UIView *root) {
    __block UILabel *title = nil;
    NSMutableArray<UILabel *> *labels = [NSMutableArray array];
    SGForEachView(root, ^(UIView *view) {
        if (![view isKindOfClass:UILabel.class] || view.hidden || view.alpha < 0.01) return;
        UILabel *label = (UILabel *)view;
        if (label.font.pointSize < 10 || !label.text.length) return;
        [labels addObject:label];
        if (!title || CGRectGetMinY(SGFrameIn(label, root)) < CGRectGetMinY(SGFrameIn(title, root))) title = label;
    });
    for (UILabel *label in labels) SGRStyleText(label,
        label == title ? SGRTextPrimary : SGRTextSecondary, label == title ? nil : SGRSecondary());
}

void SGRStyleSeparator(UIView *row, const void *key, CGFloat leading, CGFloat trailing) {
    if (!row || !key) return;
    CALayer *line = objc_getAssociatedObject(row, key);
    if (!line) {
        line = [CALayer layer];
        line.zPosition = 1;
        objc_setAssociatedObject(row, key, line, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (line.superlayer != row.layer) [row.layer addSublayer:line];
    CGFloat pixel = 1 / MAX(1, row.window.screen.scale ?: UIScreen.mainScreen.scale);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    line.backgroundColor = SGRHairline().CGColor;
    line.frame = CGRectMake(leading, row.bounds.size.height - pixel,
        MAX(0, row.bounds.size.width - leading - trailing), pixel);
    [CATransaction commit];
}

void SGRStyleSheet(UIViewController *controller) {
    controller.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    // A custom Spotify sheet stays custom. A system sheet retains its existing detents and actions.
    UISheetPresentationController *sheet = controller.sheetPresentationController;
    if (!sheet) return;
    sheet.prefersGrabberVisible = YES;
    sheet.preferredCornerRadius = SGRRadiusSheet;
    sheet.prefersEdgeAttachedInCompactHeight = YES;
    sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = YES;
}
