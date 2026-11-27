#import "CommunicationUI.h"
#import <CarPlay/CarPlay.h>
#import <QuartzCore/QuartzCore.h>

// In iOS 16 Contacts uses a UICollectionViewListCell. Messages' list template supplies a
// CPUIMessageCell with the resolved contact image, title, timestamp and state glyphs.
@protocol CP26MessageParts <NSObject>
- (UILabel *)primaryLabel;
- (UILabel *)secondaryLabel;
- (UILabel *)trailingLabel;
- (UIImageView *)primaryImageView;
- (UIImageView *)leadingGlyphView;
- (UIImageView *)trailingGlyphView;
- (UIImageView *)trailingImageView;
- (UIImageView *)unreadImageView;
@end
static BOOL NamedKind(UIView *view, NSString *name) { return [view isKindOfClass:NSClassFromString(name)]; }
static UIImage *VisibleImage(UIImageView *view) { return !view.hidden && view.alpha>.01 ? view.image : nil; }
static UIColor *Primary(BOOL dark) { return dark ? UIColor.whiteColor : UIColor.blackColor; }
static UIColor *Secondary(BOOL dark) { return [UIColor colorWithWhite:dark ? 1 : 0 alpha:dark ? .72 : .67]; }

@interface CP26Row : UIView
@property(nonatomic,strong) UILabel *title, *detail, *time;
@property(nonatomic,strong) UIImageView *avatar, *status, *chevron, *leading;
@property(nonatomic,strong) UIView *line;
@end
@implementation CP26Row
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self=[super initWithFrame:frame])) {
        self.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        self.userInteractionEnabled=NO; self.accessibilityElementsHidden=YES;
        _title=[UILabel new]; _detail=[UILabel new]; _time=[UILabel new];
        _title.font=[UIFont systemFontOfSize:12.2 weight:UIFontWeightMedium];
        _detail.font=[UIFont systemFontOfSize:9.5]; _time.font=[UIFont systemFontOfSize:12];
        _avatar=[UIImageView new]; _avatar.clipsToBounds=YES;
        _leading=[UIImageView new]; _status=[UIImageView new]; _chevron=[UIImageView new];
        _leading.contentMode=_status.contentMode=_chevron.contentMode=UIViewContentModeScaleAspectFit;
        _chevron.image=[UIImage systemImageNamed:@"chevron.forward" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:10 weight:UIImageSymbolWeightSemibold]];
        _line=[UIView new];
        for (UIView *v in @[_title,_detail,_time,_avatar,_leading,_status,_chevron,_line]) [self addSubview:v];
    }
    return self;
}
@end

// Only list coordinates are projected. Cell and accessory hit rectangles remain owned by the data source.
static CGRect RowBox(UIView *cell, CGFloat x, CGFloat y, CGFloat w, CGFloat h) {
    if (cell.effectiveUserInterfaceLayoutDirection==UIUserInterfaceLayoutDirectionRightToLeft) x=cell.bounds.size.width-x-w;
    return CGRectMake(x,y,MAX(0,w),h);
}
static CGFloat LeadingInCell(UIView *cell, CGFloat fromWindow) {
    CGRect box=[cell convertRect:cell.bounds toView:cell.window];
    BOOL rtl=cell.effectiveUserInterfaceLayoutDirection==UIUserInterfaceLayoutDirectionRightToLeft;
    CGFloat inset=rtl ? cell.window.bounds.size.width-CGRectGetMaxX(box) : CGRectGetMinX(box);
    return MAX(0,fromWindow-inset);
}
static CGFloat TrailingInCell(UIView *cell, CGFloat fromWindow) {
    CGRect box=[cell convertRect:cell.bounds toView:cell.window];
    BOOL rtl=cell.effectiveUserInterfaceLayoutDirection==UIUserInterfaceLayoutDirectionRightToLeft;
    CGFloat inset=rtl ? CGRectGetMinX(box) : cell.window.bounds.size.width-CGRectGetMaxX(box);
    return MAX(0,fromWindow-inset);
}
static void ClearCell(UIView *cell, CP26CommunicationStyle *s, BOOL active) {
    UIBackgroundConfiguration *bg=[UIBackgroundConfiguration clearConfiguration];
    if (active) bg.backgroundColor=[UIColor colorWithWhite:cell.traitCollection.userInterfaceStyle==UIUserInterfaceStyleDark ? 1 : 0 alpha:.15];
    [s set:bg key:@"backgroundConfiguration" on:cell]; [s set:UIColor.clearColor key:@"backgroundColor" on:cell];
}
static NSString *ContactTitle(UICollectionViewCell *cell) {
    id config=cell.contentConfiguration;
    if ([config isKindOfClass:UIListContentConfiguration.class]) {
        UIListContentConfiguration *list=config;
        return list.attributedText.string.length ? list.attributedText.string : list.text;
    }
    for (UIView *view in cell.contentView.subviews) {
        if ([view isKindOfClass:UILabel.class]) return ((UILabel *)view).text;
        for (UIView *child in view.subviews) if ([child isKindOfClass:UILabel.class]) return ((UILabel *)child).text;
    }
    return nil;
}
static CPMessageListItem *MessageModel(UITableViewCell *cell) {
    UIView *parent=cell.superview;
    while (parent && ![parent isKindOfClass:UITableView.class]) parent=parent.superview;
    UITableView *table=(UITableView *)parent;
    NSIndexPath *path=[table indexPathForCell:cell];
    id item=path ? CP26BrowseModel(table,path) : nil;
    return [item isKindOfClass:CPMessageListItem.class] ? item : nil;
}
void CP26CommunicationCell(UIView *cell) {
    CP26CommunicationApp app=CP26AppForView(cell);
    BOOL contact=app==CP26PhoneApp && NamedKind(cell,@"CNContactListCollectionViewCell");
    BOOL tableRow=[cell isKindOfClass:UITableViewCell.class];
    BOOL nativeMessage=app==CP26MessagesApp && tableRow && [cell respondsToSelector:@selector(primaryLabel)] && [cell respondsToSelector:@selector(primaryImageView)];
    UITableViewCell *tableCell=tableRow ? (UITableViewCell *)cell : nil;
    UICollectionViewCell *contactCell=contact ? (UICollectionViewCell *)cell : nil;
    BOOL regularPhone=app==CP26PhoneApp && tableRow;
    if (regularPhone) {
        CP26CommunicationStyle *s=CP26StyleForView(cell,YES);
        ClearCell(cell,s,cell.focused||tableCell.highlighted||tableCell.selected);
        return;
    }
    id<CP26MessageParts> parts=nativeMessage ? (id)cell : nil;
    CPMessageListItem *model=app==CP26MessagesApp && tableRow && !nativeMessage ? MessageModel(tableCell) : nil;
    BOOL message=nativeMessage || model!=nil;
    NSString *title=contact ? ContactTitle(contactCell) : (parts.primaryLabel.text ?: model.text);
    CP26CommunicationStyle *s=CP26StyleForView(cell,title.length && (contact||message));
    if (!s) return;
    BOOL dark=cell.traitCollection.userInterfaceStyle==UIUserInterfaceStyleDark;
    BOOL active=cell.focused||tableCell.highlighted||tableCell.selected||contactCell.highlighted||contactCell.selected;
    ClearCell(cell,s,active);
    UIView *content=contact ? contactCell.contentView : tableCell.contentView;
    [s concealDrawing:content];
    CP26Row *row=(CP26Row *)s.face;
    if (!row) { row=[[CP26Row alloc] initWithFrame:cell.bounds]; s.face=row; [cell addSubview:row]; }
    row.frame=cell.bounds; if (cell.subviews.lastObject!=row) [cell bringSubviewToFront:row];
    CGFloat w=cell.bounds.size.width, h=cell.bounds.size.height, cy=h/2;
    BOOL rtl=cell.effectiveUserInterfaceLayoutDirection==UIUserInterfaceLayoutDirectionRightToLeft;
    CGFloat x=LeadingInCell(cell,message ? 58 : 20), end=w-TrailingInCell(cell,message ? 29 : 40);
    CGFloat textEnd=end;
    row.title.text=title; row.title.textColor=Primary(dark); row.title.textAlignment=rtl ? NSTextAlignmentRight : NSTextAlignmentLeft;
    row.detail.textColor=row.time.textColor=Secondary(dark); row.detail.textAlignment=row.title.textAlignment;
    row.time.textAlignment=rtl ? NSTextAlignmentLeft : NSTextAlignmentRight;
    row.detail.text=nil; row.time.text=nil;
    row.avatar.hidden=row.chevron.hidden=row.status.hidden=row.leading.hidden=!message;
    if (message) {
        UIImage *avatar=VisibleImage(parts.primaryImageView) ?: model.leadingConfiguration.leadingImage;
        CGFloat diameter=MIN(24,MAX(0,h-4));
        row.avatar.frame=RowBox(cell,LeadingInCell(cell,27),cy-diameter/2,diameter,diameter);
        row.avatar.layer.cornerRadius=diameter/2;
        row.avatar.contentMode=avatar ? UIViewContentModeScaleAspectFill : UIViewContentModeScaleAspectFit;
        row.avatar.image=avatar ?: [UIImage systemImageNamed:@"person.crop.circle.fill"];
        row.avatar.tintColor=UIColor.whiteColor; row.avatar.backgroundColor=avatar ? UIColor.clearColor : [UIColor colorWithRed:.55 green:.63 blue:.80 alpha:1];
        UIImageView *unread=[parts respondsToSelector:@selector(unreadImageView)] ? parts.unreadImageView : nil;
        UIImageView *leading=[parts respondsToSelector:@selector(leadingGlyphView)] ? parts.leadingGlyphView : nil;
        row.leading.image=VisibleImage(unread) ?: VisibleImage(leading);
        if (!row.leading.image && model.leadingConfiguration.isUnread) row.leading.image=[UIImage systemImageNamed:@"circle.fill"];
        row.leading.hidden=!row.leading.image;
        row.leading.tintColor=unread.tintColor ?: leading.tintColor;
        row.leading.frame=RowBox(cell,LeadingInCell(cell,13),cy-4,8,8);
        UIImageView *trailing=[parts respondsToSelector:@selector(trailingGlyphView)] ? parts.trailingGlyphView : nil;
        UIImageView *trailingImage=[parts respondsToSelector:@selector(trailingImageView)] ? parts.trailingImageView : nil;
        row.status.image=VisibleImage(trailing) ?: VisibleImage(trailingImage) ?: model.trailingConfiguration.trailingImage; row.status.hidden=!row.status.image;
        row.status.tintColor=Secondary(dark); row.chevron.tintColor=[Secondary(dark) colorWithAlphaComponent:.47];
        CGFloat arrowX=end-16;
        row.chevron.frame=RowBox(cell,arrowX,cy-5,7,10);
        // Preserve a native trailing state glyph in the trailing slot when present.
        row.status.frame=RowBox(cell,arrowX-2,cy-6,11,12); row.chevron.hidden=!row.status.hidden;
        UILabel *timestamp=[parts respondsToSelector:@selector(trailingLabel)] ? parts.trailingLabel : nil;
        UILabel *subtitle=[parts respondsToSelector:@selector(secondaryLabel)] ? parts.secondaryLabel : nil;
        NSString *trailingText=timestamp.text ?: model.trailingText;
        NSString *detail=subtitle.text ?: model.detailText;
        row.time.text=trailingText.length ? trailingText : detail;
        if (trailingText.length && !subtitle.hidden && ![detail isEqual:trailingText]) row.detail.text=detail;
        CGFloat tw=MIN(MAX(0,(end-x)*.48),ceil([row.time sizeThatFits:CGSizeMake(CGFLOAT_MAX,h)].width));
        row.time.frame=RowBox(cell,arrowX-5-tw,0,tw,h); textEnd=arrowX-10-tw;
    }
    BOOL twoLines=row.detail.text.length>0;
    row.title.frame=RowBox(cell,x,twoLines ? cy-13 : 0,MAX(0,textEnd-x),twoLines ? 16 : h);
    row.detail.frame=RowBox(cell,x,cy+2,MAX(0,textEnd-x),12);
    CGFloat pixel=1/MAX(1,cell.window.screen.scale);
    row.line.backgroundColor=[UIColor colorWithWhite:dark ? 1 : 0 alpha:dark ? .21 : .24];
    row.line.frame=RowBox(cell,x,h-pixel,MAX(0,end-x),pixel);
}

void CP26CommunicationList(UIScrollView *list) {
    CP26CommunicationApp app=CP26AppForView(list);
    BOOL collection=app==CP26PhoneApp && NamedKind(list,@"CNContactListCollectionView");
    BOOL table=[list isKindOfClass:UITableView.class] && app!=CP26OtherApp;
    CP26CommunicationStyle *s=CP26StyleForView(list,collection||table);
    if (!s) return;
    if (!s.field) s.field=[CP26CommunicationBackdrop new];
    [s set:s.field key:@"backgroundView" on:list]; [s set:UIColor.clearColor key:@"backgroundColor" on:list];
    [s set:@NO key:@"opaque" on:list];
    if (table) {
        UITableView *tv=(UITableView *)list;
        BOOL messages=app==CP26MessagesApp;
        // Rows with a custom face draw their own pixel rule. Other Phone tables retain UIKit's separators.
        [s set:@(messages ? UITableViewCellSeparatorStyleNone : UITableViewCellSeparatorStyleSingleLine) key:@"separatorStyle" on:tv];
        if (!messages) [s set:[UIColor colorWithWhite:list.traitCollection.userInterfaceStyle==UIUserInterfaceStyleDark ? 1 : 0 alpha:.24] key:@"separatorColor" on:tv];
        for (UITableViewCell *cell in tv.visibleCells) CP26CommunicationCell(cell);
    } else {
        UICollectionView *cv=(UICollectionView *)list;
        for (UICollectionViewCell *cell in cv.visibleCells) CP26CommunicationCell(cell);
        for (UIView *decoration in cv.subviews) {
            if (NamedKind(decoration,@"_UICollectionViewListSeparatorView")) [s concealDrawing:decoration];
        }
        for (UICollectionReusableView *header in [cv visibleSupplementaryViewsOfKind:UICollectionElementKindSectionHeader]) {
            // A plain section heading lets the shared material show through as the index scrolls.
            CP26CommunicationStyle *hs=CP26StyleForView(header,YES);
            [hs set:UIColor.clearColor key:@"backgroundColor" on:header];
            if ([header isKindOfClass:UICollectionViewCell.class]) ClearCell(header,hs,NO);
            if (NamedKind(header,@"CNContactListSectionHeaderFooterView")) {
                UIView *effect=[header valueForKey:@"visualEffectView"];
                [hs concealDrawing:effect];
            }
        }
    }
}

static void UpdateSiriCaption(UIView *parent, CP26CommunicationStyle *s, BOOL dark) {
    for (UIView *v in parent.subviews) {
        if ([v isKindOfClass:UILabel.class]) {
            [s set:Primary(dark) key:@"textColor" on:v]; [s set:[UIFont systemFontOfSize:12 weight:UIFontWeightSemibold] key:@"font" on:v];
        } else if (v!=s.face) {
            if (NamedKind(v,@"CNStarkHeaderPlatterView")) [s set:UIColor.clearColor key:@"backgroundColor" on:v];
            UpdateSiriCaption(v,s,dark);
        }
    }
}
void CP26CommunicationSiriRow(UIView *header) {
    if (!header || header.bounds.size.width<=0) return;
    CP26CommunicationStyle *s=CP26StyleForView(header,CP26AppForView(header)==CP26PhoneApp);
    if (!s) return;
    BOOL dark=header.traitCollection.userInterfaceStyle==UIUserInterfaceStyleDark;
    [s set:UIColor.clearColor key:@"backgroundColor" on:header];
    if (!s.face) { s.face=[UIView new]; s.face.userInteractionEnabled=NO; s.face.accessibilityElementsHidden=YES; [header insertSubview:s.face atIndex:0]; }
    CGFloat left=LeadingInCell(header,11), right=TrailingInCell(header,41), height=MIN(33,header.bounds.size.height);
    s.face.frame=RowBox(header,left,(header.bounds.size.height-height)/2,header.bounds.size.width-left-right,height);
    s.face.layer.cornerRadius=height/2; s.face.backgroundColor=[UIColor colorWithWhite:dark ? 1 : 0 alpha:dark ? .13 : .085];
    if (header.subviews.firstObject!=s.face) [header sendSubviewToBack:s.face];
    UpdateSiriCaption(header,s,dark);
    UIView *platter=NamedKind(header,@"CNStarkHeaderPlatterView") ? header : nil;
    for (UIView *part in header.subviews) if (NamedKind(part,@"CNStarkHeaderPlatterView")) { platter=part; break; }
    if (platter) {
        UIView *label=[platter valueForKey:@"label"], *icon=[platter valueForKey:@"accessory"];
        CGFloat x=left+9, end=header.bounds.size.width-right-14;
        [s.positions place:label in:header rect:RowBox(header,x,CGRectGetMinY(s.face.frame),end-x-16,height)];
        [s.positions place:icon in:header rect:RowBox(header,end-12,CGRectGetMidY(s.face.frame)-6,12,12)];
    }
}
