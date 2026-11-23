// CarPlay26 v0.2.35 - reversible proof on native CarPlay wallpaper display
// Only the selected 2022 Colour wallpaper gets a visible test banner
// No system assets, cache files, selection identifiers, or other UI are changed
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "WallpaperAssets.h"
#import <objc/runtime.h>
#include <stdarg.h>

static NSMutableString *cpbgReport;
static NSObject *cpbgLock;
static NSUInteger cpbgLargeImages = 0;
static NSUInteger cpbgWindowEntries = 0;
static NSUInteger cpbgRootEvents = 0;
static BOOL cpbgReportedSaveFailure = NO;
static BOOL cpbgIsWallpaperProcess = NO;
static NSUInteger cpbgHomeProofHits = 0;
// All nine native image entries are supported; the two original solids are untouched
static char cpbgRootRefKey;

// Weak reference prevents the image view's diagnostic marker from retaining
// its owning wallpaper controller. Read the live identifier on every update,
// so switching wallpaper never leaves the proof enabled for another slot.
@interface CPBGWeakRoot : NSObject
@property(nonatomic, weak) id root;
@end
@implementation CPBGWeakRoot
@end


static NSString *CPBGProcess(void) {
    NSString *process = NSProcessInfo.processInfo.processName;
    return ([process isEqualToString:@"CarPlay"] ||
            [process isEqualToString:@"CarPlayWallpaper"]) ? process : nil;
}

static void CPBGAppend(NSString *format, ...) {
    va_list ap;
    va_start(ap, format);
    NSString *line = [[NSString alloc] initWithFormat:format arguments:ap];
    va_end(ap);
    if (!cpbgReport) cpbgReport = [NSMutableString string];
    if (line && cpbgReport.length + line.length < 42000) [cpbgReport appendString:line];
}

static void CPBGSave(void) {
    if (!cpbgReport.length) return;
    NSString *filename = [NSString stringWithFormat:@"CarPlay26-background-%@.txt", CPBGProcess() ?: @"unknown"];
    NSMutableArray<NSString *> *folders = [NSMutableArray array];
    for (NSString *folder in @[
        [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"],
        [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches"],
        @"/var/mobile/Documents", @"/var/mobile/Library/Caches",
        NSTemporaryDirectory() ?: @"/private/var/tmp",
        @"/private/var/tmp", @"/tmp"
    ]) {
        if (folder.length && ![folders containsObject:folder]) [folders addObject:folder];
    }
    NSURL *cache = [[NSFileManager defaultManager] URLForDirectory:NSCachesDirectory
         inDomain:NSUserDomainMask appropriateForURL:nil create:NO error:nil];
    if (cache.path.length && ![folders containsObject:cache.path]) [folders addObject:cache.path];
    NSData *bytes = [cpbgReport dataUsingEncoding:NSUTF8StringEncoding];
    NSError *lastError = nil;
    for (NSString *folder in folders) {
        // Do not try to create inaccessible system directories
        if (![[NSFileManager defaultManager] fileExistsAtPath:folder]) continue;
        NSError *error = nil;
        if ([bytes writeToFile:[folder stringByAppendingPathComponent:filename] options:0 error:&error]) return;
        lastError = error;
    }
    if (!cpbgReportedSaveFailure) {
        cpbgReportedSaveFailure = YES;
        NSLog(@"[CarPlay26 BGTrace] unable to save %@ process=%@ home=%@ temporary=%@ lastError=%@",
              filename, CPBGProcess(), NSHomeDirectory(), NSTemporaryDirectory(), lastError);
    }
}

static NSString *CPBGViewParents(UIView *view) {
    NSMutableArray<NSString *> *classes = [NSMutableArray array];
    for (UIView *v=view; v && classes.count<6; v=v.superview) {
        [classes addObject:NSStringFromClass(v.class) ?: @"?"];
    }
    return [classes componentsJoinedByString:@" < "];
}

static BOOL CPBGLargeImage(UIImage *image) {
    return image && image.size.width * image.scale >= 700 &&
           image.size.height * image.scale >= 400;
}

static BOOL CPBGIsSelectedWallpaperView(UIImageView *view, UIImage *image) {
    if (!cpbgIsWallpaperProcess || !CPBGLargeImage(image)) return NO;
    CPBGWeakRoot *ref = objc_getAssociatedObject(view, &cpbgRootRefKey);
    id controller = ref.root;
    if (!controller) return NO;
    Ivar idIvar = class_getInstanceVariable(object_getClass(controller), "_wallpaperIdentifier");
    id identifier = idIvar ? object_getIvar(controller,idIvar) : nil;
    return [identifier isKindOfClass:[NSString class]] &&
           CP26HasWallpaperSlot(identifier);
}

static UIImage *CPBGHomeWallpaperImage(UIImageView *view, UIImage *native) {
    if (!native) return native;
    CPBGWeakRoot *ref=objc_getAssociatedObject(view,&cpbgRootRefKey);
    id controller=ref.root;
    if (!controller) return native;
    Ivar iv=class_getInstanceVariable(object_getClass(controller),"_wallpaperIdentifier");
    id identifier=iv?object_getIvar(controller,iv):nil;
    if (![identifier isKindOfClass:[NSString class]]) return native;
    UIUserInterfaceStyle style=UIUserInterfaceStyleUnspecified;
    if ([controller isKindOfClass:[UIViewController class]])
        style=[(UIViewController *)controller traitCollection].userInterfaceStyle;
    if (style==UIUserInterfaceStyleUnspecified)
        style=view.traitCollection.userInterfaceStyle;
    UIImage *replacement=CP26WallpaperImage(identifier,NO,style);
    return replacement ?: native;
}

static void CPBGRecordImage(UIImageView *view, UIImage *image, NSString *reason, BOOL enteredWindow) {
    if (!CPBGLargeImage(image)) return;
    @synchronized(cpbgLock) {
        if (enteredWindow) {
            if (cpbgWindowEntries >= 20) return;
            cpbgWindowEntries++;
        } else {
            if (cpbgLargeImages >= 30) return;
            cpbgLargeImages++;
        }
        UIWindow *window = view.window;
        CPBGAppend(@"[LARGE IMAGE %@ #%lu] process=%@ image=%.0fx%.0f scale=%.2f viewFrame=%@ window=%@ level=%.1f parents=%@\n",
            reason, (unsigned long)(enteredWindow ? cpbgWindowEntries : cpbgLargeImages),
            CPBGProcess(), image.size.width, image.size.height, image.scale,
            NSStringFromCGRect(view.frame),
            window ? NSStringFromClass(window.class) : @"none",
            window ? (double)window.windowLevel : 0,
            CPBGViewParents(view));
        CPBGSave();
    }
}

static void CPBGClassInventory(void) {
    unsigned int count=0;
    Class *classes=objc_copyClassList(&count);
    NSMutableArray<NSString *> *names=[NSMutableArray array];
    for (unsigned int i=0; i<count; ++i) {
        NSString *n=NSStringFromClass(classes[i]);
        if (!n) continue;
        BOOL prefix = [n hasPrefix:@"DB"] || [n hasPrefix:@"CPW"] ||
                      [n hasPrefix:@"CRS"] || [n hasPrefix:@"CAR"];
        if (prefix && ([n.lowercaseString containsString:@"wallpaper"] ||
                       [n.lowercaseString containsString:@"background"])) [names addObject:n];
    }
    free(classes);
    [names sortUsingSelector:@selector(compare:)];
    CPBGAppend(@"[CLASSES] runtime=%u matched=%lu\n",count,(unsigned long)names.count);
    for (NSString *name in names) {
        Class c=NSClassFromString(name);
        CPBGAppend(@"  Class %@ extends %@\n",name,NSStringFromClass(class_getSuperclass(c)));
        unsigned int nm=0;
        Method *methods=class_copyMethodList(c,&nm);
        for (unsigned int j=0; methods && j<nm && j<24; ++j) {
            CPBGAppend(@"    - %@\n",NSStringFromSelector(method_getName(methods[j])));
        }
        free(methods);
    }
}

// Avoid touching Apple images. Only observe large images presented by
// UIImageViews in the two potential wallpaper-rendering processes
%group CP26BackgroundImageTrace
%hook UIImageView
- (void)setImage:(UIImage *)image {
    UIImage *displayImage=image;
    if (CPBGIsSelectedWallpaperView(self,image)) {
        displayImage=CPBGHomeWallpaperImage(self,image);
        if (displayImage != image) {
            @synchronized(cpbgLock) {
                if (cpbgHomeProofHits++ < 16) {
                    CPBGWeakRoot *ref=objc_getAssociatedObject(self,&cpbgRootRefKey);
                    Ivar iv=class_getInstanceVariable(object_getClass(ref.root),"_wallpaperIdentifier");
                    id identifier=iv?object_getIvar(ref.root,iv):nil;
                    CPBGAppend(@"[HOME WALLPAPER REPLACED #%lu] id=%@ source=%.0fx%.0f\n",
                        (unsigned long)cpbgHomeProofHits,identifier,
                        image.size.width,image.size.height);
                    CPBGSave();
                }
            }
        }
    }
    %orig(displayImage);
    CPBGRecordImage(self, displayImage, @"setImage", NO);
}
- (void)didMoveToWindow {
    %orig;
    if (self.window) CPBGRecordImage(self, self.image, @"didMoveToWindow", YES);
}
%end
%end

// CPWRootViewController declared these methods in the actual iOS 16.4.1
// runtime inventory. Hooking them helps distinguish CarPlayWallpaper's renderer
// from the separate main CarPlay shell without changing either UI
%group CP26WallpaperRootEvents
%hook CPWRootViewController
- (id)initWithWallpaperIdentifier:(id)identifier {
    id result=%orig;
    @synchronized(cpbgLock) {
        if (++cpbgRootEvents <= 12) {
            CPBGAppend(@"[CPW ROOT INIT #%lu] identifier=%@\n",(unsigned long)cpbgRootEvents,
                       [identifier isKindOfClass:[NSString class]] ? identifier : @"(non-string)");
            CPBGSave();
        }
    }
    return result;
}
- (void)viewDidLoad {
    %orig;
    Ivar iv=class_getInstanceVariable(object_getClass(self),"_imageView");
    id view=iv ? object_getIvar(self,iv) : nil;
    if ([view isKindOfClass:[UIImageView class]]) {
        CPBGWeakRoot *ref=[CPBGWeakRoot new];
        ref.root=self;
        objc_setAssociatedObject(view,&cpbgRootRefKey,ref,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        @synchronized(cpbgLock) {
            CPBGAppend(@"[HOME WALLPAPER VIEW REGISTERED] controller=CPWRootViewController imageView=%@\n",
                       NSStringFromClass(object_getClass(view)));
            CPBGSave();
        }
        // The first native image may have been assigned during %orig
        // before the view was registered. Reprocess it through setImage:
        // once, so the proof appears even without another wallpaper update.
        UIImage *current=[(UIImageView *)view image];
        if (CPBGIsSelectedWallpaperView((UIImageView *)view,current)) {
            [(UIImageView *)view setImage:current];
        }
    }
    @synchronized(cpbgLock) {
        if (++cpbgRootEvents <= 12) {
            CPBGAppend(@"[CPW ROOT VIEW LOADED #%lu] imageView=%@\n",
                       (unsigned long)cpbgRootEvents,
                       view ? NSStringFromClass(object_getClass(view)) : @"nil");
            CPBGSave();
        }
    }
}
%end
%end

%ctor {
    @autoreleasepool {
        NSString *process=CPBGProcess();
        if (!process) return;
        cpbgLock=[NSObject new];
        cpbgIsWallpaperProcess=[process isEqualToString:@"CarPlayWallpaper"];
        cpbgReport=[NSMutableString string];
        CPBGAppend(@"CarPlay26 v0.2.36 - native home-screen iOS 26 wallpaper replacement\n");
        CPBGAppend(@"[HOME WALLPAPER TARGET] nine slots (CarPlayWallpaper only)\n");
        CPBGAppend(@"[START] process=%@ pid=%d bundle=%@ home=%@ temporary=%@\n",
                   process, (int)NSProcessInfo.processInfo.processIdentifier,
                   NSBundle.mainBundle.bundleIdentifier ?: @"(none)",
                   NSHomeDirectory(), NSTemporaryDirectory());
        CPBGAppend(@"[MODEL AVAILABLE] CRSUIWallpaper=%d CPWRootViewController=%d\n",
            NSClassFromString(@"CRSUIWallpaper")!=Nil,
            NSClassFromString(@"CPWRootViewController")!=Nil);
        CPBGClassInventory();
        CPBGSave();
        %init(CP26BackgroundImageTrace);
        CPBGAppend(@"[IMAGE VIEW HOOKS INSTALLED] process=%@\n",process);
        if ([process isEqualToString:@"CarPlayWallpaper"] &&
            NSClassFromString(@"CPWRootViewController")) {
            %init(CP26WallpaperRootEvents);
            CPBGAppend(@"[CPW ROOT HOOKS INSTALLED]\n");
        }
        CPBGSave();
    }
}
