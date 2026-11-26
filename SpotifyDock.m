#import "SpotifyReference.h"
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>

@protocol CP26DockApp <NSObject>
- (NSString *)bundleIdentifier;
@end

@interface CP26DockState : NSObject
@property(nonatomic,strong) NSMapTable<UIView *,NSValue *> *applied, *original;
@property(nonatomic,strong) NSHashTable<UIView *> *touched;
@property(nonatomic,strong) NSMapTable<UIView *,NSNumber *> *hiddenSettings;
@property(nonatomic,weak) UIStackView *stack;
@property(nonatomic,weak) UIControl *home;
@property(nonatomic) CGRect surface;
@property(nonatomic,copy) NSArray<UIView *> *status;
@end
@implementation CP26DockState
@end
static char stateKey;

static CGAffineTransform OriginalTransform(CP26DockState *s, UIView *v) {
    NSValue *last=[s.applied objectForKey:v], *base=[s.original objectForKey:v];
    if (last && base && CGAffineTransformEqualToTransform(v.transform,last.CGAffineTransformValue))
        return base.CGAffineTransformValue;
    [s.original setObject:[NSValue valueWithCGAffineTransform:v.transform] forKey:v];
    return v.transform;
}
static void Move(CP26DockState *s, UIView *v, UIView *root, CGPoint target, CGFloat scale) {
    if (!v.superview) return;
    CGAffineTransform base=OriginalTransform(s,v);
    CGAffineTransform t=CGAffineTransformMake(base.a*scale,base.b*scale,base.c*scale,base.d*scale,0,0);
    CGPoint point=[v.superview convertPoint:target fromView:root];
    CGPoint anchor=v.layer.anchorPoint, position=v.layer.position;
    CGPoint offset=CGPointApplyAffineTransform(CGPointMake((.5-anchor.x)*v.bounds.size.width,
                                                           (.5-anchor.y)*v.bounds.size.height),t);
    t.tx=point.x-position.x-offset.x; t.ty=point.y-position.y-offset.y;
    if (!CGAffineTransformEqualToTransform(v.transform,t)) v.transform=t;
    [s.applied setObject:[NSValue valueWithCGAffineTransform:t] forKey:v]; [s.touched addObject:v];
}
static void RestoreMove(CP26DockState *s, UIView *v) {
    NSValue *last=[s.applied objectForKey:v], *base=[s.original objectForKey:v];
    if (last && base && CGAffineTransformEqualToTransform(v.transform,last.CGAffineTransformValue))
        v.transform=base.CGAffineTransformValue;
    [s.applied removeObjectForKey:v]; [s.original removeObjectForKey:v];
}
static UIStackView *AppStack(UIView *root) {
    Class button=NSClassFromString(@"DBAppDockButton");
    for (UIView *container in root.subviews) for (UIView *v in container.subviews) {
        if (![v isKindOfClass:UIStackView.class]) continue;
        UIStackView *stack=(UIStackView *)v;
        if (stack.arrangedSubviews.count && [stack.arrangedSubviews.firstObject isKindOfClass:button]) return stack;
    }
    return nil;
}
static void RestoreVisibility(CP26DockState *s, UIView *v) {
    NSNumber *old=[s.hiddenSettings objectForKey:v];
    if (old) {
        if (v.hidden) v.hidden=old.boolValue;
        [s.hiddenSettings removeObjectForKey:v];
    }
}
// Time and network type both use _UIStatusBarStringView. Their original
// sides differ between left- and right-hand-drive head units.
static BOOL IsTime(NSString *text) {
    NSCharacterSet *digits=NSCharacterSet.decimalDigitCharacterSet;
    NSMutableArray<NSString *> *numbers=[NSMutableArray array];
    for (NSString *part in [text componentsSeparatedByCharactersInSet:digits.invertedSet])
        if (part.length) [numbers addObject:part];
    if (numbers.count!=2 && numbers.count!=3) return NO;
    return numbers[0].length<=2 && numbers[0].integerValue<24 &&
        numbers[1].length==2 && numbers[1].integerValue<60;
}
typedef NS_ENUM(NSInteger,DockItemRole) { CP26DockContainer, CP26DockClock, CP26DockBattery, CP26DockSignal, CP26DockNetwork, CP26DockWiFi, CP26DockExtra };
static DockItemRole StatusRole(UIView *v) {
    NSString *name=NSStringFromClass(v.class);
    if ([name containsString:@"Battery"]) return CP26DockBattery;
    if ([name containsString:@"CellularSignal"]) return CP26DockSignal;
    if ([name containsString:@"Wifi"] || [name containsString:@"WiFi"]) return CP26DockWiFi;
    if ([name containsString:@"Clock"] || [name containsString:@"TimeItem"]) return CP26DockClock;
    if ([name containsString:@"CellularNetwork"] || [name containsString:@"DataNetwork"]) return CP26DockNetwork;
    if ([v isKindOfClass:UILabel.class] || [name containsString:@"StringView"]) {
        UILabel *label=[v isKindOfClass:UILabel.class] ? (UILabel *)v : nil;
        NSString *value=label.text ?: label.attributedText.string ?: v.accessibilityLabel;
        if (IsTime(value)) return CP26DockClock;
        if (value.length) return CP26DockNetwork;
    }
    return [name hasPrefix:@"_UIStatusBar"] && ([name containsString:@"ImageView"] ||
        [name containsString:@"Indicator"]) ? CP26DockExtra : CP26DockContainer;
}
static void GatherStatus(UIView *v, NSMutableArray<UIView *> *items, NSUInteger depth) {
    if (v.hidden || v.alpha<=.01 || depth>5) return;
    if (StatusRole(v)!=CP26DockContainer) {
        if (!CGRectIsEmpty(v.bounds)) [items addObject:v];
        return;
    }
    for (UIView *child in v.subviews) GatherStatus(child,items,depth+1);
}
static CGFloat NaturalWidth(CP26DockState *s, UIView *v, UIView *root) {
    CGRect local=CGRectApplyAffineTransform(v.bounds,OriginalTransform(s,v));
    return CGRectGetWidth([v.superview convertRect:local toView:root]);
}
static void ArrangeStatus(CP26DockState *s, UIView *foreground, UIView *root, CGFloat cy, CGFloat u) {
    NSMutableArray<UIView *> *items=[NSMutableArray array];
    for (UIView *child in foreground.subviews) GatherStatus(child,items,0);
    [items sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(UIView *a,UIView *b) {
        NSInteger x=StatusRole(a), y=StatusRole(b);
        return x<y ? NSOrderedAscending : x>y ? NSOrderedDescending : NSOrderedSame;
    }];
    NSMutableArray<UIView *> *cluster=[NSMutableArray array];
    CGFloat sum=0;
    for (UIView *v in items) {
        if (StatusRole(v)==CP26DockClock) {
            CGFloat width=NaturalWidth(s,v,root)*u;
            Move(s,v,root,CGPointMake(CGRectGetMaxX(root.bounds)-55*u-width*.5,cy),u);
        } else { [cluster addObject:v]; sum+=NaturalWidth(s,v,root); }
    }
    CGFloat edge=CGRectGetMinX(root.bounds)+10*u, gap=3*u;
    CGFloat appsLeft=s.stack ? CGRectGetMinX([s.stack convertRect:s.stack.bounds toView:root]) : CGRectGetMidX(root.bounds);
    CGFloat scale=sum>0 ? MIN(u,MAX(0,appsLeft-edge-12*u-gap*MAX(0,(NSInteger)cluster.count-1))/sum) : u;
    for (UIView *v in cluster) {
        CGFloat width=NaturalWidth(s,v,root)*scale;
        Move(s,v,root,CGPointMake(edge+width*.5,cy),scale);
        edge+=width+gap;
    }
    s.status=items;
}
static void StatusItems(CP26DockState *s, UIView *v, UIView *root, CGFloat cy, CGFloat u, NSUInteger depth) {
    if (depth>8 || v.hidden || v.alpha<=.01) return;
    NSString *name=NSStringFromClass(v.class);
    if ([name isEqualToString:@"DBStatusBarHomeButton"]) {
        s.home=(UIControl *)v; Move(s,v,root,CGPointMake(CGRectGetMaxX(root.bounds)-26*u,cy),u); return;
    }
    if ([name isEqualToString:@"_UIStatusBarForegroundView"]) {
        ArrangeStatus(s,v,root,cy,u);
        return;
    }
    if ([v isKindOfClass:UIControl.class] || [v isKindOfClass:UIVisualEffectView.class] ||
        [v isKindOfClass:UIStackView.class]) return;
    for (UIView *child in v.subviews) StatusItems(s,child,root,cy,u,depth+1);
}
void CP26ReferenceDock(UIWindow *window, UIView *root, CGRect surface, BOOL enabled) {
    CP26DockState *s=objc_getAssociatedObject(window,&stateKey);
    if (!enabled || !root || CGRectIsEmpty(surface)) {
        if (!s) return;
        for (UIView *v in s.hiddenSettings.keyEnumerator.allObjects) RestoreVisibility(s,v);
        for (UIView *v in s.applied.keyEnumerator.allObjects) RestoreMove(s,v);
        objc_setAssociatedObject(window,&stateKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC); return;
    }
    if (!s) {
        s=[CP26DockState new]; s.applied=[NSMapTable weakToStrongObjectsMapTable];
        s.original=[NSMapTable weakToStrongObjectsMapTable]; s.touched=[NSHashTable weakObjectsHashTable];
        s.hiddenSettings=[NSMapTable weakToStrongObjectsMapTable];
        objc_setAssociatedObject(window,&stateKey,s,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [s.touched removeAllObjects];
    CGFloat u=MIN(root.bounds.size.width/400,root.bounds.size.height/45), cy=CGRectGetMidY(surface);
    s.surface=[root convertRect:surface toView:window];
    s.stack=AppStack(root); s.home=nil; s.status=nil;
    for (UIView *v in s.hiddenSettings.keyEnumerator.allObjects)
        if (![s.stack.arrangedSubviews containsObject:v]) RestoreVisibility(s,v);
    for (UIView *v in s.stack.arrangedSubviews) {
        if (![v respondsToSelector:@selector(bundleIdentifier)]) continue;
        NSString *identifier=[(id<CP26DockApp>)v bundleIdentifier];
        if ([identifier isEqualToString:@"com.apple.CarPlaySettings"]) {
            if (![s.hiddenSettings objectForKey:v]) [s.hiddenSettings setObject:@(v.hidden) forKey:v];
            if (!v.hidden) v.hidden=YES;
        } else RestoreVisibility(s,v);
    }
    UIView *group=s.stack.superview;
    if (group.superview==root && group.bounds.size.width>0)
        Move(s,group,root,CGPointMake(CGRectGetMidX(root.bounds),cy),u);
    StatusItems(s,root,root,cy,u,0);
    for (UIView *v in s.applied.keyEnumerator.allObjects) if (![s.touched containsObject:v]) RestoreMove(s,v);
}
UIView *CP26DockHit(UIWindow *w, CGPoint p, UIEvent *event, UIView *native) {
    CP26DockState *s=objc_getAssociatedObject(w,&stateKey);
    if (!s || w.hidden || !w.userInteractionEnabled) return native;
    if (!CGRectContainsPoint(s.surface,p)) return nil;
    UIView *home=CP26HitVisibleControl(s.home,w,p,event);
    if (home) return home;
    for (UIView *v in s.stack.arrangedSubviews) {
        UIView *hit=CP26HitVisibleControl(v,w,p,event);
        if (hit) return hit;
    }
    if (native && ((s.home && [native isDescendantOfView:s.home]) ||
        (s.stack && [native isDescendantOfView:s.stack]))) return nil;
    return native;
}
void CP26DockReport(UIWindow *w, NSMutableString *out) {
    CP26DockState *s=objc_getAssociatedObject(w,&stateKey);
    if (!s) return;
    [out appendFormat:@"COMPACT_DOCK surface=%@ hiddenSettings=%lu\n",NSStringFromCGRect(s.surface),
        (unsigned long)s.hiddenSettings.count];
    for (UIView *v in s.status) [out appendFormat:@"DOCK role=%ld class=%@ frame=%@\n",
        (long)StatusRole(v),NSStringFromClass(v.class),NSStringFromCGRect([v convertRect:v.bounds toView:w])];
    CP26ReportHit(out,@"dock home",s.home);
    for (UIView *v in s.stack.arrangedSubviews) if (!v.hidden) CP26ReportHit(out,@"dock app",v);
}
