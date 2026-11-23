#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#include <unistd.h>

// Read-only Spotify CarPlay renderer inventory for iOS 16.4.1.
// v0.2.51 inspects native panel backgrounds and CALayers; v0.2.54 adds
// a bounded navigation-button/layout inventory for iOS 26 comparison.
// This source file is active ONLY in the CarPlayTemplateUIHost process.
// No UI hooks, renderer overrides, gesture changes or Spotify feature flags.
// Never read UILabel.text, media metadata, accessibilityLabel or images.

static const NSUInteger CP26SpotifyMaxNodes = 1000;
static const NSUInteger CP26SpotifyMaxDepth = 18;
static NSString * const CP26SpotifyReportName = @"CarPlay26-Spotify-TemplateUIHost.txt";

static BOOL CP26SpotifyAutoCaptureEnabled(void) {
    CFPreferencesAppSynchronize(CFSTR("com.tillman109.carplay26"));
    Boolean valid = false;
    Boolean value = CFPreferencesGetAppBooleanValue(
        CFSTR("SpotifyDiagnostics"), CFSTR("com.tillman109.carplay26"), &valid);
    return valid && value;
}

static NSString *CP26SpotifyDescribeRect(CGRect r) {
    if (CGRectIsNull(r) || CGRectIsInfinite(r)) return @"invalid";
    return [NSString stringWithFormat:@"(%.1f,%.1f %.1fx%.1f)",
        r.origin.x, r.origin.y, r.size.width, r.size.height];
}

static NSString *CP26SpotifyBackground(UIColor *color) {
    if (!color) return @"none";
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if ([color getRed:&r green:&g blue:&b alpha:&a]) {
        return [NSString stringWithFormat:@"rgba(%.2f,%.2f,%.2f,%.2f)", r,g,b,a];
    }
    CGFloat w = 0;
    if ([color getWhite:&w alpha:&a]) {
        return [NSString stringWithFormat:@"gray(%.2f,%.2f)",w,a];
    }
    return @"other-color-space";
}

static void CP26SpotifyDumpView(UIView *view, NSMutableString *report,
    NSUInteger depth, NSUInteger *nodes) {
    if (!view || *nodes >= CP26SpotifyMaxNodes || depth > CP26SpotifyMaxDepth) return;
    (*nodes)++;
    // Only structural measurements, not text, art, tags or accessibility data.
    NSString *name = NSStringFromClass(view.class);
    NSString *line = [NSString stringWithFormat:
        @"%*s%@ frame=%@ bounds=%@ hidden=%d alpha=%.2f bg=%@ radius=%.1f mask=%d children=%lu\n",
        (int)MIN(depth*2,40), "", name,
        CP26SpotifyDescribeRect(view.frame), CP26SpotifyDescribeRect(view.bounds),
        view.hidden, view.alpha, CP26SpotifyBackground(view.backgroundColor),
        view.layer.cornerRadius, view.layer.masksToBounds,
        (unsigned long)view.subviews.count];
    [report appendString:line];
    for (UIView *child in view.subviews) {
        if (*nodes >= CP26SpotifyMaxNodes) break;
        CP26SpotifyDumpView(child, report, depth+1, nodes);
    }
}

static void CP26SpotifyDumpControllers(UIViewController *controller,
    NSMutableString *report, NSUInteger depth, NSUInteger *count) {
    if (!controller || *count >= 60 || depth > 10) return;
    (*count)++;
    [report appendFormat:@"%*s%@ children=%lu\n", (int)(depth*2), "",
        NSStringFromClass(controller.class), (unsigned long)controller.childViewControllers.count];
    for (UIViewController *child in controller.childViewControllers) {
        CP26SpotifyDumpControllers(child,report,depth+1,count);
    }
}

// Diagnostic additions do not set colors or hook any views. Limit the work
// to five currently attached image-row cells, 12 layers per inspected view,
// and a bounded walk of the CarPlay-scene view tree.
static NSString *CP26SpotifyLayerColor(CGColorRef color) {
    return color ? CP26SpotifyBackground([UIColor colorWithCGColor:color]) : @"none";
}

static void CP26SpotifyInspectLayers(CALayer *layer, NSMutableString *report,
                                    NSString *prefix, NSUInteger maxLayers) {
    if (!layer) return;
    [report appendFormat:@"%@ layer=%@ bg=%@ opaque=%d alpha=%.2f radius=%.1f border=%.1f contents=%@ sublayers=%lu\n",
        prefix,NSStringFromClass(layer.class),CP26SpotifyLayerColor(layer.backgroundColor),
        layer.opaque,layer.opacity,layer.cornerRadius,layer.borderWidth,
        layer.contents ? @"present" : @"none",(unsigned long)layer.sublayers.count];
    NSUInteger count=0;
    for (CALayer *sublayer in layer.sublayers) {
        if (count++ >= maxLayers) break;
        [report appendFormat:@"%@  childLayer[%lu]=%@ frame=%@ bg=%@ hidden=%d alpha=%.2f radius=%.1f contents=%@ children=%lu\n",
            prefix,(unsigned long)(count-1),NSStringFromClass(sublayer.class),
            CP26SpotifyDescribeRect(sublayer.frame),
            CP26SpotifyLayerColor(sublayer.backgroundColor),sublayer.hidden,
            sublayer.opacity,sublayer.cornerRadius,sublayer.contents ? @"present" : @"none",
            (unsigned long)sublayer.sublayers.count];
    }
}

static void CP26SpotifyInspectBacking(NSString *label, UIView *view,
                                      NSMutableString *report) {
    if (!view) {
        [report appendFormat:@"%@ absent\n",label];
        return;
    }
    [report appendFormat:@"%@ class=%@ frame=%@ bg=%@ opaque=%d hidden=%d alpha=%.2f radius=%.1f children=%lu\n",
        label,NSStringFromClass(view.class),CP26SpotifyDescribeRect(view.frame),
        CP26SpotifyBackground(view.backgroundColor),view.opaque,view.hidden,
        view.alpha,view.layer.cornerRadius,(unsigned long)view.subviews.count];
    CP26SpotifyInspectLayers(view.layer,report,label,12);
}

static void CP26SpotifyInspectImageRow(UIView *row, NSMutableString *report,
                                      NSUInteger index) {
    [report appendFormat:@"\nIMAGE_ROW_DETAIL[%lu] visible=%d\n",(unsigned long)index,
        (!row.hidden && row.alpha > .05)];
    CP26SpotifyInspectBacking(@"ROW",row,report);
    if ([row isKindOfClass:UITableViewCell.class]) {
        UITableViewCell *cell=(UITableViewCell *)row;
        CP26SpotifyInspectBacking(@"ROW.backgroundView",cell.backgroundView,report);
        CP26SpotifyInspectBacking(@"ROW.selectedBackgroundView",cell.selectedBackgroundView,report);
        CP26SpotifyInspectBacking(@"ROW.contentView",cell.contentView,report);
        UIBackgroundConfiguration *cfg=cell.backgroundConfiguration;
        if (cfg) {
            [report appendFormat:@"ROW.backgroundConfiguration present color=%@ cornerRadius=%.1f\n",
                CP26SpotifyBackground(cfg.backgroundColor),cfg.cornerRadius];
        } else {
            [report appendString:@"ROW.backgroundConfiguration absent\n"];
        }
    } else {
        [report appendString:@"ROW is not a UITableViewCell; backgroundConfiguration not examined\n"];
    }
    NSUInteger childCount=0;
    for (UIView *child in row.subviews) {
        if (childCount++ >= 12) break;
        [report appendFormat:@"ROW.child[%lu] %@ bg=%@ alpha=%.2f opaque=%d\n",
            (unsigned long)(childCount-1),NSStringFromClass(child.class),
            CP26SpotifyBackground(child.backgroundColor),child.alpha,child.opaque];
    }
    for (UIView *parent=row.superview; parent && parent!=row.window;
         parent=parent.superview) {
        NSString *name=NSStringFromClass(parent.class);
        if ([name isEqualToString:@"CPSTableView"]) {
            CP26SpotifyInspectBacking(@"ROW.table",parent,report);
            CP26SpotifyInspectBacking(@"ROW.tableSuperview",parent.superview,report);
            break;
        }
    }
}

static void CP26SpotifyFindImageRows(UIView *view, NSMutableString *report,
                                    NSUInteger depth, NSUInteger *budget,
                                    NSUInteger *rows) {
    if (!view || !*budget || depth > 22 || *rows >= 5) return;
    --*budget;
    // Prefer attached, visible cells; hidden reuse cells are already in the
    // structural report and can obscure the actual surface being painted.
    if ([NSStringFromClass(view.class) isEqualToString:@"CPSImageRowCell"] &&
        !view.hidden && view.alpha > .05 && view.window) {
        CP26SpotifyInspectImageRow(view,report,++*rows);
    }
    for (UIView *child in view.subviews) {
        if (!*budget || *rows >= 5) break;
        CP26SpotifyFindImageRows(child,report,depth+1,budget,rows);
    }
}

// v0.2.54: Inspect only the CarPlay template host's native navigation
// surfaces and loaded controller structure. No text, media, accessibility
// labels, artwork or user data are read. This is a snapshot, not a UI hook.
// Keep the view-tree walk bounded and leave native navigation unchanged.
static const NSUInteger CP26SpotifyNavMaxRoots = 8;
static const NSUInteger CP26SpotifyNavMaxNodes = 240;

static BOOL CP26SpotifyIsNavigationSurface(UIView *view) {
    NSString *name = NSStringFromClass(view.class);
    return [name isEqualToString:@"CPSNavigationBar"] ||
           [name isEqualToString:@"CPSTabBar"] ||
           [view isKindOfClass:UITabBar.class];
}

static void CP26SpotifyDumpNavigationNode(UIView *view,
    NSMutableString *report, NSUInteger depth, NSUInteger *budget) {
    if (!view || !*budget || depth > 10) return;
    --*budget;
    CGRect inWindow = view.window ? [view convertRect:view.bounds toView:view.window] : CGRectNull;
    [report appendFormat:
        @"NAV depth=%lu class=%@ frame=%@ windowRect=%@ bg=%@ layerBg=%@ "
         "alpha=%.2f hidden=%d opaque=%d clip=%d radius=%.1f "
         "interactive=%d children=%lu\n",
        (unsigned long)depth, NSStringFromClass(view.class),
        CP26SpotifyDescribeRect(view.frame),CP26SpotifyDescribeRect(inWindow),
        CP26SpotifyBackground(view.backgroundColor),
        CP26SpotifyLayerColor(view.layer.backgroundColor),
        view.alpha,view.hidden,view.opaque,view.clipsToBounds,
        view.layer.cornerRadius,view.userInteractionEnabled,
        (unsigned long)view.subviews.count];
    if ([view isKindOfClass:UIControl.class]) {
        UIControl *control=(UIControl *)view;
        [report appendFormat:
            @"NAV.control depth=%lu state=%lu selected=%d highlighted=%d enabled=%d\n",
            (unsigned long)depth,(unsigned long)control.state,
            control.selected,control.highlighted,control.enabled];
    }
    if ([view isKindOfClass:UITabBar.class]) {
        UITabBar *tab=(UITabBar *)view;
        NSArray<UITabBarItem *> *items=tab.items ?: @[];
        NSUInteger selected=[items indexOfObjectIdenticalTo:tab.selectedItem];
        [report appendFormat:@"NAV.tabBar items=%lu selectedIndex=%ld\n",
            (unsigned long)items.count,selected==NSNotFound ? -1L : (long)selected];
    }
    if ([view isKindOfClass:UILabel.class]) {
        UILabel *label=(UILabel *)view;
        [report appendFormat:
            @"NAV.label depth=%lu fontSize=%.1f alignment=%ld lines=%ld\n",
            (unsigned long)depth,label.font.pointSize,
            (long)label.textAlignment,(long)label.numberOfLines];
    }
    if ([view isKindOfClass:UIImageView.class]) {
        UIImageView *imageView=(UIImageView *)view;
        [report appendFormat:@"NAV.image depth=%lu imagePresent=%d\n",
            (unsigned long)depth,imageView.image!=nil];
    }
    if ([view isKindOfClass:UIVisualEffectView.class]) {
        UIVisualEffectView *effect=(UIVisualEffectView *)view;
        [report appendFormat:@"NAV.material depth=%lu effectClass=%@\n",
            (unsigned long)depth,effect.effect ? NSStringFromClass(effect.effect.class) : @"none"];
    }
    for (UIView *child in view.subviews) {
        if (!*budget) break;
        CP26SpotifyDumpNavigationNode(child,report,depth+1,budget);
    }
}

static void CP26SpotifyFindNavigationSurfaces(UIView *view,
    NSMutableString *report, NSUInteger depth, NSUInteger *searchBudget,
    NSUInteger *roots, NSUInteger *nodeBudget) {
    if (!view || !*searchBudget || !*nodeBudget ||
        *roots >= CP26SpotifyNavMaxRoots || depth > 24) return;
    --*searchBudget;
    if (CP26SpotifyIsNavigationSurface(view) && view.window) {
        [report appendFormat:@"\nNAVIGATION_SURFACE[%lu] %@\n",
            (unsigned long)(*roots+1),NSStringFromClass(view.class)];
        ++*roots;
        NSUInteger localBudget=MIN((NSUInteger)90,*nodeBudget);
        CP26SpotifyDumpNavigationNode(view,report,0,&localBudget);
        *nodeBudget -= MIN((NSUInteger)90,*nodeBudget)-localBudget;
        // The selected native bar already includes descendants; do not
        // count nested tab-like views as separate surfaces.
        return;
    }
    for (UIView *child in view.subviews) {
        if (!*searchBudget || !*nodeBudget || *roots >= CP26SpotifyNavMaxRoots) break;
        CP26SpotifyFindNavigationSurfaces(child,report,depth+1,searchBudget,
                                         roots,nodeBudget);
    }
}

static void CP26SpotifyNavigationControllers(UIViewController *controller,
    NSMutableString *report, NSUInteger depth, NSUInteger *budget) {
    if (!controller || !*budget || depth > 12) return;
    --*budget;
    NSString *name=NSStringFromClass(controller.class);
    if ([name isEqualToString:@"CPSTabBarViewController"] ||
        [name isEqualToString:@"CPSNowPlayingViewController"] ||
        [controller isKindOfClass:UITabBarController.class]) {
        UIView *loaded=controller.viewIfLoaded;
        [report appendFormat:
            @"NAV_CONTROLLER class=%@ children=%lu loaded=%d attached=%d\n",
            name,(unsigned long)controller.childViewControllers.count,
            loaded!=nil,loaded.window!=nil];
        if ([controller isKindOfClass:UITabBarController.class]) {
            UITabBarController *tabs=(UITabBarController *)controller;
            [report appendFormat:@"NAV_CONTROLLER nativeSelectedIndex=%lu\n",
                (unsigned long)tabs.selectedIndex];
        }
        NSUInteger idx=0;
        for (UIViewController *child in controller.childViewControllers) {
            if (idx >= 10) break;
            [report appendFormat:@"NAV_CONTROLLER child[%lu]=%@\n",
                (unsigned long)idx++,NSStringFromClass(child.class)];
        }
    }
    for (UIViewController *child in controller.childViewControllers) {
        if (!*budget) break;
        CP26SpotifyNavigationControllers(child,report,depth+1,budget);
    }
}

static void CP26SpotifyInspectNavigation(UIApplication *app,
    NSMutableString *report) {
    [report appendString:@"\n=== Spotify navigation diagnostics (v0.2.54) ===\n"];
    [report appendString:
        @"Read-only navigation geometry and control states; no label text or music metadata\n"];
    NSUInteger roots=0,navNodes=CP26SpotifyNavMaxNodes,searchBudget=4200;
    NSUInteger controllerBudget=60;
    for (UIScene *scene in app.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] ||
            ![scene.session.role isEqualToString:@"UIWindowSceneSessionRoleCarPlay"]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            CP26SpotifyNavigationControllers(window.rootViewController,
                report,0,&controllerBudget);
            CP26SpotifyFindNavigationSurfaces(window,report,0,&searchBudget,
                &roots,&navNodes);
            if (!searchBudget || !navNodes || roots>=CP26SpotifyNavMaxRoots) break;
        }
        if (!searchBudget || !navNodes || roots>=CP26SpotifyNavMaxRoots) break;
    }
    [report appendFormat:
        @"NAVIGATION_TOTAL surfaces=%lu inspectedNodes=%lu searchRemaining=%lu\n",
        (unsigned long)roots,
        (unsigned long)(CP26SpotifyNavMaxNodes-navNodes),
        (unsigned long)searchBudget];
    if (!roots)
        [report appendString:
            @"No native navigation surface found; keep Spotify Home visible and recapture\n"];
}

static void CP26SpotifyCaptureNow(NSString *reason) {
    if (![NSThread isMainThread]) return;
    UIApplication *app = UIApplication.sharedApplication;
    NSMutableString *report = [NSMutableString stringWithFormat:
        @"CarPlay26 v0.2.54 | Read-only Spotify template host report\n"
         "Date=%@\nPID=%d\nProcess=%@\nTrigger=%@\n"
         "No app text, track titles, contact names, images or playlist data collected\n\n",
        NSDate.date, getpid(), NSProcessInfo.processInfo.processName, reason];
    NSUInteger windows = 0, nodes = 0, controllers = 0;
    for (UIScene *scene in app.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        [report appendFormat:@"SCENE role=%@ state=%ld windows=%lu\n",
            scene.session.role, (long)scene.activationState,
            (unsigned long)windowScene.windows.count];
        for (UIWindow *window in windowScene.windows) {
            if (windows >= 20 || nodes >= CP26SpotifyMaxNodes) break;
            windows++;
            [report appendFormat:@"WINDOW %@ bounds=%@ level=%.1f hidden=%d root=%@\n",
                NSStringFromClass(window.class),CP26SpotifyDescribeRect(window.bounds),
                window.windowLevel,window.hidden,
                window.rootViewController ? NSStringFromClass(window.rootViewController.class) : @"none"];
            CP26SpotifyDumpControllers(window.rootViewController,report,0,&controllers);
            CP26SpotifyDumpView(window,report,0,&nodes);
        }
        if (windows >= 20 || nodes >= CP26SpotifyMaxNodes) break;
    }
    // UIWindowScene.windows is the supported path above. Some legacy
    // template-host configurations may expose no UIWindowScenes, so keep a
    // host-local UIApplication.windows fallback on iOS 16. This property is
    // deprecated but still available; suppress only that single warning,
    // without weakening compiler checks for the rest of the project.
    if (windows == 0) {
        [report appendString:@"NO SCENE WINDOWS; legacy host-window fallback\n"];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        NSArray<UIWindow *> *legacyWindows = app.windows;
#pragma clang diagnostic pop
        for (UIWindow *window in legacyWindows) {
            if (windows >= 20 || nodes >= CP26SpotifyMaxNodes) break;
            windows++;
            [report appendFormat:@"WINDOW %@ bounds=%@ root=%@\n",
                NSStringFromClass(window.class),CP26SpotifyDescribeRect(window.bounds),
                window.rootViewController ? NSStringFromClass(window.rootViewController.class) : @"none"];
            CP26SpotifyDumpControllers(window.rootViewController,report,0,&controllers);
            CP26SpotifyDumpView(window,report,0,&nodes);
        }
    }
    [report appendFormat:@"\nTOTAL windows=%lu views=%lu controllers=%lu truncated=%@\n",
        (unsigned long)windows,(unsigned long)nodes,(unsigned long)controllers,
        nodes >= CP26SpotifyMaxNodes ? @"yes" : @"no"];

    [report appendString:@"\n=== Spotify Home panel backing diagnostics (v0.2.51) ===\n"];
    NSUInteger rowBudget=1800, inspectedRows=0;
    for (UIScene *scene in app.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] ||
            ![scene.session.role isEqualToString:@"UIWindowSceneSessionRoleCarPlay"]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            CP26SpotifyFindImageRows(window,report,0,&rowBudget,&inspectedRows);
            if (!rowBudget || inspectedRows >= 5) break;
        }
        if (!rowBudget || inspectedRows >= 5) break;
    }
    [report appendFormat:@"INSPECTED_IMAGE_ROWS=%lu (maximum=5)\n",
        (unsigned long)inspectedRows];
    if (!inspectedRows)
        [report appendString:@"No attached visible artwork row found; open Spotify Home and recapture\n"];

    CP26SpotifyInspectNavigation(app,report);

    NSFileManager *fs = NSFileManager.defaultManager;
    NSString *home = NSHomeDirectory();
    NSMutableArray<NSString *> *destinations = [NSMutableArray array];
    if (home.length) {
        [destinations addObject:[home stringByAppendingPathComponent:@"Library/Caches"]];
        [destinations addObject:[home stringByAppendingPathComponent:@"tmp"]];
    }
    NSString *tmp = NSTemporaryDirectory();
    if (tmp.length) [destinations addObject:tmp];
    NSError *lastError = nil;
    for (NSString *directory in destinations) {
        if (![fs fileExistsAtPath:directory]) {
            if (![fs createDirectoryAtPath:directory withIntermediateDirectories:YES
                attributes:nil error:&lastError]) continue;
        }
        NSString *file = [directory stringByAppendingPathComponent:CP26SpotifyReportName];
        if ([report writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:&lastError]) {
            NSLog(@"CarPlay26 Spotify diagnostic report saved: %@",file);
            return;
        }
    }
    NSLog(@"CarPlay26 Spotify diagnostic report could not be saved: %@",lastError);
}

static void CP26SpotifyReportRequested(__unused CFNotificationCenterRef center,
    __unused void *observer, __unused CFStringRef name,
    __unused const void *object, __unused CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        CP26SpotifyCaptureNow(@"Settings button");
    });
}

%ctor {
    @autoreleasepool {
        if (![NSProcessInfo.processInfo.processName isEqualToString:@"CarPlayTemplateUIHost"]) return;
        // Register the request handler even when auto-capture is off. The
        // capture button works without a shared-preference read in RootHide.
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
            NULL, CP26SpotifyReportRequested,
            CFSTR("com.tillman109.carplay26.spotify.capture"),NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);
        if (CP26SpotifyAutoCaptureEnabled()) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 8 * NSEC_PER_SEC),
                dispatch_get_main_queue(), ^{
                    CP26SpotifyCaptureNow(@"Automatic on host launch");
                });
        }
    }
}
