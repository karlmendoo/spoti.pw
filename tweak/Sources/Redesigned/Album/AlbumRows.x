// Album redesign: the track rows on the field, the way the Music app has them -- no surface of their own
// and a hairline from the text's edge between one row and the next.
//
// Tree (trees/clean/album/03.txt:524-575): every row of the page is an Element_List.CollectionViewCell
// holding an Encore.ListRow, id=Components.UI.RetrievalRowElementUI, with the title
// (EncoreConsumerMobile.View.Granular.Title), the artists under it (…Granular.Subtitle) and, at the
// trailing edge, Components.UI.ContextMenuButton. An album row carries no artwork -- every track on the
// page shares the cover the header is already showing -- so the hairline runs from the page's own margin,
// where the text starts.
//
// The row's paint is cleared here rather than left to the Kit's repaint hook, which only hears about a
// colour when Spotify sets it and not when a reused cell already carries one.
//
// Spotify's type and its spacing are left alone: the row is 56pt for a title of 13pt, and a larger font of
// the Kit's would be cut off by the box the element framework measured for it.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Album.h"

// Under the text rather than the whole row, as the Music app draws it; the trailing end clears the page
// margin.

static char kRowKey, kTitleKey, kSubtitleKey, kLineKey;

static void clearSurface(UIView *view) {
    UIColor *color = view.backgroundColor;
    if (color && SGIsBaseSurface(color.CGColor)) view.backgroundColor = UIColor.clearColor;
}

static void applyRow(UIView *cell) {
    clearSurface(cell);
    UIView *row = SGRFindByIdentifier(cell, @"Components.UI.RetrievalRow*", &kRowKey);
    if (!row) return;
    // The row, and every box the element framework wraps it in on the way back up to the cell.
    for (UIView *v = row; v; v = v.superview) {
        clearSurface(v);
        if (v == cell) break;
    }

    UIView *subtitle = SGRFindByIdentifier(row, @"EncoreConsumerMobile.View.Granular.Subtitle", &kSubtitleKey);
    SGForEachView(subtitle, ^(UIView *v) {
        if (![v isKindOfClass:UILabel.class]) return;
        UILabel *label = (UILabel *)v;
        if (![label.textColor isEqual:SGRSecondary()]) label.textColor = SGRSecondary();
    });

    SGRStyleText(SGRFindByIdentifier(row, @"EncoreConsumerMobile.View.Granular.Title", &kTitleKey), SGRTextPrimary, nil);
    SGRStyleText(subtitle, SGRTextSecondary, SGRSecondary());
    SGRStyleSeparator(row, &kLineKey, SGRSideMargin, SGRSideMargin);
}

// Which cells of Element_List belong to an album's track list, answered once per content class: the same
// cell class carries Home's sections and the album's footer too, and a walk up to the page on every pass of
// every cell is what the answer is cached to avoid.
static BOOL isTrackContent(UIView *content) {
    static NSMutableDictionary<id, NSNumber *> *answers;
    if (!answers) answers = [NSMutableDictionary dictionary];
    Class cls = object_getClass(content);
    if (!cls) return NO;
    NSNumber *answer = answers[(id<NSCopying>)cls];
    if (!answer) {
        answer = @([NSStringFromClass(cls) containsString:@"RetrievalListStructuredData"]);
        answers[(id<NSCopying>)cls] = answer;
    }
    return answer.boolValue;
}

%hook _TtC12Element_List18CollectionViewCell
- (void)layoutSubviews {
    %orig;
    UICollectionViewCell *cell = (UICollectionViewCell *)self;
    if (!isTrackContent(cell.contentView.subviews.firstObject)) return;
    if (SGRAlbumPageOf(cell)) applyRow(cell);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[@"_TtC12Element_List18CollectionViewCell"]);
}
