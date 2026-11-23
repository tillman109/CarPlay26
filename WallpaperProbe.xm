// CarPlay26 v0.2.32 — direct native controller hooks plus early class inventory
// Injection limited to CarPlaySettings and CarPlayWallpaper; no hooks in the
// primary CarPlay shell, dashboard, map, media player, or SpringBoard.
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <stdarg.h>
#include <stdlib.h>

static BOOL wpProbeEnabled = NO;
static NSUInteger wpSnapshotCount = 0;
static BOOL wpDidClassInventory = NO;
static BOOL wpDidAutoCapture = NO;
static BOOL wpNativeHookInstalled = NO;
static NSUInteger wpHookPollAttempts = 0;
static NSMutableSet<NSString *> *wpSeenControllers;
static NSMutableString *wpLog;
static NSString *wpSavedPath;

static NSString *WPSourceProcess(void) {
    NSString *name = NSProcessInfo.processInfo.processName;
    if ([name isEqualToString:@"CarPlaySettings"] || [name isEqualToString:@"CarPlayWallpaper"]) return name;
    NSString *executable = NSBundle.mainBundle.executablePath.lastPathComponent;
    if ([executable isEqualToString:@"CarPlaySettings"] ||
        [executable isEqualToString:@"CarPlayWallpaper"]) return executable;
    return nil;
}

static NSString *WPTrim(NSString *value, NSUInteger cap) {
    if (![value isKindOfClass:[NSString class]]) return @"";
    return value.length <= cap ? value : [[value substringToIndex:cap] stringByAppendingString:@"…"];
}

static void WPAppend(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);
static void WPAppend(NSString *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    NSString *s = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    if (!wpLog) wpLog = [NSMutableString string];
    if (wpLog.length + s.length < 160000) [wpLog appendString:s];
}

// Wallpaper processes may be sandboxed even when RootHide injects our dylib.
// Use the same shared preference + Darwin notification protocol already used
// by the confirmed working Restart CarPlay Services function. The main CarPlay
// shell (which previously saved reports successfully) writes the relay file.
// Darwin notifications signal only; no sensitive wallpaper contents are read.
static void WPRelayToShell(void) {
    NSString *process = WPSourceProcess();
    if (!process) return;
    NSString *key = [@"WallpaperProbeRelay_" stringByAppendingString:process];
    NSString *content = [wpLog copy] ?: @"";
    if (content.length > 125000) content = [content substringFromIndex:content.length - 125000];
    NSDictionary *record = @{
        @"process": process,
        @"time": @(NSDate.date.timeIntervalSince1970),
        @"snapshotCount": @(wpSnapshotCount),
        @"content": content
    };
    CFPreferencesSetAppValue((__bridge CFStringRef)key,
        (__bridge CFPropertyListRef)record, CFSTR("com.tillman109.carplay26"));
    Boolean stored = CFPreferencesAppSynchronize(CFSTR("com.tillman109.carplay26"));
    NSLog(@"[CarPlay26 WallpaperProbe] Relay preferences synchronized=%d process=%@", (int)stored, process);
    CFStringRef event = [process isEqualToString:@"CarPlayWallpaper"]
        ? CFSTR("com.tillman109.carplay26.wallpaper.CarPlayWallpaper")
        : CFSTR("com.tillman109.carplay26.wallpaper.CarPlaySettings");
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        event, NULL, NULL, TRUE);
}

static void WPPersist(void) {
    if (!wpLog.length) return;
    NSString *filename = [NSString stringWithFormat:@"CarPlay26-wallpaper-%@.txt", WPSourceProcess() ?: @"unknown"];
    // System wallpaper apps may be sandboxed. Try the shared mobile Documents
    // directory first, then process-owned Documents, Caches and temporary files.
    // Keep each attempt read-only with respect to Apple wallpaper resources.
    NSArray<NSString *> *paths = @[
        [@"/var/mobile/Documents" stringByAppendingPathComponent:filename],
        [[NSHomeDirectory() stringByAppendingPathComponent:@"Documents"] stringByAppendingPathComponent:filename],
        [[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches"] stringByAppendingPathComponent:filename],
        [NSTemporaryDirectory() stringByAppendingPathComponent:filename]
    ];
    NSMutableArray<NSString *> *destinations = [paths mutableCopy];
    NSURL *userCache = [[NSFileManager defaultManager]
        URLForDirectory:NSCachesDirectory inDomain:NSUserDomainMask
        appropriateForURL:nil create:YES error:nil];
    if (userCache.path.length) [destinations addObject:
        [userCache.path stringByAppendingPathComponent:filename]];
    NSString *base = nil;
    NSError *lastError = nil;
    for (NSString *candidate in destinations) {
        [[NSFileManager defaultManager] createDirectoryAtPath:[candidate stringByDeletingLastPathComponent]
                                  withIntermediateDirectories:YES attributes:nil error:nil];
        NSError *err = nil;
        if ([[wpLog dataUsingEncoding:NSUTF8StringEncoding] writeToFile:candidate options:0 error:&err]) {
            base = candidate;
            break;
        }
        lastError = err;
    }
    if (base) {
        if (![wpSavedPath isEqualToString:base]) NSLog(@"[CarPlay26 WallpaperProbe] Saved report to %@", base);
        wpSavedPath = base;
    } else {
        NSLog(@"[CarPlay26 WallpaperProbe] Failed all report locations: %@", lastError);
    }
    WPAppend(@"Local report write: %@ (%@)\n", base ?: @"FAILED", lastError.localizedDescription ?: @"no error");
    WPRelayToShell();
}

static void WPObjectClassSummary(Class c, NSUInteger maxMethods) {
    if (!c) return;
    WPAppend(@"  Class %@ extends %@\n", NSStringFromClass(c), NSStringFromClass(class_getSuperclass(c)));
    unsigned int nm=0;
    Method *methods=class_copyMethodList(c,&nm);
    WPAppend(@"    declared instance methods=%u\n",nm);
    for (unsigned int i=0; i<nm && i<maxMethods; i++) {
        SEL sel=method_getName(methods[i]);
        const char *sig=method_getTypeEncoding(methods[i]);
        WPAppend(@"      - %@  %s\n", NSStringFromSelector(sel), sig ?: "?");
    }
    if (nm>maxMethods) WPAppend(@"      ... %u more\n",nm-(unsigned int)maxMethods);
    free(methods);
    unsigned int ni=0;
    Ivar *ivars=class_copyIvarList(c,&ni);
    WPAppend(@"    declared ivars=%u\n",ni);
    for(unsigned int i=0; i<ni && i<32; i++) {
        WPAppend(@"      ivar %s %s\n",ivar_getName(ivars[i]) ?: "?", ivar_getTypeEncoding(ivars[i]) ?: "?");
    }
    free(ivars);
}

// The old 48-class generic inventory was saturated by PhotosUI and PosterBoard
// classes before it ever reached CARWallpaperPanel or CPWRootViewController.
// Log only classes owned by CarPlay's wallpaper UI and presentation components.
static void WPClassInventory(void) {
    if (wpDidClassInventory) return;
    wpDidClassInventory = YES;
    unsigned int count=0;
    Class *classes=objc_copyClassList(&count);
    WPAppend(@"Focused CarPlay wallpaper runtime classes (total runtime=%u):\n",count);
    NSMutableArray<NSString *> *matches=[NSMutableArray array];
    for (unsigned int i=0;i<count;i++) {
        NSString *name=NSStringFromClass(classes[i]);
        if (!name) continue;
        BOOL target = [name isEqualToString:@"CARWallpaperPanel"] ||
            [name isEqualToString:@"CPWRootViewController"] ||
            ([name hasPrefix:@"CAR"] && [name.lowercaseString containsString:@"wallpaper"]) ||
            ([name hasPrefix:@"CPW"] && ([name.lowercaseString containsString:@"wallpaper"] ||
                                         [name.lowercaseString containsString:@"root"]));
        if (target) [matches addObject:name];
    }
    [matches sortUsingSelector:@selector(compare:)];
    WPAppend(@"Matched %lu specific CarPlay classes\n",(unsigned long)matches.count);
    for (NSString *name in matches) {
        WPObjectClassSummary(NSClassFromString(name),100);
    }
    free(classes);
    WPAppend(@"\n");
}

// Read-only inspection of the native picker controller's object ivars. We do
// not send unknown selectors, mutate any model, or enumerate personal content.
static void WPInspectControllerState(UIViewController *vc) {
    if (!vc) return;
    NSString *name=NSStringFromClass(vc.class);
    if (![name isEqualToString:@"CARWallpaperPanel"] &&
        ![name isEqualToString:@"CPWRootViewController"]) return;
    WPAppend(@"Target controller state: %@ loaded=%d\n",name,(int)vc.isViewLoaded);
    unsigned int n=0;
    Ivar *ivars=class_copyIvarList(vc.class,&n);
    for (unsigned int i=0;i<n && i<75;i++) {
        Ivar iv=ivars[i];
        const char *enc=ivar_getTypeEncoding(iv);
        const char *raw=ivar_getName(iv);
        if (!enc || enc[0]!='@') continue;  // avoid primitive, C++ and raw-pointer ivars
        id value=object_getIvar(vc,iv);
        NSString *type=value ? NSStringFromClass([value class]) : @"nil";
        WPAppend(@"  %s -> %@",raw ?: "?",type);
        if ([value isKindOfClass:[NSString class]]) {
            WPAppend(@" value=%@",WPTrim(value,100));
        } else if ([value isKindOfClass:[NSURL class]]) {
            WPAppend(@" path=%@",WPTrim([(NSURL *)value path],150));
        } else if ([value isKindOfClass:[NSArray class]]) {
            NSArray *items=(NSArray *)value;
            WPAppend(@" count=%lu",(unsigned long)items.count);
            for (id item in [items subarrayWithRange:NSMakeRange(0,MIN(items.count,8))]) {
                WPAppend(@"\n    array item class=%@",NSStringFromClass([item class]));
                // Never stringify arbitrary objects, as that can execute custom code.
            }
        } else if ([value isKindOfClass:[NSDictionary class]]) {
            WPAppend(@" keys=%@",WPTrim([[(NSDictionary *)value allKeys] description],200));
        }
        WPAppend(@"\n");
    }
    free(ivars);
    if (vc.isViewLoaded) {
        WPAppend(@"Target controller view: %@ bounds=%@\n",
            NSStringFromClass(vc.view.class),NSStringFromCGRect(vc.view.bounds));
    }
}

static void WPViewTree(UIView *view, NSUInteger depth, NSUInteger *remaining, NSUInteger maxDepth) {
    if (!view || depth>maxDepth || *remaining==0) return;
    (*remaining)--;
    NSString *pad=[@"" stringByPaddingToLength:depth*2 withString:@" " startingAtIndex:0];
    CGRect r=view.frame;
    WPAppend(@"%@%@ frame=(%.0f %.0f %.0f %.0f) hidden=%d alpha=%.2f\n",pad,NSStringFromClass(view.class),
        r.origin.x,r.origin.y,r.size.width,r.size.height,view.hidden,view.alpha);
    if ([view isKindOfClass:[UICollectionView class]]) {
        UICollectionView *cv=(UICollectionView *)view;
        WPAppend(@"%@  Collection: dataSource=%@ delegate=%@ layout=%@\n",pad,
            NSStringFromClass([cv.dataSource class]),NSStringFromClass([cv.delegate class]),
            NSStringFromClass([cv.collectionViewLayout class]));
        NSInteger sections=[cv numberOfSections];
        WPAppend(@"%@  sections=%ld",pad,(long)sections);
        for (NSInteger i=0;i<MIN(sections,8);i++) WPAppend(@" items[%ld]=%ld",(long)i,(long)[cv numberOfItemsInSection:i]);
        WPAppend(@"\n");
        WPObjectClassSummary([cv.dataSource class], 35);
    }
    if ([view isKindOfClass:[UITableView class]]) {
        UITableView *tv=(UITableView *)view;
        WPAppend(@"%@  Table: dataSource=%@ delegate=%@\n",pad,
            NSStringFromClass([tv.dataSource class]),NSStringFromClass([tv.delegate class]));
    }
    if ([view isKindOfClass:[UIImageView class]]) {
        UIImage *image=((UIImageView *)view).image;
        if (image) WPAppend(@"%@  Image size=%.0fx%.0f scale=%.1f\n",pad,image.size.width,image.size.height,image.scale);
    }
    for (UIView *sub in view.subviews) WPViewTree(sub,depth+1,remaining,maxDepth);
}

static void WPControllers(UIViewController *vc, NSUInteger depth, NSUInteger *remaining) {
    if (!vc || depth>5 || *remaining==0) return;
    (*remaining)--;
    NSString *pad=[@"" stringByPaddingToLength:depth*2 withString:@" " startingAtIndex:0];
    WPAppend(@"%@Controller %@ title=%@ children=%lu\n",pad,NSStringFromClass(vc.class),WPTrim(vc.title,64),(unsigned long)vc.childViewControllers.count);
    WPInspectControllerState(vc);
    for (UIViewController *child in vc.childViewControllers) WPControllers(child,depth+1,remaining);
    if (vc.presentedViewController) WPControllers(vc.presentedViewController,depth+1,remaining);
}

static void WPSnapshot(NSString *reason) {
    if (!wpProbeEnabled || wpSnapshotCount>=10 || ![NSThread isMainThread]) return;
    wpSnapshotCount++;
    WPAppend(@"\n=== Snapshot %lu | %@ | %@ ===\n",(unsigned long)wpSnapshotCount,[NSDate date],WPTrim(reason,100));
    WPAppend(@"process=%@ bundle=%@ path=%@\n",NSProcessInfo.processInfo.processName,
        NSBundle.mainBundle.bundleIdentifier,NSBundle.mainBundle.bundlePath);
    WPClassInventory();
    UIApplication *app = [UIApplication sharedApplication];
    NSUInteger wc = 0;
    // iOS 15+ requires scene-owned window enumeration (UIApplication.windows is deprecated).
    for (UIScene *scene in app.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        for (UIWindow *window in windowScene.windows) {
            if (wc >= 9) break;
            wc++;
            WPAppend(@"Window %@ root=%@\n", NSStringFromClass(window.class), NSStringFromClass(window.rootViewController.class));
            NSUInteger controllers = 28; WPControllers(window.rootViewController, 0, &controllers);
            // The original window tree stops above the nested wallpaper grid.
            // Descend through controller containment to inspect the real picker
            // rather than UIKit's unrelated index-overlay collection view.
            NSMutableArray<UIViewController *> *queue=[NSMutableArray array];
            if (window.rootViewController) [queue addObject:window.rootViewController];
            NSUInteger traversed=0;
            while (queue.count && traversed++<36) {
                UIViewController *candidate=queue.firstObject;
                [queue removeObjectAtIndex:0];
                if ([candidate isKindOfClass:[UIViewController class]]) {
                    NSString *className=NSStringFromClass(candidate.class);
                    if (([className isEqualToString:@"CARWallpaperPanel"] ||
                         [className isEqualToString:@"CPWRootViewController"]) &&
                        candidate.isViewLoaded) {
                        WPAppend(@"=== FOCUSED %@ UIView hierarchy ===\n",className);
                        NSUInteger nodes=180;
                        WPViewTree(candidate.view,0,&nodes,12);
                    }
                    [queue addObjectsFromArray:candidate.childViewControllers];
                    if (candidate.presentedViewController) [queue addObject:candidate.presentedViewController];
                }
            }
            if (!window.hidden && window.alpha > .05) {
                NSUInteger views = 135; WPViewTree(window, 0, &views,5);
            }
        }
        if (wc >= 9) break;
    }
    WPPersist();
}

// v0.2.32: Apple native controller classes may override viewWillAppear/
// viewDidAppear without calling their UIViewController superclass. Hook the
// specific runtime class itself, rather than its parent, so our one-shot
// probe executes regardless of whether super is called.
static void WPOnNativeWallpaperController(UIViewController *vc, NSString *event) {
    NSString *process = WPSourceProcess();
    NSString *className = NSStringFromClass([vc class]);
    BOOL valid =
        ([process isEqualToString:@"CarPlaySettings"] &&
         [className isEqualToString:@"CARWallpaperPanel"]) ||
        ([process isEqualToString:@"CarPlayWallpaper"] &&
         [className isEqualToString:@"CPWRootViewController"]);
    if (!valid || wpDidAutoCapture) return;
    wpDidAutoCapture = YES;
    wpProbeEnabled = YES;
    wpSnapshotCount = 0;
    wpDidClassInventory = NO;
    wpSeenControllers = [NSMutableSet set];
    wpLog = [NSMutableString string];
    WPAppend(@"CarPlay26 0.2.30 - DIRECT native wallpaper controller capture\n");
    WPAppend(@"Direct %@ hook fired in %@ on main thread=%d at %@\n",
             event, process, (int)[NSThread isMainThread], NSDate.date);
    WPAppend(@"Controller=%@ loaded=%d\n", className, (int)vc.isViewLoaded);
    // Save receipt immediately: it distinguishes a live class hook from a
    // deferred snapshot that could be postponed by the CarPlay process.
    WPPersist();
    if ([NSThread isMainThread]) {
        WPSnapshot([@"direct hook: " stringByAppendingString:event]);
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            WPSnapshot([@"direct hook: " stringByAppendingString:event]);
        });
    }
}

%group CarPlay26WallpaperPickerDirect
%hook CARWallpaperPanel
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    WPOnNativeWallpaperController((UIViewController *)self, @"CARWallpaperPanel viewWillAppear");
}
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    WPOnNativeWallpaperController((UIViewController *)self, @"CARWallpaperPanel viewDidAppear");
}
%end
%end

%group CarPlay26WallpaperDisplayDirect
%hook CPWRootViewController
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    WPOnNativeWallpaperController((UIViewController *)self, @"CPWRootViewController viewWillAppear");
}
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    WPOnNativeWallpaperController((UIViewController *)self, @"CPWRootViewController viewDidAppear");
}
%end
%end

// v0.2.32: inspect the actual CarPlay wallpaper model path synchronously.
// All selectors here were confirmed in the v0.2.30 runtime class inventory.
// Do not queue to the main thread, patch image caches, or change wallpaper
// preferences: this probe is only for identifying image source and identifiers.
static NSUInteger wpCellInitHits=0;
static NSUInteger wpCellSetterHits=0;
static NSUInteger wpPanelSectionsHits=0;
static NSUInteger wpDisplayIdentifierHits=0;
static NSUInteger wpDisplayImageHits=0;

static void WPDescribeModelObject(id model, NSString *context) {
    if (!model) {
        WPAppend(@"[MODEL] %@ model=nil\n",context);
        return;
    }
    WPAppend(@"[MODEL] %@ class=%@\n",context,NSStringFromClass(object_getClass(model)));
    // Never send private/unknown getter messages to model objects. Only inspect
    // their already-allocated object ivars, bounded to two class levels.
    Class cls=object_getClass(model);
    NSUInteger levels=0;
    for (; cls && cls != [NSObject class] && levels < 2;
           cls=class_getSuperclass(cls),levels++) {
        unsigned int n=0;
        Ivar *ivars=class_copyIvarList(cls,&n);
        for (unsigned int i=0; ivars && i<n && i<32; i++) {
            Ivar iv=ivars[i];
            const char *encoding=ivar_getTypeEncoding(iv);
            if (!encoding || encoding[0]!='@') continue;
            id value=object_getIvar(model,iv);
            NSString *name=[NSString stringWithUTF8String:ivar_getName(iv) ?: "?"];
            NSString *valueClass=value ? NSStringFromClass(object_getClass(value)) : @"nil";
            WPAppend(@"    %@ -> %@",name,valueClass);
            if ([value isKindOfClass:[NSString class]]) {
                WPAppend(@" text=%@",WPTrim(value,160));
            } else if ([value isKindOfClass:[NSURL class]]) {
                WPAppend(@" file=%@",WPTrim([(NSURL *)value path],180));
            } else if ([value isKindOfClass:[NSArray class]]) {
                WPAppend(@" count=%lu",(unsigned long)[(NSArray *)value count]);
            } else if ([value isKindOfClass:[NSDictionary class]]) {
                WPAppend(@" count=%lu",(unsigned long)[(NSDictionary *)value count]);
            } else if ([value isKindOfClass:[UIImage class]]) {
                UIImage *image=(UIImage *)value;
                WPAppend(@" dimensions=%.0fx%.0f",image.size.width,image.size.height);
            }
            WPAppend(@"\n");
        }
        free(ivars);
    }
}

static void WPLogDisplayState(id controller, NSString *label) {
    if (!controller) return;
    Class c=object_getClass(controller);
    Ivar idIvar=class_getInstanceVariable(c,"_wallpaperIdentifier");
    id ident=idIvar ? object_getIvar(controller,idIvar) : nil;
    WPAppend(@"[DISPLAY] %@ wallpaperIdentifier=%@\n",label,
             [ident isKindOfClass:[NSString class]] ? WPTrim(ident,160) : @"unavailable");
    Ivar imgIvar=class_getInstanceVariable(c,"_imageView");
    id view=imgIvar ? object_getIvar(controller,imgIvar) : nil;
    if ([view isKindOfClass:[UIImageView class]]) {
        UIImage *image=[(UIImageView *)view image];
        WPAppend(@"[DISPLAY] image=%@ size=%.0fx%.0f scale=%.2f\n",
                 image ? @"present" : @"nil",image.size.width,image.size.height,image.scale);
    }
    WPPersist();
}

%group CarPlay26WallpaperModelProbe
%hook CARWallpaperCellView
- (id)initWithWallpaper:(id)wallpaper wallpaperPreferences:(id)preferences {
    id result=%orig;
    if (wpCellInitHits++ < 6) {
        WPAppend(@"[CELL INIT] hit=%lu view=%@\n",(unsigned long)wpCellInitHits,
                 NSStringFromClass(object_getClass(result)));
        WPDescribeModelObject(wallpaper,@"CARWallpaperCellView initWithWallpaper");
        WPAppend(@"[PREFERENCES] class=%@\n",preferences ? NSStringFromClass(object_getClass(preferences)) : @"nil");
        WPPersist();
    }
    return result;
}
- (void)setWallpaper:(id)wallpaper {
    %orig;
    if (wpCellSetterHits++ < 6) {
        WPAppend(@"[CELL SET] hit=%lu\n",(unsigned long)wpCellSetterHits);
        WPDescribeModelObject(wallpaper,@"CARWallpaperCellView setWallpaper");
        WPPersist();
    }
}
%end
%hook CARWallpaperPanel
- (id)specifierSections {
    id result=%orig;
    if (wpPanelSectionsHits++ < 3) {
        WPAppend(@"[PANEL SECTIONS] hit=%lu type=%@\n",
                 (unsigned long)wpPanelSectionsHits,
                 result ? NSStringFromClass(object_getClass(result)) : @"nil");
        if ([result isKindOfClass:[NSArray class]]) {
            NSArray *sections=(NSArray *)result;
            WPAppend(@"[PANEL SECTIONS] count=%lu\n",(unsigned long)sections.count);
            NSUInteger n=MIN(sections.count,5);
            for (NSUInteger i=0;i<n;i++) {
                id item=sections[i];
                WPAppend(@"  section[%lu] class=%@\n",(unsigned long)i,
                         item ? NSStringFromClass(object_getClass(item)) : @"nil");
            }
        }
        WPPersist();
    }
    return result;
}
%end
%end

%group CarPlay26WallpaperDisplayModelProbe
%hook CPWRootViewController
- (void)setWallpaperIdentifier:(id)identifier {
    %orig;
    if (wpDisplayIdentifierHits++ < 8) {
        WPAppend(@"[SET IDENTIFIER] hit=%lu identifier=%@\n",
                 (unsigned long)wpDisplayIdentifierHits,
                 [identifier isKindOfClass:[NSString class]] ? WPTrim(identifier,160) : @"non-string");
        WPLogDisplayState(self,@"setWallpaperIdentifier:");
    }
}
- (void)_updateWallpaperImage {
    %orig;
    if (wpDisplayImageHits++ < 8) {
        WPAppend(@"[UPDATE IMAGE] hit=%lu\n",(unsigned long)wpDisplayImageHits);
        WPLogDisplayState(self,@"_updateWallpaperImage");
    }
}
%end
%end

// Explicit capture from the user's Preferences page, independent of whether
// the sandboxed wallpaper processes can read the tweak's CFPreferences domain.
// This is one-shot, read-only and does not alter any cached wallpaper assets.
static char wpCaptureObserver;
static void WPCaptureReceived(__unused CFNotificationCenterRef center,
    __unused void *observer, __unused CFStringRef name,
    __unused const void *object, __unused CFDictionaryRef userInfo) {
    // Persist a receipt on the notification-delivery thread, *before* relying
    // on the app's main queue. If main-thread work is suspended, this proves
    // whether the message reached the wallpaper process at all.
    WPAppend(@"MANUAL capture notification RECEIVED at %@ process=%@\n",
             NSDate.date, WPSourceProcess() ?: @"unknown");
    WPPersist();
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *process = WPSourceProcess();
        if (!process) return;
        wpProbeEnabled = YES;
        wpSnapshotCount = 0;
        wpDidClassInventory = NO;
        wpSeenControllers = [NSMutableSet set];
        wpLog = [NSMutableString string];
        WPAppend(@"CarPlay26 0.2.30 - MANUAL native CarPlay wallpaper capture\n");
        WPAppend(@"Captured at %@ in process=%@ bundle=%@\n",
            NSDate.date, process, NSBundle.mainBundle.bundleIdentifier);
        WPAppend(@"Triggered by direct Darwin notification; no shared preference needed\n");
        WPSnapshot(@"manual capture from CarPlay26 Settings");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{ WPSnapshot(@"manual capture +2 seconds"); });
    });
}

// CarPlay shell requests an explicit response after both wallpaper apps load.
// This is needed if their original startup broadcasts occurred before CarPlay
// registered its listener; requests also enable bounded snapshots when a
// sandboxed process could not read the shared InspectWallpaperPicker toggle.
static char wpRequestObserver;
static void WPRequestReceived(__unused CFNotificationCenterRef center,
    __unused void *observer, __unused CFStringRef name,
    __unused const void *object, __unused CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        WPAppend(@"Main CarPlay shell requested diagnostic report at %@\n", NSDate.date);
        if (!wpSeenControllers) wpSeenControllers = [NSMutableSet set];
        wpProbeEnabled = YES; // The shell sends requests only when setting is enabled
        WPSnapshot(@"explicit shell request");
        // If we've reached the snapshot cap, still emit an acknowledgment.
        WPRelayToShell();
    });
}

// The native picker class may be registered after dylib constructors run.
// Wait for it on the app's main queue rather than treating an early missing
// class as a permanent failure. At most 120 inexpensive checks over 90 s.
static void WPPollForNativeWallpaperClass(void) {
    if (wpNativeHookInstalled || wpHookPollAttempts >= 120) return;
    NSString *process = WPSourceProcess();
    if (!process) return;
    NSString *target = [process isEqualToString:@"CarPlaySettings"]
        ? @"CARWallpaperPanel" : @"CPWRootViewController";
    wpHookPollAttempts++;
    Class c = NSClassFromString(target);
    if (c) {
        wpNativeHookInstalled = YES;
        WPAppend(@"LATE CLASS FOUND target=%@ after attempt=%lu at %@\n",
                 target, (unsigned long)wpHookPollAttempts, NSDate.date);
        if ([process isEqualToString:@"CarPlaySettings"]) {
            %init(CarPlay26WallpaperPickerDirect);
        } else {
            %init(CarPlay26WallpaperDisplayDirect);
        }
        WPAppend(@"DIRECT HOOK INSTALLED target=%@ at %@\n", target, NSDate.date);
        // A fresh class inventory now includes late-loaded CarPlay UI classes.
        wpDidClassInventory = NO;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            WPSnapshot(@"automatic snapshot after native wallpaper class loaded");
        });
        WPPersist();
    } else if (wpHookPollAttempts < 120) {
        if (wpHookPollAttempts == 1 || wpHookPollAttempts == 12) {
            WPAppend(@"WAITING FOR CLASS target=%@ attempt=%lu at %@\n",
                     target, (unsigned long)wpHookPollAttempts, NSDate.date);
            WPPersist();
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(750 * NSEC_PER_MSEC)),
                       dispatch_get_main_queue(), ^{ WPPollForNativeWallpaperClass(); });
    } else {
        WPAppend(@"CLASS NOT FOUND after 120 checks target=%@ at %@\n", target, NSDate.date);
        WPPersist();
    }
}

// Temporary one-shot diagnostics: CarPlaySettings and CarPlayWallpaper cannot
// reliably read the settings app's CFPreferences domain under RootHide.
// Capture a bounded number of snapshots regardless of that preference.
static void WPScheduleIndependentCapture(NSTimeInterval delay, NSString *reason) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        wpProbeEnabled = YES;
        wpDidClassInventory = NO;
        WPSnapshot(reason);
    });
}

%ctor {
    @autoreleasepool {
        NSString *process=WPSourceProcess();
        NSString *exe=NSBundle.mainBundle.executablePath.lastPathComponent;
        if (!process) return;
        wpLog=[NSMutableString string];
        WPAppend(@"CarPlay26 0.2.30 — FOCUSED native CarPlay wallpaper picker probe\n");
        WPAppend(@"Loaded processName=%@ executable=%@ bundle=%@ iOS=%@\n",
            NSProcessInfo.processInfo.processName, exe,
            NSBundle.mainBundle.bundleIdentifier, UIDevice.currentDevice.systemVersion);
        WPAppend(@"home=%@ temporary=%@\n",NSHomeDirectory(),NSTemporaryDirectory());
        NSLog(@"[CarPlay26 WallpaperProbe] v0.2.32 constructor in %@ (exe=%@)",process,exe);
        // Register BEFORE attempting file IO or preference reads, so that an
        // isolated wallpaper process can answer the main shell regardless.
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
            &wpRequestObserver, WPRequestReceived,
            CFSTR("com.tillman109.carplay26.wallpaper.request"),
            NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
            &wpCaptureObserver, WPCaptureReceived,
            CFSTR("com.tillman109.carplay26.wallpaper.capture"),
            NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        Boolean synced=CFPreferencesAppSynchronize(CFSTR("com.tillman109.carplay26"));
        Boolean valid=NO;
        Boolean setting=CFPreferencesGetAppBooleanValue(CFSTR("InspectWallpaperPicker"),
                      CFSTR("com.tillman109.carplay26"),&valid);
        wpProbeEnabled=(setting && valid);
        WPAppend(@"InspectWallpaperPicker setting=%d valid=%d synced=%d enabled=%d\n",
                 (int)setting,(int)valid,(int)synced,(int)wpProbeEnabled);
        // Send a lightweight startup signal even if local file IO and shared
        // preferences are denied, then attempt a local report.
        WPRelayToShell();
        WPPersist();
        // Probe the actual app-owned filesystem again after startup.  A
        // backgrounded wallpaper app can lack a ready sandbox at constructor
        // time, even though the injected dylib is present in memory.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC),
          dispatch_get_main_queue(), ^{
              WPAppend(@"Delayed startup file test at %@\n", NSDate.date);
              WPPersist();
          });
        wpSeenControllers=[NSMutableSet set];
        WPAppend(@"Automatic diagnostic capture enabled for v0.2.32; independent of inaccessible settings preference\n");
        // Hook target may arrive late via framework loading: poll on main queue.
        dispatch_async(dispatch_get_main_queue(), ^{ WPPollForNativeWallpaperClass(); });
        // Even if neither native appearance hook fires, inspect live windows
        // at several times; class registration can happen after startup.
        WPScheduleIndependentCapture(3, @"independent startup +3 seconds");
        WPScheduleIndependentCapture(12, @"independent startup +12 seconds");
        WPScheduleIndependentCapture(25, @"independent startup +25 seconds");
        WPClassInventory();
        WPAppend(@"[MODEL INVENTORY] synchronous runtime class inspection\n");
        if ([process isEqualToString:@"CarPlaySettings"]) {
            WPObjectClassSummary(NSClassFromString(@"CRSUIWallpaper"),100);
            WPObjectClassSummary(NSClassFromString(@"CRSUIWallpaperPreferences"),80);
            WPObjectClassSummary(NSClassFromString(@"CARWallpaperCellView"),60);
            WPObjectClassSummary(NSClassFromString(@"CARWallpaperPanel"),50);
            Class cell=NSClassFromString(@"CARWallpaperCellView");
            Class panel=NSClassFromString(@"CARWallpaperPanel");
            WPAppend(@"[HOOK AVAILABILITY] cell=%d panel=%d\n",(int)(cell!=Nil),(int)(panel!=Nil));
            if (cell && panel) {
                %init(CarPlay26WallpaperModelProbe);
                WPAppend(@"[MODEL HOOK INSTALLED] CARWallpaperCellView and CARWallpaperPanel\n");
            }
        } else if ([process isEqualToString:@"CarPlayWallpaper"]) {
            WPObjectClassSummary(NSClassFromString(@"CPWRootViewController"),40);
            Class root=NSClassFromString(@"CPWRootViewController");
            WPAppend(@"[HOOK AVAILABILITY] display=%d\n",(int)(root!=Nil));
            if (root) {
                %init(CarPlay26WallpaperDisplayModelProbe);
                WPAppend(@"[MODEL HOOK INSTALLED] CPWRootViewController\n");
            }
        }
        WPPersist();
    }
}
