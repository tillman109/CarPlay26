#import "CommunicationAppearance.h"
#import "SpotifyReference.h"

typedef NS_ENUM(NSInteger, CP26CommunicationApp) { CP26OtherApp, CP26PhoneApp, CP26MessagesApp };

// Each styled surface owns its decorations and remembers native values across layout and reuse.
@interface CP26CommunicationStyle : NSObject
@property(nonatomic,strong,readonly) CP26PlacedViews *positions;
@property(nonatomic,strong) UIView *face;
@property(nonatomic,strong) CP26CommunicationBackdrop *field;
- (void)set:(id)value key:(NSString *)key on:(id)object;
- (void)concealDrawing:(UIView *)view;
@end

#ifdef __cplusplus
extern "C" {
#endif
BOOL CP26CallAppearanceEnabled(void);
void CP26StartCommunicationPreferences(BOOL shell);
CP26CommunicationApp CP26AppForView(UIView *view);
CP26CommunicationStyle *CP26StyleForView(UIView *view, BOOL active);
void CP26CommunicationTabs(UITabBar *bar);
void CP26CommunicationSegments(UISegmentedControl *segments);
void CP26CommunicationNavigation(UINavigationBar *bar);
void CP26CommunicationRowBackground(UITableViewCell *cell);
void CP26LayoutMessage(UITableViewCell *cell);
void CP26ConfigureContact(UICollectionReusableView *cell, UICollectionView *list, BOOL sectionHeader);
void CP26CommunicationList(UIScrollView *list);
void CP26CommunicationSiriRow(UIView *header);
#ifdef __cplusplus
}
#endif
