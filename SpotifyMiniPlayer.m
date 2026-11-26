#import "SpotifyReference.h"
#import <CoreFoundation/CoreFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <ImageIO/ImageIO.h>

// Access only the active CarPlay model. Several of these getters differ
// between host versions, so each optional selector is tested before use.
typedef struct {
    double snapshotTime, startTime, endTime, duration, elapsedDuration;
    float rate, defaultRate;
    bool live, loading;
} CP26DurationSnapshot;

@protocol CP26MediaModel <NSObject>
@optional
+ (id)sharedManager;
- (id)nowPlayingManager;
- (id)snapshot;
- (CP26DurationSnapshot)durationSnapshot;
- (NSString *)bundleIdentifier;
- (NSString *)title;
- (NSString *)artist;
- (NSString *)album;
- (id)artworkCatalog;
- (void)requestImageWithCompletion:(void (^)(UIImage *))completion;
- (id)response;
- (id)tracklist;
- (id)changeItemCommand;
- (id)nextItem;
- (id)play;
- (id)pause;
- (BOOL)shouldEnableNextButton;
- (void)performCommandRequest:(id)request completion:(void (^)(void))completion;
- (void)_nowPlayingButtonTapped;
@end

static char miniKey;
static NSHashTable *players;
static NSString *const spotifyID = @"com.spotify.client";
typedef void (*GetClient)(dispatch_queue_t,void (^)(CFTypeRef));
typedef CFStringRef (*GetBundleID)(CFTypeRef);
typedef void (*GetInfo)(dispatch_queue_t,void (^)(CFDictionaryRef));
typedef void (*GetPlaying)(dispatch_queue_t,void (^)(Boolean));
typedef Boolean (*SendCommand)(int,CFDictionaryRef);
static GetClient getClient;
static GetBundleID bundleID;
static GetPlaying getPlaying;
static GetInfo getInfo;
static SendCommand sendCommand;
static NSString *titleKey, *artistKey, *artworkKey;
static NSMutableArray<NSString *> *changeNames;

static void LoadPlaybackAPI(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSBundle *bundle = [NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/MediaRemote.framework"];
        if (!bundle.loaded && ![bundle load]) return;
        CFBundleRef cf = CFBundleGetBundleWithIdentifier((__bridge CFStringRef)bundle.bundleIdentifier);
        if (!cf) return;
        CFStringRef *titleSymbol=(CFStringRef *)CFBundleGetDataPointerForName(cf,CFSTR("kMRMediaRemoteNowPlayingInfoTitle"));
        CFStringRef *artSymbol=(CFStringRef *)CFBundleGetDataPointerForName(cf,CFSTR("kMRMediaRemoteNowPlayingInfoArtworkData"));
        titleKey=titleSymbol && *titleSymbol ? (__bridge NSString *)*titleSymbol : @"kMRMediaRemoteNowPlayingInfoTitle";
        artworkKey=artSymbol && *artSymbol ? (__bridge NSString *)*artSymbol : @"kMRMediaRemoteNowPlayingInfoArtworkData";
        CFStringRef *artist=(CFStringRef *)CFBundleGetDataPointerForName(cf,CFSTR("kMRMediaRemoteNowPlayingInfoArtist"));
        artistKey=artist && *artist ? (__bridge NSString *)*artist : @"kMRMediaRemoteNowPlayingInfoArtist";
        changeNames=[NSMutableArray array];
        for (NSString *key in @[@"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
             @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
             @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification"]) {
            CFStringRef *name=(CFStringRef *)CFBundleGetDataPointerForName(cf,(__bridge CFStringRef)key);
            if (name && *name) [changeNames addObject:(__bridge NSString *)*name];
        }
        // The template host is already a Now Playing consumer. Observe deliveries
        // it receives without registering/unregistering its process-wide service.

        getClient = (GetClient)CFBundleGetFunctionPointerForName(cf,CFSTR("MRMediaRemoteGetNowPlayingClient"));
        bundleID = (GetBundleID)CFBundleGetFunctionPointerForName(cf,CFSTR("MRNowPlayingClientGetBundleIdentifier"));
        getInfo = (GetInfo)CFBundleGetFunctionPointerForName(cf,CFSTR("MRMediaRemoteGetNowPlayingInfo"));
        getPlaying = (GetPlaying)CFBundleGetFunctionPointerForName(cf,CFSTR("MRMediaRemoteGetNowPlayingApplicationIsPlaying"));
        sendCommand = (SendCommand)CFBundleGetFunctionPointerForName(cf,CFSTR("MRMediaRemoteSendCommand"));
    });
}

static UITabBarController *Owner(UIView *bar) {
    for (UIResponder *r=bar; r; r=r.nextResponder)
        if ([r isKindOfClass:UITabBarController.class] && ((UITabBarController *)r).tabBar==bar)
            return (UITabBarController *)r;
    return nil;
}

static id<CP26MediaModel> Manager(UIView *bar, UIViewController *context) {
    UIViewController *vc=context ?: Owner(bar).selectedViewController;
    if ([vc isKindOfClass:UINavigationController.class]) vc=((UINavigationController *)vc).topViewController;
    id<CP26MediaModel> host=(id)vc;
    id manager=[host respondsToSelector:@selector(nowPlayingManager)] ? [host nowPlayingManager] : nil;
    if (!manager) {
        Class cls=NSClassFromString(@"CPUINowPlayingManager");
        if ([cls respondsToSelector:@selector(sharedManager)]) manager=[(id)cls sharedManager];
    }
    return manager;
}

static id<CP26MediaModel> Snapshot(id<CP26MediaModel> manager) {
    id<CP26MediaModel> snapshot=[manager respondsToSelector:@selector(snapshot)] ? manager.snapshot : nil;
    NSString *owner=[snapshot respondsToSelector:@selector(bundleIdentifier)] ? snapshot.bundleIdentifier : nil;
    if (!owner.length && [manager respondsToSelector:@selector(bundleIdentifier)]) owner=manager.bundleIdentifier;
    return [owner isEqualToString:spotifyID] ? snapshot : nil;
}

static BOOL SpotifyClient(CFTypeRef client) {
    return client && bundleID && [(__bridge NSString *)bundleID(client) isEqualToString:spotifyID];
}

static NSString *HostTrack(id<CP26MediaModel> snapshot) {
    NSString *title=[snapshot respondsToSelector:@selector(title)] ? snapshot.title : nil;
    NSString *artist=[snapshot respondsToSelector:@selector(artist)] ? snapshot.artist : nil;
    return [NSString stringWithFormat:@"%@\n%@",title ?: @"",artist ?: @""];
}

@interface CP26MiniPlayer : UIView
@property(nonatomic,weak) UIView *bar;
@property(nonatomic,weak) UIViewController *context;
@property(nonatomic,weak) UIBarButtonItem *openItem;
@property(nonatomic,weak) UIControl *nativeButton;
@property(nonatomic,strong) UIView *glass;
@property(nonatomic,strong) UIButton *openButton, *transport, *next;
@property(nonatomic,strong) UIImageView *art;
@property(nonatomic,strong) UILabel *caption, *captionRepeat;
@property(nonatomic,strong) UIView *captionClip, *captionTrack;
@property(nonatomic,strong) CAGradientLayer *tickerMask;
@property(nonatomic,strong) CABasicAnimation *ticker;
@property(nonatomic) CGFloat captionWidth;
@property(nonatomic) CGFloat captionViewportWidth;
@property(nonatomic,strong) NSTimer *timer;
@property(nonatomic,copy) NSString *trackKey, *remoteTitle, *remoteArtist, *queriedHostTrack;
@property(nonatomic,strong) UIImage *remoteArt, *catalogArt;
@property(nonatomic,strong) NSData *lastData;
@property(nonatomic,strong) NSNumber *playing, *remotePlaying;
@property(nonatomic,strong) id catalog;
@property(nonatomic) BOOL remoteOwned, active, wanted, requestQueued;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) NSTimeInterval lastQuery;
@property(nonatomic,copy) NSString *symbol;
@property(nonatomic) CGFloat symbolSize;
@end

@implementation CP26MiniPlayer
- (UIButton *)button:(NSString *)label action:(SEL)action {
    UIButton *button=[UIButton buttonWithType:UIButtonTypeCustom];
    button.backgroundColor=UIColor.clearColor; button.opaque=NO;
    button.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
    button.tintColor=UIColor.whiteColor;
    button.accessibilityLabel=label;
    [button addTarget:self action:action forControlEvents:UIControlEventPrimaryActionTriggered];
    [self addSubview:button];
    return button;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self=[super initWithFrame:frame])) {
        _active=YES; _glass=[UIView new]; _glass.userInteractionEnabled=NO;
        [self addSubview:_glass];
        _openButton=[self button:@"Now Playing" action:@selector(open)];
        _transport=[self button:@"Play or pause" action:@selector(toggle)];
        _next=[self button:@"Next track" action:@selector(skip)];
        _art=[UIImageView new]; _art.clipsToBounds=YES; _art.layer.cornerRadius=3.5;
        _art.contentMode=UIViewContentModeScaleAspectFill; _art.userInteractionEnabled=NO;
        _captionClip=[UIView new]; _captionClip.clipsToBounds=YES;
        _captionClip.userInteractionEnabled=NO;
        _tickerMask=[CAGradientLayer layer];
        _tickerMask.startPoint=CGPointMake(0,.5); _tickerMask.endPoint=CGPointMake(1,.5);
        _tickerMask.colors=@[(id)UIColor.clearColor.CGColor,(id)UIColor.blackColor.CGColor,
            (id)UIColor.blackColor.CGColor,(id)UIColor.clearColor.CGColor];
        _tickerMask.locations=@[@0,@.07,@.93,@1];
        _captionClip.layer.mask=_tickerMask;
        _captionTrack=[UIView new]; _captionTrack.userInteractionEnabled=NO;
        _caption=[UILabel new]; _caption.textColor=UIColor.whiteColor;
        _caption.lineBreakMode=NSLineBreakByClipping; _caption.numberOfLines=1;
        _captionRepeat=[UILabel new]; _captionRepeat.textColor=UIColor.whiteColor;
        _captionRepeat.lineBreakMode=NSLineBreakByClipping; _captionRepeat.numberOfLines=1;
        [_captionTrack addSubview:_caption]; [_captionTrack addSubview:_captionRepeat];
        [_captionClip addSubview:_captionTrack];
        [_openButton addSubview:_art]; [_openButton addSubview:_captionClip];
        self.accessibilityElements=@[_openButton,_transport,_next];
        __weak CP26MiniPlayer *weakSelf=self;
        for (NSString *name in changeNames) [NSNotificationCenter.defaultCenter addObserver:self
            selector:@selector(playbackChanged:) name:name object:nil];
        // A coarse fallback covers host versions missing snapshot notifications.
        _timer=[NSTimer scheduledTimerWithTimeInterval:10 repeats:YES block:^(NSTimer *timer) {
            CP26MiniPlayer *player=weakSelf;
            if (!player) { [timer invalidate]; return; }
            if ([player barVisible])
                [player refreshRemote];
        }];
        _timer.tolerance=.5;
    }
    return self;
}
- (BOOL)barVisible {
    if (!self.active || !self.bar.window) return NO;
    for (UIView *v=self.bar; v; v=v.superview) if (v.hidden || v.alpha<.01) return NO;
    return YES;
}
- (void)playbackChanged:(NSNotification *)note { CP26InvalidatePlayback(); }
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; [_timer invalidate]; }
- (void)open {
    if (!self.wanted || ![self barVisible]) return;
    if (CP26ActivateBarItem(self.openItem,self.nativeButton)) return;
    id<CP26MediaModel> owner=(id)Owner(self.bar);
    if ([owner respondsToSelector:@selector(_nowPlayingButtonTapped)]) [owner _nowPlayingButtonTapped];
}
- (void)command:(BOOL)next {
    if (!self.wanted || ![self barVisible]) return;
    id<CP26MediaModel> manager=Manager(self.bar,self.context), snapshot=Snapshot(manager);
    id<CP26MediaModel> response=[snapshot respondsToSelector:@selector(response)] ? snapshot.response : nil;
    id request=nil;
    if (next) {
        if ([snapshot respondsToSelector:@selector(shouldEnableNextButton)] && !snapshot.shouldEnableNextButton) return;
        id<CP26MediaModel> list=[response respondsToSelector:@selector(tracklist)] ? response.tracklist : nil;
        id<CP26MediaModel> change=[list respondsToSelector:@selector(changeItemCommand)] ? list.changeItemCommand : nil;
        if ([change respondsToSelector:@selector(nextItem)]) request=[change nextItem];
    } else if (self.playing) {
        if (self.playing.boolValue && [response respondsToSelector:@selector(pause)]) request=[response pause];
        if (!self.playing.boolValue && [response respondsToSelector:@selector(play)]) request=[response play];
    }
    if (request && [manager respondsToSelector:@selector(performCommandRequest:completion:)]) {
        [manager performCommandRequest:request completion:^{
            dispatch_async(dispatch_get_main_queue(), ^{ [self refreshRemote]; });
        }];
    } else if (getClient && bundleID && sendCommand) {
        // Revalidate the actual playback client at the instant of the tap.
        getClient(dispatch_get_main_queue(), ^(CFTypeRef client) {
            if (![self barVisible] || !self.wanted || !SpotifyClient(client)) return;
            sendCommand(next ? 4 : 2,NULL);
            [self refreshRemote];
        });
    }
}
- (void)toggle { [self command:NO]; }
- (void)skip { [self command:YES]; }
- (void)refreshRemote {
    if (!self.active || !self.bar.window) return;
    self.lastQuery=CACurrentMediaTime();
    NSString *hostAtRequest=HostTrack(Snapshot(Manager(self.bar,self.context)));
    NSUInteger token=++self.generation;
    dispatch_queue_t main=dispatch_get_main_queue();
    if (!getClient || !bundleID) { [self.bar setNeedsLayout]; return; }
    getClient(main, ^(CFTypeRef client) {
        if (!self.active || token!=self.generation) return;
        self.remoteOwned=SpotifyClient(client);
        if (!self.remoteOwned || !getInfo) {
            self.remoteTitle=nil; self.remoteArt=nil; self.lastData=nil; self.remotePlaying=nil;
            [self.bar setNeedsLayout]; return;
        }
        if (getPlaying) getPlaying(main, ^(Boolean playing) {
            if (!self.active || token!=self.generation || !self.remoteOwned) return;
            NSNumber *value=@((BOOL)playing);
            if (![self.remotePlaying isEqual:value]) { self.remotePlaying=value; [self.bar setNeedsLayout]; }
        });
        getInfo(main, ^(CFDictionaryRef raw) {
            if (!self.active || token!=self.generation) return;
            NSDictionary *info=(__bridge NSDictionary *)raw;
            id title=info[titleKey];
            self.remoteTitle=[title isKindOfClass:NSString.class] ? title : nil;
            self.queriedHostTrack=hostAtRequest;
            self.remoteArtist=[info[artistKey] isKindOfClass:NSString.class] ? info[artistKey] : nil;
            id art=info[artworkKey];
            NSData *bytes=[art isKindOfClass:NSData.class] ? art : nil;
            if (bytes.length>16*1024*1024) bytes=nil;
            if (bytes!=self.lastData && ![bytes isEqualToData:self.lastData]) {
                self.lastData=bytes;
                self.remoteArt=nil;
                if (bytes.length) dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{
                    CGImageSourceRef source=CGImageSourceCreateWithData((__bridge CFDataRef)bytes,NULL);
                    if (!source) return;
                    NSDictionary *options=@{(id)kCGImageSourceCreateThumbnailFromImageAlways:@YES,
                        (id)kCGImageSourceCreateThumbnailWithTransform:@YES,(id)kCGImageSourceThumbnailMaxPixelSize:@96};
                    CGImageRef thumb=CGImageSourceCreateThumbnailAtIndex(source,0,(__bridge CFDictionaryRef)options);
                    UIImage *image=thumb ? [UIImage imageWithCGImage:thumb] : nil;
                    if (thumb) CGImageRelease(thumb); CFRelease(source);
                    dispatch_async(main,^{
                        if (self.active && self.remoteOwned && self.lastData==bytes) {
                            self.remoteArt=image; [self.bar setNeedsLayout];
                        }
                    });
                });
            }
            [self.bar setNeedsLayout];
        });
    });
}
- (BOOL)update {
    id<CP26MediaModel> manager=Manager(self.bar,self.context), snapshot=Snapshot(manager);
    NSString *title=[snapshot respondsToSelector:@selector(title)] ? snapshot.title : nil;
    NSString *artist=[snapshot respondsToSelector:@selector(artist)] ? snapshot.artist : nil;
    BOOL useRemote=self.remoteOwned && self.remoteTitle.length &&
        (!title.length || [self.queriedHostTrack isEqualToString:HostTrack(snapshot)]);
    BOOL matchesRemote=[title isEqualToString:self.remoteTitle] &&
        (!artist.length || !self.remoteArtist.length || [artist isEqualToString:self.remoteArtist]);
    if (useRemote) { title=self.remoteTitle; artist=self.remoteArtist; }
    id<CP26MediaModel> owner=(id)Owner(self.bar);
    self.wanted=title.length && ((self.openItem.enabled && self.openItem.action) ||
        [owner respondsToSelector:@selector(_nowPlayingButtonTapped)] ||
        (self.nativeButton.enabled && (self.nativeButton.allControlEvents &
           (UIControlEventTouchUpInside | UIControlEventPrimaryActionTriggered))));
    self.hidden=!self.wanted;
    self.playing=snapshot && [snapshot respondsToSelector:@selector(durationSnapshot)] ?
        @(snapshot.durationSnapshot.rate>0) : (self.remoteOwned ? self.remotePlaying : nil);
    // Layout can be repeated many times before the first async response.
    if (self.lastQuery==0) [self refreshRemote];
    if (!self.wanted) {
        self.trackKey=nil; self.catalog=nil; self.catalogArt=nil; self.art.image=nil;
        return NO;
    }
    NSString *key=[NSString stringWithFormat:@"%@\n%@",title,artist ?: @""];
    if (![key isEqualToString:self.trackKey]) {
        self.trackKey=key; self.catalog=nil; self.catalogArt=nil; self.art.image=nil;
        [self.captionTrack.layer removeAnimationForKey:@"CP26HomeTitleScroll"];
        self.ticker=nil; self.captionWidth=0;
    }
    if (![self.caption.text isEqualToString:title]) {
        self.caption.text=title; self.captionRepeat.text=title;
        [self.captionTrack.layer removeAnimationForKey:@"CP26HomeTitleScroll"];
        self.ticker=nil; self.captionWidth=0;
    }
    [self setNeedsLayout];
    self.openButton.accessibilityLabel=[@"Now Playing, " stringByAppendingString:title];
    id<CP26MediaModel> catalog=(!useRemote || matchesRemote) && [snapshot respondsToSelector:@selector(artworkCatalog)] ? snapshot.artworkCatalog : nil;
    if (catalog!=self.catalog && [catalog respondsToSelector:@selector(requestImageWithCompletion:)]) {
        self.catalog=catalog;
        __weak CP26MiniPlayer *weakSelf=self;
        [catalog requestImageWithCompletion:^(UIImage *image) {
            if (![image isKindOfClass:UIImage.class]) return;
            dispatch_async(dispatch_get_main_queue(), ^{
                CP26MiniPlayer *p=weakSelf;
                if (p.active && p.catalog==catalog && [p.trackKey isEqualToString:key]) {
                    p.catalogArt=image; [p.bar setNeedsLayout];
                }
            });
        }];
    }
    UIImage *currentArt=(useRemote || matchesRemote ? self.remoteArt : nil) ?: self.catalogArt;
    if (self.art.image!=currentArt) self.art.image=currentArt;
    BOOL scoped=[manager respondsToSelector:@selector(performCommandRequest:completion:)] && snapshot;
    BOOL system=self.remoteOwned && getClient && bundleID && sendCommand;
    self.transport.enabled=(scoped && self.playing!=nil) || system;
    self.next.enabled=(scoped || system) && (![snapshot respondsToSelector:@selector(shouldEnableNextButton)] || snapshot.shouldEnableNextButton);
    NSString *symbol=self.playing ? (self.playing.boolValue ? @"pause.fill" : @"play.fill") : @"playpause.fill";
    self.transport.accessibilityLabel=self.playing ? (self.playing.boolValue ? @"Pause" : @"Play") : @"Play or pause";
    CGFloat size=12*CGRectGetWidth(self.frame)/164;
    if (![symbol isEqualToString:self.symbol] || size!=self.symbolSize) {
        self.symbol=symbol; self.symbolSize=size;
        UIImageSymbolConfiguration *config=[UIImageSymbolConfiguration configurationWithPointSize:size weight:UIImageSymbolWeightBold];
        [self.transport setImage:[UIImage systemImageNamed:symbol withConfiguration:config] forState:UIControlStateNormal];
        [self.next setImage:[UIImage systemImageNamed:@"forward.fill" withConfiguration:config] forState:UIControlStateNormal];
    }
    return YES;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w=self.bounds.size.width, h=self.bounds.size.height, u=w/164.0;
    CGFloat button=33*u, artwork=18*u, left=8*u;
    _glass.frame=CGRectInset(self.bounds,0,3*u);
    CP26GlassPill(_glass,CGRectGetHeight(_glass.bounds)/2);
    _openButton.frame=CGRectMake(0,0,w-2*button,h);
    _transport.frame=CGRectMake(w-2*button,0,button,h);
    _next.frame=CGRectMake(w-button,0,button,h);
    _art.frame=CGRectMake(left,(h-artwork)/2,artwork,artwork);
    UIFont *font=[UIFont systemFontOfSize:9.7*u weight:UIFontWeightSemibold];
    _caption.font=font; _captionRepeat.font=font;
    CGFloat x=left+artwork+6*u;
    CGFloat viewportWidth=MAX(1,_openButton.bounds.size.width-x-1.5*u);
    _captionClip.frame=CGRectMake(x,0,viewportWidth,h);
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    _tickerMask.frame=_captionClip.bounds;
    CGFloat textWidth=ceil([_caption sizeThatFits:CGSizeMake(CGFLOAT_MAX,h)].width);
    BOOL needsTicker=textWidth>viewportWidth+1;
    _captionRepeat.hidden=!needsTicker;
    _captionClip.layer.mask=needsTicker ? _tickerMask : nil;
    CGFloat gap=12*u, cycle=textWidth+gap;
    BOOL geometryChanged=fabs(_captionWidth-textWidth)>1 || fabs(_captionViewportWidth-viewportWidth)>1;
    _captionWidth=textWidth; _captionViewportWidth=viewportWidth;
    _caption.frame=CGRectMake(0,0,textWidth,h);
    _captionRepeat.frame=CGRectMake(textWidth+gap,0,textWidth,h);
    _captionTrack.frame=CGRectMake(0,0,needsTicker ? textWidth*2+gap : viewportWidth,h);
    if (needsTicker) {
        if (geometryChanged || !_ticker || ![_captionTrack.layer animationForKey:@"CP26HomeTitleScroll"]) {
            [_captionTrack.layer removeAnimationForKey:@"CP26HomeTitleScroll"];
            CABasicAnimation *scroll=[CABasicAnimation animationWithKeyPath:@"transform.translation.x"];
            scroll.fromValue=@0;
            scroll.toValue=@(-cycle);
            scroll.beginTime=CACurrentMediaTime()+.8;
            scroll.duration=cycle/18.0;
            scroll.repeatCount=HUGE_VALF;
            scroll.timingFunction=[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
            [_captionTrack.layer addAnimation:scroll forKey:@"CP26HomeTitleScroll"];
            _ticker=scroll;
        }
    } else {
        [_captionTrack.layer removeAnimationForKey:@"CP26HomeTitleScroll"];
        _ticker=nil; _captionWidth=0; _captionViewportWidth=0;
        _captionTrack.frame=CGRectMake(0,0,viewportWidth,h);
        _caption.frame=CGRectMake(0,0,viewportWidth,h);
        _captionRepeat.frame=CGRectZero;
    }
    [CATransaction commit];
}
@end

BOOL CP26UpdateMiniPlayer(UIView *bar, UIView *wrapper, UIViewController *context, UIBarButtonItem *item, CGRect frame) {
    CP26MiniPlayer *mini=objc_getAssociatedObject(bar,&miniKey);
    if (!mini) {
        LoadPlaybackAPI();
        mini=[[CP26MiniPlayer alloc] initWithFrame:frame]; mini.bar=bar;
        objc_setAssociatedObject(bar,&miniKey,mini,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [bar addSubview:mini];
        if (!players) players=[NSHashTable weakObjectsHashTable];
        [players addObject:mini];
    }
    mini.context=context; mini.openItem=item;
    UIControl *button=[wrapper isKindOfClass:UIControl.class] ? (UIControl *)wrapper : nil;
    for (UIView *v in wrapper.subviews)
        if ([v isKindOfClass:UIControl.class] && [v isKindOfClass:NSClassFromString(@"CPUINowPlayingButton")])
            { button=(UIControl *)v; break; }
    mini.nativeButton=button;
    if (!CGRectEqualToRect(mini.frame,frame)) mini.frame=frame;
    if (bar.subviews.lastObject!=mini) [bar bringSubviewToFront:mini];
    return [mini update];
}
UIView *CP26MiniPlayerHit(UIView *bar, CGPoint p, UIEvent *event) {
    CP26MiniPlayer *mini=objc_getAssociatedObject(bar,&miniKey);
    return CP26HitVisibleControl(mini,bar,p,event);
}
void CP26RemoveMiniPlayer(UIView *bar) {
    CP26MiniPlayer *p=objc_getAssociatedObject(bar,&miniKey);
    if (!p) return;
    p.active=NO; [p.timer invalidate]; [p removeFromSuperview];
    objc_setAssociatedObject(bar,&miniKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
void CP26InvalidatePlayback(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        CP26RefreshBrowseGeometry();
        for (CP26MiniPlayer *p in players.allObjects) {
            if (![p barVisible] || p.requestQueued) continue;
            p.requestQueued=YES;
            dispatch_async(dispatch_get_main_queue(), ^{
                p.requestQueued=NO;
                if ([p barVisible]) { [p refreshRemote]; [p.bar setNeedsLayout]; }
            });
        }
    });
}
void CP26PlaybackReport(NSMutableString *out) {
    for (CP26MiniPlayer *p in players.allObjects) {
        if (!p.window) continue;
        if (!p.hidden) {
            CP26ReportHit(out,@"mini open",p.openButton); CP26ReportHit(out,@"mini play",p.transport);
            CP26ReportHit(out,@"mini next",p.next);
        }
        [out appendFormat:@"MINI visible=%d frame=%@ model=%d remoteSpotify=%d artwork=%d play=%d skip=%d playingKnown=%d\n",
            !p.hidden,NSStringFromCGRect(p.frame),Snapshot(Manager(p.bar,p.context))!=nil,p.remoteOwned,
            p.art.image!=nil,p.transport.enabled,p.next.enabled,p.playing!=nil];
    }
}
