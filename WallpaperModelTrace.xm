// CarPlay26 v0.2.33 — one-wallpaper visual replacement proof
// Complementary to WallpaperProbe.xm; no UIKit appearance modifications.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "WallpaperAssets.h"
#import <objc/runtime.h>
#include <stdarg.h>

static NSMutableString *cpwmReport;
static NSString *cpwmSaved;
static NSUInteger cpwmCreates, cpwmThumbnails, cpwmFullImages;
static id cpwmLock;

static NSString *CPWMProcess(void) {
    NSString *p = NSProcessInfo.processInfo.processName;
    return [@[@"CarPlay", @"CarPlaySettings", @"CarPlayWallpaper"] containsObject:p] ? p : nil;
}

static void CPWMAppend(NSString *fmt, ...) {
    if (!cpwmReport) cpwmReport = [NSMutableString string];
    va_list args;
    va_start(args,fmt);
    NSString *s=[[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    if (s && cpwmReport.length + s.length < 24000) [cpwmReport appendString:s];
}

static void CPWMSave(void) {
    if (!cpwmReport.length) return;
    NSString *name=[NSString stringWithFormat:@"CarPlay26-modeltrace-%@.txt",CPWMProcess() ?: @"unknown"];
    NSArray *folders=@[
        [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"],
        [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches"],
        NSTemporaryDirectory() ?: @"/tmp"
    ];
    NSData *data=[cpwmReport dataUsingEncoding:NSUTF8StringEncoding];
    for (NSString *folder in folders) {
        if (!folder.length) continue;
        [[NSFileManager defaultManager] createDirectoryAtPath:folder
                                  withIntermediateDirectories:YES attributes:nil error:nil];
        NSString *file=[folder stringByAppendingPathComponent:name];
        NSError *e=nil;
        if ([data writeToFile:file options:0 error:&e]) {
            cpwmSaved=file;
            break;
        }
    }
}

static NSString *CPWMText(id candidate) {
    return [candidate isKindOfClass:[NSString class]] ?
        [(NSString *)candidate substringToIndex:MIN([(NSString *)candidate length],160)] : @"(none)";
}

static id CPWMIvar(id model, const char *name) {
    if (!model) return nil;
    Ivar iv=class_getInstanceVariable(object_getClass(model),name);
    return iv ? object_getIvar(model,iv) : nil;
}

static void CPWMRecord(id model, NSString *event, UITraitCollection *traits, id result, NSUInteger number) {
    @synchronized(cpwmLock) {
        NSString *identifier=CPWMText(CPWMIvar(model,"_wallpaperIdentifier"));
        NSString *catalog=CPWMText(CPWMIvar(model,"_wallpaperAssetCatalogName"));
        NSString *thumbCatalog=CPWMText(CPWMIvar(model,"_thumbnailAssetCatalogName"));
        NSInteger style=[traits isKindOfClass:[UITraitCollection class]] ? traits.userInterfaceStyle : -1;
        NSString *imageDetail=@"not-UIImage";
        if ([result isKindOfClass:[UIImage class]]) {
            UIImage *img=(UIImage *)result;
            imageDetail=[NSString stringWithFormat:@"UIImage %.0fx%.0f scale=%.2f",img.size.width,img.size.height,img.scale];
        }
        CPWMAppend(@"[%@ #%lu] id=%@ catalog=%@ thumbCatalog=%@ style=%ld result=%@\n",
                   event,(unsigned long)number,identifier,catalog,thumbCatalog,(long)style,imageDetail);
        CPWMSave();
    }
}

// 0.2.36: Replace the nine image entries in the stock 3x3 picker grid.
// The last two Apple solid wallpaper identifiers remain untouched.
// Model IDs and settings persistence are unchanged.
static NSUInteger cpwmProofThumbHits=0;
static NSUInteger cpwmProofFullHits=0;
static NSString *CPWMIdentifier(id model) {
    id value=CPWMIvar(model,"_wallpaperIdentifier");
    return [value isKindOfClass:[NSString class]] ? value : nil;
}
static UIImage *CPWMStockImage(id model, UIImage *native, BOOL thumbnail,
                              UITraitCollection *traits) {
    if (!native) return nil;
    NSString *identifier=CPWMIdentifier(model);
    if (!CP26HasWallpaperSlot(identifier)) return native;
    // Trait unspecified is treated as light, matching normal CarPlay UI defaults
    UIUserInterfaceStyle style=traits ? traits.userInterfaceStyle : UIUserInterfaceStyleLight;
    UIImage *replacement=CP26WallpaperImage(identifier,thumbnail,style);
    return replacement ?: native; // fail open if package resources are inaccessible
}

%group CP26WallpaperModelTrace
%hook CRSUIWallpaper
- (id)initWithWallpaperIdentifier:(id)identifier {
    id model=%orig;
    if (++cpwmCreates<=20) CPWMRecord(model,@"MODEL CREATED",nil,nil,cpwmCreates);
    return model;
}
- (id)thumbnailImageCompatibleWithTraitCollection:(UITraitCollection *)traits {
    id image=%orig;
    if ([image isKindOfClass:[UIImage class]] && CP26HasWallpaperSlot(CPWMIdentifier(self))) {
        UIImage *replacement=CPWMStockImage(self,(UIImage *)image,YES,traits);
        if (replacement != image) {
            image=replacement;
            if (++cpwmProofThumbHits <= 8) {
            CPWMAppend(@"[WALLPAPER THUMB REPLACED #%lu] id=%@ style=%ld\n",
                (unsigned long)cpwmProofThumbHits,CPWMIdentifier(self),
                (long)(traits ? traits.userInterfaceStyle : -1));
                CPWMSave();
            }
        }
    }
    if (++cpwmThumbnails<=24) CPWMRecord(self,@"THUMBNAIL RETURN",traits,image,cpwmThumbnails);
    return image;
}
- (id)wallpaperImageCompatibleWithTraitCollection:(UITraitCollection *)traits {
    id image=%orig;
    if ([image isKindOfClass:[UIImage class]] && CP26HasWallpaperSlot(CPWMIdentifier(self))) {
        UIImage *replacement=CPWMStockImage(self,(UIImage *)image,NO,traits);
        if (replacement != image) {
            image=replacement;
            if (++cpwmProofFullHits <= 8) {
            CPWMAppend(@"[WALLPAPER FULL REPLACED #%lu] id=%@ style=%ld\n",
                (unsigned long)cpwmProofFullHits,CPWMIdentifier(self),
                (long)(traits ? traits.userInterfaceStyle : -1));
                CPWMSave();
            }
        }
    }
    if (++cpwmFullImages<=24) CPWMRecord(self,@"FULL IMAGE RETURN",traits,image,cpwmFullImages);
    return image;
}
%end
%end

%ctor {
    @autoreleasepool {
        NSString *p=CPWMProcess();
        if (!p) return;
        cpwmLock=[NSObject new];
        cpwmReport=[NSMutableString string];
        CPWMAppend(@"CarPlay26 v0.2.36 — nine-slot iOS 26 stock wallpaper replacement\n");
        CPWMAppend(@"process=%@ pid=%d bundle=%@ home=%@\n",p,
                   (int)NSProcessInfo.processInfo.processIdentifier,
                   NSBundle.mainBundle.bundleIdentifier ?: @"(none)",NSHomeDirectory());
        Class c=NSClassFromString(@"CRSUIWallpaper");
        CPWMAppend(@"[CLASS AVAILABILITY] CRSUIWallpaper=%d\n",(int)(c!=Nil));
        CPWMAppend(@"[WALLPAPER TARGET] nine stock image slots, light/dark\n");
        if (c) {
            BOOL valid=class_getInstanceMethod(c,@selector(thumbnailImageCompatibleWithTraitCollection:))!=NULL &&
                       class_getInstanceMethod(c,@selector(wallpaperImageCompatibleWithTraitCollection:))!=NULL;
            CPWMAppend(@"[CLASS METHODS] imageGetters=%d\n",(int)valid);
            if (valid) {
                %init(CP26WallpaperModelTrace);
                CPWMAppend(@"[MODEL IMAGE HOOKS INSTALLED] process=%@\n",p);
            }
        }
        CPWMSave();
    }
}
