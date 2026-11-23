// CarPlay26 0.2.36 — native picker/preview/home screen image assets
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// For stock iOS 16 wallpaper identifiers only; returns nil for other IDs or missing assets
FOUNDATION_EXTERN UIImage *CP26WallpaperImage(NSString *identifier,
    BOOL thumbnail, UIUserInterfaceStyle style);
FOUNDATION_EXTERN BOOL CP26HasWallpaperSlot(NSString *identifier);
