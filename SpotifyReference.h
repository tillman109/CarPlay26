#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif
// All sizes are mapped into the actual CarPlay window, in points.
UIView *CP26ReferenceCanvas(void);
void CP26GlassPill(UIView *view, CGFloat radius);
void CP26RemoveGlass(UIView *view);
BOOL CP26HasCompactHeader(UITabBar *bar);
void CP26RefreshBrowseGeometry(void);
void CP26BrowseCellReused(UITableViewCell *cell);
void CP26BrowseCellStateChanged(UITableViewCell *cell);
void CP26RefreshGlassDock(void);
void CP26UpdateBrowseTable(UITableView *table, NSUInteger tab, BOOL compactHeader);
void CP26RestoreBrowseTables(void);
BOOL CP26BrowseHasCanvas(UIWindow *window);
void CP26BrowseReport(NSMutableString *report);
id CP26BrowseModel(UITableView *table, NSIndexPath *path);
void CP26FullPlayerReport(NSMutableString *report);
BOOL CP26UpdateMiniPlayer(UITabBar *bar, UIView *wrapper, CGRect frame);
void CP26RemoveMiniPlayer(UITabBar *bar);
void CP26InvalidatePlayback(void);
void CP26PlayerLayout(UIViewController *controller, BOOL enabled);
void CP26RestorePlayers(void);
void CP26PlayerViewLaidOut(UIView *host);
void CP26PlaybackReport(NSMutableString *report);
void CP26DockReport(UIWindow *window, NSMutableString *report);
void CP26ReferenceDock(UIWindow *window, UIView *root, CGRect surface, BOOL enabled);
#ifdef __cplusplus
}
#endif

// Apple's constraints still own the underlying layout. Remember the latest
// native rect when UIKit lays a component out again, and restore only our edit.
@interface CP26PlacedViews : NSObject
- (void)place:(UIView *)view in:(UIView *)space rect:(CGRect)rect;
- (void)restoreView:(UIView *)view;
- (void)restore;
@end
