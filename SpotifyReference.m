#import "SpotifyReference.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

static UIImage *BackdropField(void) {
    static UIImage *field;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // Low-frequency samples of uncovered wallpaper in the Library reference.
        static const uint32_t colors[16 * 17] = {
        0x2a2a34, 0x2b2b35, 0x2c2c37, 0x2f2f3b, 0x31303e, 0x2e2e3a, 0x2b2b35, 0x2d2d38, 0x30303d, 0x343343, 0x38384a, 0x343343, 0x2c2c36, 0x2c2c37, 0x333342, 0x393a4d,
        0x2b2934, 0x2b2b35, 0x2c2c37, 0x302f3c, 0x32313f, 0x2f2f3c, 0x2c2b36, 0x2c2c37, 0x31303e, 0x373648, 0x3a3a4e, 0x353545, 0x2d2d38, 0x2d2d38, 0x343443, 0x393a4c,
        0x2c2a35, 0x2c2c37, 0x2e2e3a, 0x323140, 0x343342, 0x31313f, 0x2d2d38, 0x2d2d38, 0x333240, 0x3a394c, 0x3c3d51, 0x373748, 0x2f2f3b, 0x302f3c, 0x363647, 0x3a3b4e,
        0x2e2d38, 0x2e2d39, 0x302f3d, 0x343443, 0x353545, 0x333241, 0x2e2e3a, 0x2f2e3b, 0x353444, 0x3c3b4f, 0x3e3e53, 0x38384a, 0x31313f, 0x343443, 0x393a4d, 0x3c3d51,
        0x302f3c, 0x31303c, 0x353443, 0x373647, 0x363647, 0x333241, 0x2f2f3c, 0x31303f, 0x373648, 0x3c3c51, 0x3c3d51, 0x363747, 0x343443, 0x373849, 0x3b3c4f, 0x3c3d51,
        0x353341, 0x373544, 0x3a394b, 0x39384a, 0x373647, 0x323140, 0x302f3d, 0x343343, 0x39384b, 0x3a3b4f, 0x38384b, 0x353546, 0x373748, 0x3a3b4e, 0x3b3c50, 0x3b3c50,
        0x3a3848, 0x3b3a4b, 0x3d3b4e, 0x3a394c, 0x363545, 0x31313f, 0x323140, 0x353546, 0x373749, 0x363749, 0x353647, 0x373748, 0x3a3b4e, 0x3c3d51, 0x3c3d50, 0x3c3d51,
        0x403e51, 0x444256, 0x444257, 0x3d3b4e, 0x353444, 0x323241, 0x333343, 0x343445, 0x343545, 0x343545, 0x363748, 0x3a3b4d, 0x3d3e52, 0x3d3e51, 0x3d3e51, 0x414257,
        0x454258, 0x49475c, 0x464459, 0x3d3c4e, 0x373646, 0x343343, 0x333342, 0x333343, 0x343544, 0x353646, 0x38394a, 0x3c3d51, 0x3e3f53, 0x3c3d50, 0x404156, 0x484a62,
        0x454358, 0x47455a, 0x434155, 0x3b394b, 0x363544, 0x333342, 0x343343, 0x343545, 0x353545, 0x353646, 0x393a4c, 0x3d3e52, 0x3d3e51, 0x3b3d50, 0x43455a, 0x4b4f67,
        0x424155, 0x424054, 0x3d3b4d, 0x373646, 0x343343, 0x343444, 0x353647, 0x353545, 0x343443, 0x353646, 0x3a3b4d, 0x3d3e51, 0x3a3c4e, 0x3c3e51, 0x45485e, 0x4c5169,
        0x3d3c4e, 0x3b3a4b, 0x373645, 0x353443, 0x363546, 0x373849, 0x363647, 0x343342, 0x333341, 0x363747, 0x3b3c4f, 0x3b3d50, 0x393a4c, 0x3c3e52, 0x45495f, 0x4c5168,
        0x373646, 0x353442, 0x333241, 0x363545, 0x39394b, 0x38384a, 0x343443, 0x32313f, 0x333342, 0x373849, 0x3a3c4f, 0x393b4d, 0x37394a, 0x3b3e51, 0x43475c, 0x494e65,
        0x31313d, 0x30303c, 0x333240, 0x383849, 0x39394c, 0x353545, 0x31303e, 0x31303e, 0x343443, 0x373849, 0x393b4d, 0x37394a, 0x363847, 0x393c4e, 0x404458, 0x44495e,
        0x2d2c37, 0x2e2d39, 0x333240, 0x383748, 0x373647, 0x31313f, 0x2f2e3b, 0x31303e, 0x343443, 0x373849, 0x38394b, 0x353746, 0x333544, 0x363949, 0x3b3f51, 0x3e4356,
        0x2a2a33, 0x2d2c36, 0x32313f, 0x363545, 0x343342, 0x2f2f3b, 0x2e2d3a, 0x30303e, 0x343443, 0x363748, 0x363849, 0x333543, 0x313341, 0x343645, 0x383b4c, 0x3b3e51,
        0x2a2931, 0x2c2b35, 0x31303e, 0x343343, 0x323140, 0x2e2e3a, 0x2d2d39, 0x302f3d, 0x333443, 0x363747, 0x363748, 0x323442, 0x303240, 0x333543, 0x37394a, 0x393c4e
        };
        uint8_t rgba[16 * 17 * 4];
        for (NSUInteger i = 0; i < 16 * 17; i++) {
            rgba[i*4] = colors[i] >> 16;
            rgba[i*4+1] = colors[i] >> 8;
            rgba[i*4+2] = colors[i];
            rgba[i*4+3] = 255;
        }
        NSData *data = [NSData dataWithBytes:rgba length:sizeof(rgba)];
        CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGImageRef cg = CGImageCreate(16,17,8,32,64,space,kCGImageAlphaNoneSkipLast |
            kCGBitmapByteOrder32Big,provider,NULL,true,kCGRenderingIntentDefault);
        if (cg) { field = [UIImage imageWithCGImage:cg]; CGImageRelease(cg); }
        CGColorSpaceRelease(space); CGDataProviderRelease(provider);
    });
    return field;
}

@interface CP26ReferenceBackdrop : UIView
@property(nonatomic,strong) UIImageView *field;
@end
@implementation CP26ReferenceBackdrop
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.userInteractionEnabled = NO;
        self.accessibilityElementsHidden = YES;
        self.clipsToBounds = YES;
        self.backgroundColor = [UIColor colorWithRed:.19 green:.19 blue:.24 alpha:1];
        _field = [[UIImageView alloc] initWithImage:BackdropField()];
        _field.contentMode = UIViewContentModeScaleToFill;
        [self addSubview:_field];
    }
    return self;
}
- (void)didMoveToWindow { [super didMoveToWindow]; [self setNeedsLayout]; }
- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect rect = self.window ? [self convertRect:self.window.bounds fromView:self.window] : self.bounds;
    if (!CGRectEqualToRect(_field.frame,rect)) _field.frame = rect;
}
@end

UIView *CP26ReferenceCanvas(void) { return [CP26ReferenceBackdrop new]; }

UIView *CP26HitVisibleControl(UIView *v, UIView *space, CGPoint point, UIEvent *event) {
    UIWindow *window=[space isKindOfClass:UIWindow.class] ? (UIWindow *)space : space.window;
    if (!v || !v.window || v.window!=window || !v.userInteractionEnabled) return nil;
    for (UIView *a=v; a; a=a.superview) {
        if (a.hidden || a.alpha<=.01 || !a.userInteractionEnabled) return nil;
    }
    CGPoint local=[v convertPoint:point fromView:space];
    return CGRectContainsPoint(v.bounds,local) ? [v hitTest:local withEvent:event] : nil;
}
void CP26ReportHit(NSMutableString *out, NSString *role, UIView *v) {
    UIWindow *w=v.window;
    if (!w || v.hidden || CGRectIsEmpty(v.bounds)) return;
    CGRect box=[v convertRect:v.bounds toView:w];
    const CGPoint samples[]={{.5,.5},{.18,.5},{.82,.5}};
    unsigned hits=0;
    for (NSUInteger i=0;i<3;i++) {
        CGPoint p=CGPointMake(box.origin.x+box.size.width*samples[i].x,box.origin.y+box.size.height*samples[i].y);
        UIView *hit=[w hitTest:p withEvent:nil];
        if (hit==v || [hit isDescendantOfView:v]) hits|=1<<i;
    }
    [out appendFormat:@"HIT %@ frame=%@ centre=%d left=%d right=%d\n",role,NSStringFromCGRect(box),
        !!(hits&1),!!(hits&2),!!(hits&4)];
}

static char glassKey;
void CP26GlassPill(UIView *view, CGFloat radius) {
    if (!view) return;
    UIVisualEffectView *effect = objc_getAssociatedObject(view,&glassKey);
    if (!effect) {
        effect = [[UIVisualEffectView alloc] initWithEffect:
            [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark]];
        effect.userInteractionEnabled = NO; effect.accessibilityElementsHidden = YES;
        effect.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        effect.clipsToBounds = YES;
        effect.layer.cornerCurve = kCACornerCurveContinuous;
        effect.layer.borderColor = [UIColor colorWithWhite:1 alpha:.19].CGColor;
        effect.layer.borderWidth = .55;
        effect.contentView.backgroundColor = [UIColor colorWithWhite:.51 alpha:.12];
        [view insertSubview:effect atIndex:0];
        objc_setAssociatedObject(view,&glassKey,effect,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (!CGRectEqualToRect(effect.frame,view.bounds)) effect.frame=view.bounds;
    if (effect.layer.cornerRadius!=radius) effect.layer.cornerRadius=radius;
}
void CP26RemoveGlass(UIView *view) {
    [((UIView *)objc_getAssociatedObject(view,&glassKey)) removeFromSuperview];
    objc_setAssociatedObject(view,&glassKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@interface CP26PlacedViews ()
@property(nonatomic,strong) NSMapTable<UIView *,NSValue *> *original;
@property(nonatomic,strong) NSMapTable<UIView *,NSValue *> *applied;
@end
// UIKit may replace just a height or origin while our width is still applied.
// Reconcile each coordinate independently to retain the newest native layout.
static CGRect NativeRect(CGRect now, CGRect applied, CGRect original) {
    return CGRectMake(now.origin.x==applied.origin.x ? original.origin.x : now.origin.x,
        now.origin.y==applied.origin.y ? original.origin.y : now.origin.y,
        now.size.width==applied.size.width ? original.size.width : now.size.width,
        now.size.height==applied.size.height ? original.size.height : now.size.height);
}
@implementation CP26PlacedViews
- (instancetype)init {
    if ((self=[super init])) {
        _original=[NSMapTable weakToStrongObjectsMapTable];
        _applied=[NSMapTable weakToStrongObjectsMapTable];
    }
    return self;
}
- (void)place:(UIView *)view in:(UIView *)space rect:(CGRect)rect {
    if (!view.superview || !space || CGRectIsEmpty(rect) || !CGAffineTransformIsIdentity(view.transform)) return;
    CGRect dest = [space convertRect:rect toView:view.superview];
    NSValue *last = [_applied objectForKey:view];
    if (!last || !CGRectEqualToRect(last.CGRectValue,view.frame)) {
        CGRect base=last ? NativeRect(view.frame,last.CGRectValue,[_original objectForKey:view].CGRectValue) : view.frame;
        [_original setObject:[NSValue valueWithCGRect:base] forKey:view];
    }
    if (!CGRectEqualToRect(view.frame,dest)) view.frame=dest;
    [_applied setObject:[NSValue valueWithCGRect:view.frame] forKey:view];
}
- (void)restoreView:(UIView *)view {
    NSValue *old=[_original objectForKey:view], *last=[_applied objectForKey:view];
    if (old && last) {
        CGRect native=NativeRect(view.frame,last.CGRectValue,old.CGRectValue);
        if (!CGRectEqualToRect(view.frame,native)) view.frame=native;
        [view.superview setNeedsLayout];
    }
    [_original removeObjectForKey:view]; [_applied removeObjectForKey:view];
}
- (void)restore {
    for (UIView *view in _original.keyEnumerator.allObjects) [self restoreView:view];
}
@end
