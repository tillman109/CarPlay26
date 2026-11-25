#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#include <math.h>
#import "SpotifyHomeLayout.h"
#import "SpotifyReference.h"

// Spotify template styling and foreground state for CarPlay26.
// The CarPlay shell identifies the foreground app via the already-observed
// DBAppDockViewController.activeBundleIdentifier native getter. A Darwin
// notification conveys foreground and preference states to CarPlayTemplateUIHost.
// Its mini-player reads the active Spotify playback session inside that host.
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
    CP26RefreshGlassDock();
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

// Spotify v0.2.54 diagnostics confirmed a 400x44 UITabBar with four native
// tab buttons. Now Playing eventually occupies the last ~38 points, but it is
// not present when Spotify initially renders. Do NOT require its presence:
// otherwise a correctly active Spotify screen flashes the stock tab bar until
// playback controls initialise. Preserve native tab/button touch handlers.
BOOL CP26SpotifyUsesGlassDock(void) {
    return CP26SpotifyLastStateKnown && CP26SpotifyLastState && CP26SpotifyStyleEnabled;
}

static char nativeTabKey, compactTabKey, bandKey, barAppearanceKey, managedWrapperKey;
BOOL CP26HasCompactHeader(UITabBar *bar) { return bar && objc_getAssociatedObject(bar,&bandKey)!=nil; }

static CGRect NativeTabFrame(UIView *button) {
    NSValue *last = objc_getAssociatedObject(button,&compactTabKey);
    NSValue *original = objc_getAssociatedObject(button,&nativeTabKey);
    return last && original && CGRectEqualToRect(button.frame,last.CGRectValue)
        ? original.CGRectValue : button.frame;
}

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
        (bar.window.bounds.size.height<bar.window.bounds.size.width &&
         (bar.bounds.size.width<385 || bar.bounds.size.width>445)) ||
        bar.bounds.size.width<320 || bar.bounds.size.width>560 ||
        bar.bounds.size.height<40 || bar.bounds.size.height>55) return nil;
    // If the wrapper exists, verify it is still the original native control.
    // Without it, accept the same four-tab arrangement spanning either 100%
    // of the bar or the ~90% space reserved for Now Playing.
    if (nowPlaying && (nowPlaying.bounds.size.width<30 ||
                       nowPlaying.bounds.size.width>48)) return nil;
    [buttons sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        if (NativeTabFrame(a).origin.x < NativeTabFrame(b).origin.x) return NSOrderedAscending;
        if (NativeTabFrame(a).origin.x > NativeTabFrame(b).origin.x) return NSOrderedDescending;
        return NSOrderedSame;
    }];
    CGFloat barWidth=bar.bounds.size.width;
    CGFloat lastRight=CGRectGetMaxX(NativeTabFrame(buttons[3]));
    CGFloat trailingSpace=barWidth-lastRight;
    if (fabs(CGRectGetMinX(NativeTabFrame(buttons[0])))>3.0 ||
        trailingSpace< -2.0 || trailingSpace>MAX(55.0,barWidth*.14)) return nil;
    if (nowPlaying && fabs(lastRight-CGRectGetMinX(nowPlaying.frame))>5.0)
        return nil;
    for (NSUInteger i=0;i<buttons.count;i++) {
        UIView *b=buttons[i];
        if (NativeTabFrame(b).size.width<barWidth*.17 || NativeTabFrame(b).size.width>barWidth*.28 ||
            NativeTabFrame(b).size.height<38 || NativeTabFrame(b).size.height>55) return nil;
        if (i>0 && fabs(CGRectGetMinX(NativeTabFrame(b))-
                         CGRectGetMaxX(NativeTabFrame(buttons[i-1])))>3.0) return nil;
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
        CGRect original = NativeTabFrame(button);
        if (!CGRectEqualToRect(original,button.frame)) button.frame = original;
        objc_setAssociatedObject(button,&compactTabKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(button,&nativeTabKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        for (UIView *part in button.subviews) CP26SpotifyRestoreNavPart(part);
    }
    UIView *pill=objc_getAssociatedObject(bar,CP26SpotifyNavPillKey);
    // If the switch is disabled mid-slide, cancel presentation animations and
    // drop the remembered selection before returning all native visuals.
    [pill.layer removeAllAnimations];
    for (UIView *indicator in pill.subviews) [indicator.layer removeAllAnimations];
    CP26RemoveMiniPlayer(bar);
    UIView *wrapped=objc_getAssociatedObject(bar,&managedWrapperKey);
    if (wrapped) CP26SpotifyRestoreNavPart(wrapped);
    objc_setAssociatedObject(bar,&managedWrapperKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSDictionary *appearance=objc_getAssociatedObject(bar,&barAppearanceKey);
    if (appearance) {
        bar.backgroundColor=appearance[@"color"]==NSNull.null ? nil : appearance[@"color"];
        bar.opaque=[appearance[@"opaque"] boolValue];
        for (UIView *child in bar.subviews)
            if ([NSStringFromClass(child.class) isEqualToString:@"_UIBarBackground"]) CP26SpotifyRestoreNavPart(child);
        objc_setAssociatedObject(bar,&barAppearanceKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UIView *band = objc_getAssociatedObject(bar,&bandKey);
    [band removeFromSuperview];
    objc_setAssociatedObject(bar,&bandKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [pill removeFromSuperview];
    objc_setAssociatedObject(bar,CP26SpotifyNavSelectedIndexKey,nil,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(bar,CP26SpotifyNavPillKey,nil,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [CP26SpotifyStyledNavBars removeObject:bar];
    CP26RefreshBrowseGeometry();
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
    return r.size.width>=30 && r.size.width<=105 &&
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
        selection.tag=1; selection.userInteractionEnabled=NO;
        selection.layer.cornerRadius=14;
        [pill addSubview:selection];
        UIView *pressed=[[UIView alloc] initWithFrame:CGRectZero];
        pressed.tag=2; pressed.userInteractionEnabled=NO;
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
    CGFloat w=bar.bounds.size.width;
    CGFloat u=MIN(w/400.0,bar.bounds.size.height/33.0), span=192*u, h=27*u;
    UIView *wrapper=nil;
    if (!objc_getAssociatedObject(bar,&barAppearanceKey))
        objc_setAssociatedObject(bar,&barAppearanceKey,@{@"opaque":@(bar.opaque),
            @"color":bar.backgroundColor ?: (id)NSNull.null},OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    bar.opaque=NO;
    if (![bar.backgroundColor isEqual:UIColor.clearColor]) bar.backgroundColor=UIColor.clearColor;
    for (UIView *child in bar.subviews) {
        NSString *cls=NSStringFromClass(child.class);
        if ([cls isEqualToString:@"CPUINowPlayingButtonWrapperView"]) wrapper=child;
        if ([cls isEqualToString:@"_UIBarBackground"]) {
            CP26SpotifyRememberNavPart(child); child.alpha=0;
        }
    }
    BOOL expanded=CP26UpdateMiniPlayer(bar,wrapper,CGRectMake(w-165*u,0,164*u,33*u));
    UIView *previousWrapper=objc_getAssociatedObject(bar,&managedWrapperKey);
    if (previousWrapper && (previousWrapper!=wrapper || !expanded)) {
        CP26SpotifyRestoreNavPart(previousWrapper);
        objc_setAssociatedObject(bar,&managedWrapperKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (expanded && wrapper) {
        CP26SpotifyRememberNavPart(wrapper); wrapper.alpha=0;
        objc_setAssociatedObject(bar,&managedWrapperKey,wrapper,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    CGRect pillFrame=CGRectMake(3*u,3*u,span,h);
    if (!CGRectEqualToRect(pill.frame,pillFrame)) pill.frame=pillFrame;
    pill.layer.cornerRadius=h*.5;
    BOOL dark=bar.traitCollection.userInterfaceStyle==UIUserInterfaceStyleDark;
    UIView *band=objc_getAssociatedObject(bar,&bandKey);
    if (!band) {
        band=CP26ReferenceCanvas();
        objc_setAssociatedObject(bar,&bandKey,band,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [bar insertSubview:band belowSubview:pill];
        CP26RefreshBrowseGeometry();
    }
    CGRect bandFrame=CGRectMake(0,0,w,33*u);
    if (!CGRectEqualToRect(band.frame,bandFrame)) band.frame=bandFrame;
    // With a live list underneath, let its scrolling content feed both blur views.
    band.hidden=CP26SpotifyHostHomeEnabled && CP26BrowseHasCanvas(bar.window);
    CP26GlassPill(pill,h*.5);
    for (NSUInteger i=0;i<buttons.count;i++) {
        UIView *button=buttons[i];
        CGRect original=NativeTabFrame(button);
        // Edges of the four labels in the portrait reference, in 400-point coordinates.
        static const CGFloat edges[] = {0,44,96,142,192};
        CGRect compact=CGRectMake(pillFrame.origin.x+edges[i]*u,0,
            (edges[i+1]-edges[i])*u,33*u);
        objc_setAssociatedObject(button,&nativeTabKey,[NSValue valueWithCGRect:original],OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(button,&compactTabKey,[NSValue valueWithCGRect:compact],OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (!CGRectEqualToRect(button.frame,compact)) button.frame=compact;
    }
    CGFloat selectionInset=2.0;
    NSUInteger selected=[bar.items indexOfObjectIdenticalTo:bar.selectedItem];
    NSNumber *priorSelection=objc_getAssociatedObject(bar,CP26SpotifyNavSelectedIndexKey);
    BOOL changedSelection=priorSelection &&
        priorSelection.unsignedIntegerValue< buttons.count &&
        selected< buttons.count && priorSelection.unsignedIntegerValue!=selected;
    UIView *selection=[pill viewWithTag:1];
    BOOL shouldHideSelection=selected==NSNotFound || selected>=buttons.count;
    BOOL selectionWasVisible=!selection.hidden;
    selection.hidden=shouldHideSelection;
    selection.backgroundColor=[UIColor colorWithRed:.075 green:.075 blue:.11 alpha:.72];
    selection.layer.cornerRadius=(h-6)*.5;
    if (!shouldHideSelection) {
        UIView *chosen=buttons[selected];
        CGRect destination=CGRectMake(CGRectGetMinX(chosen.frame)-pillFrame.origin.x+selectionInset,
            3,chosen.bounds.size.width-2*selectionInset,h-6);
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
    UIView *pressed=[pill viewWithTag:2];
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
            3,touched.bounds.size.width-2*selectionInset,h-6);
        if (!CGRectEqualToRect(pressed.frame,rect)) pressed.frame=rect;
        pressed.backgroundColor=[UIColor colorWithWhite:1 alpha:dark?.16:.20];
        pressed.layer.cornerRadius=selection.layer.cornerRadius;
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
                UIFont *pillFont=[UIFont systemFontOfSize:10*u weight:UIFontWeightMedium];
                if (![label.font isEqual:pillFont]) label.font=pillFont;
                CP26SpotifyCenterNavLabel(button,label);
                // Reinstate our text colour after UIKit's pressed/selected
                // transitions, which can otherwise temporarily turn it black.
                BOOL active=selected==i || pressedIndex==i;
                label.textColor=[UIColor colorWithWhite:1 alpha:active ? 1 : .91];
            }
        }
    }
    CP26SpotifyNavMutating=NO;
}

static void CP26SpotifyVisitViews(UIView *view, NSUInteger depth, NSUInteger *budget) {
    if (!view || !*budget || depth > 22) return;
    --*budget;
    UIResponder *owner=view.nextResponder;
    if (CP26SpotifyHostHomeEnabled && [owner isKindOfClass:NSClassFromString(@"CPSNowPlayingViewController")] &&
        ((UIViewController *)owner).viewIfLoaded==view) CP26PlayerLayout((UIViewController *)owner,YES);
    if ([NSStringFromClass(view.class) isEqualToString:@"CPSTableView"] &&
        CP26SpotifyHostHomeEnabled) CP26HomeTableLayout((UITableView *)view);
    if ([view isKindOfClass:UITabBar.class] && CP26SpotifyHostNavEnabled)
        CP26SpotifyUpdateNavBar((UITabBar *)view);
    for (UIView *child in view.subviews) {
        if (!*budget) break;
        CP26SpotifyVisitViews(child, depth + 1, budget);
    }
}

static void CP26SpotifyRefreshHost(void) {
    if (!NSThread.isMainThread) return;
    BOOL style=CP26SpotifyHostIsActive && CP26SpotifyHostHomeEnabled;
    CP26HomeSetEnabled(style);
    if (!style) CP26RestorePlayers();
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
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    UITabBar *bar=(UITabBar *)self;
    if (objc_getAssociatedObject(bar,&bandKey) && point.y>MIN(bar.bounds.size.height,bar.bounds.size.width*33/400.0)) {
        // The idle native waveform can be taller than the new header.
        for (UIView *child in bar.subviews)
            if ([NSStringFromClass(child.class) isEqualToString:@"CPUINowPlayingButtonWrapperView"] &&
                !child.hidden && child.alpha>.01 && CGRectContainsPoint(child.frame,point)) return %orig;
        return NO;
    }
    return %orig;
}
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
    CP26HomeLayoutRow((UITableViewCell *)self);
}
- (void)didMoveToWindow {
    %orig;
    CP26HomeLayoutRow((UITableViewCell *)self);
}
- (void)prepareForReuse {
    CP26HomeRestoreRow((UITableViewCell *)self);
    %orig;
}
- (NSArray *)preferredFocusEnvironments {
    NSArray *targets = CP26HomeFocusTargets((UITableViewCell *)self);
    if (targets.count) return targets;
    return %orig;
}
%end
%end

%group CP26SpotifyRowConfiguration
%hook CPSImageRowCell
- (void)configureWithImageRowItem:(id)item selectGridItemBlock:(id)onImage
    selectTitleBlock:(id)onTitle showActivityIndicator:(BOOL)show {
    %orig;
    CP26HomeInvalidateRow((UITableViewCell *)self);
}
%end
%end

%group CP26SpotifyListCellLifecycle
%hook UITableViewCell
- (void)prepareForReuse {
    CP26BrowseCellReused((UITableViewCell *)self);
    %orig;
}
- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    %orig;
    CP26BrowseCellStateChanged((UITableViewCell *)self);
}
- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    %orig;
    CP26BrowseCellStateChanged((UITableViewCell *)self);
}
- (void)didUpdateFocusInContext:(UIFocusUpdateContext *)context withAnimationCoordinator:(UIFocusAnimationCoordinator *)coordinator {
    %orig;
    CP26BrowseCellStateChanged((UITableViewCell *)self);
}
%end
%end

%group CP26SpotifyHomeTable
%hook CPSTableView
- (void)layoutSubviews {
    %orig;
    CP26HomeTableLayout((UITableView *)self);
}
- (void)reloadData {
    %orig;
    CP26HomeTableReloaded((UITableView *)self);
}
%end
%end

%group CP26SpotifyHomeList
%hook CPSListTemplateViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    CP26HomeListAppeared((UIViewController *)self);
}
- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    CP26HomeListDisappeared((UIViewController *)self);
}
%end
%end

%group CP26SpotifySnapshotChange
%hook CPSListTemplateViewController
- (void)nowPlayingManager:(id)manager didUpdateSnapshot:(id)snapshot {
    %orig;
    if (CP26SpotifyHostIsActive && CP26SpotifyHostNavEnabled) CP26InvalidatePlayback();
}
%end
%end

%group CP26SpotifyPlayerViewLayout
%hook CPUINowPlayingView
- (void)layoutSubviews {
    %orig;
    if (CP26SpotifyHostIsActive && CP26SpotifyHostHomeEnabled) CP26PlayerViewLaidOut((UIView *)self);
}
%end
%end

%group CP26SpotifyPlaybackScreen
%hook CPSNowPlayingViewController
- (void)viewDidLayoutSubviews {
    %orig;
    CP26PlayerLayout((UIViewController *)self,CP26SpotifyHostIsActive && CP26SpotifyHostHomeEnabled);
}
- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    CP26PlayerLayout((UIViewController *)self,NO);
}
%end
%end

%group CP26SpotifyHomeNativeSelection
%hook CPSListTemplateViewController
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    CP26HomeNativeSelection(table);
    %orig;
}
%end
%end

%group CP26SpotifyHomeRowHeight
%hook CPSListTemplateViewController
- (CGFloat)tableView:(UITableView *)table heightForRowAtIndexPath:(NSIndexPath *)path {
    CGFloat nativeHeight = %orig;
    return CP26HomeHeight(table,path,nativeHeight);
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
            Class artworkCell = NSClassFromString(@"CPSImageRowCell");
            Class listController = NSClassFromString(@"CPSListTemplateViewController");
            if (artworkCell && listController && NSClassFromString(@"CPSTableView")) {
                %init(CP26SpotifyArtworkRowStyle);
                %init(CP26SpotifyHomeTable);
                %init(CP26SpotifyListCellLifecycle);
                %init(CP26SpotifyHomeList);
                if (class_getInstanceMethod(listController,@selector(tableView:didSelectRowAtIndexPath:))) {
                    %init(CP26SpotifyHomeNativeSelection);
                }
                if (class_getInstanceMethod(listController,@selector(tableView:heightForRowAtIndexPath:))) {
                    %init(CP26SpotifyHomeRowHeight);
                }
                SEL configure = NSSelectorFromString(@"configureWithImageRowItem:selectGridItemBlock:selectTitleBlock:showActivityIndicator:");
                if (class_getInstanceMethod(artworkCell,configure)) {
                    %init(CP26SpotifyRowConfiguration);
                }
            }
            if (listController && class_getInstanceMethod(listController,@selector(nowPlayingManager:didUpdateSnapshot:))) {
                %init(CP26SpotifySnapshotChange);
            }
            if (NSClassFromString(@"CPSNowPlayingViewController")) {
                %init(CP26SpotifyPlaybackScreen);
            }
            if (NSClassFromString(@"CPUINowPlayingView")) {
                %init(CP26SpotifyPlayerViewLayout);
            }
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
