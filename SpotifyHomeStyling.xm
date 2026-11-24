#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#include <math.h>

// CarPlay26 v0.2.60: Animate Spotify pill selection changes, preserving native tabs.
// The CarPlay shell identifies the foreground app via the already-observed
// DBAppDockViewController.activeBundleIdentifier native getter. A Darwin
// notification conveys only a boolean to CarPlayTemplateUIHost, avoiding
// cross-sandbox preference reads and access to music/user data.
// No Spotify process injection or template-content hooks are used.

static BOOL CP26SpotifyStyleEnabled = NO;       // CarPlay shell: home panels
static BOOL CP26SpotifyNavEnabled = NO;         // CarPlay shell: pill nav
static BOOL CP26SpotifyHostIsActive = NO;       // Template host: foreground Spotify
static BOOL CP26SpotifyHostHomeEnabled = NO;    // Template host: explicit shell state
static BOOL CP26SpotifyHostNavEnabled = NO;     // Template host: explicit shell state
static BOOL CP26SpotifyNavMutating = NO;
static NSHashTable<UITabBar *> *CP26SpotifyStyledNavBars;
static const void *CP26SpotifyNavPillKey = &CP26SpotifyNavPillKey;
// Last confirmed tab selection on each verified native bar. Separate from
// UIKit state so presentation can animate once per transition, not every layout.
static const void *CP26SpotifyNavSelectedIndexKey = &CP26SpotifyNavSelectedIndexKey;
// Both our persistent selection and temporary pressed indicators live inside
// the non-interactive custom pill, never on top of native tab hit targets.
static const void *CP26SpotifyNavPartSnapshotKey = &CP26SpotifyNavPartSnapshotKey;
static NSHashTable<UIViewController *> *CP26SpotifyDockControllers;
static NSHashTable<UIView *> *CP26SpotifyStyledCells;
static NSHashTable<UIView *> *CP26SpotifyStyledBackings;
static const void *CP26SpotifyOriginalColorKey = &CP26SpotifyOriginalColorKey;
static const void *CP26SpotifyOriginalOpaqueKey = &CP26SpotifyOriginalOpaqueKey;
static const void *CP26SpotifyBackdropSnapshotKey = &CP26SpotifyBackdropSnapshotKey;
static BOOL CP26SpotifyLastStateKnown = NO;
static BOOL CP26SpotifyLastState = NO;

static BOOL CP26SpotifySetting(CFStringRef key) {
    Boolean valid = false;
    Boolean value = CFPreferencesGetAppBooleanValue(key,
        CFSTR("com.tillman109.carplay26"), &valid);
    return valid && value;
}

@interface UIViewController (CP26SpotifyNativeDock)
- (NSString *)activeBundleIdentifier;
@end

static BOOL CP26SpotifyIsCarPlayWindow(UIWindow *window) {
    return window && [window.windowScene.session.role
        isEqualToString:@"UIWindowSceneSessionRoleCarPlay"];
}

static void CP26SpotifySendShellState(BOOL force) {
    if (![NSThread isMainThread]) return;
    BOOL spotifyIsForeground = NO;
    if (CP26SpotifyStyleEnabled || CP26SpotifyNavEnabled) {
        for (UIViewController *controller in CP26SpotifyDockControllers.allObjects) {
            UIWindow *window = controller.viewIfLoaded.window;
            if (!CP26SpotifyIsCarPlayWindow(window) || window.hidden ||
                ![controller respondsToSelector:@selector(activeBundleIdentifier)]) continue;
            NSString *bundleID = nil;
            @try { bundleID = [controller activeBundleIdentifier]; }
            @catch (__unused NSException *exception) { continue; }
            if ([bundleID isKindOfClass:NSString.class] &&
                [bundleID isEqualToString:@"com.spotify.client"]) {
                spotifyIsForeground = YES;
                break;
            }
        }
    }
    if (!force && CP26SpotifyLastStateKnown &&
        CP26SpotifyLastState == spotifyIsForeground) return;
    CP26SpotifyLastStateKnown = YES;
    CP26SpotifyLastState = spotifyIsForeground;
    // Mode notifications precede the foreground signal so the host can keep
    // panel and navigation switches independent without reading shell prefs.
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        CP26SpotifyStyleEnabled ? CFSTR("com.tillman109.carplay26.spotify.hosthome.enable") :
            CFSTR("com.tillman109.carplay26.spotify.hosthome.disable"),
        NULL, NULL, TRUE);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        CP26SpotifyNavEnabled ? CFSTR("com.tillman109.carplay26.spotify.hostnav.enable") :
            CFSTR("com.tillman109.carplay26.spotify.hostnav.disable"),
        NULL, NULL, TRUE);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        spotifyIsForeground ? CFSTR("com.tillman109.carplay26.spotify.foreground") :
            CFSTR("com.tillman109.carplay26.spotify.background"),
        NULL, NULL, TRUE);
}

static void CP26SpotifyTrackDock(UIViewController *controller) {
    if (!NSThread.isMainThread || !controller) return;
    if (!CP26SpotifyDockControllers)
        CP26SpotifyDockControllers = [NSHashTable weakObjectsHashTable];
    [CP26SpotifyDockControllers addObject:controller];
    CP26SpotifySendShellState(NO);
}

static void CP26SpotifyStateRequested(__unused CFNotificationCenterRef center,
    __unused void *observer, __unused CFStringRef name,
    __unused const void *object, __unused CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{ CP26SpotifySendShellState(YES); });
}

// Settings sends the requested ON or OFF value explicitly after persisting it.
// Don't depend on cfprefsd instantly invalidating another process's cache.
// The CarPlay26 master Enabled setting still takes precedence. This event can
// turn styling on while the CarPlay shell and template host remain running.
static void CP26SpotifyStyleChanged(__unused CFNotificationCenterRef center,
    __unused void *observer, CFStringRef name,
    __unused const void *object, __unused CFDictionaryRef userInfo) {
    BOOL requestedOn = CFEqual(name,
        CFSTR("com.tillman109.carplay26.spotify.style.enable"));
    dispatch_async(dispatch_get_main_queue(), ^{
        CFPreferencesAppSynchronize(CFSTR("com.tillman109.carplay26"));
        CP26SpotifyStyleEnabled = requestedOn && CP26SpotifySetting(CFSTR("Enabled"));
        CP26SpotifySendShellState(YES);
    });
}

// Dedicated new pill-navigation switch; no dependency on the Home panels
// setting. The master CarPlay26 Enabled preference always takes precedence.
static void CP26SpotifyNavChanged(__unused CFNotificationCenterRef center,
    __unused void *observer, CFStringRef name,
    __unused const void *object, __unused CFDictionaryRef userInfo) {
    BOOL requestedOn = CFEqual(name,
        CFSTR("com.tillman109.carplay26.spotify.nav.enable"));
    dispatch_async(dispatch_get_main_queue(), ^{
        CFPreferencesAppSynchronize(CFSTR("com.tillman109.carplay26"));
        CP26SpotifyNavEnabled = requestedOn && CP26SpotifySetting(CFSTR("Enabled"));
        CP26SpotifySendShellState(YES);
    });
}

%group CP26SpotifyShellAppState
%hook DBAppDockViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    CP26SpotifyTrackDock((UIViewController *)self);
}
- (void)setActiveBundleIdentifier:(NSString *)bundleID animated:(BOOL)animated {
    %orig;
    UIViewController *controller = (UIViewController *)self;
    // Use the committed native getter after the setter, not its input argument.
    dispatch_async(dispatch_get_main_queue(), ^{ CP26SpotifyTrackDock(controller); });
}
%end
%end

// Never apply the experiment to all CarPlay template applications.
// Only the foreground Spotify state from the CarPlay shell can enable it.
// The earlier 12%-black fill over the observed light backing recreated
// the stock grey almost exactly (218/217/223). For a visually useful
// diagnostic, remove the panel fill completely. This does not introduce
// a wallpaper/blur material: it exposes whatever the native host draws.
static UIColor *CP26SpotifyExperimentalColor(void) {
    return UIColor.clearColor;
}

static BOOL CP26SpotifyIsArtworkRow(UIView *cell) {
    if (!cell || !CP26SpotifyHostIsActive || !CP26SpotifyHostHomeEnabled ||
        !CP26SpotifyIsCarPlayWindow(cell.window)) return NO;
    CGRect r = cell.bounds;
    if (r.size.width < 300 || r.size.width > 600 ||
        r.size.height < 95 || r.size.height > 165) return NO;
    BOOL insideNativeTable = NO;
    for (UIView *a = cell.superview; a && a != cell.window; a = a.superview) {
        if ([NSStringFromClass(a.class) isEqualToString:@"CPSTableView"]) {
            insideNativeTable = YES;
            break;
        }
    }
    if (!insideNativeTable) return NO;
    // The verified v0.2.48 Home rows contain a stack of four 61-point art buttons.
    // Keep this guard so other kinds of CPSImageRowCell are not changed.
    for (UIView *subview in cell.subviews) {
        if (![subview isKindOfClass:UIStackView.class]) continue;
        NSUInteger artworkButtons = 0;
        for (UIView *item in subview.subviews) {
            if ([NSStringFromClass(item.class) isEqualToString:@"CPUIHighlightButton"] &&
                item.bounds.size.width >= 40 && item.bounds.size.width <= 85)
                artworkButtons++;
        }
        if (artworkButtons == 4) return YES;
    }
    return NO;
}

// The v0.2.49 live report confirmed that the row itself became transparent,
// but also identified two opaque stock white surfaces under it:
// CPSTableView and its direct UIView content canvas. Treat both as one
// narrowly-scoped surface, and never modify the host window or navigation bar.
static BOOL CP26SpotifyBackdropEligible(UIView *view) {
    if (!view || !CP26SpotifyIsCarPlayWindow(view.window)) return NO;
    if (objc_getAssociatedObject(view, CP26SpotifyBackdropSnapshotKey)) return YES;
    UIColor *color = view.backgroundColor;
    if (!color) return NO;
    CGFloat white=0, a=0, r=0, g=0, b=0;
    if ([color getWhite:&white alpha:&a]) return a >= .95 && white >= .75;
    if ([color getRed:&r green:&g blue:&b alpha:&a])
        return a >= .95 && r >= .75 && g >= .75 && b >= .75 &&
            fabs(r-g) < .10 && fabs(g-b) < .10;
    return NO;
}

static void CP26SpotifyApplyBackdrop(UIView *view) {
    if (!view || !NSThread.isMainThread) return;
    if (!objc_getAssociatedObject(view, CP26SpotifyBackdropSnapshotKey)) {
        NSDictionary *snapshot = @{
            @"color": view.backgroundColor ?: (id)[NSNull null],
            @"opaque": @(view.opaque)
        };
        objc_setAssociatedObject(view, CP26SpotifyBackdropSnapshotKey,
            snapshot, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (!CP26SpotifyStyledBackings)
            CP26SpotifyStyledBackings = [NSHashTable weakObjectsHashTable];
        [CP26SpotifyStyledBackings addObject:view];
    }
    if (![view.backgroundColor isEqual:UIColor.clearColor])
        view.backgroundColor = UIColor.clearColor;
    if (view.opaque) view.opaque = NO;
}

static void CP26SpotifyRestoreBackdrop(UIView *view) {
    NSDictionary *snapshot = objc_getAssociatedObject(view, CP26SpotifyBackdropSnapshotKey);
    if (!snapshot) return;
    id color = snapshot[@"color"];
    view.backgroundColor = color == [NSNull null] ? nil : (UIColor *)color;
    view.opaque = [snapshot[@"opaque"] boolValue];
    objc_setAssociatedObject(view, CP26SpotifyBackdropSnapshotKey,
        nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [CP26SpotifyStyledBackings removeObject:view];
}

static void CP26SpotifyStyleArtworkBackings(UIView *cell) {
    if (!CP26SpotifyHostIsActive || !cell.window) return;
    UIView *table = nil;
    for (UIView *a = cell.superview; a && a != cell.window; a = a.superview) {
        if ([NSStringFromClass(a.class) isEqualToString:@"CPSTableView"]) {
            table = a;
            break;
        }
    }
    UIView *canvas = table.superview;
    // Only the exact iOS 16 Spotify Home hierarchy observed in diagnostics:
    // native CPSTableView directly inside a plain UIView content canvas.
    // This excludes overlay/nav-bar surfaces, all windows, and other apps.
    if (!table || ![NSStringFromClass(canvas.class) isEqualToString:@"UIView"] ||
        canvas.window != cell.window ||
        fabs(table.bounds.size.width - canvas.bounds.size.width) > 2.0 ||
        !CP26SpotifyBackdropEligible(table) ||
        !CP26SpotifyBackdropEligible(canvas)) return;
    CP26SpotifyApplyBackdrop(canvas);
    CP26SpotifyApplyBackdrop(table);
}

static void CP26SpotifyRestoreCell(UIView *cell) {
    id saved = objc_getAssociatedObject(cell, CP26SpotifyOriginalColorKey);
    if (!saved) return;
    UIColor *original = saved == [NSNull null] ? nil : (UIColor *)saved;
    if (cell.backgroundColor != original &&
        ![cell.backgroundColor isEqual:original]) cell.backgroundColor = original;
    NSNumber *originalOpaque = objc_getAssociatedObject(cell, CP26SpotifyOriginalOpaqueKey);
    if (originalOpaque) cell.opaque = originalOpaque.boolValue;
    objc_setAssociatedObject(cell, CP26SpotifyOriginalOpaqueKey,
        nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(cell, CP26SpotifyOriginalColorKey,
        nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [CP26SpotifyStyledCells removeObject:cell];
}

static void CP26SpotifyUpdateCell(UIView *cell) {
    if (![NSThread isMainThread] || !cell) return;
    if (!CP26SpotifyIsArtworkRow(cell)) {
        CP26SpotifyRestoreCell(cell);
        return;
    }
    id saved = objc_getAssociatedObject(cell, CP26SpotifyOriginalColorKey);
    if (!saved) {
        // Do not style cells already managed by another theme or with an
        // unknown native background. The observed stock row is opaque grey.
        UIColor *nativeColor = cell.backgroundColor;
        CGFloat white=0,alpha=0,red=0,green=0,blue=0;
        BOOL stock = [nativeColor getWhite:&white alpha:&alpha] ?
            (white > .55 && alpha > .90) :
            ([nativeColor getRed:&red green:&green blue:&blue alpha:&alpha] &&
             red > .55 && green > .55 && blue > .55 && alpha > .90 &&
             fabs(red-green) < .10 && fabs(green-blue) < .10);
        if (!stock) return;
        objc_setAssociatedObject(cell, CP26SpotifyOriginalColorKey,
            nativeColor ?: [NSNull null], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(cell, CP26SpotifyOriginalOpaqueKey,
            @(cell.opaque), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (!CP26SpotifyStyledCells)
            CP26SpotifyStyledCells = [NSHashTable weakObjectsHashTable];
        [CP26SpotifyStyledCells addObject:cell];
    }
    UIColor *experimentalColor = CP26SpotifyExperimentalColor();
    if (![cell.backgroundColor isEqual:experimentalColor])
        cell.backgroundColor = experimentalColor;
    // A truly clear UIView must not promise UIKit that it draws opaque pixels.
    // Preserve and restore the native opaque flag on deactivation.
    if (cell.opaque) cell.opaque = NO;
    CP26SpotifyStyleArtworkBackings(cell);
}


// Spotify v0.2.54 diagnostics confirmed a 400x44 UITabBar with four native
// tab buttons. Now Playing eventually occupies the last ~38 points, but it is
// not present when Spotify initially renders. Do NOT require its presence:
// otherwise a correctly active Spotify screen flashes the stock tab bar until
// playback controls initialise. Preserve native tab/button touch handlers.
static NSArray<UIView *> *CP26SpotifyNavButtons(UITabBar *bar) {
    NSMutableArray<UIView *> *buttons=[NSMutableArray array];
    UIView *nowPlaying=nil;
    for (UIView *child in bar.subviews) {
        NSString *className=NSStringFromClass(child.class);
        if ([className isEqualToString:@"UITabBarButton"])
            [buttons addObject:child];
        if ([className isEqualToString:@"CPUINowPlayingButtonWrapperView"])
            nowPlaying=child;
    }
    if (buttons.count!=4 || bar.items.count!=4 ||
        bar.bounds.size.width<385 || bar.bounds.size.width>445 ||
        bar.bounds.size.height<40 || bar.bounds.size.height>55) return nil;
    // If the wrapper exists, verify it is still the original native control.
    // Without it, accept the same four-tab arrangement spanning either 100%
    // of the bar or the ~90% space reserved for Now Playing.
    if (nowPlaying && (nowPlaying.bounds.size.width<30 ||
                       nowPlaying.bounds.size.width>48)) return nil;
    [buttons sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        if (a.frame.origin.x < b.frame.origin.x) return NSOrderedAscending;
        if (a.frame.origin.x > b.frame.origin.x) return NSOrderedDescending;
        return NSOrderedSame;
    }];
    CGFloat barWidth=bar.bounds.size.width;
    CGFloat lastRight=CGRectGetMaxX(buttons[3].frame);
    CGFloat trailingSpace=barWidth-lastRight;
    if (fabs(CGRectGetMinX(buttons[0].frame))>3.0 ||
        trailingSpace< -2.0 || trailingSpace>55.0) return nil;
    if (nowPlaying && fabs(lastRight-CGRectGetMinX(nowPlaying.frame))>5.0)
        return nil;
    for (NSUInteger i=0;i<buttons.count;i++) {
        UIView *b=buttons[i];
        if (b.bounds.size.width<72 || b.bounds.size.width>105 ||
            b.bounds.size.height<38 || b.bounds.size.height>55) return nil;
        if (i>0 && fabs(CGRectGetMinX(b.frame)-
                         CGRectGetMaxX(buttons[i-1].frame))>3.0) return nil;
    }
    return buttons;
}

static void CP26SpotifyRememberNavPart(UIView *view) {
    if (!view || objc_getAssociatedObject(view,CP26SpotifyNavPartSnapshotKey)) return;
    NSMutableDictionary *snapshot=[NSMutableDictionary dictionaryWithDictionary:@{
        @"alpha":@(view.alpha),
        @"hidden":@(view.hidden),
        @"frame":[NSValue valueWithCGRect:view.frame]
    }];
    if ([view isKindOfClass:UILabel.class]) {
        UILabel *label=(UILabel *)view;
        snapshot[@"font"]=label.font ?: [UIFont systemFontOfSize:11];
        snapshot[@"alignment"]=@(label.textAlignment);
        snapshot[@"textColor"]=label.textColor ?: (id)[NSNull null];
    }
    objc_setAssociatedObject(view,CP26SpotifyNavPartSnapshotKey,
        snapshot,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static void CP26SpotifyRestoreNavPart(UIView *view) {
    NSDictionary *snapshot=objc_getAssociatedObject(view,CP26SpotifyNavPartSnapshotKey);
    if (!snapshot) return;
    view.alpha=[snapshot[@"alpha"] doubleValue];
    view.hidden=[snapshot[@"hidden"] boolValue];
    CGRect frame=[snapshot[@"frame"] CGRectValue];
    if (!CGRectEqualToRect(view.frame,frame)) view.frame=frame;
    if ([view isKindOfClass:UILabel.class]) {
        UILabel *label=(UILabel *)view;
        label.font=snapshot[@"font"];
        label.textAlignment=(NSTextAlignment)[snapshot[@"alignment"] integerValue];
        id color=snapshot[@"textColor"];
        label.textColor=(color==[NSNull null])?nil:(UIColor *)color;
    }
    objc_setAssociatedObject(view,CP26SpotifyNavPartSnapshotKey,
        nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void CP26SpotifyRestoreNavBar(UITabBar *bar) {
    if (!bar || CP26SpotifyNavMutating) return;
    CP26SpotifyNavMutating=YES;
    for (UIView *button in bar.subviews) {
        if (![NSStringFromClass(button.class) isEqualToString:@"UITabBarButton"]) continue;
        for (UIView *part in button.subviews) CP26SpotifyRestoreNavPart(part);
    }
    UIView *pill=objc_getAssociatedObject(bar,CP26SpotifyNavPillKey);
    // If the switch is disabled mid-slide, cancel presentation animations and
    // drop the remembered selection before returning all native visuals.
    [pill.layer removeAllAnimations];
    for (UIView *indicator in pill.subviews) [indicator.layer removeAllAnimations];
    [pill removeFromSuperview];
    objc_setAssociatedObject(bar,CP26SpotifyNavSelectedIndexKey,nil,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(bar,CP26SpotifyNavPillKey,nil,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [CP26SpotifyStyledNavBars removeObject:bar];
    CP26SpotifyNavMutating=NO;
}

// Native UITabBarButton can restore its own label frame after the containing
// UITabBar lays out. Use one centered label geometry for both layout stages,
// without changing the native button bounds, controller or hit testing.
static void CP26SpotifyCenterNavLabel(UIView *button, UILabel *label) {
    if (!button || !label) return;
    CGFloat height=MIN(button.bounds.size.height,
        MAX(18.0,ceil(label.font.lineHeight)+4.0));
    CGRect centered=CGRectMake(0,
        floor((button.bounds.size.height-height)*0.5),
        button.bounds.size.width,height);
    if (!CGRectEqualToRect(label.frame,centered)) label.frame=centered;
}

// The v0.2.54 device report identified a non-interactive, childless UIView
// (about 76x39, radius 8) as each UITabBarButton's stock highlight surface.
// When pressed, UIKit can paint its own blue/grey rectangular capsule ABOVE
// our iOS 26-style selection indicator. Hide ONLY that visual surface; never
// hide the UITabBarButton itself or replace its touch/selection handlers.
static BOOL CP26SpotifyIsNativeTabHighlight(UIView *part, UIView *button) {
    if (!part || !button ||
        ![NSStringFromClass(part.class) isEqualToString:@"UIView"] ||
        part.subviews.count != 0 || part.userInteractionEnabled) return NO;
    CGRect r=part.frame;
    return r.size.width>=55 && r.size.width<=96 &&
        r.size.width<=button.bounds.size.width &&
        r.size.height>=32 && r.size.height<=44 &&
        r.origin.x>=0 && r.origin.y>=0 && r.origin.y<=8 &&
        part.layer.cornerRadius>=6 && part.layer.cornerRadius<=11;
}

static void CP26SpotifyHideNativeTabHighlights(UIView *button) {
    if (!button || !NSThread.isMainThread || CP26SpotifyNavMutating ||
        !CP26SpotifyHostIsActive || !CP26SpotifyHostNavEnabled ||
        !CP26SpotifyIsCarPlayWindow(button.window)) return;
    UIView *parent=button.superview;
    if (![parent isKindOfClass:UITabBar.class] ||
        !objc_getAssociatedObject(parent,CP26SpotifyNavPillKey)) return;
    for (UIView *part in button.subviews) {
        if (!CP26SpotifyIsNativeTabHighlight(part,button)) continue;
        CP26SpotifyRememberNavPart(part);
        // Some UIKit touch-state updates change hidden; some animate alpha.
        // Suppress both while enabled, then restore both from our snapshot.
        if (!part.hidden) part.hidden=YES;
        if (part.alpha!=0) part.alpha=0;
    }
}

static void CP26SpotifyUpdateNavBar(UITabBar *bar) {
    if (!NSThread.isMainThread || CP26SpotifyNavMutating || !bar) return;
    if (!CP26SpotifyHostIsActive || !CP26SpotifyHostNavEnabled ||
        !CP26SpotifyIsCarPlayWindow(bar.window)) {
        if (objc_getAssociatedObject(bar,CP26SpotifyNavPillKey))
            CP26SpotifyRestoreNavBar(bar);
        return;
    }
    NSArray<UIView *> *buttons=CP26SpotifyNavButtons(bar);
    if (!buttons) {
        if (objc_getAssociatedObject(bar,CP26SpotifyNavPillKey))
            CP26SpotifyRestoreNavBar(bar);
        return;
    }
    CP26SpotifyNavMutating=YES;
    UIView *pill=objc_getAssociatedObject(bar,CP26SpotifyNavPillKey);
    if (!pill) {
        pill=[[UIView alloc] initWithFrame:CGRectZero];
        pill.userInteractionEnabled=NO; // all native tab buttons stay clickable
        pill.layer.cornerRadius=18;
        pill.clipsToBounds=YES;
        UIView *selection=[[UIView alloc] initWithFrame:CGRectZero];
        selection.userInteractionEnabled=NO;
        selection.layer.cornerRadius=14;
        [pill addSubview:selection];
        UIView *pressed=[[UIView alloc] initWithFrame:CGRectZero];
        pressed.userInteractionEnabled=NO;
        pressed.layer.cornerRadius=14;
        pressed.hidden=YES;
        [pill addSubview:pressed];
        objc_setAssociatedObject(bar,CP26SpotifyNavPillKey,
            pill,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (!CP26SpotifyStyledNavBars)
            CP26SpotifyStyledNavBars=[NSHashTable weakObjectsHashTable];
        [CP26SpotifyStyledNavBars addObject:bar];
    }
    // Insert immediately above the stock _UIBarBackground but under buttons.
    if (pill.superview!=bar) {
        UIView *nativeBackground=bar.subviews.firstObject;
        if (nativeBackground && nativeBackground!=pill)
            [bar insertSubview:pill aboveSubview:nativeBackground];
        else [bar insertSubview:pill atIndex:0];
    }
    CGFloat minX=CGRectGetMinX(buttons[0].frame),
            maxX=CGRectGetMaxX(buttons[3].frame);
    // The v0.2.58 selection used to start at x=0 inside the outer pill
    // for the first tab and finish at its right edge for the last tab.
    // Use matching outer (4 pt) and inner (4 pt) side insets instead.
    const CGFloat outerInset=4.0;
    const CGFloat selectionInset=8.0;
    CGRect pillFrame=CGRectMake(minX+outerInset,4,
        maxX-minX-2*outerInset,36);
    if (!CGRectEqualToRect(pill.frame,pillFrame)) pill.frame=pillFrame;
    BOOL dark=bar.traitCollection.userInterfaceStyle==UIUserInterfaceStyleDark;
    pill.backgroundColor=dark?[UIColor colorWithWhite:0.15 alpha:0.68]:
        [UIColor colorWithWhite:1 alpha:0.58];
    pill.layer.borderColor=(dark?[UIColor colorWithWhite:1 alpha:0.12]:
        [UIColor colorWithWhite:0 alpha:0.07]).CGColor;
    pill.layer.borderWidth=0.5;
    NSUInteger selected=[bar.items indexOfObjectIdenticalTo:bar.selectedItem];
    NSNumber *priorSelection=objc_getAssociatedObject(bar,CP26SpotifyNavSelectedIndexKey);
    BOOL changedSelection=priorSelection &&
        priorSelection.unsignedIntegerValue< buttons.count &&
        selected< buttons.count && priorSelection.unsignedIntegerValue!=selected;
    UIView *selection=pill.subviews.firstObject;
    BOOL shouldHideSelection=selected==NSNotFound || selected>=buttons.count;
    BOOL selectionWasVisible=!selection.hidden;
    selection.hidden=shouldHideSelection;
    selection.backgroundColor=dark?[UIColor colorWithWhite:1 alpha:0.19]:
        [UIColor colorWithWhite:0 alpha:0.12];
    if (!shouldHideSelection) {
        UIView *chosen=buttons[selected];
        CGRect destination=CGRectMake(CGRectGetMinX(chosen.frame)-pillFrame.origin.x+selectionInset,
            4,chosen.bounds.size.width-2*selectionInset,28);
        if (!CGRectEqualToRect(selection.frame,destination)) {
            // Never animate initial appearance, layout changes, or Reduce Motion.
            // BeginFromCurrentState lets rapid tab switches redirect a slide
            // smoothly without snapping back to the previous model position.
            BOOL animate=changedSelection && selectionWasVisible &&
                !UIAccessibilityIsReduceMotionEnabled();
            if (animate) {
                [UIView animateWithDuration:0.26 delay:0
                    options:UIViewAnimationOptionCurveEaseInOut |
                            UIViewAnimationOptionBeginFromCurrentState |
                            UIViewAnimationOptionAllowUserInteraction
                    animations:^{ selection.frame=destination; }
                    completion:nil];
            } else {
                // A genuine geometry relayout must not leave an old animation
                // running against the new bar bounds or Now Playing arrangement.
                [selection.layer removeAllAnimations];
                selection.frame=destination;
            }
        }
    }
    // Set the new state after scheduling movement; UIKit can lay out the bar
    // repeatedly while a single selection transition is animating.
    objc_setAssociatedObject(bar,CP26SpotifyNavSelectedIndexKey,
        selected==NSNotFound?nil:@(selected),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    // The native iOS 16 pressed rectangle is intentionally hidden, so draw a
    // temporary, rounded touch indicator of our own. Unlike the persistent
    // selected capsule it also appears when pressing a tab already selected.
    // No target/action, gesture recognizer or control state is modified.
    UIView *pressed=pill.subviews.count>1?pill.subviews[1]:nil;
    NSUInteger pressedIndex=NSNotFound;
    for (NSUInteger i=0;i<buttons.count;i++) {
        UIView *button=buttons[i];
        if ([button isKindOfClass:UIControl.class] &&
            ((UIControl *)button).highlighted) {
            pressedIndex=i;
            break;
        }
    }
    pressed.hidden=pressedIndex==NSNotFound;
    if (!pressed.hidden) {
        UIView *touched=buttons[pressedIndex];
        CGRect rect=CGRectMake(CGRectGetMinX(touched.frame)-pillFrame.origin.x+selectionInset,
            4,touched.bounds.size.width-2*selectionInset,28);
        if (!CGRectEqualToRect(pressed.frame,rect)) pressed.frame=rect;
        pressed.backgroundColor=[UIColor.systemBlueColor colorWithAlphaComponent:
            dark?0.30:0.18];
    }
    for (NSUInteger i=0;i<buttons.count;i++) {
        UIView *button=buttons[i];
        for (UIView *part in button.subviews) {
            NSString *className=NSStringFromClass(part.class);
            if (CP26SpotifyIsNativeTabHighlight(part,button)) {
                CP26SpotifyRememberNavPart(part);
                if (!part.hidden) part.hidden=YES;
                if (part.alpha!=0) part.alpha=0;
            } else if ([className isEqualToString:@"UITabBarSwappableImageView"]) {
                CP26SpotifyRememberNavPart(part);
                if (part.alpha!=0) part.alpha=0;
            } else if ([className isEqualToString:@"UITabBarButtonLabel"] &&
                [part isKindOfClass:UILabel.class]) {
                UILabel *label=(UILabel *)part;
                CP26SpotifyRememberNavPart(label);
                label.textAlignment=NSTextAlignmentCenter;
                UIFont *pillFont=[UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
                if (![label.font isEqual:pillFont]) label.font=pillFont;
                CP26SpotifyCenterNavLabel(button,label);
                // Reinstate our text colour after UIKit's pressed/selected
                // transitions, which can otherwise temporarily turn it black.
                BOOL active=selected==i || pressedIndex==i;
                label.textColor=active?UIColor.systemBlueColor:
                    (dark?UIColor.whiteColor:[UIColor colorWithWhite:0.22 alpha:1]);
            }
        }
    }
    CP26SpotifyNavMutating=NO;
}

static void CP26SpotifyVisitViews(UIView *view, NSUInteger depth, NSUInteger *budget) {
    if (!view || !*budget || depth > 22) return;
    --*budget;
    if ([NSStringFromClass(view.class) isEqualToString:@"CPSImageRowCell"] &&
        CP26SpotifyHostHomeEnabled) CP26SpotifyUpdateCell(view);
    if ([view isKindOfClass:UITabBar.class] && CP26SpotifyHostNavEnabled)
        CP26SpotifyUpdateNavBar((UITabBar *)view);
    for (UIView *child in view.subviews) {
        if (!*budget) break;
        CP26SpotifyVisitViews(child, depth + 1, budget);
    }
}

static void CP26SpotifyRefreshHost(void) {
    if (!NSThread.isMainThread) return;
    if (!CP26SpotifyHostIsActive || !CP26SpotifyHostHomeEnabled) {
        for (UIView *cell in CP26SpotifyStyledCells.allObjects)
            CP26SpotifyRestoreCell(cell);
        for (UIView *view in CP26SpotifyStyledBackings.allObjects)
            CP26SpotifyRestoreBackdrop(view);
    }
    if (!CP26SpotifyHostIsActive || !CP26SpotifyHostNavEnabled) {
        for (UITabBar *bar in CP26SpotifyStyledNavBars.allObjects)
            CP26SpotifyRestoreNavBar(bar);
    }
    if (!CP26SpotifyHostIsActive ||
        (!CP26SpotifyHostHomeEnabled && !CP26SpotifyHostNavEnabled)) return;
    NSUInteger budget=2400;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] ||
            ![scene.session.role isEqualToString:@"UIWindowSceneSessionRoleCarPlay"]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            CP26SpotifyVisitViews(window,0,&budget);
            if (!budget) return;
        }
    }
}
static void CP26SpotifyHostUpdate(BOOL foreground) {
    if (!NSThread.isMainThread) return;
    if (foreground==CP26SpotifyHostIsActive) return;
    CP26SpotifyHostIsActive=foreground;
    CP26SpotifyRefreshHost();
}
static void CP26SpotifyHostModeReceived(__unused CFNotificationCenterRef center,
    __unused void *observer, CFStringRef name,
    __unused const void *object, __unused CFDictionaryRef userInfo) {
    BOOL home=CFStringHasPrefix(name,CFSTR("com.tillman109.carplay26.spotify.hosthome."));
    BOOL on=CFStringHasSuffix(name,CFSTR(".enable"));
    dispatch_async(dispatch_get_main_queue(), ^{
        if (home) CP26SpotifyHostHomeEnabled=on;
        else CP26SpotifyHostNavEnabled=on;
        CP26SpotifyRefreshHost();
    });
}

static void CP26SpotifyHostStateReceived(__unused CFNotificationCenterRef center,
    __unused void *observer, CFStringRef name,
    __unused const void *object, __unused CFDictionaryRef userInfo) {
    BOOL foreground = CFEqual(name, CFSTR("com.tillman109.carplay26.spotify.foreground"));
    dispatch_async(dispatch_get_main_queue(), ^{ CP26SpotifyHostUpdate(foreground); });
}

static void CP26SpotifyHostAskShell(void) {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.tillman109.carplay26.spotify.state.request"), NULL, NULL, TRUE);
}

%group CP26SpotifyNavPresentation
%hook UITabBar
- (void)layoutSubviews {
    %orig;
    CP26SpotifyUpdateNavBar((UITabBar *)self);
}
- (void)setSelectedItem:(UITabBarItem *)item {
    %orig;
    // Let UIKit commit the new selection before repositioning our capsule.
    dispatch_async(dispatch_get_main_queue(), ^{
        CP26SpotifyUpdateNavBar((UITabBar *)self);
    });
}
%end
%end

// UIKit sometimes lays out a UITabBarButton *after* UITabBar.layoutSubviews,
// restoring the old bottom-aligned label frame. Correct only buttons inside
// a previously validated, Spotify-only bar carrying our associated pill.
%group CP26SpotifyNavButtonLayout
%hook UITabBarButton
- (void)layoutSubviews {
    %orig;
    UIView *button=(UIView *)self;
    if (!NSThread.isMainThread || CP26SpotifyNavMutating ||
        !CP26SpotifyHostIsActive || !CP26SpotifyHostNavEnabled ||
        !CP26SpotifyIsCarPlayWindow(button.window)) return;
    UIView *parent=button.superview;
    if (![parent isKindOfClass:UITabBar.class] ||
        !objc_getAssociatedObject(parent,CP26SpotifyNavPillKey)) return;
    for (UIView *part in button.subviews) {
        if ([NSStringFromClass(part.class) isEqualToString:@"UITabBarButtonLabel"] &&
            [part isKindOfClass:UILabel.class]) {
            CP26SpotifyCenterNavLabel(button,(UILabel *)part);
        }
    }
    CP26SpotifyHideNativeTabHighlights(button);
}
- (void)setHighlighted:(BOOL)highlighted {
    %orig;
    UIView *button=(UIView *)self;
    CP26SpotifyHideNativeTabHighlights(button);
    UIView *parent=button.superview;
    if ([parent isKindOfClass:UITabBar.class] &&
        objc_getAssociatedObject(parent,CP26SpotifyNavPillKey) &&
        !CP26SpotifyNavMutating)
        CP26SpotifyUpdateNavBar((UITabBar *)parent);
}
- (void)setSelected:(BOOL)selected {
    %orig;
    UIView *button=(UIView *)self;
    CP26SpotifyHideNativeTabHighlights(button);
    UIView *parent=button.superview;
    if ([parent isKindOfClass:UITabBar.class] &&
        objc_getAssociatedObject(parent,CP26SpotifyNavPillKey) &&
        !CP26SpotifyNavMutating)
        CP26SpotifyUpdateNavBar((UITabBar *)parent);
}
%end
%end

%group CP26SpotifyArtworkRowStyle
%hook CPSImageRowCell
- (void)layoutSubviews {
    %orig;
    CP26SpotifyUpdateCell((UIView *)self);
}
- (void)didMoveToWindow {
    %orig;
    CP26SpotifyUpdateCell((UIView *)self);
}
%end
%end

%ctor {
    @autoreleasepool {
        NSString *process = NSProcessInfo.processInfo.processName;
        if ([process isEqualToString:@"CarPlay"]) {
            CFPreferencesAppSynchronize(CFSTR("com.tillman109.carplay26"));
            CP26SpotifyStyleEnabled = CP26SpotifySetting(CFSTR("Enabled")) &&
                CP26SpotifySetting(CFSTR("SpotifyHomeStyling"));
            CP26SpotifyNavEnabled = CP26SpotifySetting(CFSTR("Enabled")) &&
                CP26SpotifySetting(CFSTR("SpotifyPillNavigation"));
            // Always reply, even while the option is off, so the shared host
            // never interprets a missing reply as permission to change UI.
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                NULL, CP26SpotifyStateRequested,
                CFSTR("com.tillman109.carplay26.spotify.state.request"), NULL,
                CFNotificationSuspensionBehaviorDeliverImmediately);
            // Install the existing read-only dock-state observer even when
            // Spotify Home Styling starts OFF. Otherwise there is nothing to
            // identify Spotify when the user enables the switch live.
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                NULL, CP26SpotifyStyleChanged,
                CFSTR("com.tillman109.carplay26.spotify.style.enable"), NULL,
                CFNotificationSuspensionBehaviorDeliverImmediately);
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                NULL, CP26SpotifyStyleChanged,
                CFSTR("com.tillman109.carplay26.spotify.style.disable"), NULL,
                CFNotificationSuspensionBehaviorDeliverImmediately);
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                NULL, CP26SpotifyNavChanged,
                CFSTR("com.tillman109.carplay26.spotify.nav.enable"), NULL,
                CFNotificationSuspensionBehaviorDeliverImmediately);
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                NULL, CP26SpotifyNavChanged,
                CFSTR("com.tillman109.carplay26.spotify.nav.disable"), NULL,
                CFNotificationSuspensionBehaviorDeliverImmediately);
            Class dockClass = NSClassFromString(@"DBAppDockViewController");
            if (CP26SpotifySetting(CFSTR("Enabled")) && dockClass &&
                class_getInstanceMethod(dockClass, @selector(activeBundleIdentifier)) &&
                class_getInstanceMethod(dockClass,
                    @selector(setActiveBundleIdentifier:animated:))) {
                %init(CP26SpotifyShellAppState);
            }
        } else if ([process isEqualToString:@"CarPlayTemplateUIHost"]) {
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                NULL, CP26SpotifyHostStateReceived,
                CFSTR("com.tillman109.carplay26.spotify.foreground"), NULL,
                CFNotificationSuspensionBehaviorDeliverImmediately);
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                NULL, CP26SpotifyHostStateReceived,
                CFSTR("com.tillman109.carplay26.spotify.background"), NULL,
                CFNotificationSuspensionBehaviorDeliverImmediately);
            for (NSString *event in @[
                @"com.tillman109.carplay26.spotify.hosthome.enable",
                @"com.tillman109.carplay26.spotify.hosthome.disable",
                @"com.tillman109.carplay26.spotify.hostnav.enable",
                @"com.tillman109.carplay26.spotify.hostnav.disable"]) {
                CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                    NULL, CP26SpotifyHostModeReceived, (__bridge CFStringRef)event, NULL,
                    CFNotificationSuspensionBehaviorDeliverImmediately);
            }
            if (NSClassFromString(@"CPSImageRowCell"))
                %init(CP26SpotifyArtworkRowStyle);
            %init(CP26SpotifyNavPresentation);
            if (NSClassFromString(@"UITabBarButton"))
                %init(CP26SpotifyNavButtonLayout);
            // Ask as soon as the main queue is available, instead of waiting
            // one second for the first request. Never assume Spotify is active
            // without the CarPlay shell's native foreground-app confirmation.
            dispatch_async(dispatch_get_main_queue(), ^{
                CP26SpotifyHostAskShell();
            });
            // A short retry helps if the shell registers just after this host;
            // retain the original 1/4/7-second recovery requests for cold start.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                (int64_t)(0.25 * NSEC_PER_SEC)),
                dispatch_get_main_queue(), ^{ CP26SpotifyHostAskShell(); });
            for (int delay=1; delay<=7; delay+=3) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                    (int64_t)(delay * NSEC_PER_SEC)),
                    dispatch_get_main_queue(), ^{ CP26SpotifyHostAskShell(); });
            }
        }
    }
}
