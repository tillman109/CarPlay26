#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif
UIUserInterfaceStyle CP26HandsetStyle(void);
#ifdef __cplusplus
}
#endif

@interface CP26MaterialView : UIVisualEffectView
- (void)applyStyle:(UIUserInterfaceStyle)style radius:(CGFloat)radius;
@end

// Draw the same part of the backdrop at a given window coordinate in every bar and list.
@interface CP26CommunicationBackdrop : UIView
@end
