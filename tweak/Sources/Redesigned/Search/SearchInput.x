// UIKit search controls on active search and in the mod's pages. Spotify retains delegates,
// text editing, recents, result grouping, cancel behavior, keyboard insets and navigation.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRTokens.h"

static void styleInput(UITextField *field) {
    if (!field.window || field.secureTextEntry) return;
    field.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    field.keyboardAppearance = UIKeyboardAppearanceDark;
    field.textColor = SGRPrimary();
    field.tintColor = SGRAccent();
    UIFont *font = SGRType(SGRTextPrimary);
    if (field.bounds.size.height >= font.lineHeight + SGRSpace8 && ![field.font isEqual:font]) field.font = font;
    NSAttributedString *placeholder = field.attributedPlaceholder;
    if (placeholder.length) {
        __block BOOL changed = NO;
        UIColor *color = SGRSecondary();
        [placeholder enumerateAttribute:NSForegroundColorAttributeName inRange:NSMakeRange(0, placeholder.length)
            options:0 usingBlock:^(id value, NSRange range, BOOL *stop) { if (![value isEqual:color]) changed = YES; }];
        if (changed) {
            NSMutableAttributedString *text = [placeholder mutableCopy];
            [text addAttribute:NSForegroundColorAttributeName value:color range:NSMakeRange(0, text.length)];
            field.attributedPlaceholder = text;
        }
    }
}

%hook UISearchBar
- (void)layoutSubviews {
    %orig;
    UISearchBar *bar = (UISearchBar *)self;
    if (!bar.window) return;
    bar.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    bar.tintColor = SGRAccent();
    styleInput(bar.searchTextField);
    bar.searchTextField.backgroundColor = [UIColor colorWithWhite:1 alpha:0.10];
    bar.searchTextField.layer.cornerRadius = SGRRadiusControl;
    bar.searchTextField.layer.cornerCurve = kCACornerCurveContinuous;
}
%end

%hook UITextField
- (void)layoutSubviews {
    %orig;
    UITextField *field = (UITextField *)self;
    // Plain Spotify inputs are included only when they explicitly advertise the Search action.
    if (field.returnKeyType == UIReturnKeySearch) styleInput(field);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
}
