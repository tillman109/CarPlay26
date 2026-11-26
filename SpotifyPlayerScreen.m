#import "SpotifyReference.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

typedef struct {
    double snapshotTime, startTime, endTime, duration, elapsedDuration;
    float rate, defaultRate;
    bool live, loading;
} CP26PlayerTime;

@protocol CP26PlaybackViews <NSObject>
@optional
- (UIView *)artworkViewBrick;
- (UIView *)songDetailsView;
- (UIView *)transportControlView;
- (UIView *)progressView;
- (UIView *)playModeControlView;
- (UIButton *)leftButton;
- (UIButton *)playPauseButton;
- (UIButton *)fastForwardButton;
- (UIStackView *)stackView;
- (UIView *)albumArtistLabelButton;
- (NSString *)trackTitle;
- (NSString *)artistName;
- (NSString *)albumTitle;
- (UIImage *)image;
- (UIImage *)artworkImage;
- (UIImageView *)imageView;
- (CP26PlayerTime)durationSnapshot;
- (BOOL)showsProgressLabels;
@end

// Map each displayed target into the original button's parent. The source
// keeps its constraints, recognizers, target/actions and focus identity.
static CGAffineTransform MapControl(CGRect bounds, CGPoint anchor, CGPoint position, CGRect target) {
    CGFloat sx=target.size.width/bounds.size.width, sy=target.size.height/bounds.size.height;
    return CGAffineTransformMake(sx,0,0,sy,
        target.origin.x+anchor.x*target.size.width-position.x,
        target.origin.y+anchor.y*target.size.height-position.y);
}
static CGRect CenterBox(CGFloat x, CGFloat y, CGFloat width, CGFloat height, CGFloat ux, CGFloat uy) {
    return CGRectMake((x-width*.5)*ux,(y-height*.5)*uy,width*ux,height*uy);
}
static CGRect MainTarget(NSUInteger i, CGFloat ux, CGFloat uy) {
    return CenterBox(73+127*i,295,56,40,ux,uy);
}
static CGRect ModeTarget(NSUInteger i, NSUInteger count, CGFloat ux, CGFloat uy) {
    CGFloat gap=MIN(42.5,342.0/MAX((CGFloat)count,1));
    return CenterBox(200+((CGFloat)i-((CGFloat)count-1)*.5)*gap,351,MIN(40,gap*.97),29,ux,uy);
}
static BOOL Offered(UIView *v, UIView *host) {
    if (!v || !v.superview) return NO;
    for (UIView *p=v; p; p=p.superview) {
        if (p.hidden || p.alpha<=.01) return NO;
        if (p==host) return YES;
    }
    return NO;
}
static UIView *FindClass(UIView *v, Class cls, NSUInteger depth) {
    if (!v || depth>9) return nil;
    if ([v isKindOfClass:cls]) return v;
    for (UIView *child in v.subviews) {
        UIView *found=FindClass(child,cls,depth+1);
        if (found) return found;
    }
    return nil;
}
static void CollectButtons(UIView *v, NSSet *skip, NSMutableArray<UIButton *> *out) {
    if (!v || v.hidden || v.alpha<=.01 || [skip containsObject:v]) return;
    if ([v isKindOfClass:UIButton.class]) { [out addObject:(UIButton *)v]; return; }
    NSArray *children=[v isKindOfClass:UIStackView.class] ? ((UIStackView *)v).arrangedSubviews : v.subviews;
    for (UIView *child in children) CollectButtons(child,skip,out);
}
static void CollectLabels(UIView *v, NSMutableArray<UILabel *> *out) {
    if (!v || v.hidden || v.alpha<=.01) return;
    if ([v isKindOfClass:UILabel.class]) { [out addObject:(UILabel *)v]; return; }
    for (UIView *child in v.subviews) CollectLabels(child,out);
}
static UIView *InteractiveSeek(UIView *v) {
    if (!v || v.hidden || v.alpha<=.01 || !v.userInteractionEnabled) return nil;
    if ([v isKindOfClass:UIControl.class]) return v;
    for (UIGestureRecognizer *gr in v.gestureRecognizers) if (gr.enabled) return v;
    for (UIView *child in v.subviews) {
        UIView *hit=InteractiveSeek(child);
        if (hit) return hit;
    }
    return nil;
}
static UILabel *PlayerLabel(CGFloat weight) {
    UILabel *label=[UILabel new];
    label.textAlignment=NSTextAlignmentCenter; label.textColor=UIColor.whiteColor;
    label.font=[UIFont systemFontOfSize:11 weight:weight];
    label.adjustsFontSizeToFitWidth=YES; label.minimumScaleFactor=.8; return label;
}
static UIImage *ButtonImage(UIButton *b) {
    return b.currentImage ?: b.configuration.image ?: b.imageView.image;
}

@interface CP26ControlTarget ()
@property(nonatomic,weak,readwrite) UIView *source;
@property(nonatomic) CGAffineTransform original, applied;
@property(nonatomic) BOOL projected;
@end
@implementation CP26ControlTarget
- (void)restore {
    UIView *v=_source;
    if (_projected && v && CGAffineTransformEqualToTransform(v.transform,_applied)) v.transform=_original;
    _projected=NO;
}
- (void)bind:(UIView *)v {
    if (_source==v) return;
    [self restore]; _source=v;
}
- (void)project {
    UIView *v=_source;
    if (!v.superview || !self.window || v.window!=self.window || CGRectIsEmpty(v.bounds) || CGRectIsEmpty(self.bounds)) return;
    if (!_projected || !CGAffineTransformEqualToTransform(v.transform,_applied)) _original=v.transform;
    CGRect target=[self convertRect:self.bounds toView:v.superview];
    if (CGRectIsEmpty(target) || CGRectIsInfinite(target)) return;
    CGAffineTransform t=MapControl(v.bounds,v.layer.anchorPoint,v.layer.position,target);
    if (!CGAffineTransformEqualToTransform(t,v.transform)) v.transform=t;
    _applied=t; _projected=YES;
}
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.hidden || !CGRectContainsPoint(self.bounds,point) || !_source) return nil;
    [self project];
    return CP26HitVisibleControl(_source,self,point,event);
}
- (void)dealloc { [self restore]; }
@end

@interface CP26PlayerSlot : CP26ControlTarget
@property(nonatomic,strong) UIImageView *glyph;
@property(nonatomic,strong) UILabel *caption;
@property(nonatomic,strong) UIImage *originalGlyph;
@property(nonatomic,strong) UIView *bezel;
@end
@implementation CP26PlayerSlot
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self=[super initWithFrame:frame])) {
        self.isAccessibilityElement=NO;
        _bezel=[UIView new]; _bezel.userInteractionEnabled=NO; _bezel.layer.cornerCurve=kCACornerCurveContinuous;
        _glyph=[UIImageView new]; _glyph.contentMode=UIViewContentModeScaleAspectFit;
        _glyph.tintColor=UIColor.whiteColor;
        _caption=PlayerLabel(UIFontWeightSemibold); _caption.userInteractionEnabled=NO;
        [self addSubview:_bezel]; [self addSubview:_glyph]; [self addSubview:_caption];
    }
    return self;
}
@end

@interface CP26PlayerSurface : UIView
@property(nonatomic,weak) UIViewController *controller;
@property(nonatomic,weak) UIView *host;
@property(nonatomic,strong) UIImageView *wash, *cover;
@property(nonatomic,strong) UIVisualEffectView *blur;
@property(nonatomic,strong) UILabel *song, *artist, *album, *elapsed, *remaining;
@property(nonatomic,strong) UIView *rail, *fill, *thumb;
@property(nonatomic,strong) NSMutableArray<CP26PlayerSlot *> *main, *modes;
@property(nonatomic,strong) CP26PlayerSlot *seek, *albumTap;
@property(nonatomic,strong) NSTimer *timer;
@property(nonatomic) BOOL applying, lyricsVisible;
@property(nonatomic,weak) UIViewController *nativeOwner;
@property(nonatomic,weak) UIControl *microphone;
@end
static char playerKey, hostKey;
static NSHashTable<UIViewController *> *controllers;

static UIImage *CurrentArt(UIView *brick, UIView *host) {
    id<CP26PlaybackViews> art=(id)brick;
    UIImage *cover=[art respondsToSelector:@selector(image)] ? art.image : nil;
    if (!cover && [art respondsToSelector:@selector(imageView)]) cover=art.imageView.image;
    if (!cover) {
        for (UIResponder *r=host.nextResponder; r; r=r.nextResponder) {
            if (![r respondsToSelector:@selector(artworkImage)]) continue;
            cover=[(id<CP26PlaybackViews>)r artworkImage];
            if (cover) break;
        }
    }
    return cover;
}
static BOOL PlayerFront(UIViewController *vc) {
    if (!vc.viewIfLoaded.window || vc.presentedViewController.viewIfLoaded.window) return NO;
    UIViewController *top=vc.navigationController.topViewController;
    if (!top) return YES;
    for (UIViewController *p=vc; p; p=p.parentViewController) if (p==top) return YES;
    return NO;
}
// carLy stores its customizer on CPUINowPlayingViewController, which can
// be a child of the template controller. This lookup never attaches one.
@protocol CP26LyricsLayout <NSObject>
@optional
+ (id)customizerForViewController:(UIViewController *)owner create:(BOOL)create;
- (BOOL)isFullScreen;
- (CGFloat)playerColumnWidth;
- (CGFloat)playerStripHeight;
- (UIButton *)microphoneButton;
@end
static UIViewController *NativeOwner(UIView *host, UIViewController *outer) {
    for (UIResponder *r=host; r; r=r.nextResponder)
        if ([r isKindOfClass:NSClassFromString(@"CPUINowPlayingViewController")]) return (UIViewController *)r;
    return outer;
}
static void Unmount(UIViewController *vc) {
    CP26PlayerSurface *s=objc_getAssociatedObject(vc,&playerKey);
    if (!s) return;
    [s.timer invalidate];
    [s.microphone removeTarget:s action:@selector(micAction:) forControlEvents:UIControlEventTouchUpInside | UIControlEventPrimaryActionTriggered];
    for (CP26PlayerSlot *slot in s.main) [slot restore];
    for (CP26PlayerSlot *slot in s.modes) [slot restore];
    [s.seek restore]; [s.albumTap restore];
    objc_setAssociatedObject(s.host,&hostKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [s removeFromSuperview]; [controllers removeObject:vc];
    objc_setAssociatedObject(vc,&playerKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static void SetFrame(UIView *view, CGRect frame) {
    if (!CGRectEqualToRect(view.frame,frame)) view.frame=frame;
}
static void Label(UILabel *v, NSString *text, CGRect rect, UIFont *font) {
    if (![v.text isEqualToString:text]) v.text=text;
    if (![v.font isEqual:font]) v.font=font;
    SetFrame(v,rect);
}
static BOOL TimeText(NSString *s, double *seconds) {
    if (!s.length) return NO;
    NSCharacterSet *nonDigits=NSCharacterSet.decimalDigitCharacterSet.invertedSet;
    s=[s stringByTrimmingCharactersInSet:nonDigits];
    NSArray *parts=[s componentsSeparatedByString:@":"];
    if (parts.count<2 || parts.count>3) return NO;
    double value=0;
    for (NSString *p in parts) {
        if (!p.length || [p rangeOfCharacterFromSet:nonDigits].location!=NSNotFound) return NO;
        value=60*value+p.integerValue;
    }
    *seconds=value; return YES;
}
static NSString *ClockText(double seconds, BOOL negative) {
    NSInteger t=(NSInteger)floor(MAX(0,seconds));
    NSString *clock=t>=3600 ? [NSString stringWithFormat:@"%ld:%02ld:%02ld",(long)(t/3600),(long)(t/60%60),(long)(t%60)] :
        [NSString stringWithFormat:@"%ld:%02ld",(long)(t/60),(long)(t%60)];
    return negative ? [@"−" stringByAppendingString:clock] : clock;
}
@implementation CP26PlayerSurface
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self=[super initWithFrame:frame])) {
        self.opaque=YES; self.clipsToBounds=YES;
        self.accessibilityElementsHidden=YES; // original CarPlay controls remain the focus elements
        self.backgroundColor=[UIColor colorWithRed:.17 green:.16 blue:.19 alpha:1];
        _wash=[UIImageView new]; _wash.contentMode=UIViewContentModeScaleAspectFill;
        _wash.clipsToBounds=YES; [self addSubview:_wash];
        _blur=[[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
        _blur.userInteractionEnabled=NO;
        _blur.contentView.backgroundColor=[UIColor colorWithRed:.10 green:.09 blue:.12 alpha:.34];
        [self addSubview:_blur];
        _cover=[UIImageView new]; _cover.clipsToBounds=YES; _cover.contentMode=UIViewContentModeScaleAspectFill;
        _song=PlayerLabel(UIFontWeightSemibold); _artist=PlayerLabel(UIFontWeightRegular); _album=PlayerLabel(UIFontWeightRegular);
        _album.textColor=[UIColor colorWithWhite:1 alpha:.72];
        _elapsed=PlayerLabel(UIFontWeightRegular); _remaining=PlayerLabel(UIFontWeightRegular);
        _elapsed.textAlignment=NSTextAlignmentRight; _remaining.textAlignment=NSTextAlignmentLeft;
        _rail=[UIView new]; _rail.backgroundColor=[UIColor colorWithWhite:1 alpha:.27];
        _fill=[UIView new]; _fill.backgroundColor=UIColor.whiteColor;
        _thumb=[UIView new]; _thumb.backgroundColor=UIColor.whiteColor;
        for (UIView *v in @[_cover,_song,_artist,_album,_elapsed,_remaining,_rail,_fill,_thumb]) {
            v.userInteractionEnabled=NO; [self addSubview:v];
        }
        _seek=[CP26PlayerSlot new]; _albumTap=[CP26PlayerSlot new];
        [self addSubview:_seek]; [self addSubview:_albumTap];
        _main=[NSMutableArray array]; _modes=[NSMutableArray array];
    }
    return self;
}
- (void)drawButton:(UIButton *)b slot:(CP26PlayerSlot *)slot frame:(CGRect)frame symbol:(NSString *)fallback mode:(BOOL)mode ux:(CGFloat)u {
    [slot bind:b]; SetFrame(slot,frame); slot.hidden=!b;
    if (!b) return;
    [slot project];
    CGRect bounds=slot.bounds;
    CGFloat size=(mode ? 12.3 : 20.5)*u;
    UIImage *image=ButtonImage(b);
    if (!image && fallback) image=[UIImage systemImageNamed:fallback];
    if (slot.originalGlyph!=image) {
        slot.originalGlyph=image;
        slot.glyph.image=image && image.renderingMode!=UIImageRenderingModeAlwaysTemplate ?
            [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] : image;
    }
    // 'currentImage' may be original artwork supplied by the app. Render the
    // button glyph with the same monochrome treatment as the reference.
    slot.glyph.tintColor=(mode && b.selected) ? [UIColor colorWithWhite:.13 alpha:1] : UIColor.whiteColor;
    NSString *title=b.currentTitle ?: b.currentAttributedTitle.string ?: b.configuration.title;
    Label(slot.caption,image ? nil : title,slot.bounds,[UIFont systemFontOfSize:10*u weight:UIFontWeightSemibold]);
    slot.caption.textColor=slot.glyph.tintColor;
    SetFrame(slot.glyph,CGRectMake((bounds.size.width-size*1.16)/2,(bounds.size.height-size)/2,size*1.16,size));
    BOOL show=b.isFocused || b.highlighted || (mode && b.selected);
    slot.bezel.hidden=!show;
    CGFloat bw=MIN(bounds.size.width,(mode ? 33.5 : 42)*u), bh=MIN(bounds.size.height,(mode ? 21.5 : 27)*u);
    SetFrame(slot.bezel,CGRectMake((bounds.size.width-bw)/2,(bounds.size.height-bh)/2,bw,bh));
    slot.bezel.layer.cornerRadius=bh/2;
    slot.bezel.backgroundColor=[UIColor colorWithWhite:1 alpha:mode && b.selected ? .57 : .20];
    slot.alpha=b.enabled ? (mode && !show ? .78 : 1) : .38;
}
- (void)resizeSlots:(NSMutableArray<CP26PlayerSlot *> *)slots count:(NSUInteger)count {
    while (slots.count>count) {
        CP26PlayerSlot *slot=slots.lastObject; [slot bind:nil]; [slot removeFromSuperview]; [slots removeLastObject];
    }
    while (slots.count<count) {
        CP26PlayerSlot *slot=[CP26PlayerSlot new]; [slots addObject:slot]; [self addSubview:slot];
    }
}
- (void)progress:(UIView *)progress ux:(CGFloat)ux uy:(CGFloat)uy {
    BOOL available=Offered(progress,self.host);
    CGFloat fraction=0;
    NSString *left=nil,*right=nil;
    CP26PlayerTime snapshot={0};
    if ([progress respondsToSelector:@selector(durationSnapshot)]) snapshot=[(id<CP26PlaybackViews>)progress durationSnapshot];
    BOOL timed=isfinite(snapshot.duration) && snapshot.duration>0 && !snapshot.live;
    if (timed) {
        double e=isfinite(snapshot.elapsedDuration) ? snapshot.elapsedDuration : 0;
        fraction=MAX(0,MIN(1,e/snapshot.duration));
        left=ClockText(e,NO); right=ClockText(snapshot.duration-e,YES);
    }
    NSMutableArray<UILabel *> *labels=[NSMutableArray array];
    CollectLabels(progress,labels);
    double elapsed=-1,remaining=-1;
    for (UILabel *label in labels) {
        double t=0;
        if (TimeText(label.text,&t)) {
            CGFloat x=[label convertPoint:CGPointMake(CGRectGetMidX(label.bounds),0) toView:progress].x;
            if (x<CGRectGetMidX(progress.bounds)) { left=label.text; elapsed=t; }
            else { right=label.text; remaining=t; }
        } else if (snapshot.live && label.text.length) left=label.text;
    }
    if (elapsed>=0 && remaining>=0 && elapsed+remaining>0) fraction=elapsed/(elapsed+remaining);
    UISlider *slider=(UISlider *)FindClass(progress,UISlider.class,0);
    if (slider.maximumValue>slider.minimumValue) fraction=MAX(0,MIN(1,(slider.value-slider.minimumValue)/(slider.maximumValue-slider.minimumValue)));
    BOOL track=available && !snapshot.live && (timed || elapsed>=0 || slider);
    self.rail.hidden=self.fill.hidden=self.thumb.hidden=!track;
    CGFloat y=326*uy, x=46*ux, width=308*ux, line=4.4*ux, thumb=14*ux;
    SetFrame(_rail,CGRectMake(x,y-line/2,width,line)); _rail.layer.cornerRadius=line/2;
    SetFrame(_fill,CGRectMake(x,y-line/2,width*fraction,line)); _fill.layer.cornerRadius=line/2;
    SetFrame(_thumb,CGRectMake(x+MIN(width-thumb,MAX(0,width*fraction-thumb/2)),y-3.6*ux,thumb,7.2*ux)); _thumb.layer.cornerRadius=3.6*ux;
    UIFont *font=[UIFont monospacedDigitSystemFontOfSize:9.2*ux weight:UIFontWeightRegular];
    Label(_elapsed,available ? left : nil,CGRectMake(1*ux,y-9*uy,39*ux,18*uy),font);
    Label(_remaining,available ? right : nil,CGRectMake(359*ux,y-9*uy,40*ux,18*uy),font);
    UIView *source=track ? InteractiveSeek(progress) : nil;
    [_seek bind:source]; _seek.hidden=!source;
    SetFrame(_seek,CGRectMake(x,y-9*uy,width,18*uy)); [_seek project];
}
- (void)micAction:(UIControl *)sender {
    __weak CP26PlayerSurface *weak=self;
    dispatch_async(dispatch_get_main_queue(), ^{ [weak refresh]; });
}
- (BOOL)updateLyricsPresentation {
    Class cls=NSClassFromString(@"CLLayoutCustomizer");
    id<CP26LyricsLayout> layout=[cls respondsToSelector:@selector(customizerForViewController:create:)] ?
        [(Class<CP26LyricsLayout>)cls customizerForViewController:_nativeOwner create:NO] : nil;
    UIControl *mic=[layout respondsToSelector:@selector(microphoneButton)] ? layout.microphoneButton : nil;
    if (_microphone!=mic) {
        UIControlEvents events=UIControlEventTouchUpInside | UIControlEventPrimaryActionTriggered;
        [_microphone removeTarget:self action:@selector(micAction:) forControlEvents:events];
        _microphone=mic; [mic addTarget:self action:@selector(micAction:) forControlEvents:events];
    }
    BOOL shown=_host.hidden || ([layout respondsToSelector:@selector(isFullScreen)] && layout.isFullScreen) ||
        ([layout respondsToSelector:@selector(playerColumnWidth)] && layout.playerColumnWidth>0) ||
        ([layout respondsToSelector:@selector(playerStripHeight)] && layout.playerStripHeight>0);
    if (!shown) for (UIView *v in _nativeOwner.viewIfLoaded.subviews)
        if (!v.hidden && v.alpha>.01 && [v isKindOfClass:NSClassFromString(@"CLLyricsFullScreenView")]) { shown=YES; break; }
    if (_lyricsVisible!=shown) {
        _lyricsVisible=shown;
        if (shown) {
            for (CP26PlayerSlot *slot in _main) [slot restore];
            for (CP26PlayerSlot *slot in _modes) [slot restore];
            [_seek restore]; [_albumTap restore];
        }
        self.hidden=shown;
    }
    return shown;
}
- (void)refresh {
    UIView *v=_host;
    if (!v || _applying || !self.window) return;
    _applying=YES;
    if ([self updateLyricsPresentation]) { _applying=NO; return; }
    CGFloat w=self.bounds.size.width,h=self.bounds.size.height, ux=w/400,uy=h/381.5;
    id<CP26PlaybackViews> host=(id)v;
    UIView *brick=host.artworkViewBrick, *details=host.songDetailsView, *transport=host.transportControlView;
    UIView *mode=host.playModeControlView, *progress=host.progressView;
    UIImage *art=CurrentArt(brick,v);
    SetFrame(_wash,self.bounds); SetFrame(_blur,self.bounds);
    if (_cover.image!=art) { _cover.image=art; _wash.image=art; }
    CGFloat side=MIN(172*ux,172*uy);
    SetFrame(_cover,CGRectMake((w-side)*.5,39*uy,side,side)); _cover.layer.cornerRadius=4.5*ux;
    id<CP26PlaybackViews> d=(id)details;
    NSString *song=[d respondsToSelector:@selector(trackTitle)] ? d.trackTitle : nil;
    NSString *artist=[d respondsToSelector:@selector(artistName)] ? d.artistName : nil;
    NSString *album=[d respondsToSelector:@selector(albumTitle)] ? d.albumTitle : nil;
    UIView *albumAction=[d respondsToSelector:@selector(albumArtistLabelButton)] ? d.albumArtistLabelButton : nil;
    if (!song.length) {
        NSMutableArray<UILabel *> *labels=[NSMutableArray array]; CollectLabels(details,labels);
        for (UILabel *l in labels) if (l.text.length && ![l.text isEqual:artist] && ![l.text isEqual:album]) { song=l.text; break; }
    }
    Label(_song,song,CenterBox(200,227,364,16,ux,uy),[UIFont systemFontOfSize:12.4*ux weight:UIFontWeightSemibold]);
    Label(_artist,artist,CenterBox(200,240,364,12,ux,uy),[UIFont systemFontOfSize:9.6*ux]);
    BOOL open=Offered(albumAction,v) && album.length && ([albumAction isKindOfClass:UIControl.class] || albumAction.gestureRecognizers.count);
    NSString *albumLine=(open && album.length) ? [album stringByAppendingString:@"  ›"] : album;
    Label(_album,albumLine,CenterBox(200,251.5,364,12,ux,uy),[UIFont systemFontOfSize:9.5*ux]);
    [_albumTap bind:open ? albumAction : nil]; _albumTap.hidden=!open;
    CGFloat labelWidth=MIN(300*ux,MAX(46*ux,[_album sizeThatFits:CGSizeMake(w,18*uy)].width+12*ux));
    SetFrame(_albumTap,CGRectMake((w-labelWidth)*.5,244.5*uy,labelWidth,17*uy)); [_albumTap project];

    id<CP26PlaybackViews> t=(id)transport;
    NSArray *primary=@[t.leftButton ?: (id)NSNull.null,t.playPauseButton ?: (id)NSNull.null,t.fastForwardButton ?: (id)NSNull.null];
    [self resizeSlots:_main count:3];
    for (NSUInteger i=0;i<3;i++) {
        UIButton *button=primary[i]==NSNull.null ? nil : primary[i];
        NSString *fallback=i==0 ? @"backward.fill" : i==2 ? @"forward.fill" : nil;
        if (i==1 && !ButtonImage(button) && [progress respondsToSelector:@selector(durationSnapshot)])
            fallback=[(id<CP26PlaybackViews>)progress durationSnapshot].rate>0 ? @"pause.fill" : @"play.fill";
        [self drawButton:Offered(button,v) ? button : nil slot:_main[i] frame:MainTarget(i,ux,uy) symbol:fallback mode:NO ux:ux];
    }
    NSMutableArray<UIButton *> *buttons=[NSMutableArray array];
    if (Offered(mode,v)) CollectButtons(mode,nil,buttons);
    NSMutableSet *skip=[NSMutableSet setWithObjects:self,brick,details,transport,nil];
    if (mode) [skip addObject:mode];
    if (progress) [skip addObject:progress];
    CollectButtons(v,skip,buttons);
    // Restore previous projections before a mode is removed or moved to a
    // different slot; the same native button can change position after a tap.
    for (NSUInteger i=0;i<_modes.count;i++)
        if (i>=buttons.count || _modes[i].source!=buttons[i]) [_modes[i] bind:nil];
    [self resizeSlots:_modes count:buttons.count];
    for (NSUInteger i=0;i<buttons.count;i++)
        [self drawButton:buttons[i] slot:_modes[i] frame:ModeTarget(i,buttons.count,ux,uy) symbol:nil mode:YES ux:ux];
    [self progress:progress ux:ux uy:uy];
    _applying=NO;
}
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.hidden || !CGRectContainsPoint(self.bounds,point) || !PlayerFront(self.controller) ||
        [self updateLyricsPresentation]) return nil;
    // The glass is in front of the native body. Route to the original view
    // directly because its old parent may no longer enclose the new target.
    for (UIView *slot in self.subviews.reverseObjectEnumerator) {
        if (![slot isKindOfClass:CP26PlayerSlot.class] || slot.hidden) continue;
        UIView *hit=[slot hitTest:[slot convertPoint:point fromView:self] withEvent:event];
        if (hit) return hit;
    }
    return self; // the original grey rectangles underneath have no active area
}
@end

void CP26PlayerLayout(UIViewController *vc, BOOL enabled) {
    if (!vc || !NSThread.isMainThread) return;
    UIWindow *win=vc.viewIfLoaded.window;
    CP26PlayerSurface *s=objc_getAssociatedObject(vc,&playerKey);
    if (s.applying) return;
    CGFloat w=win.bounds.size.width,h=win.bounds.size.height;
    if (!enabled || !PlayerFront(vc) || !win || win.hidden || w<320 || w>560 || h<w ||
        ![win.windowScene.session.role isEqualToString:@"UIWindowSceneSessionRoleCarPlay"]) { Unmount(vc); return; }
    UIView *host=s.host ?: FindClass(vc.viewIfLoaded,NSClassFromString(@"CPUINowPlayingView"),0);
    id<CP26PlaybackViews> hv=(id)host;
    if (![hv respondsToSelector:@selector(transportControlView)] || ![hv respondsToSelector:@selector(artworkViewBrick)] ||
        ![hv respondsToSelector:@selector(songDetailsView)] || ![hv respondsToSelector:@selector(progressView)] ||
        ![hv respondsToSelector:@selector(playModeControlView)]) { Unmount(vc); return; }
    id<CP26PlaybackViews> t=(id)hv.transportControlView;
    if (![t respondsToSelector:@selector(leftButton)] || ![t respondsToSelector:@selector(fastForwardButton)] ||
        ![t respondsToSelector:@selector(playPauseButton)] || !t.playPauseButton.superview || CGRectIsEmpty(t.playPauseButton.bounds) ||
        !hv.songDetailsView || !hv.artworkViewBrick) { Unmount(vc); return; }
    UINavigationBar *bar=vc.navigationController.navigationBar;
    UIView *parent=bar.window==win && bar.superview==vc.navigationController.viewIfLoaded && !bar.hidden ? bar.superview : vc.viewIfLoaded;
    if (!s) {
        s=[CP26PlayerSurface new]; s.host=host; s.controller=vc; s.nativeOwner=NativeOwner(host,vc);
        objc_setAssociatedObject(vc,&playerKey,s,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(host,&hostKey,s,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (!controllers) controllers=[NSHashTable weakObjectsHashTable]; [controllers addObject:vc];
        __weak UIViewController *weak=vc;
        s.timer=[NSTimer scheduledTimerWithTimeInterval:.32 repeats:YES block:^(NSTimer *timer) {
            UIViewController *owner=weak;
            if (!owner) { [timer invalidate]; return; }
            if (!PlayerFront(owner)) { Unmount(owner); return; }
            CP26PlayerSurface *face=objc_getAssociatedObject(owner,&playerKey);
            [face refresh];
        }];
        s.timer.tolerance=.06;
    }
    UIView *root=s.nativeOwner.viewIfLoaded, *branch=host;
    while (branch && branch.superview!=root) branch=branch.superview;
    CGRect box=[root convertRect:root.bounds toView:win];
    CGRect body=CGRectMake(0,0,w,h-43*w/400);
    if (branch && root.window==win && CGRectGetMinX(box)<=1 && CGRectGetMaxX(box)>=w-1 &&
        (!root.clipsToBounds || CGRectContainsRect(CGRectInset(box,-1,-1),body))) parent=root;
    if (s.superview!=parent) {
        if (parent==root && branch) [parent insertSubview:s aboveSubview:branch];
        else if (parent==bar.superview) [parent insertSubview:s belowSubview:bar];
        else [parent addSubview:s];
    }
    SetFrame(s,[parent convertRect:CGRectMake(0,0,w,h-43*w/400) fromView:win]);
    [s refresh];
}
void CP26PlayerViewLaidOut(UIView *host) {
    CP26PlayerSurface *s=objc_getAssociatedObject(host,&hostKey);
    if (s && !s.applying) CP26PlayerLayout(s.controller,YES);
}
void CP26RestorePlayers(void) {
    for (UIViewController *vc in controllers.allObjects) Unmount(vc);
}
void CP26FullPlayerReport(NSMutableString *out) {
    for (UIViewController *vc in controllers.allObjects) {
        CP26PlayerSurface *s=objc_getAssociatedObject(vc,&playerKey);
        if (!s.window) continue;
        [out appendFormat:@"PLAYER artwork=%@ progress=%@ albumBlur=%d modeCount=%lu\n",
            NSStringFromCGRect([s.cover convertRect:s.cover.bounds toView:s.window]),
            NSStringFromCGRect([s.rail convertRect:s.rail.bounds toView:s.window]),s.cover.image!=nil,(unsigned long)s.modes.count];
        [out appendFormat:@"LYRICS ownsPlayer=%d visibleSurface=%d\n",s.lyricsVisible,!s.hidden];
        if (s.lyricsVisible) continue;
        NSArray *names=@[@"previous",@"play/pause",@"next"];
        for (NSUInteger i=0;i<s.main.count;i++) CP26ReportHit(out,names[i],s.main[i].source);
        for (NSUInteger i=0;i<s.modes.count;i++) CP26ReportHit(out,[NSString stringWithFormat:@"mode %lu",(unsigned long)i],s.modes[i].source);
        CP26ReportHit(out,@"seek",s.seek.source); CP26ReportHit(out,@"album",s.albumTap.source);
    }
}
