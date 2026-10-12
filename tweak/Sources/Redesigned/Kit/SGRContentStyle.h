// Presentation of Spotify's measured content. No data source, action or constraint is replaced.
#import "SGRTokens.h"

void SGRStyleText(UIView *root, SGRTextRole role, UIColor *color);
void SGRStyleArtwork(UIView *artwork, CGFloat radius);
void SGRStyleMediaLabels(UIView *root);
void SGRStyleSeparator(UIView *row, const void *key, CGFloat leading, CGFloat trailing);
void SGRStyleSheet(UIViewController *controller);
