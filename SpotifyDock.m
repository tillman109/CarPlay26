#import "SpotifyReference.h"
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>

// Observed on the user's 16.4.1 dock, including the native button action and
// CarPlaySettings bundle. Session visibility is checked before adding a slot.
@protocol CP26DockAPI <NSObject>
@optional
- (id)iconProvider;
- (id)appHistory;
- (BOOL)isDockEnabled;
- (id)appDockViewControllerDelegate;
- (void)appDockViewController:(id)owner didSelectBundleID:(NSString *)identifier;
- (BOOL)applicationVisibleInCarPlay:(NSString *)identifier withIconProvider:(id)provider;
- (BOOL)isBundleIdentifierValidForDock:(NSString *)identifier;
- (instancetype)initWithIconProvider:(id)provider;
- (void)setBundleIdentifier:(NSString *)identifier animated:(BOOL)animated;
- (NSString *)bundleIdentifier;
- (void)_dockButtonPressed:(UIControl *)sender;
- (UIStackView *)dockItemStackView;
- (UIControl *)otherAppButton;
@end

@interface CP26DockState : NSObject
@property(nonatomic,strong) NSMapTable<UIView *,NSValue *> *applied;
@property(nonatomic,strong) NSHashTable<UIView *> *touched;
@property(nonatomic,strong) UIControl *fourth, *phone;
@property(nonatomic,weak) UIControl *covered;
@property(nonatomic) CGFloat previousAlpha;
@property(nonatomic,weak) id<CP26DockAPI> owner;
- (void)openSlot:(UIControl *)sender;
@end
@implementation CP26DockState
- (void)openSlot:(UIControl *)sender {
    id<CP26DockAPI> owner=self.owner;
    if (!sender.window || !owner || (sender!=self.fourth && sender!=self.phone) ||
        ([owner respondsToSelector:@selector(isDockEnabled)] && !owner.isDockEnabled)) return;
    NSString *identifier=[(id<CP26DockAPI>)sender bundleIdentifier];
    if (!identifier.length) return;
    id<CP26DockAPI> delegate=[owner respondsToSelector:@selector(appDockViewControllerDelegate)] ?
        owner.appDockViewControllerDelegate : nil;
    if ([delegate respondsToSelector:@selector(appDockViewController:didSelectBundleID:)])
        [delegate appDockViewController:owner didSelectBundleID:identifier];
    else if ([owner respondsToSelector:@selector(_dockButtonPressed:)]) [owner _dockButtonPressed:sender];
}
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
static void RevealOther(CP26DockState *s) {
    if (s.covered && s.covered.alpha==0) s.covered.alpha=s.previousAlpha;
    s.covered=nil;
}
static void RemoveSlots(CP26DockState *s) {
    RevealOther(s); [s.fourth removeFromSuperview]; [s.phone removeFromSuperview];
    s.fourth=nil; s.phone=nil;
}
static UIControl *NewSlot(CP26DockState *s, NSString *identifier, NSString *label) {
    id<CP26DockAPI> owner=s.owner;
    if (![owner respondsToSelector:@selector(iconProvider)] || ![owner respondsToSelector:@selector(appHistory)] ||
        ![owner respondsToSelector:@selector(_dockButtonPressed:)]) return nil;
    id provider=owner.iconProvider; id<CP26DockAPI> history=owner.appHistory;
    if (!provider || !history) return nil;
    BOOL allowed=NO;
    if ([history respondsToSelector:@selector(applicationVisibleInCarPlay:withIconProvider:)])
        allowed=[history applicationVisibleInCarPlay:identifier withIconProvider:provider];
    else if ([history respondsToSelector:@selector(isBundleIdentifierValidForDock:)])
        allowed=[history isBundleIdentifierValidForDock:identifier];
    if (!allowed) return nil;
    Class cls=NSClassFromString(@"DBAppDockButton");
    if (![cls instancesRespondToSelector:@selector(initWithIconProvider:)] ||
        ![cls instancesRespondToSelector:@selector(setBundleIdentifier:animated:)]) return nil;
    UIControl *slot=(UIControl *)[(id<CP26DockAPI>)[cls alloc] initWithIconProvider:provider];
    if (![slot isKindOfClass:UIControl.class]) return nil;
    [(id<CP26DockAPI>)slot setBundleIdentifier:identifier animated:NO];
    [slot addTarget:s action:@selector(openSlot:) forControlEvents:UIControlEventTouchUpInside];
    slot.accessibilityLabel=label;
    return slot;
}
static void PlaceSlot(UIControl *slot, UIView *root, CGPoint center, CGFloat scale) {
    if (!slot) return;
    if (slot.superview!=root) [root addSubview:slot];
    CGRect bounds=CGRectMake(0,0,37,45);
    if (!CGRectEqualToRect(slot.bounds,bounds)) slot.bounds=bounds;
    if (!CGPointEqualToPoint(slot.center,center)) slot.center=center;
    CGAffineTransform t=CGAffineTransformMakeScale(scale,scale);
    if (!CGAffineTransformEqualToTransform(slot.transform,t)) slot.transform=t;
}
static id<CP26DockAPI> DockOwner(UIView *root) {
    // The two siblings inserted by this tweak are never used for discovery.
    for (UIView *container in root.subviews) for (UIView *view in container.subviews) {
        if (![view isKindOfClass:UIStackView.class]) continue;
        for (UIControl *button in ((UIStackView *)view).arrangedSubviews) {
            if (![button isKindOfClass:NSClassFromString(@"DBAppDockButton")]) continue;
            for (id target in button.allTargets) if ([target isKindOfClass:NSClassFromString(@"DBAppDockViewController")]) return target;
        }
    }
    return nil;
}
static void StatusItems(CP26DockState *s, UIView *v, UIView *root, CGFloat cy, CGFloat u, NSUInteger depth) {
    if (depth>6 || v==s.fourth || v==s.phone) return;
    NSString *name=NSStringFromClass(v.class);
    if ([name isEqualToString:@"DBStatusBarHomeButton"]) {
        Move(s,v,root,CGPointMake(19.5*u,cy),.78*u); return;
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
        RemoveSlots(s);
        for (UIView *v in s.applied.keyEnumerator.allObjects) RestoreMove(s,v);
        objc_setAssociatedObject(window,&stateKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC); return;
    }
    if (!s) {
        s=[CP26DockState new]; s.applied=[NSMapTable weakToStrongObjectsMapTable]; s.touched=[NSHashTable weakObjectsHashTable];
        objc_setAssociatedObject(window,&stateKey,s,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [s.touched removeAllObjects];
    CGFloat u=root.bounds.size.width/400, cy=CGRectGetMidY(surface);
    id<CP26DockAPI> owner=DockOwner(root);
    if (s.owner!=owner) { RemoveSlots(s); s.owner=owner; }
    UIStackView *stack=[owner respondsToSelector:@selector(dockItemStackView)] ? owner.dockItemStackView : nil;
    UIView *group=stack.superview;
    if (stack.arrangedSubviews.count==3 && group.superview==root && group.bounds.size.width>=75) {
        NSString *settings=@"com.apple.CarPlaySettings", *phone=@"com.apple.mobilephone";
        UIControl *other=[owner respondsToSelector:@selector(otherAppButton)] ? owner.otherAppButton : nil;
        NSString *current=[other respondsToSelector:@selector(bundleIdentifier)] ? [(id<CP26DockAPI>)other bundleIdentifier] : nil;
        BOOL pinned=CFPreferencesGetAppBooleanValue(CFSTR("PinDockApp"),CFSTR("com.tillman109.carplay26"),NULL);
        BOOL needsPhone=!pinned && current && ![current isEqualToString:phone];
        if (needsPhone && !s.phone) s.phone=NewSlot(s,phone,@"Phone");
        if (!needsPhone) { RevealOther(s); [s.phone removeFromSuperview]; s.phone=nil; }
        BOOL needsSettings=s.phone || ![current isEqualToString:settings];
        if (needsSettings && !s.fourth) s.fourth=NewSlot(s,settings,@"Settings");
        if (!needsSettings) { [s.fourth removeFromSuperview]; s.fourth=nil; }
        CGFloat cx=(s.fourth ? 186.2 : 200)*u, scale=.765*u;
        Move(s,group,root,CGPointMake(cx,cy),scale);
        if (s.phone && other) {
            if (s.covered!=other) { RevealOther(s); s.covered=other; s.previousAlpha=other.alpha; }
            if (other.alpha!=0) other.alpha=0;
            PlaceSlot(s.phone,root,CGPointMake(cx+28.2*u,cy),scale);
        }
        PlaceSlot(s.fourth,root,CGPointMake(cx+56.4*u,cy),scale);
    } else {
        RemoveSlots(s);
        if (stack.arrangedSubviews.count==4 && group.superview==root)
            Move(s,group,root,CGPointMake(200*u,cy),.765*u);
    }
    StatusItems(s,root,root,cy,u,0);
    for (UIView *v in s.applied.keyEnumerator.allObjects) if (![s.touched containsObject:v]) RestoreMove(s,v);
}
void CP26DockReport(UIWindow *window, NSMutableString *out) {
    CP26DockState *s=objc_getAssociatedObject(window,&stateKey);
    if (s) [out appendFormat:@"SPOTIFY_DOCK nativeGroup=%d settingsShortcut=%d phoneShortcut=%d adjustedStatusViews=%lu\n",
        s.owner!=nil,s.fourth.superview!=nil,s.phone.superview!=nil,(unsigned long)s.applied.count];
}
