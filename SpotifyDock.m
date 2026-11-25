#import "SpotifyReference.h"
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>

@protocol CP26DockApp <NSObject>
- (NSString *)bundleIdentifier;
@end

@interface CP26DockState : NSObject
@property(nonatomic,strong) NSMapTable<UIView *,NSValue *> *applied;
@property(nonatomic,strong) NSHashTable<UIView *> *touched;
@property(nonatomic,strong) NSMapTable<UIView *,NSNumber *> *hiddenSettings;
@property(nonatomic,weak) UIStackView *stack;
@property(nonatomic,weak) UIControl *home;
@property(nonatomic) CGRect surface;
@end
@implementation CP26DockState
@end
static char stateKey;

static void Move(CP26DockState *s, UIView *v, UIView *root, CGPoint target, CGFloat scale) {
    if (!v.superview) return;
    NSValue *prior=[s.applied objectForKey:v];
    // A transition may have its own transform in flight.
    if (!CGAffineTransformIsIdentity(v.transform) && (!prior ||
        !CGAffineTransformEqualToTransform(v.transform,prior.CGAffineTransformValue))) return;
    CGPoint inParent=[v.superview convertPoint:target fromView:root];
    CGAffineTransform t=CGAffineTransformMake(scale,0,0,scale,inParent.x-v.center.x,inParent.y-v.center.y);
    if (!CGAffineTransformEqualToTransform(v.transform,t)) v.transform=t;
    [s.applied setObject:[NSValue valueWithCGAffineTransform:t] forKey:v]; [s.touched addObject:v];
}
static void RestoreMove(CP26DockState *s, UIView *v) {
    NSValue *prior=[s.applied objectForKey:v];
    if (prior && CGAffineTransformEqualToTransform(v.transform,prior.CGAffineTransformValue)) v.transform=CGAffineTransformIdentity;
    [s.applied removeObjectForKey:v];
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
static void StatusItems(CP26DockState *s, UIView *v, UIView *root, CGFloat cy, CGFloat u, NSUInteger depth) {
    if (depth>6) return;
    NSString *name=NSStringFromClass(v.class);
    if ([name isEqualToString:@"DBStatusBarHomeButton"]) {
        s.home=(UIControl *)v; Move(s,v,root,CGPointMake(19.5*u,cy),.78*u); return;
    }
    if ([name isEqualToString:@"_UIStatusBarForegroundView"]) {
        for (UIView *part in v.subviews) {
            CGPoint base=[part.superview convertPoint:part.center toView:root];
            NSString *type=NSStringFromClass(part.class);
            if ([type isEqualToString:@"_UIStatusBarStringView"] && base.x<root.bounds.size.width*.4) {
                Move(s,part,root,CGPointMake(54.5*u,cy),.83*u);
            } else if (base.x>root.bounds.size.width*.66 && ([type hasPrefix:@"_UIStatusBar"] || [type isEqualToString:@"_UIBatteryView"])) {
                CGFloat right=root.bounds.size.width-8*u;
                Move(s,part,root,CGPointMake(right+(base.x-(root.bounds.size.width-10))*.78*u,cy),.78*u);
            }
        }
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
        s=[CP26DockState new]; s.applied=[NSMapTable weakToStrongObjectsMapTable]; s.touched=[NSHashTable weakObjectsHashTable];
        s.hiddenSettings=[NSMapTable weakToStrongObjectsMapTable];
        objc_setAssociatedObject(window,&stateKey,s,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [s.touched removeAllObjects];
    CGFloat u=MIN(root.bounds.size.width/400,root.bounds.size.height/45), cy=CGRectGetMidY(surface);
    s.surface=[root convertRect:surface toView:window];
    s.stack=AppStack(root); s.home=nil;
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
        Move(s,group,root,CGPointMake(CGRectGetMidX(root.bounds),cy),.765*u);
    StatusItems(s,root,root,cy,u,0);
    for (UIView *v in s.applied.keyEnumerator.allObjects) if (![s.touched containsObject:v]) RestoreMove(s,v);
}
UIView *CP26DockHit(UIWindow *w, CGPoint p, UIEvent *event, UIView *native) {
    CP26DockState *s=objc_getAssociatedObject(w,&stateKey);
    if (!s || w.hidden || !w.userInteractionEnabled) return native;
    if (!CGRectContainsPoint(s.surface,p)) return nil;
    // Preserve native overlays and the simulator's independent expand control.
    for (UIView *v=native; v && v!=w; v=v.superview)
        if ([v isKindOfClass:UIControl.class] && v!=s.home && (!s.stack || ![v isDescendantOfView:s.stack])) return native;
    for (UIView *v in s.stack.arrangedSubviews) {
        UIView *hit=CP26HitVisibleControl(v,w,p,event);
        if (hit) return hit;
    }
    UIView *home=CP26HitVisibleControl(s.home,w,p,event);
    if (home) return home;
    if (native && ((s.home && [native isDescendantOfView:s.home]) ||
        (s.stack && [native isDescendantOfView:s.stack]))) return nil;
    return native;
}
void CP26DockReport(UIWindow *w, NSMutableString *out) {
    CP26DockState *s=objc_getAssociatedObject(w,&stateKey);
    if (!s) return;
    [out appendFormat:@"COMPACT_DOCK surface=%@ hiddenSettings=%lu\n",NSStringFromCGRect(s.surface),
        (unsigned long)s.hiddenSettings.count];
    CP26ReportHit(out,@"dock home",s.home);
    for (UIView *v in s.stack.arrangedSubviews) if (!v.hidden) CP26ReportHit(out,@"dock app",v);
}
