#import "SpotifyReference.h"
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#include <math.h>
#include <stdlib.h>
#include <unistd.h>

// Only loaded in the CarPlay shell. Targeted grid and dashboard hooks only; no
// hooks in SpringBoard, navigation apps or template hosts.
static BOOL CP26Bool(NSString *key) {
    Boolean valid = false;
    Boolean value = CFPreferencesGetAppBooleanValue((__bridge CFStringRef)key, CFSTR("com.tillman109.carplay26"), &valid);
    return valid && value;
}
static NSString *CP26Mode(void) {
    id raw = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("AppearanceMode"), CFSTR("com.tillman109.carplay26")));
    return [@[@"auto", @"light", @"dark"] containsObject:raw ?: @""] ? raw : @"auto";
}
static NSString *mode;
static BOOL dockEnabled, dockGlassEnabled, dockLiquidStyle, labelsEnabled, cardsEnabled, iconsEnabled, controlsEnabled, diagnosticsEnabled;
static BOOL dockShortcutProbeEnabled;
static NSString *pinnedDockBundle;
static NSUInteger pinGeneratedCount, pinAppliedCount;
static NSString *pinLastResult;
// Weakly track only the actual right-hand dock button, never navigation/media.
static NSHashTable *pinOtherButtons;
static NSUInteger pinButtonCorrections, pinBlockedNativeAssignments;
static NSString *pinButtonLastResult;

static NSString *CP26PinnedBundle(void) {
    if (!CP26Bool(@"PinDockApp")) return nil;
    id raw = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("PinnedDockApp"), CFSTR("com.tillman109.carplay26")));
    if (!raw) return @"com.apple.MobileSMS";
    if ([raw isKindOfClass:NSString.class] && [@[@"com.apple.MobileSMS", @"com.apple.mobilephone"] containsObject:raw]) return raw;
    return nil;
}
static dispatch_source_t refreshTimer;
static NSMapTable<UIView *, CAGradientLayer *> *overlays;
// Fallback layers are siblings of the text layer. Retain their keys until
// the next bounded scan so a removed label cannot orphan its decoration.
static NSMapTable<UIView *, CAGradientLayer *> *labelOverlays;
// Owned masks are applied to native label material only, never the text.
// Do not replace masks installed by UIKit or Airaw.
static NSMapTable<UIView *, CAShapeLayer *> *adaptiveLabelMasks;
static NSMapTable<UIView *, CAGradientLayer *> *dockOverlays;
// Only decorative layers on CarPlay26's existing fixed-tint capsule.
// Kept separate from the v0.2.16 backing-colour guards and pinning hooks.
static NSMapTable<UIView *, CAGradientLayer *> *dockLiquidSheens;
static NSMapTable<UIView *, CAGradientLayer *> *dockLiquidRims;
static NSMapTable<UIView *, CAGradientLayer *> *dockLiquidInnerShades;
static NSMapTable<UIWindow *, UIView *> *dockSurfaces;
static NSMapTable<UIView *, CAShapeLayer *> *dockMasks;
static NSMapTable<UIView *, NSDictionary *> *dockBackings;
// Weak references only: protect precisely the two backing layers already
// validated and registered by ApplyDock, never the remote host or foreground.
static NSHashTable<CALayer *> *dockProtectedLayers;
static NSUInteger dockBlockedViewColors, dockBlockedLayerColors;
static NSMutableString *report;
static NSString *lastSignature;
static NSUInteger connectedTicks;
static BOOL hadWindows;
static BOOL writeErrorLogged;
static NSString *diagnosticReportPath;

static NSString *StyleName(UIUserInterfaceStyle s) {
    if (s == UIUserInterfaceStyleDark) return @"dark";
    if (s == UIUserInterfaceStyleLight) return @"light";
    return @"unspecified";
}
static UIUserInterfaceStyle Theme(UIUserInterfaceStyle native) {
    if ([mode isEqualToString:@"dark"]) return UIUserInterfaceStyleDark;
    if ([mode isEqualToString:@"light"]) return UIUserInterfaceStyleLight;
    return native;
}
static BOOL Visible(UIView *v) {
    return !v.hidden && v.alpha > 0.05;
}
// Targets are limited to observed CarPlay shell classes. No layout or touch changes.
typedef NS_ENUM(NSInteger, CP26Surface) {
    CP26None = 0, CP26Label, CP26Card, CP26Icon, CP26Control
};
static NSString *KindName(NSInteger kind) {
    switch (kind) {
        case CP26Label: return @"label";
        case CP26Card: return @"card";
        case CP26Icon: return @"icon";
        case CP26Control: return @"control";
        default: return @"none";
    }
}
static BOOL Named(UIView *v, NSString *name) {
    return v && [NSStringFromClass(v.class) isEqualToString:name];
}
// Validate icons against their own page, not the visible window. Scrolling
// changes page origins but not the icon geometry in page coordinates.
static UIView *GridPage(UIView *v, UIWindow *w) {
    UIView *page = nil;
    for (UIView *a = v; a && a != w; a = a.superview) {
        if (Named(a,@"DBIconListView")) page = a;
        if (Named(a,@"DBIconScrollView")) return page;
    }
    return nil;
}
static BOOL ValidRect(CGRect r) {
    return !CGRectIsEmpty(r) && !CGRectIsInfinite(r) &&
        isfinite(r.origin.x) && isfinite(r.origin.y) &&
        isfinite(r.size.width) && isfinite(r.size.height);
}
// The dashboard is a sibling of the app-grid pages inside DBIconScrollView.
// Its origin moves offscreen while the widget geometry relative to the page
// remains unchanged. Only accept the observed CarPlay hierarchy.
static UIView *DashboardPage(UIView *v, UIWindow *w) {
    if (![w.windowScene.session.role isEqualToString:@"UIWindowSceneSessionRoleCarPlay"]) return nil;
    for (UIView *a = v; a && a != w; a = a.superview) {
        if (Named(a,@"_SBRootFolderLayoutWrapperView") && Named(a.superview,@"DBIconScrollView")) return a;
    }
    return nil;
}
static BOOL LowerCard(UIView *v, UIWindow *w) {
    if (!Named(v,@"DBWidgetView")) return NO;
    UIView *page = DashboardPage(v,w);
    if (!page || !ValidRect(page.bounds)) return NO;
    CGRect r = [v convertRect:v.bounds toView:page], b = w.bounds;
    CGFloat width = b.size.width, height = b.size.height;
    return ValidRect(r) && CGRectContainsRect(CGRectInset(page.bounds,-2,-2),r) &&
        r.size.width >= width * .30 && r.size.width <= width * .60 &&
        r.size.height >= height * .25 && r.size.height <= height * .60 &&
        CGRectGetMinY(r) >= CGRectGetMinY(page.bounds) + height * .35;
}
static BOOL DashboardGeometry(UIView *v, UIWindow *w) {
    UIView *page = DashboardPage(v,w);
    if (!page || !ValidRect(page.bounds)) return NO;
    CGRect r = [v convertRect:v.bounds toView:page];
    return ValidRect(r) && CGRectContainsRect(CGRectInset(page.bounds,-2,-2),r);
}
static BOOL GridGeometry(UIView *v, UIWindow *w) {
    if (![w.windowScene.session.role isEqualToString:@"UIWindowSceneSessionRoleCarPlay"]) return NO;
    UIView *page = GridPage(v,w);
    if (!page || !ValidRect(page.bounds)) return NO;
    CGRect r = [v convertRect:v.bounds toView:page];
    return ValidRect(r) && CGRectContainsRect(CGRectInset(page.bounds,-2,-2),r);
}
// The stock label platter exists even in appearances where it has zero
// bounds. Only prefer it when it has usable geometry and is visible.
static BOOL NativeLabelMaterial(UIView *v, UIWindow *w) {
    UIView *platter = v.superview;
    UIView *backdrop = platter.superview;
    if (!Named(v,@"MTMaterialView") || !Named(platter,@"DashBoard.DBDashboardPlatterView") ||
        !Named(backdrop,@"DBIconLabelBackdropView") || !Named(backdrop.superview,@"DBIconView")) return NO;
    if (!Visible(v) || !Visible(platter) || !Visible(backdrop)) return NO;
    CGRect r = [v convertRect:v.bounds toView:w];
    return ValidRect(r) && r.size.width >= 12 && r.size.width <= w.bounds.size.width * .30 &&
        r.size.height >= 8 && r.size.height <= 35 && GridGeometry(v,w);
}
static BOOL HasNativeLabelMaterial(UIView *icon, UIWindow *w) {
    for (UIView *backdrop in icon.subviews) {
        if (!Named(backdrop,@"DBIconLabelBackdropView")) continue;
        for (UIView *platter in backdrop.subviews) {
            if (!Named(platter,@"DashBoard.DBDashboardPlatterView")) continue;
            for (UIView *material in platter.subviews) {
                if (NativeLabelMaterial(material,w)) return YES;
            }
        }
    }
    return NO;
}
static NSInteger SurfaceKind(UIView *v, UIWindow *w) {
    CGRect r = [v convertRect:v.bounds toView:w], b = w.bounds;
    CGFloat width = b.size.width, height = b.size.height;
    if (width < 250 || height < 200 || !ValidRect(r)) return CP26None;
    if (Named(v,@"SBIconImageView") && Named(v.superview,@"DBIconView") &&
        r.size.width >= 32 && r.size.width <= 110 && fabs(r.size.width-r.size.height) <= 3)
        return GridGeometry(v,w) ? CP26Icon : CP26None;
    if (NativeLabelMaterial(v,w)) return CP26Label;
    if (Named(v,@"SBIconSimpleLabelView") && Named(v.superview,@"DBIconView") && Visible(v) &&
        r.size.width >= 12 && r.size.width <= width * .30 && r.size.height >= 8 && r.size.height <= 35 &&
        GridGeometry(v,w) && !HasNativeLabelMaterial(v.superview,w)) return CP26Label;
    // Retain dashboard decorations on loaded, offscreen pages as well.
    if (!DashboardGeometry(v,w)) return CP26None;
    // Match the native material INSIDE the two lower dashboard widgets.
    // An overlay on DBWidgetView sits below the system's opaque material
    // and cannot be seen. The material is a background, not a new card.
    if (Named(v,@"MTMaterialView") &&
        Named(v.superview,@"DashBoard.DBDashboardPlatterView") &&
        LowerCard(v.superview.superview,w)) return CP26Card;
    if (Named(v,@"DBNowPlayingFocusHighlightButton") && [v isKindOfClass:UIControl.class] &&
        r.size.width >= 24 && r.size.width <= 70 && r.size.height >= 20 && r.size.height <= 60) {
        for (UIView *a = v.superview; a && a != w; a = a.superview) {
            if (Named(a,@"DBWidgetView")) return LowerCard(a,w) ? CP26Control : CP26None;
        }
    }
    // Other card content and the top map must keep native drawing/layout.
    return CP26None;
}
static void Scan(UIView *v, UIWindow *w, NSMutableArray<UIView *> *matches, NSMutableString *tree, NSUInteger depth, NSUInteger *budget) {
    if (!*budget || depth > 16 || (!Visible(v) && !GridPage(v,w) && !DashboardPage(v,w))) return;
    (*budget)--;
    NSInteger kind = v != w ? SurfaceKind(v,w) : 0;
    if (kind) [matches addObject:v];
    if (tree) {
        CGRect r = [v convertRect:v.bounds toView:w];
        [tree appendFormat:@"%*s%@ x=%.0f y=%.0f w=%.0f h=%.0f style=%@%@\n", (int)(depth * 2), "", NSStringFromClass(v.class), r.origin.x,r.origin.y,r.size.width,r.size.height,StyleName(v.traitCollection.userInterfaceStyle),kind ? [NSString stringWithFormat:@" [%@ target%@]",KindName(kind),kind == CP26Label && Named(v,@"SBIconSimpleLabelView") ? @" fallback" : @""] : @""];
    }
    for (UIView *c in v.subviews) {
        if (!*budget) break;
        Scan(c,w,matches,tree,depth+1,budget);
    }
}
static void RemoveStale(NSHashTable<UIView *> *keep) {
    for (UIView *v in overlays.keyEnumerator.allObjects) {
        if (![keep containsObject:v]) { [[overlays objectForKey:v] removeFromSuperlayer]; [overlays removeObjectForKey:v]; }
    }
    for (UIView *v in labelOverlays.keyEnumerator.allObjects) {
        if (![keep containsObject:v]) { [[labelOverlays objectForKey:v] removeFromSuperlayer]; [labelOverlays removeObjectForKey:v]; }
    }
    for (UIView *v in adaptiveLabelMasks.keyEnumerator.allObjects) {
        if (![keep containsObject:v]) {
            CAShapeLayer *mask = [adaptiveLabelMasks objectForKey:v];
            if (v.layer.mask == mask) v.layer.mask = nil;
            [adaptiveLabelMasks removeObjectForKey:v];
        }
    }
}
// Match the visible dark label backing to the actual icon title rather than
// the fixed-width icon slot that Airaw/iOS 16 provides. We deliberately do not
// resize the label, its icon cell, or its touch/accessibility target.
static NSString *CP26SafeLabelText(NSString *value) {
    if (![value isKindOfClass:NSString.class]) return nil;
    NSString *name = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (name.length < 1 || name.length > 32) return nil;
    if ([name rangeOfCharacterFromSet:NSCharacterSet.newlineCharacterSet].location != NSNotFound ||
        [name containsString:@","] || [name containsString:@":"]) return nil;
    return name;
}
static UIView *CP26OwnerIcon(UIView *view) {
    for (UIView *v = view; v; v = v.superview) {
        if (Named(v,@"DBIconView")) return v;
    }
    return nil;
}
static NSString *CP26IconTitle(UIView *icon, UIFont **fontOut) {
    if (!icon) return nil;
    // Prefer the exact native simple-label view: accessibility text is more
    // reliable here than the icon's accessibility description (which may
    // include notification counts).
    for (UIView *child in icon.subviews) {
        if (!Named(child,@"SBIconSimpleLabelView")) continue;
        if ([child isKindOfClass:UILabel.class]) {
            UILabel *label = (UILabel *)child;
            NSString *title = CP26SafeLabelText(label.text);
            if (title) {
                if (fontOut && label.font) *fontOut = label.font;
                return title;
            }
        }
        for (UIView *subview in child.subviews) {
            if (![subview isKindOfClass:UILabel.class]) continue;
            UILabel *label = (UILabel *)subview;
            NSString *title = CP26SafeLabelText(label.text);
            if (title) {
                if (fontOut && label.font) *fontOut = label.font;
                return title;
            }
        }
        NSString *title = CP26SafeLabelText(child.accessibilityLabel);
        if (title) return title;
    }
    return CP26SafeLabelText(icon.accessibilityLabel);
}
static CGFloat CP26AdaptiveLabelWidth(UIView *target) {
    CGRect bounds = target.bounds;
    if (!ValidRect(bounds) || bounds.size.width < 20 || bounds.size.height < 9) return 0;
    UIFont *font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightMedium];
    NSString *title = CP26IconTitle(CP26OwnerIcon(target),&font);
    if (!title) return 0; // Don't guess when native title isn't exposed
    CGFloat textWidth = ceil([title sizeWithAttributes:@{NSFontAttributeName:font}].width);
    if (!isfinite(textWidth) || textWidth <= 0) return 0;
    // Horizontal padding is balanced; a longer label keeps the full native
    // backing width when it cannot be fitted inside the existing slot.
    return MIN(bounds.size.width,MAX(22.0,textWidth + 14.0));
}
static void CP26FitNativeLabelMaterial(UIView *view) {
    if (!adaptiveLabelMasks || !Named(view,@"MTMaterialView")) return;
    CAShapeLayer *mask = [adaptiveLabelMasks objectForKey:view];
    if (view.layer.mask && view.layer.mask != mask) return; // external mask wins
    CGFloat width = CP26AdaptiveLabelWidth(view);
    CGRect b = view.bounds;
    if (width <= 0 || width >= b.size.width - 1.0) {
        if (view.layer.mask == mask) view.layer.mask = nil;
        [adaptiveLabelMasks removeObjectForKey:view];
        return;
    }
    if (!mask) {
        mask = [CAShapeLayer layer];
        mask.name = @"CarPlay26.AdaptiveLabelMask";
        mask.fillColor = UIColor.blackColor.CGColor;
        [adaptiveLabelMasks setObject:mask forKey:view];
    }
    CGRect pill = CGRectMake((b.size.width-width)*.5,0,width,b.size.height);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    mask.frame = b;
    mask.path = [UIBezierPath bezierPathWithRoundedRect:pill
                                          cornerRadius:b.size.height*.5].CGPath;
    if (view.layer.mask != mask) view.layer.mask = mask;
    [CATransaction commit];
}

// Draw a separate, noninteractive layer immediately behind the stock label.
// Use its actual bounds; no text replacement, layout mutation or new UIView.
static BOOL ApplyFallbackLabel(UIView *v, UIUserInterfaceStyle theme, UIUserInterfaceStyle native) {
    UIView *owner = v.superview;
    if (!owner || v.layer.superlayer != owner.layer) return NO;
    CGRect frame = [v convertRect:v.bounds toView:owner];
    if (!ValidRect(frame)) return NO;
    CAGradientLayer *layer = [labelOverlays objectForKey:v];
    if (!layer) {
        layer = [CAGradientLayer layer];
        layer.name = @"CarPlay26.LabelBackdrop";
        [labelOverlays setObject:layer forKey:v];
    }
    BOOL dark = theme == UIUserInterfaceStyleDark;
    BOOL nativeDark = native == UIUserInterfaceStyleDark;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    // SBIconSimpleLabelView is a fixed-width cell under some Airaw layouts;
    // the glass background is narrower but the label itself stays untouched.
    CGFloat fitted = CP26AdaptiveLabelWidth(v);
    if (fitted > 0 && fitted < frame.size.width)
        frame = CGRectMake(CGRectGetMidX(frame)-fitted*.5, frame.origin.y,
                           fitted, frame.size.height);
    layer.frame = frame;
    layer.cornerRadius = v.layer.cornerRadius;
    layer.masksToBounds = YES;
    layer.startPoint = CGPointMake(.1,0);
    layer.endPoint = CGPointMake(.85,1);
    // Keep the existing dark treatment and measured label geometry.
    // In native light mode use a midpoint between v0.2.40's faint backing
    // and v0.2.41's darker fill, without modifying the native text.
    UIColor *top;
    UIColor *bottom;
    if (!dark && !nativeDark) {
        top = [UIColor colorWithWhite:.12 alpha:.46];
        bottom = [UIColor colorWithWhite:.09 alpha:.41];
    } else {
        top = dark ? [UIColor colorWithWhite:.035 alpha:nativeDark ? .46 : .27] :
            [UIColor colorWithWhite:.12 alpha:nativeDark ? .28 : .17];
        bottom = dark ? [UIColor colorWithWhite:.01 alpha:nativeDark ? .40 : .23] :
            [UIColor colorWithWhite:.17 alpha:nativeDark ? .21 : .14];
    }
    layer.colors = @[(id)top.CGColor,(id)bottom.CGColor];
    layer.borderColor = [UIColor colorWithWhite:1 alpha:nativeDark ? .12 : .10].CGColor;
    layer.borderWidth = .35;
    layer.zPosition = v.layer.zPosition;
    NSArray<CALayer *> *siblings = owner.layer.sublayers;
    NSUInteger at = [siblings indexOfObjectIdenticalTo:layer];
    NSUInteger textAt = [siblings indexOfObjectIdenticalTo:v.layer];
    if (layer.superlayer != owner.layer || at == NSNotFound || textAt == NSNotFound || at + 1 != textAt) {
        [layer removeFromSuperlayer];
        [owner.layer insertSublayer:layer below:v.layer];
    }
    [CATransaction commit];
    return YES;
}

// Find the current native notification badge only inside this icon's cell.
// The rectangle is in image-view coordinates so only our optional rim can be
// masked out underneath it. Native badge artwork, text, masks and layers remain
// untouched; a badge appearing/disappearing does not hide the entire icon rim.
static CGRect CP26IconBadgeRect(UIView *node, UIView *image, NSUInteger depth) {
    if (!node || !image || depth > 6 || node.hidden || node.alpha <= .05) return CGRectNull;
    NSString *name = NSStringFromClass(node.class);
    if ([name rangeOfString:@"Badge" options:NSCaseInsensitiveSearch].location != NSNotFound &&
        ValidRect(node.bounds)) {
        CGRect r = [node convertRect:node.bounds toView:image];
        if (ValidRect(r) && CGRectIntersectsRect(CGRectInset(image.bounds,-16,-16),r))
            return r;
    }
    for (UIView *child in node.subviews) {
        CGRect r = CP26IconBadgeRect(child,image,depth+1);
        if (!CGRectIsNull(r)) return r;
    }
    return CGRectNull;
}

// The icon-rim mask has a small opening where the native badge overlaps the
// upper corner. The rest of the rim stays visible. Only our own gradient layer
// receives this mask; it never clips the app artwork or badge subview.
static void CP26ProtectIconBadge(CAGradientLayer *rim, UIView *image) {
    CGRect r = CP26IconBadgeRect(image.superview,image,0);
    if (CGRectIsNull(r)) {
        rim.mask = nil;
        return;
    }
    CGRect cutout = CGRectIntersection(rim.bounds, CGRectInset(
        CGRectOffset(r,-rim.frame.origin.x,-rim.frame.origin.y),-2.5,-2.5));
    if (CGRectIsNull(cutout) || CGRectIsEmpty(cutout)) {
        rim.mask = nil;
        return;
    }
    CAShapeLayer *mask = [rim.mask isKindOfClass:CAShapeLayer.class] ? (CAShapeLayer *)rim.mask : nil;
    if (!mask || ![mask.name isEqualToString:@"CarPlay26.IconBadgeGap"]) {
        mask = [CAShapeLayer layer];
        mask.name = @"CarPlay26.IconBadgeGap";
        mask.fillRule = kCAFillRuleEvenOdd;
        mask.fillColor = UIColor.blackColor.CGColor;
    }
    UIBezierPath *visible = [UIBezierPath bezierPathWithRect:rim.bounds];
    [visible appendPath:[UIBezierPath bezierPathWithRect:cutout]];
    mask.frame = rim.bounds;
    mask.path = visible.CGPath;
    if (rim.mask != mask) rim.mask = mask;
}

static BOOL Apply(UIView *v, UIUserInterfaceStyle theme, UIUserInterfaceStyle native, NSInteger kind) {
    if (kind == CP26Label && Named(v,@"SBIconSimpleLabelView")) {
        return ApplyFallbackLabel(v,theme,native);
    }
    CAGradientLayer *layer = [overlays objectForKey:v];
    if (!layer) {
        layer = [CAGradientLayer layer];
        layer.name = @"CarPlay26.GlassSurface";
        [overlays setObject:layer forKey:v];
    }
    BOOL dark = theme == UIUserInterfaceStyleDark;
    // A gradient sheen on the existing material, not real Liquid Glass.
    // The original background, foreground text, blur and touch areas remain.
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    BOOL edgeOnly = kind == CP26Icon || kind == CP26Control;
    // No inset or invented corner radius for cards. Use the existing native
    // material bounds and the existing platter's rounded clipping geometry.
    CGFloat decorationInset = edgeOnly ? 1.0 : 0.0;
    layer.frame = CGRectInset(v.bounds,decorationInset,decorationInset);
    CGFloat shortSide = MIN(layer.bounds.size.width,layer.bounds.size.height);
    CGFloat fallback = kind == CP26Label ? shortSide * .44 : kind == CP26Icon ? shortSide * .22 : kind == CP26Control ? shortSide * .35 : 10.0;
    CGFloat nativeCorner = v.layer.cornerRadius > 0 ? v.layer.cornerRadius : v.superview.layer.cornerRadius;
    layer.cornerRadius = kind == CP26Card ? MAX(0.0,nativeCorner) :
        MIN(shortSide * .5, v.layer.cornerRadius > 0 ? v.layer.cornerRadius : fallback);
    layer.masksToBounds = YES;
    layer.startPoint = CGPointMake(0.1,0);
    layer.endPoint = CGPointMake(0.85,1);
    // Keep the foreground contrast of Apple's current appearance. Manual
    // finish selection does not force the native text or map appearance.
    BOOL nativeDark = native == UIUserInterfaceStyleDark;
    UIColor *top = dark ? [UIColor colorWithRed:.30 green:.48 blue:.72 alpha:nativeDark ? .44 : .23] :
        [UIColor colorWithWhite:1 alpha:nativeDark ? .12 : .48];
    UIColor *bottom = dark ? [UIColor colorWithRed:.06 green:.14 blue:.27 alpha:nativeDark ? .48 : .16] :
        [UIColor colorWithRed:.38 green:.64 blue:.85 alpha:nativeDark ? .18 : .28];
    if (kind == CP26Label) {
        // Dark, understated labels like the iOS 26 home screen reference.
        // This is a decoration on the native material, never a text replacement.
        UIColor *labelTop;
        UIColor *labelBottom;
        if (!dark && !nativeDark) {
            // Intermediate light-mode opacity; dark-mode labels untouched.
            labelTop = [UIColor colorWithWhite:.12 alpha:.46];
            labelBottom = [UIColor colorWithWhite:.09 alpha:.41];
        } else {
            labelTop = dark ? [UIColor colorWithWhite:.04 alpha:nativeDark ? .33 : .19] :
                [UIColor colorWithWhite:.15 alpha:nativeDark ? .23 : .15];
            labelBottom = dark ? [UIColor colorWithWhite:.01 alpha:nativeDark ? .29 : .17] :
                [UIColor colorWithWhite:.19 alpha:nativeDark ? .20 : .13];
        }
        layer.colors = @[(id)labelTop.CGColor,(id)labelBottom.CGColor];
        layer.borderColor = [UIColor colorWithWhite:1 alpha:nativeDark ? .12 : .10].CGColor;
        layer.borderWidth = .35;
    } else if (kind == CP26Card) {
        // A tint on the native material itself, not another rounded card.
        // It is translucent to retain Apple's blur, with no inset/border;
        // media artwork, labels, maps and touches remain owned by the widget.
        UIColor *cardTop = dark ?
            [UIColor colorWithRed:.33 green:.49 blue:.70 alpha:nativeDark ? .22 : .15] :
            [UIColor colorWithRed:.88 green:.97 blue:1.0 alpha:nativeDark ? .14 : .24];
        UIColor *cardMiddle = dark ?
            [UIColor colorWithRed:.22 green:.36 blue:.55 alpha:nativeDark ? .24 : .16] :
            [UIColor colorWithRed:.49 green:.74 blue:.88 alpha:nativeDark ? .12 : .22];
        UIColor *cardBottom = dark ?
            [UIColor colorWithRed:.08 green:.17 blue:.34 alpha:nativeDark ? .30 : .19] :
            [UIColor colorWithRed:.23 green:.41 blue:.62 alpha:nativeDark ? .14 : .26];
        layer.colors = @[(id)cardTop.CGColor,(id)cardMiddle.CGColor,(id)cardBottom.CGColor];
        layer.locations = @[@0.0, @0.51, @1.0];
        layer.borderColor = UIColor.clearColor.CGColor;
        layer.borderWidth = 0.0;
    } else if (edgeOnly) {
        // A transparent rim only: do not wash out app artwork or playback glyphs.
        layer.colors = @[(id)UIColor.clearColor.CGColor,(id)UIColor.clearColor.CGColor];
        // Media controls on iOS 26 use quiet outlines; retain original
        // buttons, icons, selection state and hit areas. App-icon rims stay as-is.
        layer.borderColor = [UIColor colorWithWhite:dark ? .76 : 1 alpha:kind == CP26Icon ? .56 : (dark ? .18 : .24)].CGColor;
        layer.borderWidth = kind == CP26Icon ? 1.0 : .45;
    } else {
        layer.colors = @[(id)top.CGColor, (id)bottom.CGColor];
        layer.borderColor = [UIColor colorWithWhite:1 alpha:nativeDark ? .35 : .85].CGColor;
        layer.borderWidth = 1.2;
    }
    if (kind == CP26Icon) {
        // Keep native icon badge art above our rim, as verified in v0.2.44.
        if (layer.superlayer != v.layer || v.layer.sublayers.firstObject != layer) {
            [layer removeFromSuperlayer];
            [v.layer insertSublayer:layer atIndex:0];
        }
        CP26ProtectIconBadge(layer,v);
    } else if (kind == CP26Card) {
        // MTMaterialView is the system background, not the widget content.
        // Its own material can cover a layer at index 0, so tint it above
        // the native backing while leaving card labels and controls untouched.
        if (layer.superlayer != v.layer || v.layer.sublayers.lastObject != layer) {
            [layer removeFromSuperlayer];
            [v.layer addSublayer:layer];
        }
    } else if (layer.superlayer != v.layer) {
        [layer removeFromSuperlayer];
        [v.layer addSublayer:layer];
    }
    [CATransaction commit];
    if (kind == CP26Label) CP26FitNativeLabelMaterial(v);
    return YES;
}
// A bounded per-icon pass for newly laid out or attached icon views.
// It does not walk the whole window or wait for the periodic diagnostics.
static void PrimeIcon(UIView *icon) {
    if (!overlays || !NSThread.isMainThread || (!labelsEnabled && !iconsEnabled)) return;
    UIWindow *w = icon.window;
    if (!w || !GridPage(icon,w)) return;
    NSMutableArray<UIView *> *matches = [NSMutableArray array];
    NSUInteger budget = 40;
    Scan(icon,w,matches,nil,0,&budget);
    for (UIView *v in matches) {
        NSInteger kind = SurfaceKind(v,w);
        if (!((kind == CP26Icon && iconsEnabled) || (kind == CP26Label && labelsEnabled))) continue;
        UIUserInterfaceStyle native = v.traitCollection.userInterfaceStyle;
        if (native == UIUserInterfaceStyleUnspecified) native = w.traitCollection.userInterfaceStyle;
        if (native == UIUserInterfaceStyleUnspecified) continue;
        Apply(v,Theme(native),native,kind);
    }
}

%group GridLifecycle
%hook DBIconView
- (void)layoutSubviews {
    %orig;
    PrimeIcon((UIView *)self);
}
- (void)didMoveToWindow {
    %orig;
    PrimeIcon((UIView *)self);
}
%end
%end

// Prime only the known lower widget subtree when UIKit lays it out or
// attaches it. No full-window passes in layout hooks. The periodic scan
// still maintains and cleans up the same overlays.
static void PrimeDashboardWidget(UIView *widget) {
    if (!overlays || !NSThread.isMainThread || (!cardsEnabled && !controlsEnabled)) return;
    UIWindow *w = widget.window;
    if (!w || !LowerCard(widget,w)) return;
    NSMutableArray<UIView *> *matches = [NSMutableArray array];
    NSUInteger budget = 64;
    Scan(widget,w,matches,nil,0,&budget);
    for (UIView *v in matches) {
        NSInteger kind = SurfaceKind(v,w);
        if (!((kind == CP26Card && cardsEnabled) || (kind == CP26Control && controlsEnabled))) continue;
        UIUserInterfaceStyle native = v.traitCollection.userInterfaceStyle;
        if (native == UIUserInterfaceStyleUnspecified) native = w.traitCollection.userInterfaceStyle;
        if (native == UIUserInterfaceStyleUnspecified) continue;
        Apply(v,Theme(native),native,kind);
    }
}

static void PrimeMediaControl(UIView *v) {
    if (!overlays || !NSThread.isMainThread || !controlsEnabled) return;
    UIWindow *w = v.window;
    if (!w || SurfaceKind(v,w) != CP26Control) return;
    UIUserInterfaceStyle native = v.traitCollection.userInterfaceStyle;
    if (native == UIUserInterfaceStyleUnspecified) native = w.traitCollection.userInterfaceStyle;
    if (native != UIUserInterfaceStyleUnspecified) Apply(v,Theme(native),native,CP26Control);
}

%group DashboardLifecycle
%hook DBWidgetView
- (void)layoutSubviews {
    %orig;
    PrimeDashboardWidget((UIView *)self);
}
- (void)didMoveToWindow {
    %orig;
    PrimeDashboardWidget((UIView *)self);
}
%end
%end

%group MediaLifecycle
%hook DBNowPlayingFocusHighlightButton
- (void)layoutSubviews {
    %orig;
    PrimeMediaControl((UIView *)self);
}
- (void)didMoveToWindow {
    %orig;
    PrimeMediaControl((UIView *)self);
}
%end
%end

// The actual local status bar is a short window in the CarPlay process.
// Decorate the local dock and constrain its composited output to a capsule.
// Size and route the local controls in the same dock coordinate space.
static UIView *DockRoot(UIWindow *w) {
    if (!Named(w,@"DBStatusBarWindow") ||
        ![w.windowScene.session.role isEqualToString:@"UIWindowSceneSessionRoleCarPlay"] ||
        ![NSStringFromClass(w.rootViewController.class) isEqualToString:@"DBRootStatusBarViewController"]) return nil;
    CGRect b = w.bounds;
    if (!ValidRect(b) || b.size.width < 250 || b.size.height < 28 || b.size.height > 85 ||
        b.size.width < b.size.height * 4) return nil;
    UIView *root = w.rootViewController.viewIfLoaded;
    return root && root.window == w ? root : nil;
}
// Match only the direct, full-bar native background effects identified in
// the dock inventory. Do not depend on which effect iOS currently activates.
static BOOL DockNativeBackground(UIView *v, UIWindow *w) {
    if (![v isKindOfClass:UIVisualEffectView.class] || v == [dockSurfaces objectForKey:w]) return NO;
    CGRect b = w.bounds, r = [v convertRect:v.bounds toView:w];
    return ValidRect(r) && fabs(r.size.width-b.size.width)<=2 && fabs(r.size.height-b.size.height)<=2 &&
        fabs(r.origin.x-b.origin.x)<=2 && fabs(r.origin.y-b.origin.y)<=2;
}
// The native root/backdrop may be repainted during an app-page transition.
// Constrain the entire *local* status bar output as a final clipping boundary.
// The extra half point preserves the existing capsule rim and antialiasing.
// Preserve masks owned by UIKit or another tweak.
static CGRect CompactDockRect(CGRect bounds) {
    CGFloat u=MIN(bounds.size.width/400,bounds.size.height/45);
    return CGRectInset(bounds,4*u,2*u);
}
static void ClipLocalDockWindow(UIWindow *w, NSHashTable<UIView *> *keep) {
    if (!dockGlassEnabled || !dockMasks || !DockRoot(w)) return;
    CALayer *backing = w.layer;
    CGRect bounds = backing.bounds;
    CGRect capsule=CGRectInset(CompactDockRect(bounds),-.4,-.4);
    if (!ValidRect(capsule)) return;
    CAShapeLayer *mask = [dockMasks objectForKey:w];
    if (backing.mask && backing.mask != mask) return;
    if (!mask) {
        mask = [CAShapeLayer layer];
        mask.name = @"CarPlay26.DockWindowMask";
        mask.fillColor = UIColor.blackColor.CGColor;
        [dockMasks setObject:mask forKey:w];
    }
    if (!CGRectEqualToRect(mask.frame,bounds) || !mask.path ||
        !CGRectEqualToRect(CGPathGetBoundingBox(mask.path),capsule)) {
        mask.frame = bounds;
        mask.path = [UIBezierPath bezierPathWithRoundedRect:capsule cornerRadius:capsule.size.height*.4].CGPath;
    }
    if (backing.mask != mask) backing.mask = mask;
    if (keep) [keep addObject:w];
}
// The native effects may crossfade or replace their material during swipes.
// Keep their rendering empty, including inactive effects, while a separate
// fixed translucent surface is installed. Do not mutate their alpha/effect state
// or replace any mask owned by UIKit/another tweak.
static void SuppressDockBackgrounds(UIWindow *w, NSHashTable<UIView *> *keep) {
    UIView *root = DockRoot(w);
    UIView *surface = [dockSurfaces objectForKey:w];
    if (!dockMasks || !root || !surface || surface.superview != root) return;
    for (UIView *v in root.subviews) {
        if (!DockNativeBackground(v,w)) continue;
        CGRect bounds = v.layer.bounds;
        if (!ValidRect(bounds)) continue;
        CAShapeLayer *mask = [dockMasks objectForKey:v];
        if (v.layer.mask && v.layer.mask != mask) continue;
        if (!mask) {
            mask = [CAShapeLayer layer];
            mask.name = @"CarPlay26.DockNativeSuppression";
            mask.fillColor = UIColor.blackColor.CGColor;
            [dockMasks setObject:mask forKey:v];
        }
        if (!CGRectEqualToRect(mask.frame,bounds) || !mask.path) {
            mask.frame = bounds;
            // A nonempty shape wholly outside the mask's visible bounds.
            // Unlike view.alpha, this does not compete with native crossfades.
            mask.path = [UIBezierPath bezierPathWithRect:CGRectMake(-20,-20,1,1)].CGPath;
        }
        if (v.layer.mask != mask) v.layer.mask = mask;
        if (keep) [keep addObject:v];
    }
}
// Leave the independent translucent capsule in place, but clear any rectangular backing
// behind it. Only touch the already validated local dock window and root.
// Save both view and layer values so stale-window cleanup is reversible.
static void ClearDockBacking(UIView *v, NSHashTable<UIView *> *keep) {
    if (!v || !dockBackings) return;
    if (![dockBackings objectForKey:v]) {
        NSDictionary *original = @{
            @"background": v.backgroundColor ?: (id)NSNull.null,
            @"layerBackground": v.layer.backgroundColor ? (__bridge id)v.layer.backgroundColor : (id)NSNull.null,
            @"opaque": @(v.opaque), @"layerOpaque": @(v.layer.opaque)
        };
        [dockBackings setObject:original forKey:v];
    }
    [dockProtectedLayers addObject:v.layer];
    if (v.opaque) v.opaque = NO;
    if (v.layer.opaque) v.layer.opaque = NO;
    if (v.backgroundColor && CGColorGetAlpha(v.backgroundColor.CGColor) > 0) v.backgroundColor = UIColor.clearColor;
    if (v.layer.backgroundColor && CGColorGetAlpha(v.layer.backgroundColor) > 0) v.layer.backgroundColor = UIColor.clearColor.CGColor;
    if (keep) [keep addObject:v];
}
static void RestoreDockBacking(UIView *v, NSDictionary *original) {
    if (!original) return;
    id bg = original[@"background"], layerBg = original[@"layerBackground"];
    v.backgroundColor = bg == NSNull.null ? nil : (UIColor *)bg;
    v.layer.backgroundColor = layerBg == NSNull.null ? NULL : (__bridge CGColorRef)layerBg;
    v.opaque = [original[@"opaque"] boolValue];
    v.layer.opaque = [original[@"layerOpaque"] boolValue];
}
static BOOL ApplyDock(UIWindow *w, NSHashTable<UIView *> *keep, NSHashTable<UIView *> *maskKeep, NSHashTable<UIView *> *backingKeep) {
    if (!dockGlassEnabled || !dockOverlays || !dockSurfaces || !NSThread.isMainThread) return NO;
    UIView *root = DockRoot(w);
    if (!root || !Visible(w) || !Visible(root)) return NO;
    UIView *v = [dockSurfaces objectForKey:w];
    // Only install in a root containing a confirmed native full-bar effect.
    // If a third-party/native mask is already present, do not replace it.
    BOOL confirmed = NO;
    for (UIView *child in root.subviews) {
        if (!DockNativeBackground(child,w)) continue;
        confirmed = YES;
        if (child.layer.mask && child.layer.mask != [dockMasks objectForKey:child]) {
            return NO;
        }
    }
    if (!confirmed && !v) return NO;
    UIUserInterfaceStyle native = root.traitCollection.userInterfaceStyle;
    if (native == UIUserInterfaceStyleUnspecified) native = w.traitCollection.userInterfaceStyle;
    UIUserInterfaceStyle theme = Theme(native);
    if (native == UIUserInterfaceStyleUnspecified || theme == UIUserInterfaceStyleUnspecified) return NO;
    CGRect frame=CompactDockRect(root.bounds);
    if (!ValidRect(frame)) return NO;
    BOOL dark = theme == UIUserInterfaceStyleDark;
    BOOL nativeDark = native == UIUserInterfaceStyleDark;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (!v) {
        // The shared surface sits behind the native apps and status indicators.
        v = [[UIView alloc] initWithFrame:frame];
        v.opaque = NO;
        v.layer.opaque = NO;
        v.backgroundColor = UIColor.clearColor;
        v.userInteractionEnabled = NO;
        v.accessibilityElementsHidden = YES;
        v.layer.name = @"CarPlay26.DockFixedTint";
        [dockSurfaces setObject:v forKey:w];
    }
    if (!CGRectEqualToRect(v.frame,frame)) v.frame = frame;
    v.layer.cornerRadius = frame.size.height*.4;
    v.clipsToBounds = YES;
    if (v.superview != root || root.subviews.firstObject != v) {
        if (v.superview == root) [root sendSubviewToBack:v];
        else { [v removeFromSuperview]; [root insertSubview:v atIndex:0]; }
    }
    CAGradientLayer *layer = [dockOverlays objectForKey:v];
    if (!layer) {
        layer = [CAGradientLayer layer];
        layer.name = @"CarPlay26.DockGlass";
        [dockOverlays setObject:layer forKey:v];
    }
    layer.frame = v.bounds;
    layer.cornerRadius = v.layer.cornerRadius;
    layer.masksToBounds = YES;
    layer.startPoint = CGPointMake(.1,0);
    layer.endPoint = CGPointMake(.85,1);
    CP26ReferenceDock(w,root,frame,YES);
    CP26GlassPill(v,v.layer.cornerRadius);
    UIColor *top=dark ? [UIColor colorWithRed:.25 green:.25 blue:.29 alpha:.73] :
        [UIColor colorWithWhite:.89 alpha:nativeDark?.42:.76];
    UIColor *bottom=dark ? [UIColor colorWithRed:.21 green:.21 blue:.25 alpha:.73] :
        [UIColor colorWithRed:.79 green:.80 blue:.84 alpha:nativeDark?.38:.72];
    layer.colors=@[(id)top.CGColor,(id)bottom.CGColor];
    layer.locations=nil; layer.borderWidth=.55;
    layer.borderColor=[UIColor colorWithWhite:1 alpha:dark?.17:.32].CGColor;
    if (layer.superlayer != v.layer) { [layer removeFromSuperlayer]; [v.layer addSublayer:layer]; }
    if (dockLiquidStyle && dockLiquidSheens && dockLiquidRims && dockLiquidInnerShades) {
        // An upper glass catchlight. It is static, noninteractive and does not
        // sample the changing home-screen wallpaper during page transitions.
        CAGradientLayer *sheen = [dockLiquidSheens objectForKey:v];
        if (!sheen) {
            sheen = [CAGradientLayer layer];
            sheen.name = @"CarPlay26.DockLiquidCatchlight";
            [dockLiquidSheens setObject:sheen forKey:v];
        }
        sheen.frame = v.bounds;
        sheen.cornerRadius = frame.size.height * .5;
        sheen.masksToBounds = YES;
        sheen.startPoint = CGPointMake(.3,0);
        sheen.endPoint = CGPointMake(.7,1);
        sheen.colors = @[
            (id)[UIColor colorWithWhite:1 alpha:dark ? .19 : .31].CGColor,
            (id)[UIColor colorWithWhite:1 alpha:dark ? .065 : .08].CGColor,
            (id)UIColor.clearColor.CGColor
        ];
        sheen.locations = @[@0,@.26,@.66];
        if (sheen.superlayer != v.layer) { [sheen removeFromSuperlayer]; [v.layer addSublayer:sheen]; }

        // Gentle bottom-edge shading gives the capsule an inner curved lip
        // without clipping or darkening the native dock icons.
        CAGradientLayer *shade = [dockLiquidInnerShades objectForKey:v];
        if (!shade) {
            shade = [CAGradientLayer layer];
            shade.name = @"CarPlay26.DockLiquidInnerShade";
            [dockLiquidInnerShades setObject:shade forKey:v];
        }
        shade.frame = v.bounds;
        shade.cornerRadius = frame.size.height * .5;
        shade.masksToBounds = YES;
        shade.startPoint = CGPointMake(.5,0);
        shade.endPoint = CGPointMake(.5,1);
        shade.colors = @[
            (id)UIColor.clearColor.CGColor,
            (id)UIColor.clearColor.CGColor,
            (id)[UIColor colorWithWhite:0 alpha:dark ? .20 : .12].CGColor
        ];
        shade.locations = @[@0,@.74,@1];
        if (shade.superlayer != v.layer) { [shade removeFromSuperlayer]; [v.layer addSublayer:shade]; }

        // A specular outline varying from bright at the top-left to faint on
        // the lower-right; line stays within the existing 41-point capsule.
        CAGradientLayer *rim = [dockLiquidRims objectForKey:v];
        if (!rim) {
            rim = [CAGradientLayer layer];
            rim.name = @"CarPlay26.DockLiquidSpecularRim";
            [dockLiquidRims setObject:rim forKey:v];
        }
        rim.frame = v.bounds;
        rim.startPoint = CGPointMake(0,0);
        rim.endPoint = CGPointMake(1,1);
        rim.colors = @[
            (id)[UIColor colorWithWhite:1 alpha:dark ? .78 : .92].CGColor,
            (id)[UIColor colorWithWhite:1 alpha:dark ? .40 : .51].CGColor,
            (id)[UIColor colorWithWhite:1 alpha:dark ? .13 : .18].CGColor,
            (id)[UIColor colorWithWhite:1 alpha:dark ? .31 : .41].CGColor
        ];
        rim.locations = @[@0,@.31,@.67,@1];
        CAShapeLayer *stroke = [rim.mask isKindOfClass:CAShapeLayer.class] ? (CAShapeLayer *)rim.mask : nil;
        if (!stroke) {
            stroke = [CAShapeLayer layer];
            stroke.fillColor = UIColor.clearColor.CGColor;
            stroke.strokeColor = UIColor.whiteColor.CGColor;
            rim.mask = stroke;
        }
        stroke.frame = rim.bounds;
        stroke.lineWidth = 1.2;
        CGRect rimRect = CGRectInset(rim.bounds,.85,.85);
        stroke.path = [UIBezierPath bezierPathWithRoundedRect:rimRect cornerRadius:rimRect.size.height*.5].CGPath;
        if (rim.superlayer != v.layer) { [rim removeFromSuperlayer]; [v.layer addSublayer:rim]; }
    } else {
        CAGradientLayer *sheen = [dockLiquidSheens objectForKey:v];
        CAGradientLayer *rim = [dockLiquidRims objectForKey:v];
        CAGradientLayer *shade = [dockLiquidInnerShades objectForKey:v];
        [sheen removeFromSuperlayer];
        [rim removeFromSuperlayer];
        [shade removeFromSuperlayer];
    }
    SuppressDockBackgrounds(w,maskKeep);
    ClipLocalDockWindow(w,maskKeep);
    ClearDockBacking(w,backingKeep);
    ClearDockBacking(root,backingKeep);
    [CATransaction commit];
    if (keep) [keep addObject:v];
    return YES;
}
// Guard against reentry when UIKit performs nested layout while styling.
static BOOL dockLayoutBusy;
static void PrimeLocalDock(UIWindow *w) {
    if (!dockGlassEnabled || !dockBackings || !NSThread.isMainThread || dockLayoutBusy) return;
    dockLayoutBusy = YES;
    ApplyDock(w,nil,nil,nil);
    dockLayoutBusy = NO;
}
static BOOL ProtectDockWindow(UIWindow *w) {
    return dockGlassEnabled && NSThread.isMainThread &&
        [dockBackings objectForKey:w] != nil && DockRoot(w) != nil;
}
// 0.2.15 inventory caught a native .93/.93/.93/.60 background on the
// actual dock root while its window mask and our fixed tint were still intact.
// Intercept writes synchronously, after the root has been positively identified.
// The hooks are installed only in CarPlay with Glass Dock enabled, and all
// unregistered objects take the original path without any styling changes.
static BOOL ProtectRegisteredDockRoot(UIView *v) {
    return dockGlassEnabled && NSThread.isMainThread && dockBackings &&
        ![v isKindOfClass:UIWindow.class] && [dockBackings objectForKey:v] != nil;
}
static BOOL ProtectRegisteredDockLayer(CALayer *layer) {
    return dockGlassEnabled && NSThread.isMainThread && dockProtectedLayers &&
        [dockProtectedLayers containsObject:layer];
}
%group DockBackingColorGuard
%hook UIView
- (void)setBackgroundColor:(UIColor *)color {
    if (ProtectRegisteredDockRoot(self) && color && CGColorGetAlpha(color.CGColor) > 0) {
        if (diagnosticsEnabled) dockBlockedViewColors++;
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        %orig(UIColor.clearColor);
        [CATransaction commit];
    } else {
        %orig;
    }
}
- (void)setOpaque:(BOOL)opaque {
    if (opaque && ProtectRegisteredDockRoot(self)) { %orig(NO); }
    else { %orig; }
}
%end
%hook CALayer
- (void)setBackgroundColor:(CGColorRef)color {
    if (color && CGColorGetAlpha(color) > 0 && ProtectRegisteredDockLayer(self)) {
        if (diagnosticsEnabled) dockBlockedLayerColors++;
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        %orig(UIColor.clearColor.CGColor);
        [CATransaction commit];
    } else {
        %orig;
    }
}
- (void)setOpaque:(BOOL)opaque {
    if (opaque && ProtectRegisteredDockLayer(self)) { %orig(NO); }
    else { %orig; }
}
%end
%end

%group DockLifecycle
%hook DBRootStatusBarViewController
- (void)viewDidLayoutSubviews {
    %orig;
    UIViewController *vc = (UIViewController *)self;
    PrimeLocalDock(vc.viewIfLoaded.window);
}
%end
%end

%group DockStatusLayout
%hook _UIStatusBarForegroundView
- (void)layoutSubviews {
    %orig;
    UIWindow *w=((UIView *)self).window;
    if (DockRoot(w)) PrimeLocalDock(w);
}
%end
%end

%group DockWindowLifecycle
%hook DBStatusBarWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *native=%orig;
    return CP26DockHit((UIWindow *)self,point,event,native);
}
- (void)layoutSubviews {
    %orig;
    PrimeLocalDock((UIWindow *)self);
}
- (void)setBackgroundColor:(UIColor *)color {
    if (ProtectDockWindow((UIWindow *)self)) {
        %orig(UIColor.clearColor);
    } else {
        %orig;
    }
}
- (void)setOpaque:(BOOL)opaque {
    if (ProtectDockWindow((UIWindow *)self)) {
        %orig(NO);
    } else {
        %orig;
    }
}
%end
%end

// Page transitions can reset the root backing without the dock controller
// receiving its own layout callback. Reassert only known dock backgrounds.
%group DockScrollLifecycle
%hook DBIconScrollView
- (void)layoutSubviews {
    %orig;
    UIView *scroll = (UIView *)self;
    if ([scroll.window.windowScene.session.role isEqualToString:@"UIWindowSceneSessionRoleCarPlay"] && !dockLayoutBusy) {
        for (UIWindow *w in dockSurfaces.keyEnumerator.allObjects) PrimeLocalDock(w);
    }
}
%end
%end

static void AppendReport(NSString *entry) {
    if (report.length + entry.length > 120000)
        [report setString:@"CarPlay26 0.2.45 — older snapshots trimmed\n"];
    [report appendString:entry];
    NSData *bytes = [report dataUsingEncoding:NSUTF8StringEncoding];
    NSString *filename = @"CarPlay26-diagnostics.txt";
    // CarPlay's sandbox may not permit /var/mobile/Documents. Use the same
    // process-owned, non-atomic destinations as the working wallpaper relay.
    NSMutableArray<NSString *> *destinations = [NSMutableArray array];
    if (diagnosticReportPath.length) [destinations addObject:diagnosticReportPath];
    [destinations addObjectsFromArray:@[
        [@"/var/mobile/Documents" stringByAppendingPathComponent:filename],
        [@"/var/mobile/Library/Caches" stringByAppendingPathComponent:filename],
        [[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches"] stringByAppendingPathComponent:filename],
        [NSTemporaryDirectory() stringByAppendingPathComponent:filename]
    ]];
    NSURL *cache = [[NSFileManager defaultManager]
        URLForDirectory:NSCachesDirectory inDomain:NSUserDomainMask
        appropriateForURL:nil create:YES error:nil];
    if (cache.path.length)
        [destinations addObject:[cache.path stringByAppendingPathComponent:filename]];
    NSError *lastError = nil;
    for (NSString *path in destinations) {
        if (!path.length) continue;
        NSError *error = nil;
        if ([bytes writeToFile:path options:0 error:&error]) {
            if (![diagnosticReportPath isEqualToString:path]) {
                NSLog(@"[CarPlay26] diagnostics saved to %@",path);
                diagnosticReportPath = [path copy];
            }
            writeErrorLogged = NO;
            return;
        }
        lastError = error;
    }
    if (!writeErrorLogged) {
        NSLog(@"[CarPlay26] diagnostics could not be written: %@",lastError.localizedDescription ?: @"no writable destination");
        writeErrorLogged = YES;
    }
    NSLog(@"[CarPlay26] %@",entry);
}
// Read-only inventory of all known CarPlay-process windows, including hidden
// windows and short/narrow status-bar windows excluded by the styling scan.
// Does not inspect view text, images, or private backing-context properties.
static BOOL DockClassName(NSString *name) {
    return [name rangeOfString:@"StatusBar" options:NSCaseInsensitiveSearch].location != NSNotFound ||
           [name rangeOfString:@"Dock" options:NSCaseInsensitiveSearch].location != NSNotFound;
}
static void DockViewTree(UIView *v, UIWindow *w, NSMutableString *out, NSUInteger depth, NSUInteger *budget) {
    if (!*budget || depth > 12 || out.length > 45000) return;
    (*budget)--;
    CGRect r = [v convertRect:v.bounds toView:w];
    [out appendFormat:@"%*s%@ frameInWindow=(%.1f %.1f %.1f %.1f) bounds=(%.1f %.1f) hidden=%d alpha=%.2f layer=%@ subviews=%lu ownedFixedTint=%d\n",
        (int)(depth*2), "", NSStringFromClass(v.class), r.origin.x,r.origin.y,r.size.width,r.size.height,
        v.bounds.size.width,v.bounds.size.height,v.hidden,(double)v.alpha,NSStringFromClass(v.layer.class),(unsigned long)v.subviews.count,v == [dockSurfaces objectForKey:w]];
    if (depth <= 3) {
        NSDictionary *saved = [dockBackings objectForKey:v];
        [out appendFormat:@"%*s backing viewColor=%@ viewOpaque=%d layerColor=%@ layerOpaque=%d mask=%@ saved=%@\n",
            (int)(depth*2+2), "", v.backgroundColor ?: (id)NSNull.null, v.opaque,
            v.layer.backgroundColor ? (__bridge id)v.layer.backgroundColor : (id)NSNull.null,
            v.layer.opaque, v.layer.mask ? (v.layer.mask.name ?: NSStringFromClass(v.layer.mask.class)) : @"none",
            saved ?: (id)NSNull.null];
    }
    for (UIView *child in v.subviews) { if (!*budget) break; DockViewTree(child,w,out,depth+1,budget); }
}
static void DockLayerTree(CALayer *layer, NSMutableString *out, NSUInteger depth, NSUInteger *budget) {
    if (!*budget || depth > 8 || out.length > 45000) return;
    (*budget)--;
    CGRect r = layer.frame;
    [out appendFormat:@"%*s%@ frame=(%.1f %.1f %.1f %.1f) hidden=%d opacity=%.2f children=%lu\n",
        (int)(depth*2), "", NSStringFromClass(layer.class),r.origin.x,r.origin.y,r.size.width,r.size.height,
        layer.hidden,(double)layer.opacity,(unsigned long)layer.sublayers.count];
    for (CALayer *child in layer.sublayers) { if (!*budget) break; DockLayerTree(child,out,depth+1,budget); }
}
static void CaptureDockReport(UIApplication *app, NSOrderedSet<UIWindow *> *windows) {
    static NSMutableString *dockHistory;
    NSMutableString *out = [NSMutableString stringWithFormat:@"\n%@ | process=%@ | windows=%lu | scenes=%lu\n",NSDate.date,NSProcessInfo.processInfo.processName,(unsigned long)windows.count,(unsigned long)app.connectedScenes.count];
    [out appendFormat:@"Dock backing guard blockedViewColors=%lu blockedLayerColors=%lu protectedLayers=%lu\n",
        (unsigned long)dockBlockedViewColors,(unsigned long)dockBlockedLayerColors,(unsigned long)dockProtectedLayers.count];
    for (UIScene *scene in app.connectedScenes) {
        [out appendFormat:@"Scene %@ role=%@ activation=%ld",NSStringFromClass(scene.class),scene.session.role ?: @"none",(long)scene.activationState];
        if ([scene isKindOfClass:UIWindowScene.class]) {
            UIWindowScene *ws = (UIWindowScene *)scene;
            [out appendFormat:@" screen=%.1fx%.1f windows=%lu",ws.screen.bounds.size.width,ws.screen.bounds.size.height,(unsigned long)ws.windows.count];
        }
        [out appendString:@"\n"];
    }
    NSUInteger viewBudget = 240, layerBudget = 140;
    for (UIWindow *w in windows) {
        CGRect r = w.frame, b = w.bounds;
        NSString *name = NSStringFromClass(w.class);
        NSString *root = w.rootViewController ? NSStringFromClass(w.rootViewController.class) : @"none";
        BOOL named = DockClassName(name) || DockClassName(root);
        BOOL narrow = (b.size.width >= 200 && b.size.height > 0 && b.size.height <= 100) ||
                      (b.size.height >= 200 && b.size.width > 0 && b.size.width <= 100);
        [out appendFormat:@"Window %@ role=%@ root=%@ frame=(%.1f %.1f %.1f %.1f) bounds=(%.1f %.1f) level=%.1f hidden=%d alpha=%.2f safe=(%.1f %.1f %.1f %.1f) candidate=%@\n",
            name,w.windowScene.session.role ?: @"none",root,r.origin.x,r.origin.y,r.size.width,r.size.height,b.size.width,b.size.height,
            (double)w.windowLevel,w.hidden,(double)w.alpha,w.safeAreaInsets.top,w.safeAreaInsets.left,w.safeAreaInsets.bottom,w.safeAreaInsets.right,
            named?@"class":narrow?@"geometry":@"no"];
        if ((named || narrow) && !Named(w,@"UITextEffectsWindow")) {
            NSUInteger localViews = MIN(viewBudget,(NSUInteger)100), localLayers = MIN(layerBudget,(NSUInteger)60);
            NSUInteger initialViews = localViews, initialLayers = localLayers;
            [out appendString:@"  View tree (including hidden views):\n"];
            CP26DockReport(w,out);
            DockViewTree(w,w,out,1,&localViews);
            [out appendString:@"  Layer tree:\n"];
            DockLayerTree(w.layer,out,1,&localLayers);
            viewBudget -= initialViews-localViews;
            layerBudget -= initialLayers-localLayers;
        }
    }
    // Class presence does not prove that a view instance is used. The image
    // name helps distinguish classes in different frameworks/processes.
    unsigned int classCount = 0;
    __unsafe_unretained Class *classes = objc_copyClassList(&classCount);
    NSUInteger matches = 0;
    [out appendString:@"Loaded dock/status-bar classes (DB/CarPlay/DashBoard only):\n"];
    for (unsigned int i = 0; classes && i < classCount && matches < 100; i++) {
        Class cls = classes[i];
        NSString *name = NSStringFromClass(cls);
        if (!DockClassName(name) || !([name hasPrefix:@"DB"] || [name hasPrefix:@"DashBoard."] || [name hasPrefix:@"CP"] || [name hasPrefix:@"CarPlay"])) continue;
        const char *image = class_getImageName(cls);
        NSString *imageName = image ? [NSString stringWithUTF8String:image].lastPathComponent : @"unknown";
        [out appendFormat:@"  %@ image=%@\n",name,imageName ?: @"unknown"];
        matches++;
    }
    free(classes);
    [out appendFormat:@"Class matches=%lu (capped at 100)\n",(unsigned long)matches];
    if (!dockHistory) dockHistory = [NSMutableString stringWithString:@"CarPlay26 0.2.20 | dock inventory; optional local glass overlay\n"];
    if (dockHistory.length + out.length > 120000) [dockHistory setString:@"CarPlay26 0.2.18 | earlier dock snapshots trimmed\n"];
    [dockHistory appendString:out];
    NSError *error = nil;
    if (![dockHistory writeToFile:@"/var/mobile/Documents/CarPlay26-dock-diagnostics.txt" atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
        NSLog(@"[CarPlay26] dock report unavailable: %@",error.localizedDescription);
    }
}

// Select the native model item rather than replacing a UIImageView or
// intercepting taps. Signatures observed in the user's iOS 16.4.1 probe.
@interface DBAppDockItem : NSObject
- (NSString *)bundleIdentifier;
- (NSUInteger)category;
- (BOOL)isActive;
- (instancetype)initWithBundleIdentifier:(NSString *)bundleID category:(NSUInteger)category active:(BOOL)active;
@end
@interface DBAppHistory : NSObject
- (BOOL)isBundleIdentifierValidForDock:(NSString *)bundleID;
- (NSUInteger)appDockCategoryForBundleIdentifier:(NSString *)bundleID;
@end
@interface DBAppDockButton : UIControl
- (NSString *)bundleIdentifier;
- (void)setBundleIdentifier:(NSString *)bundleIdentifier;
- (void)setBundleIdentifier:(NSString *)bundleIdentifier animated:(BOOL)animated;
@end
@interface DBAppDockViewController : UIViewController
- (DBAppHistory *)appHistory;
- (NSString *)activeBundleIdentifier;
- (DBAppDockButton *)navigationAppButton;
- (DBAppDockButton *)audioAppButton;
- (DBAppDockButton *)otherAppButton;
- (NSArray *)_generateOrderedAppItems;
@end

static BOOL CP26PinAPIsAvailable(void) {
    Class controller = NSClassFromString(@"DBAppDockViewController");
    Class history = NSClassFromString(@"DBAppHistory");
    Class item = NSClassFromString(@"DBAppDockItem");
    if (!controller || !history || !item) return NO;
    Class button = NSClassFromString(@"DBAppDockButton");
    return button && class_getInstanceMethod(controller,@selector(_generateOrderedAppItems)) &&
        class_getInstanceMethod(controller,@selector(_refreshAppDock)) &&
        class_getInstanceMethod(controller,@selector(otherAppButton)) &&
        class_getInstanceMethod(button,@selector(bundleIdentifier)) &&
        class_getInstanceMethod(button,@selector(setBundleIdentifier:animated:)) &&
        class_getInstanceMethod(button,@selector(setBundleIdentifier:)) &&
        class_getInstanceMethod(controller,@selector(appHistory)) &&
        class_getInstanceMethod(controller,@selector(activeBundleIdentifier)) &&
        class_getInstanceMethod(history,@selector(isBundleIdentifierValidForDock:)) &&
        class_getInstanceMethod(history,@selector(appDockCategoryForBundleIdentifier:)) &&
        class_getInstanceMethod(item,@selector(bundleIdentifier)) &&
        class_getInstanceMethod(item,@selector(category)) &&
        class_getInstanceMethod(item,@selector(initWithBundleIdentifier:category:active:));
}

static NSArray *CP26PinnedItems(DBAppDockViewController *controller, NSArray *nativeItems) {
    if (!NSThread.isMainThread || !pinnedDockBundle.length) return nativeItems;
    pinGeneratedCount++;
    @try {
        if (![nativeItems isKindOfClass:NSArray.class] || nativeItems.count > 3 || nativeItems.count < 2) {
            pinLastResult = @"unexpected native item list; left stock";
            return nativeItems;
        }
        DBAppHistory *history = [controller appHistory];
        if (!history || ![history respondsToSelector:@selector(isBundleIdentifierValidForDock:)] ||
            ![history respondsToSelector:@selector(appDockCategoryForBundleIdentifier:)] ||
            ![history isBundleIdentifierValidForDock:pinnedDockBundle]) {
            pinLastResult = @"selected app not currently valid for dock; left stock";
            return nativeItems;
        }
        // Use Messages as the reference 'other' category, rather than guessing
        // the private numeric enum. Never attempt to pin a media/navigation app.
        NSUInteger category = [history appDockCategoryForBundleIdentifier:@"com.apple.MobileSMS"];
        if ([history appDockCategoryForBundleIdentifier:pinnedDockBundle] != category) {
            pinLastResult = @"selected app not in Messages dock category; left stock";
            return nativeItems;
        }
        Class itemClass = NSClassFromString(@"DBAppDockItem");
        NSMutableSet<NSNumber *> *seen = [NSMutableSet set];
        NSUInteger index = NSNotFound;
        for (NSUInteger i=0; i<nativeItems.count; i++) {
            DBAppDockItem *item = nativeItems[i];
            if (![item isKindOfClass:itemClass] || ![item respondsToSelector:@selector(category)] ||
                ![item respondsToSelector:@selector(bundleIdentifier)]) {
                pinLastResult = @"unexpected item class; left stock";
                return nativeItems;
            }
            NSUInteger itemCategory = [item category];
            NSNumber *key = @(itemCategory);
            if ([seen containsObject:key]) {
                pinLastResult = @"duplicate categories; left stock";
                return nativeItems;
            }
            [seen addObject:key];
            if (itemCategory == category) index = i;
            else if ([[item bundleIdentifier] isEqualToString:pinnedDockBundle]) {
                pinLastResult = @"selected app already in another slot; left stock";
                return nativeItems;
            }
        }
        // If the native list already has all three slots but no matching
        // category, don't guess which item to replace. If it has two distinct
        // categories, let the native controller handle the added third item.
        if (index == NSNotFound && nativeItems.count != 2) {
            pinLastResult = @"other category absent; left stock";
            return nativeItems;
        }
        if (index != NSNotFound && [[(DBAppDockItem *)nativeItems[index] bundleIdentifier] isEqualToString:pinnedDockBundle]) {
            pinLastResult = @"native list already contains selected app";
            return nativeItems;
        }
        // Native active-state handling is retained, including when Messages
        // is itself the foreground app. Do not activate/launch an app here.
        BOOL active = [[controller activeBundleIdentifier] isEqualToString:pinnedDockBundle];
        DBAppDockItem *replacement = [[itemClass alloc] initWithBundleIdentifier:pinnedDockBundle category:category active:active];
        if (!replacement) { pinLastResult = @"item allocation failed; left stock"; return nativeItems; }
        NSMutableArray *items = [nativeItems mutableCopy];
        if (index == NSNotFound) [items addObject:replacement];
        else items[index] = replacement;
        pinAppliedCount++;
        pinLastResult = [NSString stringWithFormat:@"%@ category=%lu slot=%@",pinnedDockBundle,(unsigned long)category,index==NSNotFound?@"append":@(index).stringValue];
        return [items copy];
    } @catch (NSException *exception) {
        pinLastResult = [NSString stringWithFormat:@"native API exception %@; left stock",exception.name];
        return nativeItems;
    }
}

// The native ordered-items list can already contain Messages while the visible
// third button is independently changed to Settings. Protect that real button,
// instead of relying on model generation alone. No timers or tap interception.
static void CP26EnforcePinnedOtherButton(DBAppDockViewController *controller, NSString *reason) {
    if (!NSThread.isMainThread || !controller || !pinnedDockBundle.length || !pinOtherButtons) return;
    @try {
        DBAppHistory *history = [controller appHistory];
        if (!history || ![history isBundleIdentifierValidForDock:pinnedDockBundle] ||
            [history appDockCategoryForBundleIdentifier:pinnedDockBundle] !=
            [history appDockCategoryForBundleIdentifier:@"com.apple.MobileSMS"]) {
            pinButtonLastResult = @"selected app failed native dock eligibility/category checks";
            return;
        }
        DBAppDockButton *button = [controller otherAppButton];
        if (!button || ![button isKindOfClass:NSClassFromString(@"DBAppDockButton")]) {
            pinButtonLastResult = @"other button not created yet";
            return;
        }
        // Register only the native otherAppButton so the setter hook cannot
        // affect navigation, media, or unrelated buttons.
        [pinOtherButtons addObject:button];
        NSString *current = [button bundleIdentifier];
        if ([current isEqualToString:pinnedDockBundle]) return;
        [button setBundleIdentifier:pinnedDockBundle animated:NO];
        NSString *actual = [button bundleIdentifier];
        if ([actual isEqualToString:pinnedDockBundle]) {
            pinButtonCorrections++;
            pinButtonLastResult = [NSString stringWithFormat:@"corrected %@ -> %@ on %@",
                current ?: @"<nil>",pinnedDockBundle,reason];
        } else {
            pinButtonLastResult = [NSString stringWithFormat:@"button setter did not hold on %@ (now %@)",
                reason,actual ?: @"<nil>"];
        }
    } @catch (NSException *exception) {
        pinButtonLastResult = [NSString stringWithFormat:@"button update exception %@",exception.name];
    }
}

%group DockPinning
%hook DBAppDockViewController
- (NSArray *)_generateOrderedAppItems {
    NSArray *nativeItems = %orig;
    return CP26PinnedItems((DBAppDockViewController *)self,nativeItems);
}
- (void)_refreshAppDock {
    %orig;
    CP26EnforcePinnedOtherButton((DBAppDockViewController *)self,@"_refreshAppDock");
}
- (void)viewWillLayoutSubviews {
    %orig;
    CP26EnforcePinnedOtherButton((DBAppDockViewController *)self,@"layout");
}
- (void)setActiveBundleIdentifier:(NSString *)bundleID animated:(BOOL)animated {
    %orig;
    CP26EnforcePinnedOtherButton((DBAppDockViewController *)self,@"active app");
}
%end

%hook DBAppDockButton
- (void)setBundleIdentifier:(NSString *)bundleID {
    if (pinnedDockBundle.length && [pinOtherButtons containsObject:self] &&
        ![bundleID isEqualToString:pinnedDockBundle]) {
        pinBlockedNativeAssignments++;
        pinButtonLastResult = [NSString stringWithFormat:@"blocked native button assignment %@ -> %@",
            bundleID ?: @"<nil>",pinnedDockBundle];
        %orig(pinnedDockBundle);
        return;
    }
    %orig;
}
- (void)setBundleIdentifier:(NSString *)bundleID animated:(BOOL)animated {
    if (pinnedDockBundle.length && [pinOtherButtons containsObject:self] &&
        ![bundleID isEqualToString:pinnedDockBundle]) {
        pinBlockedNativeAssignments++;
        pinButtonLastResult = [NSString stringWithFormat:@"blocked native animated assignment %@ -> %@",
            bundleID ?: @"<nil>",pinnedDockBundle];
        %orig(pinnedDockBundle,NO);
        return;
    }
    %orig;
}
%end
%end

// Read-only runtime inventory for the native shortcut model. No private
// methods are invoked, no history is edited and no button actions are replaced.
static void CP26DescribeShortcutClass(NSString *name, NSMutableString *out) {
    Class cls = NSClassFromString(name);
    if (!cls) { [out appendFormat:@"\n%@ not loaded\n", name]; return; }
    [out appendFormat:@"\n%@ superclass=%@\n",name,NSStringFromClass(class_getSuperclass(cls))];
    unsigned int count = 0;
    Ivar *ivars = class_copyIvarList(cls,&count);
    for (unsigned int i=0; i<count && i<200; i++) {
        [out appendFormat:@"  ivar %s %s\n",ivar_getName(ivars[i]),ivar_getTypeEncoding(ivars[i])];
    }
    free(ivars);
    for (NSUInteger kind=0; kind<2; kind++) {
        Class target = kind ? object_getClass(cls) : cls;
        Method *methods = class_copyMethodList(target,&count);
        for (unsigned int i=0; i<count && i<400; i++) {
            [out appendFormat:@"  %@ %@  %s\n",kind?@"+":@"-",NSStringFromSelector(method_getName(methods[i])),method_getTypeEncoding(methods[i]) ?: "?"];
        }
        free(methods);
    }
}
static void CP26ShortcutButtons(UIView *v, NSMutableArray<UIControl *> *buttons, NSUInteger *budget) {
    if (!v || !*budget) return;
    (*budget)--;
    if (Named(v,@"DBAppDockButton") && [v isKindOfClass:UIControl.class]) {
        [buttons addObject:(UIControl *)v];
        return;
    }
    for (UIView *child in v.subviews) {
        if (!*budget) break;
        CP26ShortcutButtons(child,buttons,budget);
    }
}
static void CP26CaptureShortcutProbe(NSOrderedSet<UIWindow *> *windows) {
    static NSUInteger samples;
    static NSString *inventory;
    static NSMutableString *observations;
    if (samples >= 30) return;
    NSMutableString *snapshot = [NSMutableString stringWithFormat:@"pin=%@ generated=%lu applied=%lu result=%@ buttonCorrections=%lu blockedNative=%lu buttonResult=%@\n",pinnedDockBundle ?: @"off",(unsigned long)pinGeneratedCount,(unsigned long)pinAppliedCount,pinLastResult ?: @"not called",(unsigned long)pinButtonCorrections,(unsigned long)pinBlockedNativeAssignments,pinButtonLastResult ?: @"no correction needed"];
    NSUInteger found = 0;
    NSMutableSet<NSString *> *targetNames = [NSMutableSet set];
    for (UIWindow *w in windows) {
        if (!Named(w,@"DBStatusBarWindow") || ![w.windowScene.session.role isEqualToString:@"UIWindowSceneSessionRoleCarPlay"] ||
            ![NSStringFromClass(w.rootViewController.class) isEqualToString:@"DBRootStatusBarViewController"] || !Visible(w)) continue;
        NSMutableArray<UIControl *> *buttons = [NSMutableArray array];
        NSUInteger budget = 250;
        CP26ShortcutButtons(w,buttons,&budget);
        if (!buttons.count) continue;
        found += buttons.count;
        [snapshot appendFormat:@"window %.0fx%.0f, buttons=%lu\n",w.bounds.size.width,w.bounds.size.height,(unsigned long)buttons.count];
        for (UIControl *button in buttons) {
            CGRect r = [button convertRect:button.bounds toView:w];
            [snapshot appendFormat:@"  %@ frame=(%.1f %.1f %.1f %.1f) hidden=%d enabled=%d events=0x%llx\n",NSStringFromClass(button.class),r.origin.x,r.origin.y,r.size.width,r.size.height,button.hidden,button.enabled,(unsigned long long)button.allControlEvents];
            for (id target in button.allTargets) {
                if (target == NSNull.null) { [snapshot appendString:@"    responder-chain target\n"]; continue; }
                NSString *targetName = NSStringFromClass([target class]);
                [targetNames addObject:targetName];
                // Read only the confirmed native button identifiers and role.
                if ([target isKindOfClass:NSClassFromString(@"DBAppDockViewController")] &&
                    [button respondsToSelector:@selector(bundleIdentifier)] &&
                    [target respondsToSelector:@selector(navigationAppButton)] &&
                    [target respondsToSelector:@selector(audioAppButton)] &&
                    [target respondsToSelector:@selector(otherAppButton)]) {
                    @try {
                        DBAppDockViewController *controller = target;
                        NSString *role = button == [controller navigationAppButton] ? @"navigation" :
                            button == [controller audioAppButton] ? @"audio" :
                            button == [controller otherAppButton] ? @"other" : @"unknown";
                        [snapshot appendFormat:@"    role=%@ bundle=%@\n",role,[(DBAppDockButton *)button bundleIdentifier] ?: @"<nil>"];
                    } @catch (__unused NSException *exception) { }
                }
                // Enumerate individual registered event bits instead of assuming touch-up-inside.
                for (NSUInteger bit=0; bit<32; bit++) {
                    UIControlEvents event = (UIControlEvents)(1UL<<bit);
                    if (!(button.allControlEvents & event)) continue;
                    NSArray *actions = [button actionsForTarget:target forControlEvent:event];
                    if (actions.count) [snapshot appendFormat:@"    target=%@ event=0x%lx actions=%@\n",targetName,(unsigned long)event,[actions componentsJoinedByString:@", "]];
                }
            }
        }
    }
    if (!found) return;
    if (!inventory) {
        NSMutableString *header = [NSMutableString stringWithFormat:@"CarPlay26 0.2.20 | native dock shortcut pinning probe | iOS %@\n",UIDevice.currentDevice.systemVersion];
        NSMutableOrderedSet<NSString *> *classes = [NSMutableOrderedSet orderedSetWithArray:@[@"DBAppDockViewController",@"DBAppDockItem",@"DBAppDockButton",@"DBAppHistory",@"DBApplication",@"DBApplicationController",@"DBApplicationInfo",@"DBRootStatusBarViewController",@"DBStatusBarViewController",@"DBWorkspace",@"DBDashboard",@"DBDashboardRootViewController",@"DBFolderController",@"DBIconModel",@"DBIconView"]];
        for (NSString *name in targetNames) if ([name hasPrefix:@"DB"] || [name hasPrefix:@"DashBoard."]) [classes addObject:name];
        for (NSString *name in classes) CP26DescribeShortcutClass(name,header);
        inventory = [header copy];
        observations = [NSMutableString string];
    }
    samples++;
    [observations appendFormat:@"\n%@ sample=%lu\n%@",NSDate.date,(unsigned long)samples,snapshot];
    // Bound work and file size; the existing two-second timer is unchanged.
    NSString *reportText = [inventory stringByAppendingString:observations];
    NSError *error = nil;
    if (![reportText writeToFile:@"/var/mobile/Documents/CarPlay26-dock-shortcuts.txt" atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
        NSLog(@"[CarPlay26] shortcut probe unavailable: %@",error.localizedDescription);
    }
}

static void Refresh(void) {
    UIApplication *app = UIApplication.sharedApplication;
    if (!app) return;
    NSMutableOrderedSet<UIWindow *> *windows = [NSMutableOrderedSet orderedSet];
    for (UIScene *scene in app.connectedScenes) {
        if ([scene isKindOfClass:UIWindowScene.class]) [windows addObjectsFromArray:((UIWindowScene *)scene).windows];
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [windows addObjectsFromArray:app.windows ?: @[]];
#pragma clang diagnostic pop
    if (dockShortcutProbeEnabled) CP26CaptureShortcutProbe(windows);
    NSHashTable<UIView *> *keep = [NSHashTable weakObjectsHashTable];
    NSHashTable<UIView *> *dockKeep = [NSHashTable weakObjectsHashTable];
    NSHashTable<UIView *> *dockMaskKeep = [NSHashTable weakObjectsHashTable];
    NSHashTable<UIView *> *dockBackingKeep = [NSHashTable weakObjectsHashTable];
    BOOL active = NO;
    for (UIWindow *w in windows) {
        if (Visible(w) && w.bounds.size.width >= 250 && w.bounds.size.height >= 200 &&
            !Named(w,@"UITextEffectsWindow")) { active = YES; break; }
    }
    if (active && !hadWindows) connectedTicks = 0;
    hadWindows = active;
    if (active) connectedTicks++;
    NSMutableString *summary = [NSMutableString stringWithFormat:@"mode=%@ dockProbe=%@ dockGlass=%@ labels=%@ cards=%@ icons=%@ controls=%@ windows=%lu\n",mode,dockEnabled?@"on":@"off",dockGlassEnabled?@"on":@"off",labelsEnabled?@"on":@"off",cardsEnabled?@"on":@"off",iconsEnabled?@"on":@"off",controlsEnabled?@"on":@"off",(unsigned long)windows.count];
    // Capture after actual connection, not just after process startup.
    BOOL capture = diagnosticsEnabled && active && (connectedTicks == 1 || connectedTicks == 3 || connectedTicks == 8 || connectedTicks == 15 || connectedTicks == 30 || connectedTicks == 60);
    if (capture && dockEnabled) CaptureDockReport(app,windows);
    NSMutableString *tree = capture ? [NSMutableString string] : nil;
    for (UIWindow *w in windows) {
        if (Named(w,@"DBStatusBarWindow")) {
            BOOL styled = ApplyDock(w,dockKeep,dockMaskKeep,dockBackingKeep);
            [summary appendFormat:@"DBStatusBarWindow %.0fx%.0f dock=%@\n",w.bounds.size.width,w.bounds.size.height,styled?@"applied":(dockGlassEnabled?@"no-valid-material":@"off")];
            continue;
        }
        if (!Visible(w) || w.bounds.size.width < 250 || w.bounds.size.height < 200 || Named(w,@"UITextEffectsWindow")) continue;
        UIUserInterfaceStyle native = w.traitCollection.userInterfaceStyle;
        NSMutableArray<UIView *> *matches = [NSMutableArray array];
        NSUInteger budget = 700;
        if (tree) [tree appendFormat:@"Window %@ %.0fx%.0f native=%@ sceneRole=%@ rootVC=%@ level=%.1f\n",NSStringFromClass(w.class),w.bounds.size.width,w.bounds.size.height,StyleName(native),w.windowScene.session.role ?: @"none",w.rootViewController ? NSStringFromClass(w.rootViewController.class) : @"none",(double)w.windowLevel];
        // The remote status-bar host is diagnostics only; never decorate it.
        if (Named(w,@"DBStatusBarHostWindow")) {
            if (tree && dockEnabled) Scan(w,w,matches,tree,0,&budget);
            [summary appendFormat:@"DBStatusBarHostWindow native=%@ dock=remote-host-unmodified\n",StyleName(native)];
            continue;
        }
        if (Named(w,@"DBLockOutWindow") || Named(w,@"DBNotificationWindow") || Named(w,@"_DBCornerRadiusWindow")) continue;
        Scan(w,w,matches,tree,0,&budget);
        NSUInteger found[5] = {0}, applied[5] = {0};
        for (UIView *target in matches) {
            NSInteger kind = SurfaceKind(target,w);
            if (kind < CP26Label || kind > CP26Control) continue;
            found[kind]++;
            BOOL enabled = kind == CP26Label ? labelsEnabled : kind == CP26Card ? cardsEnabled : kind == CP26Icon ? iconsEnabled : controlsEnabled;
            UIUserInterfaceStyle targetNative = target.traitCollection.userInterfaceStyle;
            if (targetNative == UIUserInterfaceStyleUnspecified) targetNative = native;
            UIUserInterfaceStyle theme = Theme(targetNative);
            if (enabled && theme != UIUserInterfaceStyleUnspecified && targetNative != UIUserInterfaceStyleUnspecified) {
                if (Apply(target,theme,targetNative,kind)) {
                    [keep addObject:target];
                    applied[kind]++;
                }
            }
        }
        [summary appendFormat:@"%@ %.0fx%.0f native=%@ resolved=%@ labels=%lu appliedLabels=%lu cards=%lu appliedCards=%lu icons=%lu appliedIcons=%lu controls=%lu appliedControls=%lu complete=%@\n",NSStringFromClass(w.class),w.bounds.size.width,w.bounds.size.height,StyleName(native),StyleName(Theme(native)),(unsigned long)found[1],(unsigned long)applied[1],(unsigned long)found[2],(unsigned long)applied[2],(unsigned long)found[3],(unsigned long)applied[3],(unsigned long)found[4],(unsigned long)applied[4],budget?@"yes":@"no"];
    }
    RemoveStale(keep);
    for (UIView *v in dockOverlays.keyEnumerator.allObjects) {
        if (![dockKeep containsObject:v]) { [[dockOverlays objectForKey:v] removeFromSuperlayer]; [dockOverlays removeObjectForKey:v]; }
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (UIWindow *w in dockSurfaces.keyEnumerator.allObjects) {
        UIView *surface = [dockSurfaces objectForKey:w];
        if (![dockKeep containsObject:surface]) {
            [surface removeFromSuperview];
            CP26ReferenceDock(w,nil,CGRectZero,NO);
            [dockSurfaces removeObjectForKey:w];
        }
    }
    for (UIView *v in dockMasks.keyEnumerator.allObjects) {
        if (![dockMaskKeep containsObject:v]) {
            CAShapeLayer *mask = [dockMasks objectForKey:v];
            if (v.layer.mask == mask) v.layer.mask = nil;
            [dockMasks removeObjectForKey:v];
        }
    }
    for (UIView *v in dockBackings.keyEnumerator.allObjects) {
        if (![dockBackingKeep containsObject:v]) {
            NSDictionary *original = [dockBackings objectForKey:v];
            // Unregister before restoring so the guards do not intercept cleanup.
            [dockBackings removeObjectForKey:v];
            [dockProtectedLayers removeObject:v.layer];
            RestoreDockBacking(v,original);
        }
    }
    [CATransaction commit];
    if (diagnosticsEnabled && (capture || ![lastSignature isEqualToString:summary])) {
        AppendReport([NSString stringWithFormat:@"\n%@\n%@%@",NSDate.date,summary,tree ?: @""]);
        lastSignature = [summary copy];
    }
}

// Darwin notifications are wake-up signals only. Require a fresh request
// written to our preferences, after this process started listening. Do not
// relaunch repeatedly from a stale preference on the next process startup.
static NSTimeInterval restartListenerStarted;
static BOOL restartInProgress;
static char restartObserver;
static void CP26RestartRequested(__unused CFNotificationCenterRef center,
    __unused void *observer, __unused CFStringRef name,
    __unused const void *object, __unused CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (restartInProgress) return;
        if (![NSProcessInfo.processInfo.processName isEqualToString:@"CarPlay"]) return;
        CFPreferencesAppSynchronize(CFSTR("com.tillman109.carplay26"));
        id raw = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("RestartRequest"),
            CFSTR("com.tillman109.carplay26")));
        if (![raw isKindOfClass:NSDictionary.class]) return;
        id token = raw[@"token"], stamp = raw[@"time"];
        if (![token isKindOfClass:NSString.class] || ![stamp isKindOfClass:NSNumber.class]) return;
        if (![[NSUUID alloc] initWithUUIDString:token]) return;
        NSTimeInterval requested = [stamp doubleValue];
        NSTimeInterval age = NSDate.date.timeIntervalSince1970 - requested;
        if (!isfinite(requested) || requested < restartListenerStarted || age < 0 || age > 10) return;
        restartInProgress = YES;
        NSLog(@"CarPlay26: confirmed local preference request; exiting CarPlay shell only");
        // No shell commands, privileged helper, or other daemon termination.
        // The OS decides when to launch CarPlay again; reconnect if necessary.
        _exit(0);
    });
}

// Wallpaper diagnostic transport, v0.2.25. The main CarPlay process writes its
// OWN heartbeat before relying on notifications from sandboxed wallpaper apps.
// This avoids v0.2.23's ambiguous "no relay file" result.
static char wpRelayObserver;
static NSMutableDictionary<NSString *, NSString *> *wpRelayReports;
static NSMutableDictionary<NSString *, NSString *> *wpRelayStatuses;
static NSTimeInterval wpRelayStarted;
static NSUInteger wpRelayRequests;
static NSUInteger wpRelaySignals;
static BOOL wpRelayProbeEnabled;
static NSString *wpRelayLastWriteError;
static NSString *wpRelayLastSavedPath;

static void CP26WriteWallpaperRelay(void) {
    if (![NSProcessInfo.processInfo.processName isEqualToString:@"CarPlay"]) return;
    NSMutableString *output = [NSMutableString stringWithFormat:
        @"CarPlay26 0.2.25 — delayed wallpaper relay self-test (main CarPlay process)\n"
        @"CarPlay PID=%d uptimeSinceListener=%.1fs inspectSetting=%d requests=%lu signals=%lu\n"
        @"This file is written by CarPlay itself even if wallpaper apps never respond.\n\n",
        getpid(), NSDate.date.timeIntervalSince1970 - wpRelayStarted,
        wpRelayProbeEnabled, (unsigned long)wpRelayRequests, (unsigned long)wpRelaySignals];
    for (NSString *sourceName in @[@"CarPlayWallpaper", @"CarPlaySettings"]) {
        NSString *status = wpRelayStatuses[sourceName];
        [output appendFormat:@"=== %@ ===\n%@\n\n", sourceName,
            status ?: @"No response received from this process yet"];
        NSString *body = wpRelayReports[sourceName];
        if (body.length) [output appendFormat:@"%@\n\n", body];
    }
    // A CarPlay UI service may be sandboxed from /var/mobile/Documents.
    // Find a process-owned location using UIKit/Foundation APIs instead of
    // assuming one fixed writable path.  Plain NSData writes avoid a separate
    // temporary-file rename inside sandboxed app containers.
    NSString *filename = @"CarPlay26-wallpaper-relay.txt";
    NSMutableArray<NSString *> *destinations = [NSMutableArray arrayWithObjects:
        [@"/var/mobile/Documents" stringByAppendingPathComponent:filename],
        [@"/var/mobile/Library/Caches" stringByAppendingPathComponent:filename],
        [[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches"] stringByAppendingPathComponent:filename],
        [NSTemporaryDirectory() stringByAppendingPathComponent:filename], nil];
    NSURL *userCache = [[NSFileManager defaultManager]
        URLForDirectory:NSCachesDirectory inDomain:NSUserDomainMask
        appropriateForURL:nil create:YES error:nil];
    if (userCache.path.length)
        [destinations addObject:[userCache.path stringByAppendingPathComponent:filename]];
    NSData *bytes = [output dataUsingEncoding:NSUTF8StringEncoding];
    NSError *lastError = nil;
    NSString *saved = nil;
    for (NSString *path in destinations) {
        if (!path.length) continue;
        NSError *error = nil;
        if ([bytes writeToFile:path options:0 error:&error]) {
            saved = path;
            break;
        }
        lastError = error;
    }
    if (saved) {
        if (![saved isEqualToString:wpRelayLastSavedPath]) {
            NSLog(@"CarPlay26 wallpaper relay saved to %@", saved);
            wpRelayLastSavedPath = saved;
        }
        wpRelayLastWriteError = nil;
    } else {
        NSString *message = lastError.localizedDescription ?: @"all destinations unavailable";
        if (![wpRelayLastWriteError isEqualToString:message]) {
            NSLog(@"CarPlay26 wallpaper relay write failed for all destinations: %@", message);
            wpRelayLastWriteError = message;
        }
    }
}

static void CP26WallpaperRelayReceived(__unused CFNotificationCenterRef center,
    __unused void *observer, CFStringRef name, __unused const void *object,
    __unused CFDictionaryRef userInfo) {
    NSString *event = [(__bridge NSString *)name copy];
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *source = [event hasSuffix:@"CarPlayWallpaper"] ? @"CarPlayWallpaper" : @"CarPlaySettings";
        if (!wpRelayReports) wpRelayReports = [NSMutableDictionary dictionary];
        if (!wpRelayStatuses) wpRelayStatuses = [NSMutableDictionary dictionary];
        wpRelaySignals++;
        NSString *key = [@"WallpaperProbeRelay_" stringByAppendingString:source];
        CFPreferencesAppSynchronize(CFSTR("com.tillman109.carplay26"));
        id raw = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key,
            CFSTR("com.tillman109.carplay26")));
        NSString *status = [NSString stringWithFormat:@"Darwin signal received at %@", NSDate.date];
        if ([raw isKindOfClass:NSDictionary.class] &&
            [raw[@"process"] isKindOfClass:NSString.class] &&
            [raw[@"process"] isEqualToString:source] &&
            [raw[@"time"] isKindOfClass:NSNumber.class] &&
            [raw[@"content"] isKindOfClass:NSString.class] &&
            fabs([raw[@"time"] doubleValue] - NSDate.date.timeIntervalSince1970) < 120) {
            wpRelayReports[source] = raw[@"content"];
            status = [status stringByAppendingFormat:@"; preference payload read, snapshots=%@",
                raw[@"snapshotCount"] ?: @"?"];
        } else {
            status = [status stringByAppendingString:@"; shared preference payload unavailable or stale"];
        }
        wpRelayStatuses[source] = status;
        CP26WriteWallpaperRelay();
    });
}

static void CP26RequestWallpaperReports(void) {
    // Runs a bounded number of times only in diagnostic mode; no display hooks
    // or background UI refresh frequency are changed.
    if (!wpRelayProbeEnabled) return;
    wpRelayRequests++;
    CP26WriteWallpaperRelay();
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.tillman109.carplay26.wallpaper.request"), NULL, NULL, TRUE);
}

%ctor {
    @autoreleasepool {
        if (![NSProcessInfo.processInfo.processName isEqualToString:@"CarPlay"]) return;
        restartListenerStarted = NSDate.date.timeIntervalSince1970;
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
            &restartObserver, CP26RestartRequested, CFSTR("com.tillman109.carplay26.restart"),
            NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
            &wpRelayObserver, CP26WallpaperRelayReceived,
            CFSTR("com.tillman109.carplay26.wallpaper.CarPlayWallpaper"),
            NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
            &wpRelayObserver, CP26WallpaperRelayReceived,
            CFSTR("com.tillman109.carplay26.wallpaper.CarPlaySettings"),
            NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        wpRelayStarted = NSDate.date.timeIntervalSince1970;
        CFPreferencesAppSynchronize(CFSTR("com.tillman109.carplay26"));
        wpRelayProbeEnabled = CP26Bool(@"InspectWallpaperPicker");
        wpRelayReports = [NSMutableDictionary dictionary];
        wpRelayStatuses = [NSMutableDictionary dictionary];
        // Self-test is unconditional, so even complete IPC failure leaves an
        // explicit status report, unlike v0.2.23.
        CP26WriteWallpaperRelay();
        // Repeat the self-test on the main run loop after launch, regardless
        // of the preference state.  The original constructor write may occur
        // before the process-owned cache directory is ready to use.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC),
                       dispatch_get_main_queue(), ^{ CP26WriteWallpaperRelay(); });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 12 * NSEC_PER_SEC),
                       dispatch_get_main_queue(), ^{ CP26WriteWallpaperRelay(); });
        if (wpRelayProbeEnabled) {
            // Reissue requests after the separately launched wallpaper apps
            // have time to start. This is a bounded diagnostic, not polling.
            for (NSUInteger delay = 5; delay <= 80; delay += 15) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                    (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    CP26RequestWallpaperReports();
                });
            }
        }
        // Keep both listeners available even when appearance is disabled.
        CFPreferencesAppSynchronize(CFSTR("com.tillman109.carplay26"));
        if (!CP26Bool(@"Enabled")) return;
        mode = [CP26Mode() copy];
        dockEnabled = CP26Bool(@"GlassDock");
        dockGlassEnabled = CP26Bool(@"GlassDockAppearance");
        dockLiquidStyle = CP26Bool(@"DockLiquidStyle");
        labelsEnabled = CP26Bool(@"GlassLabels");
        cardsEnabled = CP26Bool(@"GlassCards");
        iconsEnabled = CP26Bool(@"GlassIcons");
        controlsEnabled = CP26Bool(@"GlassControls");
        diagnosticsEnabled = CP26Bool(@"Diagnostics");
        dockShortcutProbeEnabled = CP26Bool(@"InspectDockShortcuts");
        // The compact shell dock uses the native third slot, keeping one
        // target for both the visible app and its launch action.
        pinnedDockBundle=[CP26PinnedBundle() copy];
        if (pinnedDockBundle.length && CP26PinAPIsAvailable()) {
            pinOtherButtons = [NSHashTable weakObjectsHashTable];
            %init(DockPinning);
        }
        else if (pinnedDockBundle.length) { pinLastResult = @"required native methods unavailable; left stock"; }
        if (!labelsEnabled && !cardsEnabled && !iconsEnabled && !controlsEnabled && !dockGlassEnabled && !diagnosticsEnabled && !dockShortcutProbeEnabled) return;
        if (NSClassFromString(@"DBIconView")) { %init(GridLifecycle); }
        if ((cardsEnabled || controlsEnabled) && NSClassFromString(@"DBWidgetView")) { %init(DashboardLifecycle); }
        if (controlsEnabled && NSClassFromString(@"DBNowPlayingFocusHighlightButton")) { %init(MediaLifecycle); }
        if (dockGlassEnabled) { %init(DockBackingColorGuard); }
        if (dockGlassEnabled && NSClassFromString(@"DBRootStatusBarViewController")) { %init(DockLifecycle); }
        if (dockGlassEnabled && NSClassFromString(@"DBStatusBarWindow")) { %init(DockWindowLifecycle); }
        if (dockGlassEnabled && NSClassFromString(@"_UIStatusBarForegroundView")) { %init(DockStatusLayout); }
        if (dockGlassEnabled && NSClassFromString(@"DBIconScrollView")) { %init(DockScrollLifecycle); }
        dispatch_async(dispatch_get_main_queue(), ^{
            dockOverlays = [NSMapTable weakToStrongObjectsMapTable];
            dockLiquidSheens = [NSMapTable weakToStrongObjectsMapTable];
            dockLiquidRims = [NSMapTable weakToStrongObjectsMapTable];
            dockLiquidInnerShades = [NSMapTable weakToStrongObjectsMapTable];
            dockSurfaces = [NSMapTable weakToStrongObjectsMapTable];
            dockMasks = [NSMapTable weakToStrongObjectsMapTable];
            dockBackings = [NSMapTable weakToStrongObjectsMapTable];
            dockProtectedLayers = [NSHashTable weakObjectsHashTable];
            overlays = [NSMapTable weakToStrongObjectsMapTable];
            labelOverlays = [NSMapTable strongToStrongObjectsMapTable];
            adaptiveLabelMasks = [NSMapTable weakToStrongObjectsMapTable];
            report = [NSMutableString stringWithFormat:@"CarPlay26 0.2.45 | CarPlay shell | PID=%d | started %@ | native dashboard material tint, sandbox-safe reports\n",getpid(),NSDate.date];
            // Low-frequency probe: the setter guards target registered backings only; no frame-rate polling.
            // Updates within about two seconds of a vehicle appearance change.
            refreshTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
            dispatch_source_set_timer(refreshTimer,dispatch_time(DISPATCH_TIME_NOW, 2*NSEC_PER_SEC),2*NSEC_PER_SEC, 250*NSEC_PER_MSEC);
            dispatch_source_set_event_handler(refreshTimer, ^{ Refresh(); });
            dispatch_resume(refreshTimer);
            Refresh();
        });
    }
}
