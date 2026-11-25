#import "SpotifyReference.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

// CPUINowPlayingView exposes the actual CarPlay transport, progress and app
// buttons. Move these controls together with their existing handlers.
@protocol CP26PlaybackViews <NSObject>
@optional
- (UIView *)nowPlayingView;
- (UIView *)artworkViewBrick;
- (UIView *)songDetailsView;
- (UIView *)transportControlView;
- (UIView *)progressView;
- (UIView *)playModeControlView;
- (UIView *)leftButton;
- (UIView *)playPauseButton;
- (UIView *)fastForwardButton;
- (UIView *)stackView;
- (UIImage *)image;
- (UIImage *)artworkImage;
@end

@interface CP26PlayerState : NSObject
@property(nonatomic,weak) UIViewController *controller;
@property(nonatomic,weak) UIView *host;
@property(nonatomic,strong) UIView *background;
@property(nonatomic,strong) UIImageView *art;
@property(nonatomic,strong) CP26PlacedViews *places;
@property(nonatomic,strong) NSHashTable<UIView *> *glassButtons;
@property(nonatomic) BOOL applying, revealedArt;
@property(nonatomic,weak) UIView *brick;
@property(nonatomic,weak) UIStackView *detailStack;
@property(nonatomic) UIStackViewAlignment originalAlignment;
@property(nonatomic,strong) NSMapTable<UILabel *,NSNumber *> *alignments;

@end
@implementation CP26PlayerState
@end
static char playerKey, hostKey;
static NSHashTable<UIViewController *> *controllers;

static UIView *FindPlayerView(UIView *v, NSUInteger depth) {
    if (!v || depth>9) return nil;
    if ([v isKindOfClass:NSClassFromString(@"CPUINowPlayingView")]) return v;
    for (UIView *child in v.subviews) {
        UIView *found=FindPlayerView(child,depth+1);
        if (found) return found;
    }
    return nil;
}
static void Restore(UIViewController *controller) {
    CP26PlayerState *s=objc_getAssociatedObject(controller,&playerKey);
    if (!s) return;
    objc_setAssociatedObject(s.host,&hostKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    for (UIView *v in s.glassButtons.allObjects) CP26RemoveGlass(v);
    if (s.revealedArt) s.brick.hidden=YES;
    if (s.detailStack && s.detailStack.alignment==UIStackViewAlignmentCenter)
        s.detailStack.alignment=s.originalAlignment;
    for (UILabel *label in s.alignments.keyEnumerator)
        if (label.textAlignment==NSTextAlignmentCenter) label.textAlignment=(NSTextAlignment)[s.alignments objectForKey:label].integerValue;
    [s.places restore]; [s.background removeFromSuperview];
    objc_setAssociatedObject(controller,&playerKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [controllers removeObject:controller];
}
static void PlayerBarGlass(CP26PlayerState *s, UIView *v, NSUInteger depth, NSHashTable<UIView *> *keep) {
    if (!v || depth>6 || v.hidden) return;
    NSString *cls=NSStringFromClass(v.class);
    if ([cls isEqualToString:@"_UIButtonBarButton"] || [v isKindOfClass:UIButton.class]) {
        if (v.bounds.size.width>=24 && v.bounds.size.height>=18) {
            CP26GlassPill(v,MIN(14,v.bounds.size.height*.5)); [s.glassButtons addObject:v]; [keep addObject:v];
        }
        return;
    }
    for (UIView *child in v.subviews) PlayerBarGlass(s,child,depth+1,keep);
}
static void CenterLabels(CP26PlayerState *s, UIView *view, NSUInteger depth) {
    if (depth>5) return;
    if ([view isKindOfClass:UILabel.class]) {
        UILabel *label=(UILabel *)view;
        if (![s.alignments objectForKey:label]) [s.alignments setObject:@(label.textAlignment) forKey:label];
        if (label.textAlignment!=NSTextAlignmentCenter) label.textAlignment=NSTextAlignmentCenter;
        return;
    }
    for (UIView *v in view.subviews) CenterLabels(s,v,depth+1);
}
void CP26PlayerLayout(UIViewController *controller, BOOL enabled) {
    if (!controller || !NSThread.isMainThread) return;
    UIWindow *window=controller.viewIfLoaded.window;
    CP26PlayerState *s=objc_getAssociatedObject(controller,&playerKey);
    if (s.applying) return;
    CGFloat w=window.bounds.size.width,h=window.bounds.size.height;
    if (!enabled || !window || window.hidden || w<320 || w>560 || h<w ||
        ![window.windowScene.session.role isEqualToString:@"UIWindowSceneSessionRoleCarPlay"]) {
        Restore(controller); return;
    }
    UIView *v=s.host ?: FindPlayerView(controller.viewIfLoaded,0);
    id<CP26PlaybackViews> host=(id)v;
    if (![host respondsToSelector:@selector(artworkViewBrick)] || ![host respondsToSelector:@selector(transportControlView)] ||
        ![host respondsToSelector:@selector(songDetailsView)] || ![host respondsToSelector:@selector(progressView)] ||
        ![host respondsToSelector:@selector(playModeControlView)]) { Restore(controller); return; }
    UIView *brick=host.artworkViewBrick, *transport=host.transportControlView, *details=host.songDetailsView;
    if (!brick.superview || !transport.superview || !details.superview) { Restore(controller); return; }
    if (!s) {
        s=[CP26PlayerState new]; s.controller=controller; s.host=v; s.places=[CP26PlacedViews new];
        s.glassButtons=[NSHashTable weakObjectsHashTable]; s.alignments=[NSMapTable weakToStrongObjectsMapTable];
        s.background=[UIView new]; s.background.clipsToBounds=YES; s.background.userInteractionEnabled=NO;
        s.background.accessibilityElementsHidden=YES;
        s.art=[UIImageView new]; s.art.contentMode=UIViewContentModeScaleAspectFill;
        s.art.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        [s.background addSubview:s.art];
        UIVisualEffectView *blur=[[UIVisualEffectView alloc] initWithEffect:
            [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterialDark]];
        blur.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        blur.contentView.backgroundColor=[UIColor colorWithWhite:.11 alpha:.20];
        [s.background addSubview:blur];
        objc_setAssociatedObject(controller,&playerKey,s,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(v,&hostKey,s,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (!controllers) controllers=[NSHashTable weakObjectsHashTable]; [controllers addObject:controller];
    }
    s.applying=YES;
    id<CP26PlaybackViews> artSource=(id)brick;
    UIImage *cover=[artSource respondsToSelector:@selector(image)] ? [artSource image] : nil;
    if (!cover) for (UIResponder *r=v.nextResponder; r; r=r.nextResponder) {
        if ([r respondsToSelector:@selector(artworkImage)]) { cover=[(id<CP26PlaybackViews>)r artworkImage]; break; }
    }
    if (cover!=s.art.image) s.art.image=cover;
    if (cover) {
        if (brick.hidden) { brick.hidden=NO; s.brick=brick; s.revealedArt=YES; }
        if (s.background.superview!=v) [v insertSubview:s.background atIndex:0];
        CGRect bg=[v convertRect:window.bounds fromView:window];
        if (!CGRectEqualToRect(s.background.frame,bg)) {
            s.background.frame=bg;
            for (UIView *layer in s.background.subviews) layer.frame=s.background.bounds;
        }
    } else {
        if (s.revealedArt) { s.brick.hidden=YES; s.revealedArt=NO; }
        [s.background removeFromSuperview];
    }
    id<CP26PlaybackViews> detailViews=(id)details;
    UIView *stack=[detailViews respondsToSelector:@selector(stackView)] ? detailViews.stackView : nil;
    if ([stack isKindOfClass:UIStackView.class] && ((UIStackView *)stack).axis==UILayoutConstraintAxisVertical) {
        UIStackView *labels=(UIStackView *)stack;
        if (s.detailStack!=labels) {
            if (s.detailStack) s.detailStack.alignment=s.originalAlignment;
            s.detailStack=labels; s.originalAlignment=labels.alignment;
        }
        if (labels.alignment!=UIStackViewAlignmentCenter) labels.alignment=UIStackViewAlignmentCenter;
    }
    CenterLabels(s,details,0);
    CGFloat ux=w/400, uy=(h-34.5*ux)/381.5;
    CGFloat side=MIN(172*ux,172*uy);
    [s.places place:brick in:window rect:CGRectMake((w-side)/2,39*uy,side,side)];
    [s.places place:details in:window rect:CGRectMake(18*ux,218*uy,364*ux,41*uy)];
    [s.places place:transport in:window rect:CGRectMake(12*ux,273*uy,376*ux,43*uy)];
    id<CP26PlaybackViews> buttons=(id)transport;
    if ([buttons respondsToSelector:@selector(leftButton)] && [buttons respondsToSelector:@selector(playPauseButton)] &&
        [buttons respondsToSelector:@selector(fastForwardButton)]) {
        CGFloat bw=52*ux,bh=40*uy;
        [s.places place:buttons.leftButton in:window rect:CGRectMake(73*ux-bw/2,295*uy-bh/2,bw,bh)];
        [s.places place:buttons.playPauseButton in:window rect:CGRectMake(200*ux-bw/2,295*uy-bh/2,bw,bh)];
        [s.places place:buttons.fastForwardButton in:window rect:CGRectMake(327*ux-bw/2,295*uy-bh/2,bw,bh)];
    }
    [s.places place:host.progressView in:window rect:CGRectMake(8*ux,316*uy,384*ux,22*uy)];
    [s.places place:host.playModeControlView in:window rect:CGRectMake(87*ux,339*uy,226*ux,26*uy)];
    UINavigationBar *nav=controller.navigationController.navigationBar;
    NSHashTable *keep=[NSHashTable weakObjectsHashTable];
    if (nav.window==window) PlayerBarGlass(s,nav,0,keep);
    for (UIView *button in s.glassButtons.allObjects) if (![keep containsObject:button]) {
        CP26RemoveGlass(button); [s.glassButtons removeObject:button];
    }
    s.applying=NO;
}
void CP26PlayerViewLaidOut(UIView *host) {
    CP26PlayerState *s=objc_getAssociatedObject(host,&hostKey);
    if (s && !s.applying && s.controller.viewIfLoaded.window) CP26PlayerLayout(s.controller,YES);
}
void CP26RestorePlayers(void) {
    for (UIViewController *controller in controllers.allObjects) Restore(controller);
}
void CP26FullPlayerReport(NSMutableString *report) {
    for (UIViewController *controller in controllers.allObjects) {
        CP26PlayerState *s=objc_getAssociatedObject(controller,&playerKey);
        id<CP26PlaybackViews> v=(id)s.host;
        if (!s.host.window) continue;
        UIView *hero=v.artworkViewBrick, *seek=v.progressView;
        [report appendFormat:@"PLAYER artwork=%@ progress=%@ albumBlur=%d navigationButtons=%lu\n",
            NSStringFromCGRect([hero convertRect:hero.bounds toView:hero.window]),
            NSStringFromCGRect([seek convertRect:seek.bounds toView:seek.window]),s.art.image!=nil,
            (unsigned long)s.glassButtons.count];
    }
}
