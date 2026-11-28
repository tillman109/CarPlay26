#import "CommunicationUI.h"

// The same view hierarchy can hold several calls, the active timer, and
// different sets of actions. Measure the visible native content after layout.
@interface CP26CallGlass : UIView
@property(nonatomic,strong) CP26MaterialView *card;
@property(nonatomic,strong) CP26MaterialView *tray;
@property(nonatomic,strong) UIImageView *symbol;
@end
@implementation CP26CallGlass
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self=[super initWithFrame:frame])) {
        self.userInteractionEnabled=NO;
        self.accessibilityElementsHidden=YES;
        _card=[CP26MaterialView new]; _tray=[CP26MaterialView new];
        _symbol=[UIImageView new]; _symbol.contentMode=UIViewContentModeScaleAspectFit;
        [self addSubview:_card]; [self addSubview:_tray]; [self addSubview:_symbol];
    }
    return self;
}
@end

static void Measure(UIView *view, UIView *root, CP26CommunicationStyle *style, BOOL actions,
                    CGRect *box, NSString **caller) {
    if (!view || view.hidden || view.alpha<.01 || [view isKindOfClass:CP26CallGlass.class]) return;
    BOOL label=[view isKindOfClass:UILabel.class] && ((UILabel *)view).text.length;
    BOOL button=actions && [view isKindOfClass:UIControl.class];
    if (label || button) {
        CGRect rect=[view convertRect:view.bounds toView:root];
        if (label && !actions) {
            CGFloat w=MIN(rect.size.width,ceil([((UILabel *)view) sizeThatFits:rect.size].width));
            rect.origin.x+=(rect.size.width-w)/2; rect.size.width=w;
            if (!*caller) *caller=((UILabel *)view).text;
        }
        if (!CGRectIsEmpty(rect) && CGRectIntersectsRect(rect,root.bounds)) *box=CGRectUnion(*box,rect);
        for (UIView *p=view.superview; p && p!=root; p=p.superview) {
            if ([p isKindOfClass:UIControl.class] && ![p isKindOfClass:NSClassFromString(@"PHCarPlayPhoneCallViewCell")]) continue;
            if (p.backgroundColor) [style set:UIColor.clearColor key:@"backgroundColor" on:p];
        }
    }
    for (UIView *child in view.subviews) Measure(child,root,style,actions,box,caller);
}

@protocol CP26CallParts <NSObject>
- (UIView *)buttonsView;
- (UIView *)galleryView;
@end
static void LayoutCall(UIViewController *vc) {
    UIView *root=vc.viewIfLoaded;
    if (!root.window) return;
    CP26CommunicationStyle *s=CP26StyleForView(root,CP26CallAppearanceEnabled());
    if (!s) return;
    id<CP26CallParts> parts=(id)vc;
    UIView *buttons=[parts respondsToSelector:@selector(buttonsView)] ? parts.buttonsView : nil;
    UIView *gallery=[parts respondsToSelector:@selector(galleryView)] ? parts.galleryView : nil;
    if (!s.field) {
        s.field=[[CP26CommunicationBackdrop alloc] initWithFrame:root.bounds];
        [root insertSubview:s.field atIndex:0];
        s.face=[[CP26CallGlass alloc] initWithFrame:root.bounds];
        [root insertSubview:s.face aboveSubview:s.field];
    }
    CP26CallGlass *glass=(CP26CallGlass *)s.face;
    glass.frame=s.field.frame=root.bounds;
    CGRect caller=CGRectNull, actions=CGRectNull; NSString *name=nil;
    Measure(gallery,root,s,NO,&caller,&name);
    Measure(buttons,root,s,YES,&actions,&name);
    CGRect safe=CGRectInset(root.bounds,6,3);
    glass.tray.hidden=CGRectIsNull(actions);
    if (!glass.tray.hidden) {
        CGRect tray=CGRectInset(actions,-11,-7);
        tray.origin.x=safe.origin.x; tray.size.width=safe.size.width;
        glass.tray.frame=CGRectIntersection(safe,tray);
        [glass.tray applyStyle:root.traitCollection.userInterfaceStyle radius:18];
    }
    glass.card.hidden=glass.symbol.hidden=CGRectIsNull(caller);
    if (!glass.card.hidden) {
        CGFloat w=MIN(safe.size.width,MAX(MIN(200,safe.size.width*.6),caller.size.width+32));
        CGRect rect=CGRectMake(CGRectGetMidX(caller)-w/2,caller.origin.y-28,w,caller.size.height+42);
        rect=CGRectIntersection(safe,rect);
        if (!glass.tray.hidden && CGRectIntersectsRect(rect,glass.tray.frame)) rect=CGRectIntersection(rect,CGRectMake(safe.origin.x,safe.origin.y,safe.size.width,MAX(0,CGRectGetMinY(glass.tray.frame)-safe.origin.y-3)));
        glass.card.hidden=CGRectIsEmpty(rect);
        if (!glass.card.hidden) {
            glass.card.frame=rect;
            [glass.card applyStyle:root.traitCollection.userInterfaceStyle radius:18];
            glass.symbol.image=[UIImage systemImageNamed:[name localizedCaseInsensitiveContainsString:@"voicemail"] ? @"recordingtape" : @"phone.fill"];
            glass.symbol.tintColor=UIColor.labelColor;
            glass.symbol.frame=CGRectMake(CGRectGetMidX(rect)-13,caller.origin.y-21,26,15);
        }
        glass.symbol.hidden=glass.card.hidden || !CGRectContainsRect(rect,glass.symbol.frame);
    }
}

%group CallAppearance
%hook PHCarPlayMainInCallViewController
- (void)viewDidLayoutSubviews { %orig; LayoutCall((UIViewController *)self); }
- (void)viewDidAppear:(BOOL)animated { %orig; LayoutCall((UIViewController *)self); }
%end
%end
%ctor {
    if (NSClassFromString(@"PHCarPlayMainInCallViewController")) { %init(CallAppearance); }
}
