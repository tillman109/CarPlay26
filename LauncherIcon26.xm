#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <math.h>

// CarPlay26 v0.2.46: visual-only home/dashboard/active-app launcher treatment
// Native DBStatusBarHomeButton remains the only interactive control
// This file does not change the dock, app grid, map, shortcuts or gestures

static BOOL CP26LauncherSetting(NSString *key) {
    Boolean valid = false;
    Boolean value = CFPreferencesGetAppBooleanValue(
        (__bridge CFStringRef)key, CFSTR("com.tillman109.carplay26"), &valid);
    return valid && value;
}

static BOOL CP26IsCarPlayWindow(UIWindow *window) {
    return window && [window.windowScene.session.role
        isEqualToString:@"UIWindowSceneSessionRoleCarPlay"];
}

static NSHashTable<UIView *> *CP26LauncherButtons;
static NSHashTable<UIScrollView *> *CP26LauncherScrollViews;
// Native CarPlay dock controllers expose the active foreground application.
// Weak ownership avoids retaining scenes and works with or without dock pinning.
static NSHashTable<UIViewController *> *CP26LauncherDockControllers;

@interface UIViewController (CP26LauncherNativeAppState)
- (NSString *)activeBundleIdentifier;
@end

static void CP26RememberDockController(UIViewController *controller) {
    if (!NSThread.isMainThread || !controller) return;
    if (!CP26LauncherDockControllers)
        CP26LauncherDockControllers = [NSHashTable weakObjectsHashTable];
    [CP26LauncherDockControllers addObject:controller];
}

// Read a confirmed iOS 16 DashBoard API, not a guessed UIApplication state.
// The dock view exists on both Home and app screens, so only a nonempty active
// bundle identifier identifies an app; nil means Home/Dashboard page tracking
// continues to own the launcher. Keep the result scoped to this display.
static BOOL CP26ForegroundAppOnScreen(UIView *button) {
    for (UIViewController *controller in CP26LauncherDockControllers.allObjects) {
        UIWindow *dockWindow = controller.viewIfLoaded.window;
        if (!CP26IsCarPlayWindow(dockWindow) || dockWindow.hidden ||
            dockWindow.screen != button.window.screen ||
            ![controller respondsToSelector:@selector(activeBundleIdentifier)]) continue;
        NSString *bundleID = nil;
        @try { bundleID = [controller activeBundleIdentifier]; }
        @catch (__unused NSException *exception) { continue; }
        if (![bundleID isKindOfClass:NSString.class] || !bundleID.length) continue;
        // Explicit exclusions are shell identifiers, not applications.
        if ([bundleID isEqualToString:@"com.apple.springboard"] ||
            [bundleID isEqualToString:@"com.apple.CarPlay"] ||
            [bundleID isEqualToString:@"com.apple.Dashboard"]) continue;
        return YES;
    }
    return NO;
}
static const void *CP26LauncherProgressKey = &CP26LauncherProgressKey;

static CAShapeLayer *CP26GlyphLayer(UIView *button, NSString *name) {
    for (CALayer *layer in button.layer.sublayers) {
        if ([layer isKindOfClass:CAShapeLayer.class] && [layer.name isEqualToString:name])
            return (CAShapeLayer *)layer;
    }
    CAShapeLayer *layer = [CAShapeLayer layer];
    layer.name = name;
    layer.lineCap = kCALineCapRound;
    layer.lineJoin = kCALineJoinRound;
    layer.zPosition = 20;
    layer.contentsScale = button.window.screen.scale;
    [button.layer addSublayer:layer];
    return layer;
}

// On iOS 16, the dashboard's _SBRootFolderLayoutWrapperView is a direct
// child of DBIconScrollView, alongside home-screen icon pages. Measure how
// much of that native page intersects the current scroll viewport. This
// follows interactive swipes without guessing fixed content offsets or pages.
// NAN means the expected native hierarchy was not found; leave prior glyph.
static CGFloat CP26DashboardFraction(UIScrollView *scroll) {
    if (!scroll || !CP26IsCarPlayWindow(scroll.window)) return NAN;
    CGRect viewport = scroll.bounds;
    CGFloat vw = CGRectGetWidth(viewport), vh = CGRectGetHeight(viewport);
    if (vw < 120 || vh < 120 || !isfinite(vw) || !isfinite(vh)) return NAN;
    for (UIView *page in scroll.subviews) {
        if (![NSStringFromClass(page.class) isEqualToString:@"_SBRootFolderLayoutWrapperView"])
            continue;
        CGRect r = [page convertRect:page.bounds toView:scroll];
        if (CGRectIsNull(r) || CGRectIsInfinite(r) || CGRectIsEmpty(r)) continue;
        CGRect intersection = CGRectIntersection(r, viewport);
        CGFloat area = MIN(CGRectGetWidth(r)*CGRectGetHeight(r), vw*vh);
        if (!isfinite(area) || area <= 0) continue;
        CGFloat intersectionArea = CGRectIsNull(intersection) ? 0 :
            CGRectGetWidth(intersection)*CGRectGetHeight(intersection);
        return MAX(0.0, MIN(1.0, intersectionArea/area));
    }
    return NAN;
}

// Windows hosting the status bar and dashboard may be different CarPlay
// windows. Restrict matching to the same display, preferring the same scene.
static CGFloat CP26LauncherFraction(UIView *button, BOOL *interactive) {
    UIScrollView *best = nil;
    CGFloat bestFraction = NAN;
    BOOL sameScene = NO;
    for (UIScrollView *scroll in CP26LauncherScrollViews.allObjects) {
        if (!CP26IsCarPlayWindow(scroll.window) || scroll.hidden || scroll.alpha < 0.05 ||
            scroll.window.screen != button.window.screen) continue;
        CGFloat f = CP26DashboardFraction(scroll);
        if (!isfinite(f)) continue;
        BOOL sceneMatches = (scroll.window.windowScene == button.window.windowScene);
        if (!best || (sceneMatches && !sameScene)) {
            best = scroll;
            bestFraction = f;
            sameScene = sceneMatches;
        }
    }
    if (interactive) *interactive = best && (best.dragging || best.tracking || best.decelerating);
    // App templates can cover a still-loaded Home grid scroll view. Without
    // the native dock state, their offscreen dashboard fraction is zero and
    // the launcher incorrectly remains an outlined square inside apps.
    if (CP26ForegroundAppOnScreen(button)) {
        if (interactive) *interactive = NO;
        return 1.0;
    }
    return bestFraction;
}

static void CP26SetGlyphOpacity(CAShapeLayer *layer, float target, BOOL animate) {
    target = fmaxf(0.0f, fminf(1.0f, target));
    float from = ((CALayer *)layer.presentationLayer ?: layer).opacity;
    [layer removeAnimationForKey:@"CarPlay26.LauncherCrossfade"];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    layer.opacity = target;
    [CATransaction commit];
    if (animate && fabsf(from-target) > .04f) {
        CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
        fade.fromValue = @(from);
        fade.toValue = @(target);
        fade.duration = .22;
        fade.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [layer addAnimation:fade forKey:@"CarPlay26.LauncherCrossfade"];
    }
}

static void CP26ApplyLauncher(UIView *button, BOOL allowFade) {
    if (!NSThread.isMainThread || !CP26IsCarPlayWindow(button.window)) return;
    CGRect bounds = button.bounds;
    if (bounds.size.width < 28 || bounds.size.width > 65 ||
        bounds.size.height < 28 || bounds.size.height > 65) return;

    BOOL hasNativeImage = NO;
    for (UIView *child in button.subviews) {
        if ([child isKindOfClass:UIImageView.class]) {
            hasNativeImage = YES;
            if (child.alpha != 0.0) child.alpha = 0.0;
        }
    }
    if (!hasNativeImage) return;

    CAShapeLayer *square = CP26GlyphLayer(button, @"CarPlay26.LauncherOutline");
    CAShapeLayer *grid = CP26GlyphLayer(button, @"CarPlay26.LauncherGrid");
    BOOL nativeLight = button.traitCollection.userInterfaceStyle == UIUserInterfaceStyleLight;
    CGColorRef ink = (nativeLight ? UIColor.blackColor : UIColor.whiteColor).CGColor;

    CGFloat side = MIN(22.0, MIN(bounds.size.width,bounds.size.height)*.58);
    CGRect rect = CGRectMake((bounds.size.width-side)*.5, (bounds.size.height-side)*.5,
                             side, side);
    UIBezierPath *squarePath = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(rect,1.3,1.3)
                                                          cornerRadius:5.0];
    CGFloat cell=4.0, gap=2.0, gridSide=3*cell+2*gap;
    CGFloat startX = (bounds.size.width-gridSide)*.5;
    CGFloat startY = (bounds.size.height-gridSide)*.5;
    UIBezierPath *gridPath = [UIBezierPath bezierPath];
    for (NSUInteger row=0;row<3;row++) {
        for (NSUInteger col=0;col<3;col++) {
            CGRect dot = CGRectMake(startX+col*(cell+gap),startY+row*(cell+gap),cell,cell);
            [gridPath appendPath:[UIBezierPath bezierPathWithRoundedRect:dot cornerRadius:.7]];
        }
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    square.frame = bounds;
    square.path = squarePath.CGPath;
    square.fillColor = UIColor.clearColor.CGColor;
    square.strokeColor = ink;
    square.lineWidth = 2.5;
    grid.frame = bounds;
    grid.path = gridPath.CGPath;
    grid.fillColor = ink;
    grid.strokeColor = NULL;
    grid.lineWidth = 0;
    [CATransaction commit];

    BOOL interactive = NO;
    CGFloat fraction = CP26LauncherFraction(button, &interactive);
    if (!isfinite(fraction)) {
        // No page geometry yet. Keep the previous state while CarPlay starts.
        NSNumber *old = objc_getAssociatedObject(button, CP26LauncherProgressKey);
        fraction = old ? old.doubleValue : 0.0;
    }
    fraction = fmax(0.0, fmin(1.0, fraction));
    NSNumber *previous = objc_getAssociatedObject(button, CP26LauncherProgressKey);
    if (!previous || fabs(previous.doubleValue-fraction) > .012) {
        BOOL animate = allowFade && previous && !interactive &&
                       fabs(previous.doubleValue-fraction) >= .15;
        CP26SetGlyphOpacity(square,(float)(1.0-fraction),animate);
        CP26SetGlyphOpacity(grid,(float)fraction,animate);
        objc_setAssociatedObject(button, CP26LauncherProgressKey,
                                 @(fraction), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void CP26RefreshLauncherButtons(BOOL allowFade) {
    if (!NSThread.isMainThread) return;
    for (UIView *button in CP26LauncherButtons.allObjects) CP26ApplyLauncher(button,allowFade);
}

%group CP26LauncherButtonHooks
%hook DBStatusBarHomeButton
- (void)layoutSubviews {
    %orig;
    if (!CP26IsCarPlayWindow(((UIView *)self).window)) return;
    if (!CP26LauncherButtons) CP26LauncherButtons = [NSHashTable weakObjectsHashTable];
    [CP26LauncherButtons addObject:(UIView *)self];
    CP26ApplyLauncher((UIView *)self,YES);
}
%end
%end

// The existing project confirms this exact selector and getter on iOS 16.4.1.
// These hooks only observe state, do not replace the active app or change dock.
// If DockPinning also hooks this method, Logos/Substrate preserve the chain.
%group CP26LauncherAppHooks
%hook DBAppDockViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    CP26RememberDockController((UIViewController *)self);
    CP26RefreshLauncherButtons(YES);
}
- (void)setActiveBundleIdentifier:(NSString *)bundleID animated:(BOOL)animated {
    %orig;
    CP26RememberDockController((UIViewController *)self);
    // Re-read the native getter after the change is committed, not the
    // incoming argument, so we follow the actual foreground state.
    dispatch_async(dispatch_get_main_queue(), ^{
        CP26RefreshLauncherButtons(YES);
    });
}
%end
%end

%group CP26LauncherPageHooks
%hook DBIconScrollView
- (void)didMoveToWindow {
    %orig;
    UIScrollView *scroll = (UIScrollView *)self;
    if (!CP26IsCarPlayWindow(scroll.window)) return;
    if (!CP26LauncherScrollViews) CP26LauncherScrollViews = [NSHashTable weakObjectsHashTable];
    [CP26LauncherScrollViews addObject:scroll];
    CP26RefreshLauncherButtons(NO);
}
- (void)setContentOffset:(CGPoint)offset {
    %orig;
    if (CP26IsCarPlayWindow(((UIView *)self).window)) CP26RefreshLauncherButtons(YES);
}
- (void)layoutSubviews {
    %orig;
    UIScrollView *scroll = (UIScrollView *)self;
    if (!CP26IsCarPlayWindow(scroll.window)) return;
    if (!CP26LauncherScrollViews) CP26LauncherScrollViews = [NSHashTable weakObjectsHashTable];
    [CP26LauncherScrollViews addObject:scroll];
    CP26RefreshLauncherButtons(NO);
}
%end
%end

%ctor {
    @autoreleasepool {
        if (![NSProcessInfo.processInfo.processName isEqualToString:@"CarPlay"]) return;
        CFPreferencesAppSynchronize(CFSTR("com.tillman109.carplay26"));
        if (!CP26LauncherSetting(@"Enabled") || !CP26LauncherSetting(@"LauncherIcon26")) return;
        if (!NSClassFromString(@"DBStatusBarHomeButton")) return;
        %init(CP26LauncherButtonHooks);
        if (NSClassFromString(@"DBIconScrollView")) %init(CP26LauncherPageHooks);
        Class dockClass = NSClassFromString(@"DBAppDockViewController");
        if (dockClass &&
            class_getInstanceMethod(dockClass, @selector(activeBundleIdentifier)) &&
            class_getInstanceMethod(dockClass, @selector(setActiveBundleIdentifier:animated:))) {
            %init(CP26LauncherAppHooks);
        }
    }
}
