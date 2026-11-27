#import "CommunicationAppearance.h"
#import <QuartzCore/QuartzCore.h>
#import <dlfcn.h>

@protocol CP26CurrentInterfaceStyle <NSObject>
- (UIUserInterfaceStyle)userInterfaceStyle;
@end
@interface UIApplication (CP26SystemStyle)
- (UIUserInterfaceStyle)_systemUserInterfaceStyle;
@end

UIUserInterfaceStyle CP26HandsetStyle(void) {
    // UIKitServices exposes the resolved device style, including a scheduled transition.
    static id<CP26CurrentInterfaceStyle> value;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ value = [NSClassFromString(@"UISCurrentUserInterfaceStyleValue") new]; });
    UIUserInterfaceStyle style = UIUserInterfaceStyleUnspecified;
    if ([value respondsToSelector:@selector(userInterfaceStyle)]) style = value.userInterfaceStyle;
    if (style != UIUserInterfaceStyleLight && style != UIUserInterfaceStyleDark) {
        UIApplication *app = UIApplication.sharedApplication;
        if ([app respondsToSelector:@selector(_systemUserInterfaceStyle)]) style = app._systemUserInterfaceStyle;
    }
    if (style != UIUserInterfaceStyleDark && style != UIUserInterfaceStyleLight) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if ([scene isKindOfClass:UIWindowScene.class] && [scene.session.role isEqualToString:UIWindowSceneSessionRoleApplication]) {
                style = ((UIWindowScene *)scene).screen.traitCollection.userInterfaceStyle;
                break;
            }
        }
    }
    static UIUserInterfaceStyle last = UIUserInterfaceStyleLight;
    if (style == UIUserInterfaceStyleDark || style == UIUserInterfaceStyleLight) last = style;
    return last;
}

@implementation CP26MaterialView {
    UIUserInterfaceStyle _appliedStyle;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithEffect:nil])) {
        self.frame = frame;
        self.userInteractionEnabled = NO;
        self.accessibilityElementsHidden = YES;
        self.clipsToBounds = YES;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    }
    return self;
}
- (void)applyStyle:(UIUserInterfaceStyle)style radius:(CGFloat)radius {
    if (self.layer.cornerRadius != radius) self.layer.cornerRadius = radius;
    CGFloat scale = self.window.screen.scale ?: UIScreen.mainScreen.scale;
    self.layer.borderWidth = 1 / MAX(scale, 1);
    if (_appliedStyle == style && self.effect) return;
    _appliedStyle = style;
    BOOL dark = style == UIUserInterfaceStyleDark;
    self.effect = [UIBlurEffect effectWithStyle:dark ? UIBlurEffectStyleSystemThinMaterialDark : UIBlurEffectStyleSystemUltraThinMaterialLight];
    self.contentView.backgroundColor = dark ? [UIColor colorWithRed:.20 green:.20 blue:.23 alpha:.36] : [UIColor colorWithWhite:.98 alpha:.39];
    self.layer.borderColor = [UIColor colorWithWhite:dark ? 1 : .35 alpha:dark ? .25 : .32].CGColor;
}
@end

static UIImage *BackgroundField(void) {
    static UIImage *image;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Dl_info info = {0};
        if (dladdr((const void *)&CP26HandsetStyle, &info) && info.dli_fname) {
            NSString *folder = [[NSString stringWithUTF8String:info.dli_fname] stringByDeletingLastPathComponent];
            image = [UIImage imageWithContentsOfFile:[folder stringByAppendingPathComponent:@"CarPlay26Materials/Communications.png"]];
        }
    });
    return image;
}
@implementation CP26CommunicationBackdrop
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.userInteractionEnabled = NO;
        self.accessibilityElementsHidden = YES;
        self.opaque = YES;
        self.contentMode = UIViewContentModeRedraw;
    }
    return self;
}
- (void)didMoveToWindow { [super didMoveToWindow]; [self setNeedsDisplay]; }
- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previous]) [self setNeedsDisplay];
}
- (void)drawRect:(CGRect)rect {
    CGRect field = self.window ? [self convertRect:self.window.bounds fromView:self.window] : self.bounds;
    [[UIColor colorWithRed:.74 green:.71 blue:.70 alpha:1] setFill];
    UIRectFill(rect);
    CGContextSetInterpolationQuality(UIGraphicsGetCurrentContext(), kCGInterpolationHigh);
    [BackgroundField() drawInRect:field];
    if (self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
        [[UIColor colorWithRed:.055 green:.055 blue:.08 alpha:.85] setFill];
        UIRectFillUsingBlendMode(rect, kCGBlendModeNormal);
    }
}
@end
