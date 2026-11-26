#import "SpotifyReference.h"
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>

// Actions belong to the template. Some system bar items dispatch through the
// responder chain, others install their action on a custom native control.
BOOL CP26ActivateBarItem(UIBarButtonItem *item, UIControl *control) {
    if (item.enabled && item.action &&
        [UIApplication.sharedApplication sendAction:item.action to:item.target from:item forEvent:nil]) return YES;
    if (!control || !control.enabled) return NO;
    UIControlEvents events=control.allControlEvents;
    UIControlEvents activation=(events & UIControlEventPrimaryActionTriggered) ?
        UIControlEventPrimaryActionTriggered : UIControlEventTouchUpInside;
    if (events & activation) { [control sendActionsForControlEvents:activation]; return YES; }
    return [control accessibilityActivate];
}

@interface CP26Header : NSObject
@property(nonatomic,weak) UIViewController *owner;
@property(nonatomic,weak) UINavigationBar *bar;
@property(nonatomic,strong) UIButton *back, *action;
@property(nonatomic,strong) UILabel *menuTitle;
@property(nonatomic,strong) UIView *backGlass, *actionGlass;
@property(nonatomic,weak) UIControl *nativeBack, *nativeAction;
@property(nonatomic,weak) UIBarButtonItem *left, *right;
@property(nonatomic,strong) NSMapTable<UIView *,NSNumber *> *suppressed;
@property(nonatomic,strong) UIColor *originalColor;
@property(nonatomic,weak) UIView *nativeActionStyled;
@property(nonatomic,strong) UIView *nativeActionGlass;
@property(nonatomic,strong) UIColor *nativeActionTint, *nativeActionTitleColor, *nativeActionBackground;
@property(nonatomic,strong) NSMapTable<UILabel *,UIColor *> *nativeActionLabelColors;
@property(nonatomic) BOOL nativeActionOpaque;
@property(nonatomic) BOOL originalOpaque, clearBar;
@property(nonatomic) BOOL player, applying;
@property(nonatomic,strong) CAShapeLayer *chevron;
@end
static char headerKey;
static NSHashTable<UINavigationBar *> *headerBars;

static BOOL IsFront(UIViewController *vc) {
    UIViewController *top=vc.navigationController.topViewController;
    if (!vc.viewIfLoaded.window || !top) return NO;
    for (UIViewController *p=vc; p; p=p.parentViewController) if (p==top) return YES;
    return NO;
}
@implementation CP26Header
- (void)goBack {
    if (!IsFront(self.owner)) return;
    if (CP26ActivateBarItem(self.left,self.nativeBack)) return;
    UINavigationController *nav=self.owner.navigationController;
    if (nav.viewControllers.count>1) [nav popViewControllerAnimated:YES];
    else if (nav.presentingViewController) [nav dismissViewControllerAnimated:YES completion:nil];
}
- (void)performRight {
    if (IsFront(self.owner)) CP26ActivateBarItem(self.right,self.nativeAction);
}
@end

static BOOL IsWave(UIView *v, NSUInteger depth) {
    if (!v || depth>5) return NO;
    if ([NSStringFromClass(v.class) containsString:@"NowPlayingButton"]) return YES;
    for (UIView *child in v.subviews) if (IsWave(child,depth+1)) return YES;
    return NO;
}
static UIControl *ActionIn(UIView *v) {
    if (!v) return nil;
    if ([v isKindOfClass:UIControl.class] && ((UIControl *)v).allControlEvents) return (UIControl *)v;
    for (UIView *child in v.subviews) {
        UIControl *hit=ActionIn(child);
        if (hit) return hit;
    }
    return [v isKindOfClass:UIControl.class] ? (UIControl *)v : nil;
}
static NSString *VisibleTitle(UIView *v) {
    if ([v isKindOfClass:UILabel.class]) return ((UILabel *)v).text;
    if ([v isKindOfClass:UIButton.class] && ((UIButton *)v).currentTitle.length) return ((UIButton *)v).currentTitle;
    for (UIView *child in v.subviews) {
        NSString *label=VisibleTitle(child);
        if (label.length) return label;
    }
    return nil;
}
static void FindBarParts(UIView *v, CP26Header *s, NSUInteger depth, UIView **left, UIView **right) {
    if (!v || depth>8 || v==s.back || v==s.action || v.hidden) return;
    NSString *name=NSStringFromClass(v.class);
    if ([name hasPrefix:@"CP26"] || [name hasPrefix:@"_UIBarBackground"]) return;
    if ([name containsString:@"BarButton"] || [name containsString:@"BackButton"] ||
        [name containsString:@"NowPlayingButton"] || [v isKindOfClass:UIControl.class]) {
        CGRect r=[v convertRect:v.bounds toView:s.bar];
        if (r.size.width>0 && r.size.width<s.bar.bounds.size.width*.65 && ActionIn(v)) {
            if (CGRectGetMidX(r)<s.bar.bounds.size.width*.28 && !*left) { *left=v; return; }
            if (CGRectGetMidX(r)>s.bar.bounds.size.width*.57 && !*right) { *right=v; return; }
        }
    }
    for (UIView *child in v.subviews) FindBarParts(child,s,depth+1,left,right);
}
static UILabel *TitleIn(UIView *v, CP26Header *s, NSString *title) {
    if (!v || !title.length || v==s.menuTitle || v==s.back || v==s.action || v.hidden ||
        [NSStringFromClass(v.class) hasPrefix:@"CP26"]) return nil;
    if ([v isKindOfClass:UILabel.class] && [((UILabel *)v).text isEqualToString:title]) {
        CGRect box=[v convertRect:v.bounds toView:s.bar];
        if (fabs(CGRectGetMidX(box)-CGRectGetMidX(s.bar.bounds))<s.bar.bounds.size.width*.22) return (UILabel *)v;
    }
    for (UIView *child in v.subviews) {
        UILabel *result=TitleIn(child,s,title);
        if (result) return result;
    }
    return nil;
}
static void Suppress(CP26Header *s, UIView *v, NSMutableSet *keep) {
    if (!v) return;
    [keep addObject:v];
    if (![s.suppressed objectForKey:v]) [s.suppressed setObject:@(v.alpha) forKey:v];
    if (v.alpha!=0) v.alpha=0;
}
static void RestoreUnused(CP26Header *s, NSSet *keep) {
    for (UIView *v in s.suppressed.keyEnumerator.allObjects) if (![keep containsObject:v]) {
        if (v.alpha==0) v.alpha=[s.suppressed objectForKey:v].doubleValue;
        [s.suppressed removeObjectForKey:v];
    }
}
static UILabel *QueueLabelIn(UIView *view, NSUInteger depth) {
    if (!view || depth>12 || view.hidden || view.alpha<=.01 || [NSStringFromClass(view.class) hasPrefix:@"CP26"]) return nil;
    if ([view isKindOfClass:UILabel.class]) {
        NSString *text=((UILabel *)view).text.lowercaseString;
        if ([text containsString:@"queue"] && [text containsString:@"jam"]) return (UILabel *)view;
    }
    if ([view isKindOfClass:UIButton.class]) {
        NSString *text=((UIButton *)view).currentTitle.lowercaseString;
        if ([text containsString:@"queue"] && [text containsString:@"jam"]) return ((UIButton *)view).titleLabel;
    }
    for (UIView *child in view.subviews) {
        UILabel *found=QueueLabelIn(child,depth+1);
        if (found) return found;
    }
    return nil;
}
static UIView *QueueContainer(UILabel *label, UIView *bar) {
    if (!label || !bar) return nil;
    UIView *branch=label;
    while (branch.superview && branch.superview!=bar) branch=branch.superview;
    return branch.superview==bar ? branch : nil;
}
static void RestoreNativeAction(CP26Header *s) {
    UIView *view=s.nativeActionStyled;
    if (view) {
        [s.nativeActionGlass removeFromSuperview];
        if (s.nativeActionTint) view.tintColor=s.nativeActionTint;
        view.backgroundColor=s.nativeActionBackground; view.opaque=s.nativeActionOpaque;
        if ([view isKindOfClass:UIButton.class] && s.nativeActionTitleColor)
            [(UIButton *)view setTitleColor:s.nativeActionTitleColor forState:UIControlStateNormal];
    }
    for (UILabel *label in s.nativeActionLabelColors.keyEnumerator.allObjects) {
        UIColor *color=[s.nativeActionLabelColors objectForKey:label];
        if (color) label.textColor=color;
    }
    s.nativeActionStyled=nil; s.nativeActionGlass=nil;
    s.nativeActionTint=nil; s.nativeActionTitleColor=nil; s.nativeActionBackground=nil;
    s.nativeActionLabelColors=nil;
}
static void StyleNativeAction(CP26Header *s, UIView *view, UILabel *label, CGFloat unit) {
    if (s.nativeActionStyled!=view) {
        RestoreNativeAction(s);
        s.nativeActionStyled=view; s.nativeActionTint=view.tintColor;
        s.nativeActionBackground=view.backgroundColor; s.nativeActionOpaque=view.opaque;
        if ([view isKindOfClass:UIButton.class])
            s.nativeActionTitleColor=[(UIButton *)view titleColorForState:UIControlStateNormal];
        s.nativeActionGlass=[UIView new]; s.nativeActionGlass.userInteractionEnabled=NO;
        s.nativeActionGlass.clipsToBounds=YES; s.nativeActionGlass.layer.cornerCurve=kCACornerCurveContinuous;
        s.nativeActionGlass.layer.borderColor=[UIColor colorWithWhite:1 alpha:.19].CGColor;
        s.nativeActionGlass.layer.borderWidth=.55;
        s.nativeActionGlass.backgroundColor=[UIColor colorWithWhite:1 alpha:.12];
        [view insertSubview:s.nativeActionGlass atIndex:0];
    }
    view.tintColor=UIColor.whiteColor; view.backgroundColor=UIColor.clearColor; view.opaque=NO;
    if ([view isKindOfClass:UIButton.class]) [(UIButton *)view setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    if (label) {
        if (!s.nativeActionLabelColors) s.nativeActionLabelColors=[NSMapTable weakToStrongObjectsMapTable];
        if (![s.nativeActionLabelColors objectForKey:label]) [s.nativeActionLabelColors setObject:label.textColor forKey:label];
        label.textColor=UIColor.whiteColor;
    }
    CGRect inset=CGRectInset(view.bounds,2.5*unit,3*unit);
    if (CGRectIsEmpty(inset)) inset=view.bounds;
    s.nativeActionGlass.frame=inset;
    s.nativeActionGlass.layer.cornerRadius=CGRectGetHeight(inset)*.5;
    CP26GlassPill(s.nativeActionGlass,CGRectGetHeight(inset)*.5);
}
static void Detach(CP26Header *s) {
    if (!s) return;
    RestoreNativeAction(s);
    CP26RemoveMiniPlayer(s.bar);
    RestoreUnused(s,nil);
    if (s.clearBar) {
        if ([s.bar.backgroundColor isEqual:UIColor.clearColor]) s.bar.backgroundColor=s.originalColor;
        if (!s.bar.opaque) s.bar.opaque=s.originalOpaque;
    }
    [s.back removeFromSuperview]; [s.action removeFromSuperview]; [s.menuTitle removeFromSuperview];
    [headerBars removeObject:s.bar];
    objc_setAssociatedObject(s.bar,&headerKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static UIButton *HeaderButton(CP26Header *s, SEL action, UIView **glass) {
    UIButton *b=[UIButton buttonWithType:UIButtonTypeCustom]; b.tintColor=UIColor.whiteColor;
    b.backgroundColor=UIColor.clearColor; b.opaque=NO; b.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
    [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    UIView *fill=[UIView new]; fill.userInteractionEnabled=NO;
    [b insertSubview:fill atIndex:0]; *glass=fill;
    [b addTarget:s action:action forControlEvents:UIControlEventPrimaryActionTriggered];
    [s.bar addSubview:b];
    return b;
}
static void ButtonSize(UIButton *b, UIView *glass, CGRect target, CGFloat insetX, CGFloat insetY) {
    if (!CGRectEqualToRect(b.frame,target)) b.frame=target;
    CGRect fill=CGRectInset(b.bounds,insetX,insetY);
    if (!CGRectEqualToRect(glass.frame,fill)) glass.frame=fill;
    CP26GlassPill(glass,CGRectGetHeight(fill)*.5);
}
void CP26LayoutHeader(UINavigationBar *bar) {
    CP26Header *s=objc_getAssociatedObject(bar,&headerKey);
    if (!s || s.applying) return;
    if (!IsFront(s.owner)) { Detach(s); return; }
    s.applying=YES;
    UIView *left=nil, *right=nil;
    FindBarParts(bar,s,0,&left,&right);
    UINavigationItem *item=bar.topItem ?: s.owner.navigationItem;
    s.left=item.leftBarButtonItem; s.right=item.rightBarButtonItem;
    left=left ?: s.left.customView; right=right ?: s.right.customView;
    s.nativeBack=ActionIn(s.left.customView) ?: ActionIn(left);
    s.nativeAction=ActionIn(s.right.customView) ?: ActionIn(right);
    CGFloat w=bar.bounds.size.width;
    CGFloat u=MIN(w/400,bar.bounds.size.height/33);
    if (u<=0) { s.applying=NO; return; }
    NSMutableSet *keep=[NSMutableSet set];
    BOOL back=left || s.left || (!item.hidesBackButton && s.owner.navigationController.viewControllers.count>1) ||
        (s.player && s.owner.navigationController.presentingViewController!=nil);
    s.back.hidden=!back;
    if (back) {
        ButtonSize(s.back,s.backGlass,CGRectMake(0,0,33*u,33*u),2.5*u,3*u);
        CGFloat side=14*u;
        if (!s.chevron) {
            CAShapeLayer *mark=[CAShapeLayer layer]; mark.fillColor=nil; mark.strokeColor=UIColor.whiteColor.CGColor;
            mark.lineCap=kCALineCapRound; mark.lineJoin=kCALineJoinRound; mark.zPosition=1;
            [s.back.layer addSublayer:mark]; s.chevron=mark;
        }
        CGRect markFrame=CGRectMake((s.back.bounds.size.width-side)/2,(s.back.bounds.size.height-side)/2,side,side);
        if (!CGRectEqualToRect(s.chevron.frame,markFrame) || !s.chevron.path) {
            UIBezierPath *path=[UIBezierPath bezierPath];
            [path moveToPoint:CGPointMake(side*.63,side*.18)]; [path addLineToPoint:CGPointMake(side*.32,side*.50)];
            [path addLineToPoint:CGPointMake(side*.63,side*.82)];
            [CATransaction begin]; [CATransaction setDisableActions:YES];
            s.chevron.frame=markFrame; s.chevron.lineWidth=2*u; s.chevron.path=path.CGPath; [CATransaction commit];
        }
        s.back.accessibilityLabel=s.nativeBack.accessibilityLabel ?: s.left.accessibilityLabel ?: @"Back";
        Suppress(s,left,keep);
    }
    BOOL wave=IsWave(right,0) || IsWave(s.right.customView,0) ||
        [NSStringFromSelector(s.right.action ?: @selector(description)).lowercaseString containsString:@"nowplaying"];
    if (!wave && s.nativeAction) for (id t in s.nativeAction.allTargets) {
        for (NSNumber *e in @[@(UIControlEventTouchUpInside),@(UIControlEventPrimaryActionTriggered)]) {
            for (NSString *a in [s.nativeAction actionsForTarget:t forControlEvent:e.unsignedIntegerValue])
                if ([a.lowercaseString containsString:@"nowplaying"]) wave=YES;
        }
    }
    BOOL mini=NO, nativeQueue=NO;
    if (!s.player && wave && item.rightBarButtonItems.count<=1) {
        mini=CP26UpdateMiniPlayer(bar,s.nativeAction,s.owner,s.right,CGRectMake(w-165*u,0,164*u,33*u));
    } else CP26RemoveMiniPlayer(bar);
    if (s.player && item.rightBarButtonItems.count<=1) {
        // Queue and Jam can be a native navigation-item view rather than a child
        // of the template controller's content view. Search the bar first.
        UILabel *queueLabel=QueueLabelIn(bar,0);
        if (!queueLabel) queueLabel=QueueLabelIn(s.owner.viewIfLoaded,0);
        if (!queueLabel) queueLabel=QueueLabelIn(s.owner.navigationController.viewIfLoaded,0);
        UIView *queueView=QueueContainer(queueLabel,bar);
        if (!queueView) queueView=right ?: (UIView *)s.nativeAction;
        NSString *title=s.right.title ?: VisibleTitle(right);
        if ((queueLabel || title.length) && queueView) {
            nativeQueue=YES;
            StyleNativeAction(s,queueView,queueLabel,u);
        }
    }
    if (!nativeQueue) RestoreNativeAction(s);
    // Keep the real menu title visible alongside the expanded playback bar.
    UILabel *original=mini && !item.titleView ? TitleIn(bar,s,item.title) : nil;
    s.menuTitle.hidden=!original;
    if (original) {
        s.menuTitle.text=item.title; s.menuTitle.font=[UIFont systemFontOfSize:13*u weight:UIFontWeightSemibold];
        CGFloat start=back ? 36*u : 5*u, end=w-168*u;
        CGFloat width=MIN(end-start,ceil([s.menuTitle sizeThatFits:CGSizeMake(w,33*u)].width));
        s.menuTitle.frame=CGRectMake(MAX(start,MIN((w-width)*.5,end-width)),0,width,33*u);
        Suppress(s,original,keep);
    }
    s.action.hidden=YES;
    if (mini) Suppress(s,right,keep);
    if (!s.clearBar) {
        s.originalColor=bar.backgroundColor; s.originalOpaque=bar.opaque; s.clearBar=YES;
    }
    if (bar.opaque) bar.opaque=NO;
    if (![bar.backgroundColor isEqual:UIColor.clearColor]) bar.backgroundColor=UIColor.clearColor;
    for (UIView *v in bar.subviews) if ([NSStringFromClass(v.class) containsString:@"BarBackground"]) Suppress(s,v,keep);
    RestoreUnused(s,keep);
    // Native layouts can insert new content above the controls. Avoid cycling
    // the order of our own views every time a track or timestamp updates.
    NSUInteger lastNative=0;
    for (UIView *v in bar.subviews)
        if (v!=s.back && v!=s.action && v!=s.menuTitle && ![NSStringFromClass(v.class) hasPrefix:@"CP26"])
            lastNative=[bar.subviews indexOfObjectIdenticalTo:v];
    if (!s.back.hidden && [bar.subviews indexOfObjectIdenticalTo:s.back]<lastNative) [bar bringSubviewToFront:s.back];
    if (!s.action.hidden && [bar.subviews indexOfObjectIdenticalTo:s.action]<lastNative) [bar bringSubviewToFront:s.action];
    s.applying=NO;
}
void CP26SetHeader(UIViewController *vc, BOOL player, BOOL enabled) {
    UINavigationBar *bar=vc.navigationController.navigationBar;
    if (!bar) return;
    CP26Header *s=objc_getAssociatedObject(bar,&headerKey);
    UIWindow *w=vc.viewIfLoaded.window;
    if (!enabled || !IsFront(vc) || !w || bar.window!=w || w.bounds.size.height<w.bounds.size.width ||
        w.bounds.size.width<320 || w.bounds.size.width>560 ||
        ![w.windowScene.session.role isEqualToString:@"UIWindowSceneSessionRoleCarPlay"]) {
        if (s.owner==vc) Detach(s);
        return;
    }
    if (s && s.owner!=vc) { Detach(s); s=nil; }
    if (!s) {
        s=[CP26Header new]; s.owner=vc; s.bar=bar; s.player=player; s.suppressed=[NSMapTable weakToStrongObjectsMapTable];
        s.menuTitle=[UILabel new]; s.menuTitle.hidden=YES; s.menuTitle.userInteractionEnabled=NO;
        s.menuTitle.textColor=UIColor.whiteColor; s.menuTitle.textAlignment=NSTextAlignmentCenter;
        s.menuTitle.lineBreakMode=NSLineBreakByTruncatingTail;
        s.menuTitle.accessibilityTraits=UIAccessibilityTraitHeader;
        [bar addSubview:s.menuTitle];
        UIView *bg=nil;
        s.back=HeaderButton(s,@selector(goBack),&bg); s.backGlass=bg;
        s.action=HeaderButton(s,@selector(performRight),&bg); s.actionGlass=bg;
        objc_setAssociatedObject(bar,&headerKey,s,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (!headerBars) headerBars=[NSHashTable weakObjectsHashTable];
        [headerBars addObject:bar];
    }
    CP26LayoutHeader(bar);
}
void CP26RestoreHeaders(BOOL details, BOOL player) {
    for (UINavigationBar *bar in headerBars.allObjects) {
        CP26Header *s=objc_getAssociatedObject(bar,&headerKey);
        if (!IsFront(s.owner) || !(s.player ? player : details)) Detach(s);
    }
}
UIView *CP26HeaderHit(UINavigationBar *bar, CGPoint p, UIEvent *event, UIView *native) {
    CP26Header *s=objc_getAssociatedObject(bar,&headerKey);
    if (!s || !IsFront(s.owner)) return native;
    UIView *hit=CP26MiniPlayerHit(bar,p,event) ?: CP26HitVisibleControl(s.back,bar,p,event) ?:
        CP26HitVisibleControl(s.action,bar,p,event);
    if (hit) return hit;
    // Preserve uncovered template-provided actions, including a fallback waveform.
    for (UIView *v=native; v && v!=bar; v=v.superview) if ([v isKindOfClass:UIControl.class]) return native;
    return nil;
}
void CP26HeaderReport(NSMutableString *out) {
    for (UINavigationBar *bar in headerBars.allObjects) {
        CP26Header *s=objc_getAssociatedObject(bar,&headerKey);
        CP26ReportHit(out,@"navigation back",s.back);
        CP26ReportHit(out,@"navigation right",s.action);
    }
}
