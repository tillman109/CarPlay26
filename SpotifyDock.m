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
@property(nonatomic) CGRect surface;
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
    s.stack=AppStack(root);
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
    for (UIView *v in s.applied.keyEnumerator.allObjects) if (![s.touched containsObject:v]) RestoreMove(s,v);
}
UIView *CP26DockHit(UIWindow *w, CGPoint p, UIEvent *event, UIView *native) {
    CP26DockState *s=objc_getAssociatedObject(w,&stateKey);
    if (!s || w.hidden || !w.userInteractionEnabled) return native;
    if (!CGRectContainsPoint(s.surface,p)) return native;
    for (UIView *v in s.stack.arrangedSubviews) {
        UIView *hit=CP26HitVisibleControl(v,w,p,event);
        if (hit) return hit;
    }
    if (s.stack && [native isDescendantOfView:s.stack]) return nil;
    return native;
}
void CP26DockReport(UIWindow *w, NSMutableString *out) {
    CP26DockState *s=objc_getAssociatedObject(w,&stateKey);
    if (!s) return;
    [out appendFormat:@"COMPACT_DOCK surface=%@ hiddenSettings=%lu\n",NSStringFromCGRect(s.surface),
        (unsigned long)s.hiddenSettings.count];
    for (UIView *v in s.stack.arrangedSubviews) if (!v.hidden) CP26ReportHit(out,@"dock app",v);
}
