#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif
void CP26HomeSetEnabled(BOOL enabled);
void CP26HomeTableLayout(UITableView *table);
void CP26HomeListAppeared(UIViewController *controller);
void CP26HomeListDisappeared(UIViewController *controller);
void CP26HomeTableReloaded(UITableView *table);
CGFloat CP26HomeHeight(UITableView *table, NSIndexPath *path, CGFloat original);
void CP26HomeLayoutRow(UITableViewCell *cell);
void CP26HomeInvalidateRow(UITableViewCell *cell);
void CP26HomeRestoreRow(UITableViewCell *cell);
NSArray *CP26HomeFocusTargets(UITableViewCell *cell);
void CP26HomeNativeSelection(UITableView *table);
void CP26HomeAppendReport(NSMutableString *report);
#ifdef __cplusplus
}
#endif
