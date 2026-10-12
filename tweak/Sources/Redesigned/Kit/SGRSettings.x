// The mod's own pages already own their rows and use automatic heights. Give them system Settings
// type and switches only in Redesigned mode; actions and all preference reads/writes stay SGModPage's.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "SGRContentStyle.h"

%hook SGModPage
- (instancetype)initWithTitle:(NSString *)title intro:(NSString *)intro sections:(NSArray<SGModSection *> *)sections footer:(NSString *)footer {
    for (SGModSection *section in sections) {
        for (SGModRow *row in section.rows) row.glows = NO;
    }
    return %orig;
}

- (void)viewDidLoad {
    %orig;
    UITableView *table = ((UITableViewController *)self).tableView;
    table.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    table.backgroundColor = UIColor.blackColor;
    table.tintColor = SGRAccent();
    table.separatorColor = SGRHairline();
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = %orig;
    if ([cell.contentConfiguration isKindOfClass:UIListContentConfiguration.class]) {
        UIListContentConfiguration *content = [(UIListContentConfiguration *)cell.contentConfiguration copy];
        content.textProperties.font = SGRType(SGRTextPrimary);
        content.secondaryTextProperties.font = SGRType(SGRTextMetadata);
        content.textToSecondaryTextVerticalPadding = SGRSpace4;
        content.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(SGRSpace12, SGRSpace16, SGRSpace12, SGRSpace16);
        cell.contentConfiguration = content;
    }
    SGForEachView(cell.accessoryView, ^(UIView *view) {
        if ([view isKindOfClass:UISwitch.class]) ((UISwitch *)view).onTintColor = SGRAccent();
    });
    return cell;
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
}
