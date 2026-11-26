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
UIView *CP26DockHit(UIWindow *window, CGPoint point, UIEvent *event, UIView *native);
void CP26UpdateBrowseTable(UITableView *table, NSUInteger tab, BOOL compactHeader);
void CP26RestoreBrowseTables(void);
BOOL CP26BrowseHasCanvas(UIWindow *window);
NSIndexPath *CP26BrowsePathAtPoint(UITableView *table, CGPoint point, NSIndexPath *native);
void CP26BrowseReport(NSMutableString *report);
id CP26BrowseModel(UITableView *table, NSIndexPath *path);
void CP26FullPlayerReport(NSMutableString *report);
BOOL CP26UpdateMiniPlayer(UIView *bar, UIView *wrapper, UIViewController *context, UIBarButtonItem *item, CGRect frame);
UIView *CP26MiniPlayerHit(UIView *bar, CGPoint p, UIEvent *event);
BOOL CP26ActivateBarItem(UIBarButtonItem *item, UIControl *control);
void CP26SetHeader(UIViewController *controller, BOOL player, BOOL enabled);
void CP26LayoutHeader(UINavigationBar *bar);
void CP26RestoreHeaders(BOOL keepDetails, BOOL keepPlayer);
UIView *CP26HeaderHit(UINavigationBar *bar, CGPoint point, UIEvent *event, UIView *native);
void CP26HeaderReport(NSMutableString *report);
void CP26RemoveMiniPlayer(UIView *bar);
void CP26InvalidatePlayback(void);
void CP26PlayerLayout(UIViewController *controller, BOOL enabled);
void CP26RestorePlayers(void);
void CP26PlayerViewLaidOut(UIView *host);
void CP26PlaybackReport(NSMutableString *report);
UIView *CP26HitVisibleControl(UIView *view, UIView *space, CGPoint point, UIEvent *event);
void CP26ReportHit(NSMutableString *report, NSString *role, UIView *view);
BOOL CP26IsBrowseDetail(UIViewController *controller);
enum { CP26BrowseDetail = 4 };
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

@interface CP26ControlTarget : UIView
@property(nonatomic,weak,readonly) UIView *source;
- (void)bind:(UIView *)source;
- (void)project;
- (void)restore;
@end
