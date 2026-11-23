// CarPlay26 0.2.47 - full-resolution, size-optimised replacement artwork
// Six Apple iOS 26 CarPlay colorways, and three solid native-style choices.
// Image resources are fetched/validated by the CI workflow; no third-party
// artwork is generated and no device/network download is performed at runtime.
#import "WallpaperAssets.h"
#import <dlfcn.h>

static NSDictionary<NSString *, NSString *> *CP26WallpaperSlots(void) {
    static NSDictionary<NSString *, NSString *> *slots;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        slots = @{
            @"CARWallpaper2022ColorDynamic": @"red",
            @"CARWallpaper2022BlueDynamic": @"blue",
            @"CARWallpaper2022GrayDynamic": @"gray",
            @"CARWallpaperWWDC2021MulticolorDynamic": @"purple",
            @"CARWallpaperWWDC2021BlueDynamic": @"green",
            @"CARWallpaperWWDC2021GrayDynamic": @"brown",
            @"CARWallpaperRedBlueDynamic": @"solid-white",
            @"CARWallpaperBlueGreenDynamic": @"solid-blue",
            @"CARWallpaperBlackDynamicV2": @"solid-beige",
        };
    });
    return slots;
}

BOOL CP26HasWallpaperSlot(NSString *identifier) {
    return identifier && (CP26WallpaperSlots()[identifier] != nil);
}

static NSString *CP26WallpaperDirectory(void) {
    static NSString *directory;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Dl_info info={0};
        if (dladdr((const void *)&CP26WallpaperImage,&info) && info.dli_fname) {
            NSString *libPath=[NSString stringWithUTF8String:info.dli_fname];
            directory=[[libPath stringByDeletingLastPathComponent]
                stringByAppendingPathComponent:@"CarPlay26Wallpapers"];
        }
    });
    return directory;
}

UIImage *CP26WallpaperImage(NSString *identifier, BOOL thumbnail, UIUserInterfaceStyle style) {
    NSString *slot=CP26WallpaperSlots()[identifier];
    NSString *folder=CP26WallpaperDirectory();
    if (!slot.length || !folder.length) return nil;
    BOOL dark=(style==UIUserInterfaceStyleDark);
    // The six patterned wallpapers ship as high-fidelity JPEG to reduce the DEB
    // size; the three solid-colour slots remain smaller as lossless PNG.
    NSString *stem=[NSString stringWithFormat:@"%@-%@-%@",slot,
                    dark?@"dark":@"light",thumbnail?@"thumb":@"full"];
    BOOL isSolid=[slot hasPrefix:@"solid-"];
    NSString *name=[stem stringByAppendingPathExtension:(isSolid?@"png":@"jpg")];
    static NSCache<NSString *,UIImage *> *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cache=[NSCache new];
        cache.countLimit=16;
        cache.totalCostLimit=48*1024*1024;
    });
    UIImage *image=[cache objectForKey:name];
    if (image) return image;
    image=[UIImage imageWithContentsOfFile:[folder stringByAppendingPathComponent:name]];
    // Backward-compatible fallback for installations still carrying older PNGs.
    // An absent or invalid new file must never result in an empty wallpaper if
    // the legacy PNG is available.
    if (!image && !isSolid) {
        NSString *legacyName=[stem stringByAppendingPathExtension:@"png"];
        image=[UIImage imageWithContentsOfFile:[folder stringByAppendingPathComponent:legacyName]];
    }
    if (image) {
        NSUInteger cost=(NSUInteger)image.size.width * (NSUInteger)image.size.height * 4;
        [cache setObject:image forKey:name cost:cost];
    }
    return image;
}
