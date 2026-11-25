#import "SpotifyHomeLayout.h"
#import <CarPlay/CarPlay.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <math.h>

// These are the iOS 16 host's list model and its configured image-row controls.
// Test each optional getter at the call site. The source of every action is the
// displayed Spotify template. Only the presentation lives in this file.
@protocol CP26ListHost <NSObject>
@optional
- (CPListTemplate *)listTemplate;
- (UITableView *)tableView;
- (id)itemAtIndexPath:(NSIndexPath *)path;
- (NSUUID *)identifier;
- (NSArray *)imageTitles;
- (BOOL)isLimitingLists;
- (void (^)(NSInteger))selectGridItemBlock;
- (void (^)(void))selectTitleBlock;
@end

static BOOL CP26HomeEnabled;
static char sessionKey, rowKey, printKey;
static const NSUInteger maxTiles = 6;

static BOOL HostClass(id value, NSString *name) {
    Class cls = NSClassFromString(name);
    return cls && [value isKindOfClass:cls];
}

static id<CP26ListHost> Host(id value) {
    return (id<CP26ListHost>)value;
}

static CPListTemplate *List(UIViewController *vc) {
    id<CP26ListHost> host = Host(vc);
    return [host respondsToSelector:@selector(listTemplate)] ? host.listTemplate : nil;
}

static NSUUID *Identifier(id item) {
    return [item respondsToSelector:@selector(identifier)] ? Host(item).identifier : nil;
}

static UIViewController *ListController(UITableView *table) {
    id owner = table.delegate;
    if (HostClass(owner, @"CPSListTemplateViewController")) return owner;
    for (UIResponder *r = table.nextResponder; r; r = r.nextResponder)
        if (HostClass(r, @"CPSListTemplateViewController")) return (UIViewController *)r;
    return nil;
}

static UITabBarController *HomeTabs(UIViewController *list) {
    UITabBarController *tabs = list.tabBarController;
    if (!HostClass(tabs, @"CPSTabBarViewController") || tabs.selectedIndex != 0) return nil;
    UIViewController *first = tabs.viewControllers.firstObject;
    if (first == list) return tabs;
    if ([first isKindOfClass:UINavigationController.class]) {
        UINavigationController *nav = (UINavigationController *)first;
        if (nav.viewControllers.firstObject == list && nav.topViewController == list) return tabs;
    }
    return nil;
}

static BOOL CarWindow(UIWindow *window) {
    return window && !window.hidden &&
        [window.windowScene.session.role isEqualToString:@"UIWindowSceneSessionRoleCarPlay"];
}

static id Model(UITableView *table, NSIndexPath *path) {
    id<CP26ListHost> source = Host(table.dataSource);
    id<UITableViewDataSource> ds = table.dataSource;
    if (!path || !ds || path.section < 0 || path.row < 0) return nil;
    NSInteger sections = [ds respondsToSelector:@selector(numberOfSectionsInTableView:)] ?
        [ds numberOfSectionsInTableView:table] : 1;
    if (path.section >= sections) return nil;
    NSInteger rows = [ds tableView:table numberOfRowsInSection:path.section];
    if (path.row >= rows) return nil;
    id item = [source respondsToSelector:@selector(itemAtIndexPath:)] ? [source itemAtIndexPath:path] : nil;
    if ([item isKindOfClass:CPListImageRowItem.class] || [item isKindOfClass:CPListItem.class]) return item;
    // Some host revisions wrap their data source items. Use the public template
    // only when its section/row map agrees with the currently exposed table.
    CPListTemplate *list = List(ListController(table));
    if (list.assistantCellConfiguration || list.sections.count != (NSUInteger)sections) return nil;
    NSArray *items = list.sections[path.section].items;
    return items.count == (NSUInteger)rows ? items[path.row] : nil;
}

// A small, inert colour field sampled from exposed background in the reference.
// Drawing it as UITableView.backgroundView keeps it fixed as native rows scroll.
static UIImage *BackdropImage(void) {
    static UIImage *image;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        static const uint32_t palette[13 * 13] = {
    0x192c2f, 0x1e3133, 0x1e3538, 0x1d3b3e, 0x1d4043, 0x1d464a, 0x1d4b4e, 0x1d4e52, 0x1e5153, 0x1d5356, 0x1e5255, 0x203c46, 0x3f444c,
    0x1e3033, 0x1e3135, 0x1e363a, 0x1d3c3f, 0x1d4244, 0x1e474a, 0x1e4c4f, 0x1d5254, 0x1d5556, 0x1d5759, 0x1d5456, 0x1f3441, 0x373943,
    0x1e3135, 0x1e3336, 0x1d393c, 0x1e3e41, 0x1e4447, 0x1e4a4d, 0x1d4f52, 0x1d5657, 0x1e5c5c, 0x205e5e, 0x205155, 0x1f2c3e, 0x353842,
    0x1e3136, 0x1e3538, 0x1e3a3d, 0x1e4043, 0x1d4549, 0x1e4c4f, 0x1d5556, 0x215e5e, 0x286462, 0x2b6261, 0x24434d, 0x20253b, 0x353942,
    0x1e3338, 0x1e363a, 0x1e3b3f, 0x1d4144, 0x1d484b, 0x1e5153, 0x215c5c, 0x2a6563, 0x326965, 0x30585b, 0x253546, 0x20263f, 0x3b3e48,
    0x1f333a, 0x1e363b, 0x1e3b40, 0x1d4246, 0x1d4b4e, 0x1e5957, 0x296462, 0x356b67, 0x396765, 0x304652, 0x2e3552, 0x2d365b, 0x3a3f4f,
    0x1e3239, 0x1e363c, 0x1e3c41, 0x1d4449, 0x1e5051, 0x245e5c, 0x316864, 0x396867, 0x3b5c64, 0x3e4c69, 0x3e4973, 0x333f6a, 0x3b4052,
    0x1e323b, 0x1e353d, 0x1e3b43, 0x1d474c, 0x1f5557, 0x2a6460, 0x346465, 0x3c5967, 0x435672, 0x45537d, 0x3f4c7b, 0x364270, 0x3e4455,
    0x1e323b, 0x1e353f, 0x1e3c44, 0x1d484e, 0x21575a, 0x2c5e61, 0x325360, 0x405171, 0x495681, 0x414d7d, 0x394675, 0x374572, 0x3e4455,
    0x1f2f3e, 0x1e323f, 0x1d3d46, 0x1d474f, 0x214f5a, 0x27465b, 0x314162, 0x48537d, 0x455180, 0x3c4878, 0x394775, 0x33416d, 0x3d4252,
    0x20253b, 0x1f2e45, 0x1f3a4f, 0x1f3b55, 0x203856, 0x2a3c5e, 0x39446e, 0x414c7a, 0x3e4a7b, 0x3b4878, 0x364472, 0x2d3a63, 0x383d4c,
    0x21314f, 0x20355b, 0x223a68, 0x223868, 0x21335d, 0x2b3961, 0x3c4a76, 0x3b4877, 0x364273, 0x34416f, 0x2e3b66, 0x273358, 0x363b49,
    0x24446b, 0x23426e, 0x233f72, 0x253b75, 0x233670, 0x27356b, 0x323e73, 0x303c6d, 0x2c3966, 0x29365f, 0x253157, 0x212d4c, 0x363a45,
        };
        uint8_t pixels[13 * 13 * 4];
        for (NSUInteger i = 0; i < 13 * 13; i++) {
            pixels[4*i] = (palette[i] >> 16) & 255;
            pixels[4*i+1] = (palette[i] >> 8) & 255;
            pixels[4*i+2] = palette[i] & 255;
            pixels[4*i+3] = 255;
        }
        CFDataRef data = CFDataCreate(NULL, pixels, sizeof(pixels));
        CGDataProviderRef provider = CGDataProviderCreateWithCFData(data);
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGImageRef cg = CGImageCreate(13, 13, 8, 32, 13*4, space,
            kCGImageAlphaNoneSkipLast | kCGBitmapByteOrder32Big, provider,
            NULL, true, kCGRenderingIntentDefault);
        if (cg) { image = [UIImage imageWithCGImage:cg]; CGImageRelease(cg); }
        CGColorSpaceRelease(space);
        CGDataProviderRelease(provider);
        CFRelease(data);
    });
    return image;
}

// Compare small rendered RGB thumbnails across the differently sized versions
// that Spotify sends for the same artwork. Reject flat placeholders and ties.
static NSData *ArtworkPrint(UIImage *image) {
    if (!image.CGImage) return nil;
    id saved = objc_getAssociatedObject(image, &printKey);
    if (saved) return saved == NSNull.null ? nil : saved;
    enum { side = 10, pixels = side * side };
    uint8_t rgba[pixels*4] = {0}, rgb[pixels*3];
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(rgba, side, side, 8, side*4, space,
        kCGImageAlphaNoneSkipLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!ctx) return nil;
    CGContextSetInterpolationQuality(ctx, kCGInterpolationHigh);
    CGContextDrawImage(ctx, CGRectMake(0,0,side,side), image.CGImage);
    CGContextRelease(ctx);
    unsigned spread = 0;
    for (unsigned c = 0; c < 3; c++) {
        unsigned lo = 255, hi = 0;
        for (unsigned i = 0; i < pixels; i++) {
            unsigned v = rgba[4*i+c]; rgb[3*i+c] = v;
            lo = MIN(lo,v); hi = MAX(hi,v);
        }
        spread += hi-lo;
    }
    NSData *key = spread >= 60 ? [NSData dataWithBytes:rgb length:sizeof(rgb)] : nil;
    objc_setAssociatedObject(image, &printKey, key ?: (id)NSNull.null, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return key;
}

static double Difference(NSData *a, NSData *b) {
    if (!a || !b || a.length != b.length) return INFINITY;
    const uint8_t *x = a.bytes, *y = b.bytes;
    unsigned sum = 0;
    for (NSUInteger i = 0; i < a.length; i++) sum += abs((int)x[i]-(int)y[i]);
    return (double)sum / a.length;
}

static BOOL SameText(NSString *a, NSString *b) {
    return a == b || [(a ?: @"") isEqualToString:(b ?: @"")];
}

// UIKit can use the image's UUID as its spoken label on iOS 16.
static NSString *DisplayText(id value) {
    if (![value isKindOfClass:NSString.class]) return nil;
    NSString *text = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!text.length) return nil;
    static NSRegularExpression *identifier;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        identifier = [NSRegularExpression regularExpressionWithPattern:
            @"^(?:[0-9a-f]{8}(?:[- ]?[0-9a-f]{4}){3}[- ]?[0-9a-f]{12}|[0-9a-f -]{24,40}|spotify:[^ ]+)$"
            options:NSRegularExpressionCaseInsensitive error:nil];
    });
    return [identifier firstMatchInString:text options:0 range:NSMakeRange(0,text.length)] ? nil : text;
}

static CPListItem *MatchArtwork(UIImage *image, NSArray<CPListItem *> *options) {
    NSData *key = ArtworkPrint(image);
    if (!key) return nil;
    CPListItem *winner = nil;
    double best = INFINITY, next = INFINITY;
    for (CPListItem *candidate in options) {
        if (!DisplayText(candidate.text)) continue;
        double d = Difference(key, ArtworkPrint(candidate.image));
        if (d > 6.0) continue;
        BOOL same = winner && SameText(winner.text,candidate.text) &&
                               SameText(winner.detailText,candidate.detailText);
        if (d < best) {
            if (!same) next = MIN(next,best);
            best = d; winner = candidate;
        } else if (!same) next = MIN(next,d);
    }
    return best <= 4.0 && next-best >= 1.2 ? winner : nil;
}

@interface CP26HomeEntry : NSObject
@property(nonatomic,strong) UIImage *art;
@property(nonatomic,copy) NSString *title;
@property(nonatomic,copy) NSString *subtitle;
@property(nonatomic,strong) CPListItem *detail;
@property(nonatomic) NSInteger nativeIndex;
@property(nonatomic) BOOL enabled;
@end
@implementation CP26HomeEntry
@end

@interface CP26HomeShelf : NSObject
@property(nonatomic,copy) NSString *title;
@property(nonatomic,copy) NSArray<UIImage *> *nativeCovers;
@property(nonatomic,copy) NSArray<CPListItem *> *items;
@end
@implementation CP26HomeShelf
@end

@interface CP26RailIcon : NSObject
@property(nonatomic) CGAffineTransform transform;
@property(nonatomic,strong) UIColor *tint;
@property(nonatomic,strong) UIImage *original;
@property(nonatomic,strong) UIImage *templated;
@end
@implementation CP26RailIcon
@end

@interface CP26HomeSession : NSObject
@property(nonatomic,weak) UITableView *table;
@property(nonatomic,weak) UIViewController *home;
@property(nonatomic,weak) UITabBarController *tabs;
@property(nonatomic,weak) UIWindow *window;
@property(nonatomic,strong) UIView *nativeBackdrop;
@property(nonatomic,strong) UIImageView *backdrop;
@property(nonatomic) UITableViewCellSeparatorStyle nativeSeparator;
@property(nonatomic,strong) NSMapTable<UIImageView *,CP26RailIcon *> *railIcons;
@property(nonatomic,strong) NSMutableDictionary<NSUUID *,CP26HomeShelf *> *shelves;
@property(nonatomic,copy) NSArray<CPListItem *> *catalogue;
@property(nonatomic,strong) NSMutableOrderedSet<CPListItem *> *visitedItems;
@property(nonatomic,strong) NSMapTable<UITableViewCell *,id> *selectionBackgrounds;
@property(nonatomic) NSUInteger revision;
@property(nonatomic) BOOL reloadQueued;
// This request exists only after a person opens a Home heading or picks an
// expanded item. It is bound to the originating window, Home row and detail list.
@property(nonatomic,strong) NSUUID *requestedShelf;
@property(nonatomic,copy) NSString *requestedTitle;
@property(nonatomic,strong) CPListItem *requestedItem;
@property(nonatomic,weak) UIViewController *detailController;
@property(nonatomic) NSTimeInterval requestTime;
@end
@implementation CP26HomeSession
@end

static NSHashTable<CP26HomeSession *> *sessions;

static BOOL Limited(UITableView *table) {
    id<CP26ListHost> source = Host(table.dataSource);
    return [source respondsToSelector:@selector(isLimitingLists)] && [source isLimitingLists];
}

static NSArray<CPListItem *> *ShelfItems(CP26HomeSession *s, CPListImageRowItem *row) {
    NSUUID *key = Identifier(row);
    CP26HomeShelf *shelf = key ? s.shelves[key] : nil;
    if (!shelf) return nil;
    NSArray<UIImage *> *images = row.gridImages;
    BOOL same = SameText(shelf.title,row.text) && shelf.nativeCovers.count == images.count;
    for (NSUInteger i=0; same && i<MIN(images.count,maxTiles); i++) {
        UIImage *a = shelf.nativeCovers[i], *b = images[i];
        same = a == b || (a.CGImage && a.CGImage == b.CGImage) ||
               Difference(ArtworkPrint(a),ArtworkPrint(b)) <= 4.0;
    }
    if (same) return shelf.items;
    [s.shelves removeObjectForKey:key];
    return nil;
}

static void CancelRequest(CP26HomeSession *s) {
    s.requestedShelf = nil; s.requestedTitle = nil; s.requestedItem = nil;
    s.detailController = nil; s.requestTime = 0;
}

static void QueueLayout(CP26HomeSession *s) {
    if (s.reloadQueued) return;
    s.reloadQueued = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        s.reloadQueued = NO;
        UITableView *table = s.table;
        if (!CP26HomeEnabled || !table || objc_getAssociatedObject(table,&sessionKey) != s ||
            !HomeTabs(s.home) || !CarWindow(table.window)) return;
        [table reloadData];
    });
}

static void UpdateCatalogue(CP26HomeSession *s) {
    NSMutableArray<CPListItem *> *catalogue = [NSMutableArray array];
    for (UIViewController *child in s.tabs.viewControllers) {
        UIViewController *vc = child;
        if ([vc isKindOfClass:UINavigationController.class])
            vc = ((UINavigationController *)vc).viewControllers.firstObject;
        for (CPListSection *section in List(vc).sections) {
            for (id item in section.items) {
                if ([item isKindOfClass:CPListItem.class] && catalogue.count < 192)
                    [catalogue addObject:item];
            }
        }
    }
    for (CP26HomeShelf *shelf in s.shelves.allValues) [catalogue addObjectsFromArray:shelf.items];
    [catalogue addObjectsFromArray:s.visitedItems.array];
    s.catalogue = catalogue;
    s.revision++;
}

static CP26HomeSession *Session(UITableView *table) {
    if (!CP26HomeEnabled || !NSThread.isMainThread || !CarWindow(table.window) ||
        !HostClass(table,@"CPSTableView")) return nil;
    UIViewController *home = ListController(table);
    UITabBarController *tabs = HomeTabs(home);
    if (!tabs || Limited(table)) return nil;
    CP26HomeSession *s = objc_getAssociatedObject(table,&sessionKey);
    if (s) return s;
    // Don't alter a loading/empty list or a different template that has taken
    // over tab zero. Wait until the native data source actually has image rows.
    BOOL hasImages = NO;
    for (NSInteger section = 0; section < table.numberOfSections && !hasImages; section++) {
        NSInteger count = [table numberOfRowsInSection:section];
        for (NSInteger row = 0; row < MIN(count,6); row++) {
            if ([Model(table,[NSIndexPath indexPathForRow:row inSection:section])
                    isKindOfClass:CPListImageRowItem.class]) { hasImages = YES; break; }
        }
    }
    if (!hasImages) return nil;
    s = [CP26HomeSession new];
    s.table = table; s.home = home; s.tabs = tabs; s.window = table.window;
    s.shelves = [NSMutableDictionary dictionary];
    s.selectionBackgrounds = [NSMapTable weakToStrongObjectsMapTable];
    s.visitedItems = [NSMutableOrderedSet orderedSet];
    s.railIcons = [NSMapTable weakToStrongObjectsMapTable];
    s.nativeBackdrop = table.backgroundView;
    s.nativeSeparator = table.separatorStyle;
    s.backdrop = [[UIImageView alloc] initWithImage:BackdropImage()];
    s.backdrop.contentMode = UIViewContentModeScaleToFill;
    s.backdrop.isAccessibilityElement = NO;
    s.backdrop.userInteractionEnabled = NO;
    objc_setAssociatedObject(table,&sessionKey,s,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!sessions) sessions = [NSHashTable weakObjectsHashTable];
    [sessions addObject:s];
    table.backgroundView = s.backdrop;
    table.separatorStyle = UITableViewCellSeparatorStyleNone;
    UpdateCatalogue(s);
    QueueLayout(s);
    return s;
}

static BOOL IsShortcut(NSIndexPath *path) { return path.section == 0 && path.row == 0; }

typedef struct {
    CGFloat inset, gap, tile, thumb, art, tileHeight, header, title, subtitle;
    CGFloat captionGap, shortcutBottom, shelfBottom;
} HomeMetrics;

static HomeMetrics Metrics(CGFloat width) {
    // Measured in the reference's 482-pixel content column, scaled into points.
    CGFloat inset = 2;
    CGFloat inner = MAX(1,width-2*inset);
    CGFloat u = MIN(1.1,MAX(.48,inner/482.0));
    CGFloat gap = 8*u;
    return (HomeMetrics){inset,gap,(inner-gap)/2,31*u,(inner-5*gap)/6,
        43*u,26*u,13*u,13*u,3*u,12*u,7*u};
}

static CGFloat RowHeight(CGFloat width, BOOL shortcut, NSUInteger count) {
    HomeMetrics m = Metrics(width);
    if (shortcut) {
        NSUInteger rows = (MIN(count,maxTiles)+1)/2;
        return rows ? 2 + rows*m.tileHeight + (rows-1)*m.gap + m.shortcutBottom : 0;
    }
    return m.header + m.art + m.captionGap + m.title + m.subtitle + m.shelfBottom;
}

static CGFloat ColumnWidth(UITableView *table) {
    for (UIView *v in table.subviews)
        if (HostClass(v,@"UITableViewWrapperView") && v.bounds.size.width > 80)
            return v.bounds.size.width;
    return MAX(100,table.bounds.size.width - 54); // measured native arrow rail + leading inset
}

CGFloat CP26HomeHeight(UITableView *table, NSIndexPath *path, CGFloat original) {
    CP26HomeSession *s = objc_getAssociatedObject(table,&sessionKey);
    if (!CP26HomeEnabled || !s || !HomeTabs(s.home) || Limited(table)) return original;
    id model = Model(table,path);
    if ([model isKindOfClass:CPListItem.class]) {
        CPListItem *item = model;
        if (!item.image && !item.detailText.length && item.text.length)
            return MIN(original > 0 ? original : 44, 44);
    }
    CPListImageRowItem *row = model;
    if (![row isKindOfClass:CPListImageRowItem.class] || !row.gridImages.count) return original;
    NSUInteger count = ShelfItems(s,row).count;
    return ceil(RowHeight(ColumnWidth(table),IsShortcut(path),count ?: row.gridImages.count));
}

static void (^GridAction(UITableViewCell *cell))(NSInteger) {
    return [cell respondsToSelector:@selector(selectGridItemBlock)] ? Host(cell).selectGridItemBlock : nil;
}

static void (^HeadingAction(UITableViewCell *cell))(void) {
    return [cell respondsToSelector:@selector(selectTitleBlock)] ? Host(cell).selectTitleBlock : nil;
}

static NSArray<UIControl *> *NativeButtons(UITableViewCell *cell) {
    for (UIView *v in cell.subviews) {
        if (![v isKindOfClass:UIStackView.class]) continue;
        NSMutableArray *buttons = [NSMutableArray array];
        for (UIView *b in ((UIStackView *)v).arrangedSubviews)
            if (HostClass(b,@"CPUIHighlightButton") && [b isKindOfClass:UIControl.class])
                [buttons addObject:b];
        if (buttons.count) return buttons;
    }
    return @[];
}

static BOOL CanPress(UIControl *control) {
    return control.enabled && (control.allControlEvents &
        (UIControlEventTouchUpInside | UIControlEventPrimaryActionTriggered));
}

static void Press(UIControl *control) {
    if (!CanPress(control)) return;
    UIControlEvents events = control.allControlEvents;
    [control sendActionsForControlEvents:(events & UIControlEventTouchUpInside) ?
        UIControlEventTouchUpInside : UIControlEventPrimaryActionTriggered];
}

static UIControl *NativeHeading(UITableViewCell *cell) {
    for (UIView *v in cell.subviews)
        if (HostClass(v,@"CPUIHighlightButton") && [v isKindOfClass:UIControl.class])
            return (UIControl *)v;
    return nil;
}

static NSInteger NativeIndex(UIImage *image, NSArray<UIImage *> *images) {
    NSData *key = ArtworkPrint(image);
    if (!key) return NSNotFound;
    NSInteger hit = NSNotFound;
    for (NSUInteger i=0; i<images.count; i++) {
        if (Difference(key,ArtworkPrint(images[i])) > 4) continue;
        if (hit != NSNotFound) return NSNotFound;
        hit = (NSInteger)i;
    }
    return hit;
}

static NSString *AccessibleTitle(UIImage *image, UIControl *button, NSString *heading) {
    for (NSString *value in @[image.accessibilityLabel ?: @"", button.accessibilityLabel ?: @""]) {
        if (![value isKindOfClass:NSString.class] || !value.length || SameText(value,heading)) continue;
        NSString *s = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (DisplayText(s) && ![@[@"image", @"button", @"album artwork", @"artwork", @"cover art"]
                containsObject:s.lowercaseString]) return s;
    }
    return nil;
}

static NSArray<CP26HomeEntry *> *Entries(CPListImageRowItem *row, UITableViewCell *cell,
                                        CP26HomeSession *s) {
    NSArray<UIImage *> *images = row.gridImages;
    NSArray<CPListItem *> *details = ShelfItems(s,row);
    NSArray<UIControl *> *buttons = NativeButtons(cell);
    NSArray *titles = [row respondsToSelector:@selector(imageTitles)] ? Host(row).imageTitles : nil;
    if (![titles isKindOfClass:NSArray.class] || titles.count != images.count) titles = nil;
    // Some templates carry per-image display metadata in userInfo. Only
    // consume explicitly named fields and require a full one-to-one slot map.
    NSDictionary *info = [row.userInfo isKindOfClass:NSDictionary.class] ? row.userInfo : nil;
    NSArray *slots = info[@"items"];
    if (![slots isKindOfClass:NSArray.class] || slots.count != images.count) slots = nil;
    BOOL gridAction = GridAction(cell) != nil;
    BOOL hasHeader = HeadingAction(cell) != nil || CanPress(NativeHeading(cell));
    NSMutableArray *entries = [NSMutableArray array];
    NSUInteger count = MIN(maxTiles,details.count ?: images.count);
    for (NSUInteger i=0; i<count; i++) {
        CPListItem *detail = details.count ? details[i] : nil;
        NSInteger index = (NSInteger)i;
        if (detail) {
            // Never redirect a reordered detail item to a different Home slot.
            // Ambiguous or different covers use the verified native detail list.
            BOOL sameSlot = i < images.count && NativeIndex(detail.image,images) == (NSInteger)i &&
                MatchArtwork(images[i],details) == detail;
            if (!sameSlot) index = NSNotFound;
        }
        UIControl *native = index >= 0 && (NSUInteger)index < buttons.count ? buttons[index] : nil;
        BOOL direct = index != NSNotFound && (gridAction || CanPress(native));
        if (!direct && !(detail && hasHeader)) continue;
        UIImage *art = detail.image ?: (index != NSNotFound ? images[index] : nil);
        CPListItem *caption = detail ?: MatchArtwork(art,s.catalogue);
        CP26HomeEntry *entry = [CP26HomeEntry new];
        entry.art = art;
        id slot = index != NSNotFound && (NSUInteger)index < slots.count ? slots[index] : nil;
        NSDictionary *metadata = [slot isKindOfClass:NSDictionary.class] ? slot : nil;
        entry.title = DisplayText(caption.text) ?: DisplayText(metadata[@"title"]) ?:
            DisplayText(metadata[@"name"]) ?:
            (index != NSNotFound && (NSUInteger)index < titles.count ? DisplayText(titles[index]) : nil) ?:
            AccessibleTitle(art,native,row.text);
        entry.subtitle = DisplayText(caption.detailText) ?: DisplayText(metadata[@"artist"]) ?: DisplayText(metadata[@"subtitle"]);
        entry.nativeIndex = direct ? index : NSNotFound;
        entry.detail = detail;
        entry.enabled = row.isEnabled && (!detail || detail.isEnabled);
        [entries addObject:entry];
    }
    return entries;
}

// The native table remains the scroll/focus container, including its arrow rail.
// Each visible button corresponds to a real selectable entry from the current row.
@interface CP26HomeButton : UIButton
@property(nonatomic,strong) UIImageView *cover;
@property(nonatomic,strong) UILabel *caption;
@property(nonatomic,strong) UILabel *byline;
@property(nonatomic,strong) UILongPressGestureRecognizer *sectionHold;
@property(nonatomic) BOOL shortcut;
@end

@implementation CP26HomeButton
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _cover = [UIImageView new];
        _cover.contentMode = UIViewContentModeScaleAspectFill;
        _cover.clipsToBounds = YES;
        _caption = [UILabel new];
        _caption.textColor = UIColor.whiteColor;
        _byline = [UILabel new];
        _byline.textColor = [UIColor colorWithWhite:1 alpha:.72];
        for (UIView *v in @[_cover,_caption,_byline]) {
            v.userInteractionEnabled = NO; v.isAccessibilityElement = NO;
            [self addSubview:v];
        }
        self.isAccessibilityElement = YES;
        self.layer.cornerCurve = kCACornerCurveContinuous;
    }
    return self;
}
- (BOOL)canBecomeFocused { return self.enabled; }
- (void)paint {
    BOOL focused = self.isFocused || self.isHighlighted;
    self.backgroundColor = focused ? [UIColor colorWithWhite:1 alpha:.30] :
        (self.shortcut ? [UIColor colorWithWhite:1 alpha:.155] : UIColor.clearColor);
    self.layer.borderWidth = self.isFocused ? 1.5 : 0;
    self.layer.borderColor = UIColor.whiteColor.CGColor;
    self.alpha = self.enabled ? 1 : .48;
}
- (void)setHighlighted:(BOOL)highlighted { [super setHighlighted:highlighted]; [self paint]; }
- (void)didUpdateFocusInContext:(UIFocusUpdateContext *)context
       withAnimationCoordinator:(UIFocusAnimationCoordinator *)coordinator {
    [super didUpdateFocusInContext:context withAnimationCoordinator:coordinator]; [self paint];
}
@end

@interface CP26HomeRow : UIView
@property(nonatomic,weak) UITableViewCell *cell;
@property(nonatomic,weak) CP26HomeSession *session;
@property(nonatomic,strong) CPListImageRowItem *model;
@property(nonatomic,strong) NSArray<CP26HomeEntry *> *entries;
@property(nonatomic,strong) NSMutableArray<CP26HomeButton *> *buttons;
@property(nonatomic,strong) UIButton *heading;
@property(nonatomic,strong) UILabel *headingText;
@property(nonatomic,strong) UIImageView *chevron;
@property(nonatomic,strong) NSMapTable<UIView *,NSNumber *> *alphaBefore;
@property(nonatomic,strong) UIColor *colorBefore;
@property(nonatomic) BOOL opaqueBefore;
@property(nonatomic) UITableViewCellSelectionStyle selectionBefore;
@property(nonatomic) BOOL accessibilityBefore;
@property(nonatomic,copy) NSArray *elementsBefore;
@property(nonatomic) BOOL shortcut;
@property(nonatomic) BOOL needsContent;
@property(nonatomic) NSUInteger revision;
@end

@implementation CP26HomeRow
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _buttons = [NSMutableArray array];
        _alphaBefore = [NSMapTable weakToStrongObjectsMapTable];
        _heading = [UIButton buttonWithType:UIButtonTypeCustom];
        _heading.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        _headingText = [UILabel new]; _headingText.textColor = UIColor.whiteColor;
        _headingText.isAccessibilityElement = NO;
        _chevron = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right"]];
        _chevron.contentMode = UIViewContentModeScaleAspectFit;
        _chevron.tintColor = [UIColor colorWithWhite:1 alpha:.75];
        [_heading addSubview:_headingText]; [_heading addSubview:_chevron];
        [_heading addTarget:self action:@selector(openHeading) forControlEvents:UIControlEventPrimaryActionTriggered];
        [self addSubview:_heading];
        self.backgroundColor = UIColor.clearColor;
        self.isAccessibilityElement = NO;
    }
    return self;
}
- (CPListImageRowItem *)currentModel {
    UITableView *table = self.session.table;
    if (!CP26HomeEnabled || !self.window || !HomeTabs(self.session.home) ||
        Limited(table) || self.needsContent) return nil;
    id current = Model(table,[table indexPathForCell:self.cell]);
    if (![current isKindOfClass:CPListImageRowItem.class] || ![(CPListImageRowItem *)current isEnabled])
        return nil;
    return current == self.model || [Identifier(current) isEqual:Identifier(self.model)] ? current : nil;
}
- (void)openShelfSelecting:(CPListItem *)desired {
    CPListImageRowItem *current = [self currentModel];
    if (!current) return;
    UITableViewCell *cell = self.cell;
    void (^action)(void) = HeadingAction(cell);
    UIControl *native = NativeHeading(cell);
    if (!action && !CanPress(native)) return;
    CP26HomeSession *s = self.session;
    CancelRequest(s);
    s.requestedShelf = Identifier(current); s.requestedTitle = current.text;
    s.requestedItem = desired; s.requestTime = CACurrentMediaTime();
    if (action) action(); else Press(native);
}
- (void)openHeading { [self openShelfSelecting:nil]; }
- (BOOL)accessibilityOpenHeading:(UIAccessibilityCustomAction *)action {
    if (![self currentModel]) return NO;
    [self openHeading]; return YES;
}
- (void)heldShortcut:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) [self openHeading];
}
- (void)selectEntry:(UIButton *)sender {
    CPListImageRowItem *current = [self currentModel];
    if (!current || sender.tag < 0 || (NSUInteger)sender.tag >= self.entries.count) return;
    CP26HomeEntry *entry = self.entries[sender.tag];
    if (!entry.enabled) return;
    CancelRequest(self.session);
    NSInteger index = entry.nativeIndex;
    NSArray<UIImage *> *images = current.gridImages;
    if (index != NSNotFound && (NSUInteger)index < images.count) {
        UIImage *liveImage = images[index];
        if (entry.art && entry.art != liveImage && !(entry.art.CGImage && entry.art.CGImage == liveImage.CGImage) &&
            Difference(ArtworkPrint(entry.art),ArtworkPrint(liveImage)) > 4.0) {
            CP26HomeInvalidateRow(self.cell); return;
        }
        void (^action)(NSInteger) = GridAction(self.cell);
        if (action) { action(index); return; }
        NSArray *buttons = NativeButtons(self.cell);
        if ((NSUInteger)index < buttons.count && CanPress(buttons[index])) {
            Press(buttons[index]); return;
        }
    }
    if (entry.detail) [self openShelfSelecting:entry.detail];
}
- (void)configure {
    NSArray *entries = Entries(self.model,self.cell,self.session);
    self.entries = entries;
    self.heading.hidden = self.shortcut;
    self.headingText.text = self.model.text;
    self.heading.enabled = self.model.isEnabled &&
        (HeadingAction(self.cell) || CanPress(NativeHeading(self.cell)));
    self.heading.accessibilityLabel = self.model.text;
    while (self.buttons.count > entries.count) {
        [self.buttons.lastObject removeFromSuperview]; [self.buttons removeLastObject];
    }
    for (NSUInteger i = 0; i < entries.count; i++) {
        CP26HomeButton *b;
        if (i < self.buttons.count) b = self.buttons[i];
        else {
            b = [[CP26HomeButton alloc] initWithFrame:CGRectZero];
            [b addTarget:self action:@selector(selectEntry:) forControlEvents:UIControlEventPrimaryActionTriggered];
            UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc]
                initWithTarget:self action:@selector(heldShortcut:)];
            hold.cancelsTouchesInView = YES; [b addGestureRecognizer:hold]; b.sectionHold = hold;
            [self.buttons addObject:b]; [self addSubview:b];
        }
        CP26HomeEntry *entry = entries[i];
        b.tag = i; b.shortcut = self.shortcut; b.enabled = entry.enabled;
        b.cover.image = entry.art; b.caption.text = entry.title; b.byline.text = entry.subtitle;
        b.caption.numberOfLines = self.shortcut ? 2 : 1;
        b.caption.lineBreakMode = NSLineBreakByTruncatingTail;
        b.byline.hidden = self.shortcut || !entry.subtitle.length;
        b.sectionHold.enabled = self.shortcut && self.heading.enabled;
        b.accessibilityLabel = entry.title.length ? entry.title : [NSString stringWithFormat:@"%@, %lu",
            self.model.text ?: @"Spotify", (unsigned long)i+1];
        b.accessibilityValue = entry.subtitle;
        b.accessibilityCustomActions = self.shortcut && self.heading.enabled ? @[
            [[UIAccessibilityCustomAction alloc] initWithName:self.model.text ?: @"Open section"
                target:self selector:@selector(accessibilityOpenHeading:)]] : nil;
        [b paint];
    }
    NSMutableArray *targets = [NSMutableArray array];
    if (!self.shortcut) [targets addObject:self.heading];
    [targets addObjectsFromArray:self.buttons];
    self.cell.isAccessibilityElement = NO;
    self.cell.accessibilityElements = targets;
    self.revision = self.session.revision; self.needsContent = NO;
    [self setNeedsLayout];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    HomeMetrics m = Metrics(self.bounds.size.width);
    CGFloat u = m.tileHeight / 43;

    self.headingText.font = [UIFont systemFontOfSize:16*u weight:UIFontWeightSemibold];
    CGFloat textWidth = MIN(MAX(0,self.bounds.size.width-2*m.inset-20*u),
        ceil([self.headingText sizeThatFits:CGSizeMake(CGFLOAT_MAX,m.header)].width));
    self.heading.frame = CGRectMake(m.inset,0,MIN(self.bounds.size.width,textWidth+22*u),m.header);
    self.headingText.frame = CGRectMake(0,0,textWidth,m.header);
    self.chevron.frame = CGRectMake(textWidth+5*u,(m.header-12*u)/2,8*u,12*u);
    for (NSUInteger i=0; i<self.buttons.count; i++) {
        CP26HomeButton *b = self.buttons[i];
        b.caption.font = [UIFont systemFontOfSize:(self.shortcut ? 13.6 : 10.9)*u
            weight:self.shortcut ? UIFontWeightMedium : UIFontWeightSemibold];
        b.byline.font = [UIFont systemFontOfSize:10.7*u weight:UIFontWeightRegular];
        if (self.shortcut) {
            b.frame = CGRectMake(m.inset+(i%2)*(m.tile+m.gap),2+(i/2)*(m.tileHeight+m.gap),m.tile,m.tileHeight);
            b.layer.cornerRadius = 9*u;
            b.cover.frame = CGRectMake(6*u,(m.tileHeight-m.thumb)/2,m.thumb,m.thumb);
            b.cover.layer.cornerRadius = 5*u;
            CGFloat x = CGRectGetMaxX(b.cover.frame)+6*u;
            b.caption.frame = CGRectMake(x,0,MAX(0,m.tile-x-5*u),m.tileHeight);
        } else {
            b.frame = CGRectMake(m.inset+i*(m.art+m.gap),m.header,m.art,m.art+m.captionGap+m.title+m.subtitle);
            b.layer.cornerRadius = 4*u;
            b.cover.frame = CGRectMake(0,0,m.art,m.art); b.cover.layer.cornerRadius = 5*u;
            b.caption.frame = CGRectMake(0,m.art+m.captionGap,m.art,m.title);
            b.byline.frame = CGRectMake(0,m.art+m.captionGap+m.title,m.art,m.subtitle);
        }
    }
}
@end

void CP26HomeRestoreRow(UITableViewCell *cell) {
    CP26HomeRow *row = objc_getAssociatedObject(cell,&rowKey);
    if (!row) return;
    for (UIView *child in row.alphaBefore.keyEnumerator)
        child.alpha = [row.alphaBefore objectForKey:child].doubleValue;
    cell.backgroundColor = row.colorBefore; cell.opaque = row.opaqueBefore;
    cell.selectionStyle = row.selectionBefore;
    cell.accessibilityElements = row.elementsBefore; cell.isAccessibilityElement = row.accessibilityBefore;
    [row removeFromSuperview];
    objc_setAssociatedObject(cell,&rowKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

void CP26HomeInvalidateRow(UITableViewCell *cell) {
    CP26HomeRow *row = objc_getAssociatedObject(cell,&rowKey);
    if (row) { row.needsContent = YES; [cell setNeedsLayout]; }
}

void CP26HomeLayoutRow(UITableViewCell *cell) {
    if (!NSThread.isMainThread) return;
    CP26HomeRow *row = objc_getAssociatedObject(cell,&rowKey);
    if (!CP26HomeEnabled || !CarWindow(cell.window)) { if (row) CP26HomeRestoreRow(cell); return; }
    UITableView *table = row.session.table;
    if (!table || ![cell isDescendantOfView:table]) {
        for (UIView *v = cell.superview; v; v = v.superview) {
            if ([v isKindOfClass:UITableView.class]) { table = (UITableView *)v; break; }
        }
    }
    CP26HomeSession *s = table ? objc_getAssociatedObject(table,&sessionKey) : nil;
    NSIndexPath *path = s && HomeTabs(s.home) && !Limited(table) ? [table indexPathForCell:cell] : nil;
    CPListImageRowItem *model = path ? Model(table,path) : nil;
    if (![model isKindOfClass:CPListImageRowItem.class]) { if (row) CP26HomeRestoreRow(cell); return; }
    if (!row) {
        row = [[CP26HomeRow alloc] initWithFrame:cell.bounds]; row.cell = cell;
        row.opaqueBefore = cell.opaque; row.colorBefore = cell.backgroundColor;
        row.selectionBefore = cell.selectionStyle;
        row.accessibilityBefore = cell.isAccessibilityElement; row.elementsBefore = cell.accessibilityElements;
        row.needsContent = YES;
        objc_setAssociatedObject(cell,&rowKey,row,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    BOOL shortcut = IsShortcut(path);
    if (row.needsContent || row.model != model || row.session != s ||
        row.shortcut != shortcut || row.revision != s.revision) {
        row.session = s; row.model = model; row.shortcut = shortcut;
        [row configure];
    }
    if (!row.entries.count) { CP26HomeRestoreRow(cell); return; }
    if (row.superview != cell) [cell addSubview:row];
    if (cell.subviews.lastObject != row) [cell bringSubviewToFront:row];
    for (UIView *child in cell.subviews) {
        if (child == row) continue;
        if (![row.alphaBefore objectForKey:child]) [row.alphaBefore setObject:@(child.alpha) forKey:child];
        if (child.alpha != 0) child.alpha = 0;
    }
    if (cell.selectionStyle != UITableViewCellSelectionStyleNone) cell.selectionStyle = UITableViewCellSelectionStyleNone;
    if (cell.opaque) cell.opaque = NO;
    if (![cell.backgroundColor isEqual:UIColor.clearColor]) cell.backgroundColor = UIColor.clearColor;
    if (!CGRectEqualToRect(row.frame,cell.bounds)) row.frame = cell.bounds;
}

NSArray *CP26HomeFocusTargets(UITableViewCell *cell) {
    CP26HomeRow *row = objc_getAssociatedObject(cell,&rowKey);
    return row.superview == cell && CP26HomeEnabled ? cell.accessibilityElements : nil;
}

void CP26HomeNativeSelection(UITableView *table) {
    for (CP26HomeSession *s in sessions.allObjects)
        if (s.requestedItem && table != s.table && table.window == s.window) s.requestedItem = nil;
}

static UITableView *NativeTable(UIViewController *vc) {
    if (!vc.isViewLoaded) return nil;
    UITableView *t = [vc respondsToSelector:@selector(tableView)] ? Host(vc).tableView : nil;
    if (HostClass(t,@"CPSTableView")) return t;
    if (HostClass(vc.viewIfLoaded,@"CPSTableView")) return (UITableView *)vc.viewIfLoaded;
    for (UIView *child in vc.viewIfLoaded.subviews)
        if (HostClass(child,@"CPSTableView")) return (UITableView *)child;
    return nil;
}

static BOOL DetailVisible(UIViewController *vc, CP26HomeSession *s) {
    if (!vc || vc == s.home || HomeTabs(vc) || s.tabs.selectedIndex != 0 ||
        vc.viewIfLoaded.window != s.window || !CarWindow(s.window)) return NO;
    if ([s.tabs.viewControllers containsObject:vc]) return NO;
    UINavigationController *nav = vc.navigationController;
    if (nav && nav.topViewController != vc && nav.topViewController != vc.parentViewController) return NO;
    for (UIView *v=vc.viewIfLoaded; v; v=v.superview) if (v.hidden || v.alpha < .01) return NO;
    return YES;
}

static BOOL SameDetailItem(CPListItem *a, CPListItem *b) {
    NSUUID *identifier = Identifier(a);
    if (identifier && [identifier isEqual:Identifier(b)]) return YES;
    if (!a.text.length || !SameText(a.text,b.text) || !SameText(a.detailText,b.detailText)) return NO;
    NSData *p = ArtworkPrint(a.image), *q = ArtworkPrint(b.image);
    return !p || !q || Difference(p,q) <= 4.0;
}

static CPListImageRowItem *RequestedRow(CP26HomeSession *s) {
    for (CPListSection *section in List(s.home).sections) {
        for (id item in section.items)
            if ([item isKindOfClass:CPListImageRowItem.class] &&
                [Identifier(item) isEqual:s.requestedShelf]) return item;
    }
    return nil;
}

// Read the same rows CarPlay currently exposes, including vehicle list limits.
// Never open a template to collect data. Only the user's own navigation arms this.
static void ReadDetail(CP26HomeSession *s, UIViewController *vc, UITableView *table) {
    if (!s.requestedShelf || !DetailVisible(vc,s) || !table || table.window != s.window ||
        (s.detailController && s.detailController != vc)) return;
    NSTimeInterval elapsed = CACurrentMediaTime()-s.requestTime;
    if (!s.detailController && elapsed > 10) { CancelRequest(s); return; }
    if (elapsed > 4) s.requestedItem = nil;
    CPListImageRowItem *origin = RequestedRow(s);
    if (!origin) { CancelRequest(s); return; }
    CPListTemplate *list = List(vc);
    NSMutableArray<CPListItem *> *first = [NSMutableArray array];
    NSIndexPath *match = nil;
    NSUInteger matches = 0, seen = 0;
    NSUInteger budget = s.requestedItem ? NSUIntegerMax : 64;
    for (NSInteger section = 0; section < table.numberOfSections && seen < budget; section++) {
        NSInteger count = [table numberOfRowsInSection:section];
        for (NSInteger row = 0; row<count && seen<budget; row++,seen++) {
            NSIndexPath *path = [NSIndexPath indexPathForRow:row inSection:section];
            CPListItem *item = Model(table,path);
            if (![item isKindOfClass:CPListItem.class] || !item.text.length) continue;
            if (first.count < maxTiles && item.image && !item.image.isSymbolImage) [first addObject:item];
            if (s.requestedItem && SameDetailItem(s.requestedItem,item)) { match = path; matches++; }
        }
    }
    if (!first.count) return;
    // A custom Spotify list may use a different navigation title. In that case
    // require two distinct native covers in common before associating the list.
    BOOL titleMatches = list.title.length && s.requestedTitle.length &&
        [list.title caseInsensitiveCompare:s.requestedTitle] == NSOrderedSame;
    if (!titleMatches) {
        NSMutableIndexSet *overlap = [NSMutableIndexSet indexSet];
        NSArray *images = origin.gridImages;
        for (CPListItem *item in first) {
            NSInteger i = NativeIndex(item.image,images);
            if (i != NSNotFound) [overlap addIndex:(NSUInteger)i];
        }
        if (overlap.count < 2) return;
    }
    s.detailController = vc;
    CP26HomeShelf *shelf = [CP26HomeShelf new];
    shelf.title = origin.text; shelf.nativeCovers = origin.gridImages; shelf.items = first;
    // A partially loaded detail page must not shrink an already populated Home row.
    NSUInteger previous = s.shelves[s.requestedShelf].items.count;
    if (first.count >= MAX(previous,MIN(maxTiles,origin.gridImages.count))) {
        s.shelves[s.requestedShelf] = shelf;
        s.revision++;
    }
    if (table.dragging || table.tracking || Limited(table) || Limited(s.table)) s.requestedItem = nil;
    if (!s.requestedItem || matches != 1) return;
    CPListItem *live = Model(table,match);
    if (![live isKindOfClass:CPListItem.class] || !live.isEnabled || !table.allowsSelection ||
        !SameDetailItem(s.requestedItem,live) ||
        ![table.delegate respondsToSelector:@selector(tableView:didSelectRowAtIndexPath:)]) return;
    CancelRequest(s); // disarm before Spotify can push a template or start playback
    [table selectRowAtIndexPath:match animated:NO scrollPosition:UITableViewScrollPositionNone];
    [table.delegate tableView:table didSelectRowAtIndexPath:match];
}

static void StyleRail(CP26HomeSession *s) {
    for (UIView *bar in s.table.subviews) {
        if (!HostClass(bar,@"_UIStaticScrollBar")) continue;
        for (UIView *button in bar.subviews) {
            if (!HostClass(button,@"_UIStaticScrollbarButton")) continue;
            for (UIImageView *v in button.subviews) {
                if (![v isKindOfClass:UIImageView.class] || !v.image) continue;
                CP26RailIcon *saved = [s.railIcons objectForKey:v];
                if (!saved) {
                    saved = [CP26RailIcon new]; saved.transform = v.transform; saved.tint = v.tintColor;
                    [s.railIcons setObject:saved forKey:v];
                }
                if (v.image != saved.templated) {
                    saved.original = v.image;
                    saved.templated = [v.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
                    if (v.image != saved.templated) v.image = saved.templated;
                }
                CGAffineTransform target = CGAffineTransformScale(saved.transform,.53,.53);
                if (!CGAffineTransformEqualToTransform(v.transform,target)) v.transform = target;
                UIColor *tint = [UIColor colorWithWhite:1 alpha:.72];
                if (![v.tintColor isEqual:tint]) v.tintColor = tint;
            }
        }
    }
}

static void RestoreSelection(CP26HomeSession *s, UITableViewCell *cell) {
    id saved = [s.selectionBackgrounds objectForKey:cell];
    if (!saved) return;
    cell.backgroundConfiguration = saved == NSNull.null ? nil : saved;
    [s.selectionBackgrounds removeObjectForKey:cell];
}

static void StyleSelection(CP26HomeSession *s, UITableViewCell *cell) {
    CPListItem *item = Model(s.table,[s.table indexPathForCell:cell]);
    if (![item isKindOfClass:CPListItem.class] || item.image || item.detailText.length || !item.text.length) {
        RestoreSelection(s,cell);
        return;
    }
    if (![s.selectionBackgrounds objectForKey:cell])
        [s.selectionBackgrounds setObject:((id)cell.backgroundConfiguration ?: NSNull.null) forKey:cell];
    UIBackgroundConfiguration *background = [UIBackgroundConfiguration clearConfiguration];
    BOOL light = cell.traitCollection.userInterfaceStyle == UIUserInterfaceStyleLight;
    CGFloat alpha = cell.isFocused || cell.isHighlighted || cell.isSelected ? .75 : (light ? .72 : .16);
    background.backgroundColor = [UIColor colorWithWhite:1 alpha:alpha];
    background.cornerRadius = 9;
    background.backgroundInsets = NSDirectionalEdgeInsetsMake(2,2,2,2);
    if (![cell.backgroundConfiguration isEqual:background]) cell.backgroundConfiguration = background;
}

static void Detach(CP26HomeSession *s) {
    for (UITableViewCell *cell in s.selectionBackgrounds.keyEnumerator.allObjects) RestoreSelection(s,cell);
    UITableView *table = s.table;
    CancelRequest(s);
    for (UITableViewCell *cell in table.visibleCells) CP26HomeRestoreRow(cell);
    for (UIImageView *v in s.railIcons.keyEnumerator) {
        CP26RailIcon *saved = [s.railIcons objectForKey:v];
        v.transform = saved.transform; v.tintColor = saved.tint;
        if (v.image == saved.templated) v.image = saved.original;
    }
    if (table.backgroundView == s.backdrop) table.backgroundView = s.nativeBackdrop;
    table.separatorStyle = s.nativeSeparator;
    if (table) objc_setAssociatedObject(table,&sessionKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [sessions removeObject:s];
}

void CP26HomeTableLayout(UITableView *table) {
    if (!CP26HomeEnabled || !NSThread.isMainThread) return;
    if (table.tracking || table.dragging)
        for (CP26HomeSession *s in sessions.allObjects)
            if (s.requestedItem && table != s.table && table.window == s.window) s.requestedItem = nil;
    CP26HomeSession *prior = objc_getAssociatedObject(table,&sessionKey);
    if (prior && (Limited(table) || prior.home != ListController(table) ||
                  (table.window && prior.window != table.window))) {
        Detach(prior);
        dispatch_async(dispatch_get_main_queue(), ^{ [table reloadData]; });
        return;
    }
    CP26HomeSession *s = Session(table);
    if (!s) return;
    StyleRail(s);
    NSArray *visible = table.visibleCells;
    for (UITableViewCell *cell in s.selectionBackgrounds.keyEnumerator.allObjects)
        if (![visible containsObject:cell] || !HomeTabs(s.home)) RestoreSelection(s,cell);
    if (!HomeTabs(s.home)) return;
    for (UITableViewCell *cell in visible) {
        if (!HostClass(cell,@"CPSImageRowCell")) { StyleSelection(s,cell); continue; }
        CP26HomeRow *row = objc_getAssociatedObject(cell,&rowKey);
        if (!row || row.needsContent || row.revision != s.revision) CP26HomeLayoutRow(cell);
    }
}

void CP26HomeListAppeared(UIViewController *vc) {
    if (!CP26HomeEnabled || !NSThread.isMainThread || !CarWindow(vc.viewIfLoaded.window)) return;
    UITableView *table = NativeTable(vc);
    CP26HomeSession *home = table ? Session(table) : nil;
    if (home) {
        CancelRequest(home);
        UpdateCatalogue(home);
        QueueLayout(home);
        return;
    }
    for (CP26HomeSession *s in sessions.allObjects) {
        if (s.window != vc.viewIfLoaded.window) continue;
        if (s.tabs.selectedIndex != 0) { CancelRequest(s); continue; }
        ReadDetail(s,vc,table);
    }
}

void CP26HomeListDisappeared(UIViewController *vc) {
    // Retain display metadata from lists the user actually visited, including
    // Recents and Library. Match by artwork only when the match is unambiguous.
    for (CP26HomeSession *s in sessions.allObjects) {
        if (vc == s.home || vc.tabBarController != s.tabs) continue;
        for (CPListSection *section in List(vc).sections) {
            for (CPListItem *item in section.items) {
                if (![item isKindOfClass:CPListItem.class] || !item.image || !DisplayText(item.text)) continue;
                [s.visitedItems addObject:item];
                if (s.visitedItems.count > 192) [s.visitedItems removeObjectAtIndex:0];
            }
        }
    }
    for (CP26HomeSession *s in sessions.allObjects)
        if (s.detailController == vc) CancelRequest(s);
}

void CP26HomeTableReloaded(UITableView *table) {
    if (!CP26HomeEnabled || !NSThread.isMainThread) return;
    CP26HomeSession *home = objc_getAssociatedObject(table,&sessionKey);
    if (home) home.revision++;
    // Detail lists can arrive after viewDidAppear. Recheck only while a user
    // navigation to this particular shelf is pending.
    for (CP26HomeSession *s in sessions.allObjects) {
        if (!s.requestedShelf || table == s.table || !CarWindow(table.window)) continue;
        __weak UITableView *weakTable = table;
        dispatch_async(dispatch_get_main_queue(), ^{
            UITableView *t = weakTable;
            if (CP26HomeEnabled && s.requestedShelf && t.window == s.window)
                ReadDetail(s,ListController(t),t);
        });
    }
}

void CP26HomeSetEnabled(BOOL enabled) {
    if (!NSThread.isMainThread || CP26HomeEnabled == enabled) return;
    CP26HomeEnabled = enabled;
    if (enabled) return;
    for (CP26HomeSession *s in sessions.allObjects) {
        UITableView *table = s.table;
        Detach(s);
        [table reloadData];
    }
    [sessions removeAllObjects];
}

void CP26HomeAppendReport(NSMutableString *report) {
    [report appendFormat:@"\nSPOTIFY_HOME_LAYOUT enabled=%d\n",CP26HomeEnabled];
    for (CP26HomeSession *s in sessions.allObjects) {
        if (!HomeTabs(s.home) || !CarWindow(s.table.window)) continue;
        [report appendFormat:@"HOME tableWidth=%.1f shelfDetails=%lu\n",s.table.bounds.size.width,
            (unsigned long)s.shelves.count];
        for (UITableViewCell *cell in s.table.visibleCells) {
            CP26HomeRow *row = objc_getAssociatedObject(cell,&rowKey);
            NSIndexPath *path = [s.table indexPathForCell:cell];
            NSUInteger titles = 0, subtitles = 0;
            for (CP26HomeEntry *e in row.entries) {
                if (e.title.length) titles++;
                if (e.subtitle.length) subtitles++;
            }
            id item = Model(s.table,path);
            NSUInteger imageCount = [item isKindOfClass:CPListImageRowItem.class] ?
                ((CPListImageRowItem *)item).gridImages.count : 0;
            [report appendFormat:@"HOME section=%ld row=%ld modelImages=%lu controls=%lu displayed=%lu titles=%lu subtitles=%lu\n",
                (long)path.section,(long)path.row,(unsigned long)imageCount,
                (unsigned long)NativeButtons(cell).count,(unsigned long)row.entries.count,
                (unsigned long)titles,(unsigned long)subtitles];
        }
    }
}
