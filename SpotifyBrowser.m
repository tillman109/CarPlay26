#import "SpotifyReference.h"
#import <CarPlay/CarPlay.h>
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>

static char browseKey, faceKey, nativeRowKey;
static NSHashTable<UITableView *> *tables;

@interface CP26ListFace : UIView
@property(nonatomic,strong) UIImageView *cover, *accessory, *playing;
@property(nonatomic,strong) UILabel *title, *detail;
@property(nonatomic,strong) UIView *separator, *progressTrack, *progressFill;
@property(nonatomic,strong) UILabel *explicitMark;
@property(nonatomic) CGFloat progress, accessoryInset;
@property(nonatomic,strong) NSMapTable<UIView *,NSNumber *> *nativeAlpha;
@property(nonatomic,strong) UIColor *nativeColor;
@property(nonatomic,strong) UIBackgroundConfiguration *nativeConfiguration;
@property(nonatomic) BOOL nativeOpaque, nativeElement;
@property(nonatomic,copy) NSString *nativeLabel;
@property(nonatomic,weak) UITableViewCell *cell;
@property(nonatomic) CGFloat unit;
@end

@implementation CP26ListFace
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self=[super initWithFrame:frame])) {
        self.userInteractionEnabled=NO;
        self.accessibilityElementsHidden=YES;
        _nativeAlpha=[NSMapTable weakToStrongObjectsMapTable];
        _cover=[UIImageView new]; _accessory=[UIImageView new]; _playing=[UIImageView new];
        _cover.contentMode=UIViewContentModeScaleAspectFill; _cover.clipsToBounds=YES;
        _accessory.contentMode=_playing.contentMode=UIViewContentModeScaleAspectFit;
        _accessory.tintColor=_playing.tintColor=[UIColor colorWithWhite:1 alpha:.61];
        _title=[UILabel new]; _detail=[UILabel new]; _separator=[UIView new];
        _explicitMark=[UILabel new]; _explicitMark.text=@"E"; _explicitMark.textAlignment=NSTextAlignmentCenter;
        _explicitMark.backgroundColor=[UIColor colorWithWhite:1 alpha:.58]; _explicitMark.textColor=[UIColor colorWithWhite:.17 alpha:1];
        _explicitMark.clipsToBounds=YES;
        _progressTrack=[UIView new]; _progressFill=[UIView new];
        _progressTrack.backgroundColor=[UIColor colorWithWhite:1 alpha:.23]; _progressFill.backgroundColor=UIColor.whiteColor;
        _progressTrack.clipsToBounds=YES; [_progressTrack addSubview:_progressFill];
        _title.textColor=UIColor.whiteColor; _detail.textColor=[UIColor colorWithWhite:1 alpha:.68];
        _separator.backgroundColor=[UIColor colorWithWhite:1 alpha:.18];
        for (UIView *view in @[_cover,_title,_detail,_accessory,_playing,_explicitMark,_separator,_progressTrack]) [self addSubview:view];
        _playing.image=[UIImage systemImageNamed:@"waveform"];
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat u=_unit, w=self.bounds.size.width, h=self.bounds.size.height;
    CGFloat side=MIN(33*u,h-2*u), x=6*u, textX=_cover.image ? x+side+6*u : x;
    _cover.frame=CGRectMake(x,(h-side)/2,side,side);
    _cover.layer.cornerRadius=4*u;
    CGFloat right=w-7*u-_accessoryInset;
    _accessory.frame=CGRectMake(right-11*u,(h-11*u)/2,11*u,11*u);
    if (!_accessory.hidden) right-=17*u;
    _playing.frame=CGRectMake(right-12*u,(h-12*u)/2,12*u,12*u);
    if (!_playing.hidden) right-=15*u;
    if (!_explicitMark.hidden) {
        _explicitMark.frame=CGRectMake(right-8*u,(h-8*u)/2,8*u,8*u);
        _explicitMark.layer.cornerRadius=1.4*u; _explicitMark.font=[UIFont systemFontOfSize:6*u weight:UIFontWeightBold];
        right-=12*u;
    }
    CGFloat textW=MAX(1,right-textX);
    _title.font=[UIFont systemFontOfSize:12.5*u weight:UIFontWeightMedium];
    _detail.font=[UIFont systemFontOfSize:9.2*u];
    _title.frame=CGRectMake(textX,_detail.hidden ? 0 : h/2-14*u,textW,_detail.hidden ? h : 16*u);
    _detail.frame=CGRectMake(textX,h/2+2*u,textW,12.5*u);
    CGFloat progressWidth=MIN(textW,56*u);
    _progressTrack.frame=CGRectMake(textX,h-3*u,progressWidth,1.4*u);
    _progressTrack.layer.cornerRadius=.7*u;
    _progressFill.frame=CGRectMake(0,0,progressWidth*_progress,1.4*u);
    _separator.frame=CGRectMake(textX,h-.6*u,MAX(0,w-textX),.6*u);
    self.backgroundColor=(_cell.highlighted || _cell.selected || _cell.focused) ?
        [UIColor colorWithWhite:1 alpha:.15] : UIColor.clearColor;
}
@end

static void RestoreFace(UITableViewCell *cell) {
    CP26ListFace *face=objc_getAssociatedObject(cell,&faceKey);
    if (!face) return;
    for (UIView *view in face.nativeAlpha.keyEnumerator)
        if (view.alpha==0) view.alpha=[face.nativeAlpha objectForKey:view].doubleValue;
    cell.backgroundConfiguration=face.nativeConfiguration;
    cell.backgroundColor=face.nativeColor; cell.opaque=face.nativeOpaque;
    cell.isAccessibilityElement=face.nativeElement; cell.accessibilityLabel=face.nativeLabel;
    [face removeFromSuperview];
    objc_setAssociatedObject(cell,&faceKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void RestoreNativeRow(UITableViewCell *cell) {
    NSDictionary *before=objc_getAssociatedObject(cell,&nativeRowKey);
    if (!before) return;
    cell.backgroundConfiguration=before[@"configuration"]==NSNull.null ? nil : before[@"configuration"];
    cell.backgroundColor=before[@"color"]==NSNull.null ? nil : before[@"color"];
    cell.opaque=[before[@"opaque"] boolValue];
    objc_setAssociatedObject(cell,&nativeRowKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static void ClearNativeRow(UITableViewCell *cell) {
    if (!objc_getAssociatedObject(cell,&nativeRowKey)) {
        NSDictionary *before=@{@"configuration":(id)cell.backgroundConfiguration ?: NSNull.null,
            @"color":(id)cell.backgroundColor ?: NSNull.null,@"opaque":@(cell.opaque)};
        objc_setAssociatedObject(cell,&nativeRowKey,before,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UIBackgroundConfiguration *bg=[UIBackgroundConfiguration clearConfiguration];
    bg.backgroundColor=(cell.isFocused || cell.isSelected || cell.isHighlighted) ?
        [UIColor colorWithWhite:1 alpha:.15] : UIColor.clearColor;
    if (![cell.backgroundConfiguration isEqual:bg]) cell.backgroundConfiguration=bg;
    cell.opaque=NO;
    if (![cell.backgroundColor isEqual:UIColor.clearColor]) cell.backgroundColor=UIColor.clearColor;
}
void CP26BrowseCellReused(UITableViewCell *cell) { RestoreFace(cell); RestoreNativeRow(cell); }
void CP26BrowseCellStateChanged(UITableViewCell *cell) {
    CP26ListFace *face=objc_getAssociatedObject(cell,&faceKey);
    [face setNeedsLayout];
    if (objc_getAssociatedObject(cell,&nativeRowKey)) ClearNativeRow(cell);
}

static void SuppressNativePart(CP26ListFace *face, UIView *view, UIView *accessory) {
    if (view==accessory || view==face) return;
    if (accessory && [accessory isDescendantOfView:view]) {
        for (UIView *child in view.subviews) SuppressNativePart(face,child,accessory);
        return;
    }
    if (![face.nativeAlpha objectForKey:view]) [face.nativeAlpha setObject:@(view.alpha) forKey:view];
    if (view.alpha!=0) view.alpha=0;
}

static void PaintFace(UITableViewCell *cell, CPListItem *item, NSUInteger tab, CGFloat u, BOOL last) {
    UIView *nativeAccessory=cell.accessoryView;
    BOOL separatelyActionable=([nativeAccessory isKindOfClass:UIControl.class] &&
        ((UIControl *)nativeAccessory).allControlEvents!=0) || nativeAccessory.gestureRecognizers.count>0;
    if (!item.text.length) { RestoreFace(cell); ClearNativeRow(cell); return; }
    RestoreNativeRow(cell);
    CP26ListFace *face=objc_getAssociatedObject(cell,&faceKey);
    if (!face) {
        face=[[CP26ListFace alloc] initWithFrame:cell.bounds];
        face.cell=cell; face.nativeColor=cell.backgroundColor; face.nativeOpaque=cell.opaque;
        face.nativeElement=cell.isAccessibilityElement; face.nativeLabel=cell.accessibilityLabel;
        face.nativeConfiguration=cell.backgroundConfiguration;
        objc_setAssociatedObject(cell,&faceKey,face,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        cell.backgroundConfiguration=[UIBackgroundConfiguration clearConfiguration];
        [cell addSubview:face];
    }
    cell.opaque=NO; cell.backgroundColor=UIColor.clearColor;
    UIView *action=separatelyActionable ? nativeAccessory : nil;
    if (action) for (UIView *v in face.nativeAlpha.keyEnumerator.allObjects) {
        if (v!=action && ![action isDescendantOfView:v] && ![v isDescendantOfView:action]) continue;
        if (v.alpha==0) v.alpha=[face.nativeAlpha objectForKey:v].doubleValue;
        [face.nativeAlpha removeObjectForKey:v];
    }
    for (UIView *v in cell.subviews)
        if (v!=face && v!=cell.selectedBackgroundView) SuppressNativePart(face,v,action);
    face.accessoryInset=action ? MAX(0,cell.bounds.size.width-CGRectGetMinX([action convertRect:action.bounds toView:cell])) : 0;
    if (cell.subviews.lastObject!=face) [cell bringSubviewToFront:face];
    face.unit=u; face.frame=cell.bounds; face.cover.image=item.image ?: cell.imageView.image;
    face.title.text=item.text; face.detail.text=item.detailText; face.detail.hidden=!item.detailText.length;
    UIImage *accessory=item.accessoryImage;
    if (!accessory) {
        if (item.accessoryType==CPListItemAccessoryTypeCloud) accessory=[UIImage systemImageNamed:@"icloud"];
        else if (item.accessoryType==CPListItemAccessoryTypeDisclosureIndicator || tab==2 || tab==3)
            accessory=[UIImage systemImageNamed:@"chevron.right"];
    }
    face.accessory.image=accessory; face.accessory.hidden=action || !accessory;
    face.playing.hidden=!item.playing; face.separator.hidden=last;
    face.alpha=item.enabled ? 1 : .55;
    face.explicitMark.hidden=!item.isExplicitContent;
    face.progress=isfinite(item.playbackProgress) ? MIN(1,MAX(0,item.playbackProgress)) : 0;
    face.progressTrack.hidden=face.progress<=0;
    cell.isAccessibilityElement=action ? face.nativeElement : YES;
    cell.accessibilityLabel=action ? face.nativeLabel : item.detailText.length ?
        [NSString stringWithFormat:@"%@, %@",item.text,item.detailText] : item.text;
    [face setNeedsLayout];
}

@interface CP26BrowseState : NSObject
@property(nonatomic,weak) UITableView *table;
@property(nonatomic,strong) UIView *canvas, *originalBackground, *underlay;
@property(nonatomic,strong) CP26PlacedViews *geometry;
@property(nonatomic,strong) NSHashTable<UITableViewCell *> *visible;
@property(nonatomic,strong) NSMapTable<UITableViewCell *,id> *assistantBackgrounds;
@property(nonatomic,strong) NSMapTable<UIImageView *,NSValue *> *railTransforms;
@property(nonatomic,strong) UIColor *tableColor;
@property(nonatomic) UITableViewCellSeparatorStyle separators;
@property(nonatomic) BOOL tableOpaque, applying, resolvingRow;
@property(nonatomic) NSUInteger tab;
@property(nonatomic,strong) NSMapTable<UITableViewHeaderFooterView *,id> *headers;
@property(nonatomic) CGFloat insetDelta, appliedInsetTop;
@end
@implementation CP26BrowseState
@end

static void HeaderInset(CP26BrowseState *s, CGFloat delta) {
    UITableView *t=s.table;
    if (s.insetDelta!=0 && fabs(t.contentInset.top-s.appliedInsetTop)>.1) s.insetDelta=0;
    if (fabs(delta-s.insetDelta)<.1) return;
    CGFloat oldTop=t.adjustedContentInset.top;
    BOOL atTop=!t.tracking && !t.decelerating && fabs(t.contentOffset.y+oldTop)<1.5;
    UIEdgeInsets inset=t.contentInset; inset.top+=delta-s.insetDelta;
    s.insetDelta=delta; s.appliedInsetTop=inset.top; t.contentInset=inset;
    if (atTop) t.contentOffset=CGPointMake(t.contentOffset.x,-t.adjustedContentInset.top);
}

static void RestoreAssistant(CP26BrowseState *s, UITableViewCell *cell) {
    id original=[s.assistantBackgrounds objectForKey:cell];
    if (original) {
        cell.backgroundConfiguration=original==NSNull.null ? nil : original;
        [s.assistantBackgrounds removeObjectForKey:cell];
    }
}
static void RestoreTable(UITableView *table) {
    CP26BrowseState *s=objc_getAssociatedObject(table,&browseKey);
    if (!s || s.applying) return;
    s.applying=YES;
    for (UITableViewCell *cell in s.visible.allObjects) { CP26BrowseCellReused(cell); RestoreAssistant(s,cell); }
    for (UIImageView *image in s.railTransforms.keyEnumerator) image.transform=[s.railTransforms objectForKey:image].CGAffineTransformValue;
    for (UITableViewHeaderFooterView *header in s.headers.keyEnumerator) {
        id old=[s.headers objectForKey:header]; header.backgroundConfiguration=old==NSNull.null ? nil : old;
    }
    HeaderInset(s,0);
    [s.geometry restore];
    if (table.backgroundView==s.canvas) table.backgroundView=s.originalBackground;
    [s.underlay removeFromSuperview];
    table.backgroundColor=s.tableColor; table.opaque=s.tableOpaque; table.separatorStyle=s.separators;
    objc_setAssociatedObject(table,&browseKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [tables removeObject:table];
}
static void LayoutRail(CP26BrowseState *s, UIView *rail, CGFloat u) {
    for (UIView *button in rail.subviews) {
        if (![NSStringFromClass(button.class) isEqualToString:@"_UIStaticScrollbarButton"]) continue;
        for (UIImageView *image in button.subviews) {
            if (![image isKindOfClass:UIImageView.class] || !image.image || image.bounds.size.width<1) continue;
            NSValue *prior=[s.railTransforms objectForKey:image];
            if (!prior) {
                prior=[NSValue valueWithCGAffineTransform:image.transform]; [s.railTransforms setObject:prior forKey:image];
            }
            // Keep the native button, focus ring and enabled/disabled presentation.
            CGFloat scale=MIN(1,(11*u)/MAX(1,MIN(image.image.size.width,image.bounds.size.width)));
            CGAffineTransform tr=CGAffineTransformScale(prior.CGAffineTransformValue,scale,scale);
            if (!CGAffineTransformEqualToTransform(image.transform,tr)) image.transform=tr;
        }
    }
}
void CP26UpdateBrowseTable(UITableView *table, NSUInteger tab, BOOL compactHeader) {
    CP26BrowseState *s=objc_getAssociatedObject(table,&browseKey);
    if (tab==NSNotFound || !table.window) { RestoreTable(table); return; }
    if (s.applying) return;
    if (!s) {
        s=[CP26BrowseState new]; s.table=table; s.geometry=[CP26PlacedViews new];
        s.originalBackground=table.backgroundView; s.separators=table.separatorStyle;
        s.tableColor=table.backgroundColor; s.tableOpaque=table.opaque;
        s.canvas=CP26ReferenceCanvas(); s.underlay=CP26ReferenceCanvas();
        s.railTransforms=[NSMapTable weakToStrongObjectsMapTable]; s.visible=[NSHashTable weakObjectsHashTable];
        s.assistantBackgrounds=[NSMapTable weakToStrongObjectsMapTable];
        s.headers=[NSMapTable weakToStrongObjectsMapTable];
        objc_setAssociatedObject(table,&browseKey,s,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (!tables) tables=[NSHashTable weakObjectsHashTable]; [tables addObject:table];
        if (tab>0) {
            __weak UITableView *weakTable=table;
            dispatch_async(dispatch_get_main_queue(), ^{
                UITableView *t=weakTable;
                if (t.window && objc_getAssociatedObject(t,&browseKey)==s && !t.hasUncommittedUpdates)
                    [UIView performWithoutAnimation:^{ [t beginUpdates]; [t endUpdates]; }];
            });
        }
    }
    s.applying=YES; s.tab=tab;
    UIWindow *window=table.window;
    CGFloat w=window.bounds.size.width, u=w/400;
    if (table.backgroundView!=s.canvas) table.backgroundView=s.canvas;
    if (table.separatorStyle!=UITableViewCellSeparatorStyleNone) table.separatorStyle=UITableViewCellSeparatorStyleNone;
    if (table.opaque) table.opaque=NO;
    if (![table.backgroundColor isEqual:UIColor.clearColor]) table.backgroundColor=UIColor.clearColor;
    if (table.superview && s.underlay.superview!=table.superview) [table.superview insertSubview:s.underlay belowSubview:table];
    if (!CGRectEqualToRect(s.underlay.frame,table.superview.bounds)) s.underlay.frame=table.superview.bounds;
    if (w<320 || w>560 || window.bounds.size.height<w) {
        // Retain the established Home shelves on other CarPlay displays. UIKit
        // supplies their viewport, rail and row widths on those displays.
        HeaderInset(s,0); [s.geometry restore]; s.applying=NO; return;
    }
    CGRect visible=[table convertRect:table.bounds toView:window];
    CGFloat nativeBottom=CGRectGetHeight(window.bounds)-CGRectGetMaxY(visible);
    CGFloat desiredBottom=CGRectGetHeight(window.bounds)-34.5*u;
    if (nativeBottom>=33*u && nativeBottom<=53*u &&
        CGRectGetMaxY([table.superview convertRect:table.superview.bounds toView:window])>=desiredBottom) {
        visible.size.height=desiredBottom-CGRectGetMinY(visible);
        [s.geometry place:table in:window rect:visible];
    }
    if (s.insetDelta!=0 && fabs(table.contentInset.top-s.appliedInsetTop)>.1) s.insetDelta=0;
    CGFloat nativeTop=table.adjustedContentInset.top-s.insetDelta;
    CGFloat wantedTop=33*u-CGRectGetMinY(visible);
    CGFloat delta=compactHeader && nativeTop>wantedTop && wantedTop>=0 ? wantedTop-nativeTop : 0;
    HeaderInset(s,delta);
    UIView *wrapper=nil, *rail=nil;
    for (UIView *view in table.subviews) {
        NSString *name=NSStringFromClass(view.class);
        if ([name isEqualToString:@"UITableViewWrapperView"]) wrapper=view;
        if ([name isEqualToString:@"_UIStaticScrollBar"] && !view.hidden && view.alpha>.01) rail=view;
    }
    BOOL scrolling=table.contentSize.height+table.adjustedContentInset.top+table.adjustedContentInset.bottom>table.bounds.size.height+1;
    CGFloat right=(scrolling ? 368 : 393)*u;
    if (wrapper) {
        CGRect frame=wrapper.frame; frame.origin.x=9*u; frame.size.width=right-frame.origin.x;
        [s.geometry place:wrapper in:table rect:frame];
    }
    if (rail && scrolling) {
        CGRect frame=rail.frame; frame.origin.x=370*u; frame.size.width=30*u;
        [s.geometry place:rail in:table rect:frame]; LayoutRail(s,rail,u);
    }
    NSArray *visibleCells=table.visibleCells;
    for (UITableViewCell *cell in s.visible.allObjects) if (![visibleCells containsObject:cell]) {
        CP26BrowseCellReused(cell); RestoreAssistant(s,cell); [s.visible removeObject:cell];
        [s.geometry restoreView:cell];
    }
    for (UITableViewCell *cell in visibleCells) {
        [s.visible addObject:cell];
        if (wrapper && cell.superview==wrapper) {
            CGRect frame=cell.frame; frame.origin.x=0; frame.size.width=wrapper.bounds.size.width;
            [s.geometry place:cell in:wrapper rect:frame];
        }
        if (tab==0) { RestoreNativeRow(cell); continue; }
        NSIndexPath *path=[table indexPathForCell:cell];
        id item=path ? CP26BrowseModel(table,path) : nil;
        if ([item isKindOfClass:CPListItem.class]) {
            RestoreAssistant(s,cell);
            BOOL last=path.section+1==table.numberOfSections && path.row+1==[table numberOfRowsInSection:path.section];
            PaintFace(cell,item,tab,u,last);
        } else {
            RestoreFace(cell);
            if ([NSStringFromClass(cell.class) rangeOfString:@"Assistant" options:NSCaseInsensitiveSearch].location!=NSNotFound) {
                if (![s.assistantBackgrounds objectForKey:cell])
                    [s.assistantBackgrounds setObject:(id)cell.backgroundConfiguration ?: NSNull.null forKey:cell];
                UIBackgroundConfiguration *bg=[UIBackgroundConfiguration clearConfiguration];
                bg.backgroundColor=[UIColor colorWithWhite:1 alpha:.13]; bg.cornerRadius=16*u;
                if (![cell.backgroundConfiguration isEqual:bg]) cell.backgroundConfiguration=bg;
            } else { RestoreAssistant(s,cell); if (tab==CP26BrowseDetail) ClearNativeRow(cell); }
        }
    }
    if (tab==CP26BrowseDetail) {
        for (NSIndexPath *path in table.indexPathsForVisibleRows) {
            UITableViewHeaderFooterView *header=[table headerViewForSection:path.section];
            if (!header) continue;
            if (![s.headers objectForKey:header]) [s.headers setObject:(id)header.backgroundConfiguration ?: NSNull.null forKey:header];
            UIBackgroundConfiguration *clear=[UIBackgroundConfiguration clearConfiguration];
            if (![header.backgroundConfiguration isEqual:clear]) header.backgroundConfiguration=clear;
        }
    }
    s.applying=NO;
}
NSIndexPath *CP26BrowsePathAtPoint(UITableView *t, CGPoint p, NSIndexPath *native) {
    CP26BrowseState *s=objc_getAssociatedObject(t,&browseKey);
    if (!s || s.applying || s.resolvingRow || s.tab==0 || !CGRectContainsPoint(t.bounds,p)) return native;
    for (UITableViewHeaderFooterView *header in s.headers.keyEnumerator)
        if (header.window && !header.hidden && CGRectContainsPoint(header.bounds,[header convertPoint:p fromView:t])) return native;
    // Keep UIKit's vertical row lookup and block selection in the scroll rail.
    // The visible native cells may be wider than the original wrapper.
    for (UITableViewCell *cell in s.visible.allObjects) {
        if (cell.hidden || !cell.window || !objc_getAssociatedObject(cell,&faceKey)) continue;
        CGRect box=[cell convertRect:cell.bounds toView:t];
        if (p.y<CGRectGetMinY(box) || p.y>=CGRectGetMaxY(box)) continue;
        if (!CGRectContainsPoint(box,p)) return nil;
        if (native) return native;
        s.resolvingRow=YES;
        NSIndexPath *path=[t indexPathForCell:cell];
        s.resolvingRow=NO;
        return path;
    }
    return native;
}
BOOL CP26BrowseHasCanvas(UIWindow *window) {
    for (UITableView *table in tables.allObjects) {
        CP26BrowseState *s=objc_getAssociatedObject(table,&browseKey);
        if (table.window==window && !table.hidden && s.canvas.superview) return YES;
    }
    return NO;
}
void CP26RefreshBrowseGeometry(void) {
    for (UITableView *t in tables.allObjects) [t setNeedsLayout];
}
void CP26RestoreBrowseTables(void) {
    for (UITableView *t in tables.allObjects) { RestoreTable(t); [t reloadData]; }
}
void CP26BrowseReport(NSMutableString *report) {
    for (UITableView *t in tables.allObjects) {
        CP26BrowseState *s=objc_getAssociatedObject(t,&browseKey);
        if (!t.window || !s) continue;
        NSUInteger painted=0;
        for (UITableViewCell *cell in t.visibleCells) if (objc_getAssociatedObject(cell,&faceKey)) painted++;
        for (UITableViewCell *cell in t.visibleCells) CP26ReportHit(report,@"browse row",cell);
        [report appendFormat:@"BROWSE tab=%lu viewport=%@ topInset=%.1f visibleRows=%lu styledListRows=%lu assistantRows=%lu\n",
            (unsigned long)s.tab,NSStringFromCGRect([t convertRect:t.bounds toView:t.window]),t.adjustedContentInset.top,
            (unsigned long)t.visibleCells.count,(unsigned long)painted,(unsigned long)s.assistantBackgrounds.count];
    }
}
