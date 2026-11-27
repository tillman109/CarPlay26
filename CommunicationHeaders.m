#import "CommunicationUI.h"
#import <QuartzCore/QuartzCore.h>

@protocol CP26BarItemView <NSObject>
- (UIView *)view;
@end

static UIView *ItemView(id item, UIView *bar) {
    UIView *view = [item respondsToSelector:@selector(view)] ? [(id<CP26BarItemView>)item view] : nil;
    return [view isDescendantOfView:bar] ? view : nil;
}
static void Collect(UIView *root, NSString *name, NSMutableArray<UIView *> *found) {
    for (UIView *child in root.subviews) {
        if ([NSStringFromClass(child.class) isEqualToString:name]) [found addObject:child];
        else if (![child isKindOfClass:CP26CommunicationBackdrop.class] && ![NSStringFromClass(child.class) hasPrefix:@"CP26"]) Collect(child, name, found);
    }
}
static void PrepareBar(UIView *bar, CP26CommunicationStyle *state) {
    [state set:@NO key:@"opaque" on:bar];
    [state set:UIColor.clearColor key:@"backgroundColor" on:bar];
    for (UIView *child in bar.subviews) {
        if ([child isKindOfClass:UIVisualEffectView.class] || [NSStringFromClass(child.class) isEqualToString:@"_UIBarBackground"])
            [state concealDrawing:child];
    }
    if (!state.field) {
        state.field = [[CP26CommunicationBackdrop alloc] initWithFrame:bar.bounds];
        [bar insertSubview:state.field atIndex:0];
    }
    state.field.frame = bar.bounds;
    if (bar.subviews.firstObject!=state.field) [bar sendSubviewToBack:state.field];
}
static BOOL IsHeader(UIView *bar) {
    if (!bar.window || bar.hidden || CGRectIsEmpty(bar.bounds)) return NO;
    CGRect rect = [bar convertRect:bar.bounds toView:bar.window];
    return CGRectGetMinY(rect) < 56 && CGRectGetMaxY(rect) > 0;
}
static CGFloat HeaderCenterY(UIView *bar) {
    return MIN(17.5, CGRectGetMidY(bar.bounds));
}
static UIColor *Ink(UIView *view) {
    return view.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? UIColor.whiteColor : UIColor.blackColor;
}

@interface CP26PhoneStrip : UIView
@property(nonatomic,strong) CP26MaterialView *glass;
@property(nonatomic,strong) UIView *selection;
@property(nonatomic,strong) NSMutableArray<UILabel *> *labels;
@property(nonatomic,strong) NSMutableArray<UIImageView *> *icons;
@property(nonatomic,weak) UISegmentedControl *segments;
@property(nonatomic,copy) NSArray<NSNumber *> *originalWidths;
@end
@implementation CP26PhoneStrip
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.userInteractionEnabled = NO;
        self.accessibilityElementsHidden = YES;
        _glass = [[CP26MaterialView alloc] initWithFrame:self.bounds];
        [self addSubview:_glass];
        _selection = [UIView new];
        _selection.layer.cornerCurve = kCACornerCurveContinuous;
        [self addSubview:_selection];
        _labels = [NSMutableArray array]; _icons = [NSMutableArray array];
    }
    return self;
}
- (void)willMoveToSuperview:(UIView *)superview {
    if (!superview && _segments.numberOfSegments == _originalWidths.count) {
        for (NSUInteger i=0; i<_originalWidths.count; i++) [_segments setWidth:_originalWidths[i].doubleValue forSegmentAtIndex:i];
    }
    [super willMoveToSuperview:superview];
}
@end

// Return one native hit rectangle per tab. The decorative text and glass cannot receive input.
static NSArray<NSValue *> *LayoutStrip(CP26PhoneStrip *strip, NSArray<NSString *> *titles,
        NSArray *images, NSArray<NSNumber *> *enabled, NSInteger selection, NSInteger focused,
        UIView *bar, CGFloat available) {
    BOOL rtl = bar.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    BOOL dark = bar.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
    UIFont *font = [UIFont systemFontOfSize:10 weight:UIFontWeightMedium];
    NSMutableArray<NSNumber *> *widths = [NSMutableArray array];
    CGFloat total = 0;
    for (NSString *title in titles) {
        CGFloat width = title.length ? MAX(39, ceil([title sizeWithAttributes:@{NSFontAttributeName:font}].width)+15) : 34;
        [widths addObject:@(width)]; total += width;
    }
    CGFloat width = MIN(total+6, MAX(1,available-4)), height = 27;
    strip.bounds = CGRectMake(0,0,width,height);
    strip.glass.frame = strip.bounds;
    [strip.glass applyStyle:bar.traitCollection.userInterfaceStyle radius:height/2];
    NSMutableArray *rects = [NSMutableArray array];
    CGFloat offset = 3;
    for (NSUInteger i=0; i<titles.count; i++) {
        CGFloat w = (width-6)*widths[i].doubleValue/total;
        CGRect box = CGRectMake(rtl ? width-offset-w : offset,3,w,21);
        [rects addObject:[NSValue valueWithCGRect:box]]; offset += w;
        if (strip.labels.count<=i) {
            UILabel *label = [UILabel new]; label.textAlignment = NSTextAlignmentCenter;
            label.adjustsFontSizeToFitWidth = YES; label.minimumScaleFactor = .78;
            [strip.labels addObject:label]; [strip addSubview:label];
            UIImageView *icon = [UIImageView new]; icon.contentMode = UIViewContentModeScaleAspectFit;
            [strip.icons addObject:icon]; [strip addSubview:icon];
        }
        UILabel *label = strip.labels[i]; UIImageView *icon = strip.icons[i];
        label.frame = CGRectInset(box,2,0); label.text = titles[i]; label.textColor = Ink(bar);
        label.font = i==(NSUInteger)selection ? [UIFont systemFontOfSize:10 weight:UIFontWeightSemibold] : font;
        label.hidden = !label.text.length; icon.hidden = !label.hidden;
        icon.image = images[i] == NSNull.null ? nil : [images[i] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        icon.tintColor = Ink(bar); icon.frame = CGRectMake(CGRectGetMidX(box)-7,CGRectGetMidY(box)-6,14,12);
        label.alpha = icon.alpha = enabled[i].boolValue ? 1 : .38;
        label.layer.cornerRadius = icon.layer.cornerRadius = 5;
        label.layer.borderColor = icon.layer.borderColor = Ink(bar).CGColor;
        label.layer.borderWidth = icon.layer.borderWidth = (NSInteger)i==focused ? 1 : 0;
    }
    for (NSUInteger i=titles.count;i<strip.labels.count;i++) { strip.labels[i].hidden=YES; strip.icons[i].hidden=YES; }
    strip.selection.hidden = selection<0 || selection>=(NSInteger)rects.count;
    if (!strip.selection.hidden) strip.selection.frame = [rects[(NSUInteger)selection] CGRectValue];
    strip.selection.layer.cornerRadius = 10.5;
    strip.selection.backgroundColor = [UIColor colorWithWhite:dark ? 1 : .18 alpha:dark ? .20 : .13];
    return rects;
}
static NSString *TabTitle(NSString *title, NSUInteger index, NSUInteger count) {
    if (count==5 && index>=3) return @"";
    if ([title isEqualToString:@"Recents"]) return @"Recent";
    return title ?: @"";
}
static UIImage *TabImage(UIImage *native, NSUInteger index, NSUInteger count) {
    if (count==5 && index>=3) return [UIImage systemImageNamed:index==3 ? @"circle.grid.3x3.fill" : @"recordingtape"] ?: native;
    return native;
}
void CP26CommunicationTabs(UITabBar *bar) {
    NSArray<UITabBarItem *> *items = bar.items;
    BOOL active = CP26AppForView(bar)==CP26PhoneApp && IsHeader(bar) && items.count>=3 && items.count<=5;
    NSMutableArray<UIView *> *buttons = [NSMutableArray array];
    if (active) for (UITabBarItem *item in items) {
        UIView *button = ItemView(item,bar);
        if (button) [buttons addObject:button];
    }
    if (active && buttons.count!=items.count) {
        [buttons removeAllObjects]; Collect(bar,@"UITabBarButton",buttons);
        BOOL rtl = bar.effectiveUserInterfaceLayoutDirection==UIUserInterfaceLayoutDirectionRightToLeft;
        [buttons sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
            NSNumber *ax = @(CGRectGetMidX([a convertRect:a.bounds toView:bar]));
            NSNumber *bx = @(CGRectGetMidX([b convertRect:b.bounds toView:bar]));
            return rtl ? [bx compare:ax] : [ax compare:bx];
        }];
    }
    CP26CommunicationStyle *s = CP26StyleForView(bar,active && buttons.count==items.count);
    if (!s) return;
    PrepareBar(bar,s);
    CP26PhoneStrip *strip = (CP26PhoneStrip *)s.face;
    if (!strip) { strip=[CP26PhoneStrip new]; s.face=strip; [bar addSubview:strip]; }
    NSMutableArray *titles=[NSMutableArray array], *images=[NSMutableArray array], *enabled=[NSMutableArray array];
    NSInteger selected=-1, focused=-1;
    for (NSUInteger i=0;i<items.count;i++) {
        UITabBarItem *item=items[i];
        if (item==bar.selectedItem) selected=(NSInteger)i;
        if (buttons[i].focused) focused=(NSInteger)i;
        [titles addObject:TabTitle(item.title,i,items.count)]; [images addObject:TabImage(item.image,i,items.count) ?: (id)NSNull.null];
        [enabled addObject:@(item.enabled)];
    }
    NSArray<NSValue *> *rects=LayoutStrip(strip,titles,images,enabled,selected,focused,bar,bar.bounds.size.width);
    strip.center=CGPointMake(CGRectGetMidX(bar.bounds),HeaderCenterY(bar));
    for (NSUInteger i=0;i<buttons.count;i++) {
        CGRect hit=[strip convertRect:rects[i].CGRectValue toView:bar]; hit.origin.y=0; hit.size.height=bar.bounds.size.height;
        [s.positions place:buttons[i] in:bar rect:hit]; [s concealDrawing:buttons[i]];
    }
    if (bar.subviews.lastObject!=strip) [bar bringSubviewToFront:strip];
}
void CP26CommunicationSegments(UISegmentedControl *control) {
    NSUInteger n=control.numberOfSegments;
    BOOL active=CP26AppForView(control)==CP26PhoneApp && IsHeader(control) && n>=3 && n<=5;
    CP26CommunicationStyle *s=CP26StyleForView(control,active);
    if (!s) return;
    CP26PhoneStrip *strip=(CP26PhoneStrip *)s.face;
    if (!strip) { strip=[CP26PhoneStrip new]; s.face=strip; [control addSubview:strip]; }
    NSMutableArray *titles=[NSMutableArray array], *images=[NSMutableArray array], *enabled=[NSMutableArray array];
    NSMutableArray *widths=[NSMutableArray array];
    for (NSUInteger i=0;i<n;i++) {
        [titles addObject:TabTitle([control titleForSegmentAtIndex:i],i,n)];
        [images addObject:TabImage([control imageForSegmentAtIndex:i],i,n) ?: (id)NSNull.null];
        [enabled addObject:@([control isEnabledForSegmentAtIndex:i])]; [widths addObject:@([control widthForSegmentAtIndex:i])];
    }
    if (strip.originalWidths.count!=n) { strip.originalWidths=widths; strip.segments=control; }
    NSArray<NSValue *> *rects=LayoutStrip(strip,titles,images,enabled,control.selectedSegmentIndex,-1,control,control.window.bounds.size.width);
    CGRect box=[control convertRect:control.bounds toView:control.window];
    box.size.width=strip.bounds.size.width; box.origin.x=CGRectGetMidX(control.window.bounds)-box.size.width/2;
    [s.positions place:control in:control.window rect:box];
    strip.center=CGPointMake(CGRectGetMidX(control.bounds),CGRectGetMidY(control.bounds));
    for (NSUInteger i=0;i<n;i++) {
        CGFloat width=rects[i].CGRectValue.size.width+(i==0 || i==n-1 ? 3 : 0);
        if (fabs([control widthForSegmentAtIndex:i]-width)>.1) [control setWidth:width forSegmentAtIndex:i];
    }
    for (UIView *child in control.subviews) if (child!=strip) [s concealDrawing:child];
    if (control.subviews.lastObject!=strip) [control bringSubviewToFront:strip];
}

@interface CP26MessagesHeader : UIView
@property(nonatomic,strong) UILabel *title;
@property(nonatomic,strong) CP26MaterialView *compose;
@property(nonatomic,strong) UIImageView *glyph;
@end
@implementation CP26MessagesHeader
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self=[super initWithFrame:frame])) {
        self.userInteractionEnabled=NO; self.accessibilityElementsHidden=YES;
        _title=[UILabel new]; _title.font=[UIFont systemFontOfSize:20 weight:UIFontWeightSemibold];
        _title.adjustsFontSizeToFitWidth=YES; _title.minimumScaleFactor=.8;
        _compose=[[CP26MaterialView alloc] initWithFrame:CGRectZero];
        _glyph=[[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"square.and.pencil"]];
        _glyph.contentMode=UIViewContentModeScaleAspectFit;
        [self addSubview:_title]; [self addSubview:_compose]; [self addSubview:_glyph];
    }
    return self;
}
@end
static void SuppressTitle(UIView *parent, NSString *title, CP26CommunicationStyle *s) {
    for (UIView *child in parent.subviews) {
        if (child==s.face || child==s.field || [child isKindOfClass:UIControl.class]) continue;
        if ([NSStringFromClass(child.class) isEqualToString:@"_CarTitleView"] ||
            ([child isKindOfClass:UILabel.class] && [((UILabel *)child).text isEqualToString:title])) [s concealDrawing:child];
        else SuppressTitle(child,title,s);
    }
}
void CP26CommunicationNavigation(UINavigationBar *bar) {
    CP26CommunicationApp app=CP26AppForView(bar);
    UINavigationItem *item=bar.topItem;
    BOOL messages=app==CP26MessagesApp && item && !bar.backItem && item.title.length;
    BOOL phone=app==CP26PhoneApp && [item.titleView isKindOfClass:UISegmentedControl.class];
    CP26CommunicationStyle *s=CP26StyleForView(bar,(messages || phone) && IsHeader(bar));
    if (!s) return;
    PrepareBar(bar,s);
    if (phone) { CP26CommunicationSegments((UISegmentedControl *)item.titleView); return; }
    CP26MessagesHeader *face=(CP26MessagesHeader *)s.face;
    if (!face) { face=[CP26MessagesHeader new]; s.face=face; [bar addSubview:face]; }
    face.frame=bar.bounds; face.title.text=item.title; face.title.textColor=Ink(bar);
    SuppressTitle(bar,item.title,s);
    UIBarButtonItem *right=item.rightBarButtonItem;
    UIView *control=ItemView(right,bar) ?: right.customView;
    if (right && !control && item.rightBarButtonItems.count==1) {
        NSMutableArray<UIView *> *candidates=[NSMutableArray array]; Collect(bar,@"_UIButtonBarButton",candidates);
        for (UIView *candidate in candidates) {
            if (candidate.hidden || candidate.alpha<.01) continue;
            CGRect r=[candidate convertRect:candidate.bounds toView:bar];
            BOOL rtl=bar.effectiveUserInterfaceLayoutDirection==UIUserInterfaceLayoutDirectionRightToLeft;
            if (rtl ? CGRectGetMidX(r)<bar.bounds.size.width*.35 : CGRectGetMidX(r)>bar.bounds.size.width*.65) { control=candidate; break; }
        }
    }
    BOOL rtl=bar.effectiveUserInterfaceLayoutDirection==UIUserInterfaceLayoutDirectionRightToLeft;
    CGFloat w=bar.bounds.size.width, cy=HeaderCenterY(bar);
    face.title.textAlignment=rtl ? NSTextAlignmentRight : NSTextAlignmentLeft;
    face.title.frame=CGRectMake(rtl ? 42 : 9,cy-15,MAX(0,w-51),30);
    face.glyph.hidden=face.compose.hidden=!(right && control && [control isDescendantOfView:bar]);
    if (!face.compose.hidden) {
        // Keep the system bar item's complete touch and rotary focus target under the new glyph.
        CGRect target=CGRectMake(rtl ? 0 : w-38,0,38,bar.bounds.size.height);
        [s.positions place:control in:bar rect:target]; [s concealDrawing:control];
        CGRect circle=CGRectMake(rtl ? 1 : w-29,cy-14,28,28);
        face.compose.frame=circle; [face.compose applyStyle:bar.traitCollection.userInterfaceStyle radius:14];
        face.glyph.frame=CGRectInset(circle,7.5,7.5); face.glyph.tintColor=Ink(bar);
        face.glyph.alpha=right.enabled ? 1 : .4;
        face.glyph.layer.borderColor=Ink(bar).CGColor; face.glyph.layer.cornerRadius=3;
        face.glyph.layer.borderWidth=control.focused ? 1 : 0;
    }
    if (bar.subviews.lastObject!=face) [bar bringSubviewToFront:face];
}
