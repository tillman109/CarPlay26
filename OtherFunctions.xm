#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <UIKit/UIKit.h>

// CarPlay26 0.2.38: isolated, opt-in experiments based on native window
// ownership. None of these hooks modifies app data, input targets or routing.
//
// Each process opts into *only* the hook group relevant to its own executable,
// and all options default to false. These are prototypes until validated on
// iOS 16.4.1 with both WinPlay and the user's vehicle.

static BOOL CP26ExtraPreference(NSString *key) {
    Boolean valid = false;
    Boolean enabled = CFPreferencesGetAppBooleanValue(
        (__bridge CFStringRef)key, CFSTR("com.tillman109.carplay26"), &valid);
    return valid && enabled;
}

static BOOL CP26IsCarPlayWindow(UIWindow *window) {
    if (!window) return NO;
    UIWindowScene *scene = window.windowScene;
    return [scene.session.role isEqualToString:@"UIWindowSceneSessionRoleCarPlay"];
}

static BOOL CP26HideSplashArtwork = NO;
static BOOL CP26HideCornerOverlay = NO;
static BOOL CP26PreferDarkStockMaps = NO;

// The standalone CarPlaySplashScreen process hosts the startup graphic.
// Hide its UIWindow instead of terminating the process: CarPlay connection
// setup, services and underlying splash lifetime remain unmodified.
// This can leave a blank frame while the receiver finishes connecting.
%group CP26StartupSplash
%hook UIWindow
- (void)setHidden:(BOOL)hidden {
    if (CP26HideSplashArtwork && !hidden) {
        %orig(YES);
    } else {
        %orig(hidden);
    }
}
- (void)makeKeyAndVisible {
    %orig;
    if (CP26HideSplashArtwork) self.hidden = YES;
}
%end
%end

// DashBoard has a separate corner-radius window in iOS 16.
// Limit the change to *that* window in CarPlay scenes. This does not control
// the receiver-side corner blending mask, which may still show black corners.
%group CP26CornerWindow
%hook _DBCornerRadiusWindow
- (void)setHidden:(BOOL)hidden {
    if (CP26HideCornerOverlay && CP26IsCarPlayWindow((UIWindow *)self)) {
        %orig(YES);
    } else {
        %orig(hidden);
    }
}
- (void)makeKeyAndVisible {
    %orig;
    if (CP26HideCornerOverlay && CP26IsCarPlayWindow((UIWindow *)self))
        ((UIWindow *)self).hidden = YES;
}
%end
%end

// Limit dark mode to Apple Maps windows attached to an actual CarPlay scene.
// The iPhone Maps UI is intentionally untouched. The map renderer's vector
// colour palette can be independent of UIKit; this remains experimental until
// an on-device visual comparison confirms it takes effect.
static void CP26ApplyDarkCarPlayMaps(UIWindow *window) {
    if (!CP26PreferDarkStockMaps || !NSThread.isMainThread ||
        !CP26IsCarPlayWindow(window)) return;
    if (window.overrideUserInterfaceStyle != UIUserInterfaceStyleDark)
        window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
}
%group CP26StockMapsAppearance
%hook UIWindow
- (void)setWindowScene:(UIWindowScene *)scene {
    %orig(scene);
    CP26ApplyDarkCarPlayMaps(self);
}
- (void)makeKeyAndVisible {
    %orig;
    CP26ApplyDarkCarPlayMaps(self);
}
%end
%end

%ctor {
    @autoreleasepool {
        CFPreferencesAppSynchronize(CFSTR("com.tillman109.carplay26"));
        if (!CP26ExtraPreference(@"Enabled")) return;

        NSString *process = NSProcessInfo.processInfo.processName;
        if ([process isEqualToString:@"CarPlay"]) {
            CP26HideCornerOverlay = CP26ExtraPreference(@"HideBlackCorners");
            if (CP26HideCornerOverlay && NSClassFromString(@"_DBCornerRadiusWindow"))
                %init(CP26CornerWindow);
        } else if ([process isEqualToString:@"CarPlaySplashScreen"]) {
            CP26HideSplashArtwork = CP26ExtraPreference(@"HideSplashScreen");
            if (CP26HideSplashArtwork) %init(CP26StartupSplash);
        } else if ([NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.Maps"] &&
                   ([process isEqualToString:@"Maps"] ||
                    [process isEqualToString:@"MobileMaps"])) {
            CP26PreferDarkStockMaps = CP26ExtraPreference(@"DarkStockMaps");
            if (CP26PreferDarkStockMaps) %init(CP26StockMapsAppearance);
        }
    }
}
