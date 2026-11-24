#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#include <math.h>

// CarPlay26 v0.2.61: very light finish on verified lower dashboard cards.
// Uses GlassCards and master Enabled preferences already present in CarPlay26.
// Never restyles Maps, the dashboard widgets' content, or touch controls.
static const void *CP26DashboardPolishLayerKey = &CP26DashboardPolishLayerKey;

static BOOL CP26DashboardSameClass(UIView *v, NSString *className) {
    return v && [NSStringFromClass(v.class) isEqualToString:className];
}

static BOOL CP26DashboardValidCard(UIView *widget) {
    if (!CP26DashboardSameClass(widget,@"DBWidgetView")) return NO;
    UIWindow *window = widget.window;
    if (!window || ![window.windowScene.session.role
        isEqualToString:@"UIWindowSceneSessionRoleCarPlay"]) return NO;
    UIView *page = nil;
    for (UIView *ancestor = widget; ancestor && ancestor != window;
         ancestor = ancestor.superview) {
        if (CP26DashboardSameClass(ancestor,@"_SBRootFolderLayoutWrapperView") &&
            CP26DashboardSameClass(ancestor.superview,@"DBIconScrollView")) {
            page = ancestor;
            break;
        }
    }
    if (!page || CGRectIsEmpty(page.bounds)) return NO;
    CGRect r = [widget convertRect:widget.bounds toView:page];
    CGFloat width = window.bounds.size.width, height = window.bounds.size.height;
    return !CGRectIsEmpty(r) && !CGRectIsInfinite(r) &&
        CGRectContainsRect(CGRectInset(page.bounds,-2,-2),r) &&
        r.size.width >= width * .30 && r.size.width <= width * .60 &&
        r.size.height >= height * .25 && r.size.height <= height * .60 &&
        CGRectGetMinY(r) >= CGRectGetMinY(page.bounds) + height * .35;
}

static void CP26DashboardPolish(UIView *widget) {
    if (![NSThread isMainThread] || !CP26DashboardValidCard(widget)) return;
    for (UIView *platter in widget.subviews) {
        if (!CP26DashboardSameClass(platter,@"DashBoard.DBDashboardPlatterView"))
            continue;
        for (UIView *material in platter.subviews) {
            if (!CP26DashboardSameClass(material,@"MTMaterialView") ||
                CGRectIsEmpty(material.bounds)) continue;
            CAGradientLayer *sheen = objc_getAssociatedObject(material,
                CP26DashboardPolishLayerKey);
            if (!sheen) {
                sheen = [CAGradientLayer layer];
                sheen.name = @"CarPlay26.DashboardSoftGlassFinish";
                sheen.masksToBounds = YES;
                objc_setAssociatedObject(material,CP26DashboardPolishLayerKey,
                    sheen,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            if (sheen.superlayer != material.layer) {
                [sheen removeFromSuperlayer];
                [material.layer addSublayer:sheen];
            }
            sheen.frame = material.bounds;  // exact native material, no extra inset
            CGFloat radius = material.layer.cornerRadius > 0 ?
                material.layer.cornerRadius : platter.layer.cornerRadius;
            sheen.cornerRadius = MAX(0.0,radius);
            BOOL dark = material.traitCollection.userInterfaceStyle ==
                UIUserInterfaceStyleDark;
            UIColor *light = [UIColor colorWithWhite:1
                alpha:dark ? .12 : .27];
            UIColor *middle = [UIColor colorWithWhite:1
                alpha:dark ? .045 : .09];
            UIColor *bottom = [UIColor colorWithWhite:1 alpha:0.0];
            sheen.colors = @[(id)light.CGColor,(id)middle.CGColor,(id)bottom.CGColor];
            sheen.locations = @[@0.0,@0.35,@1.0];
            sheen.startPoint = CGPointMake(.04,.0);
            sheen.endPoint = CGPointMake(.80,1.0);
            // Native card boundary only; no second framed widget or content cover.
            sheen.borderColor = [UIColor colorWithWhite:1
                alpha:dark ? .17 : .28].CGColor;
            sheen.borderWidth = .35;
            [CATransaction commit];
        }
    }
}

%group CP26DashboardGlassFinishing
%hook DBWidgetView
- (void)layoutSubviews {
    %orig;
    CP26DashboardPolish((UIView *)self);
}
- (void)didMoveToWindow {
    %orig;
    CP26DashboardPolish((UIView *)self);
}
%end
%end

%ctor {
    @autoreleasepool {
        if (![NSProcessInfo.processInfo.processName isEqualToString:@"CarPlay"])
            return;
        CFPreferencesAppSynchronize(CFSTR("com.tillman109.carplay26"));
        Boolean enabledValid = false, cardsValid = false;
        BOOL enabled = CFPreferencesGetAppBooleanValue(CFSTR("Enabled"),
            CFSTR("com.tillman109.carplay26"), &enabledValid);
        BOOL cards = CFPreferencesGetAppBooleanValue(CFSTR("GlassCards"),
            CFSTR("com.tillman109.carplay26"), &cardsValid);
        if (enabledValid && enabled && cardsValid && cards &&
            NSClassFromString(@"DBWidgetView"))
            %init(CP26DashboardGlassFinishing);
    }
}
