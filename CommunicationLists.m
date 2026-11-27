#import "CommunicationUI.h"
#import <QuartzCore/QuartzCore.h>

@protocol CP26MessageParts <NSObject>
- (UILabel *)primaryLabel;
- (UILabel *)secondaryLabel;
- (UILabel *)trailingLabel;
- (UIImageView *)primaryImageView;
- (UIImageView *)unreadImageView;
- (UIImageView *)leadingGlyphView;
- (UIImageView *)trailingGlyphView;
- (UIImageView *)trailingImageView;
@end

static BOOL NamedKind(UIView *view, NSString *name) { return [view isKindOfClass:NSClassFromString(name)]; }
static UIColor *Primary(BOOL dark) { return dark ? UIColor.whiteColor : UIColor.blackColor; }
static UIColor *Secondary(BOOL dark) { return [UIColor colorWithWhite:dark ? 1 : 0 alpha:dark ? .72 : .67]; }

// Build each background configuration once. UITableViewCell's setter may copy it.
static UIBackgroundConfiguration *RowBackground(BOOL dark, BOOL highlighted) {
    static UIBackgroundConfiguration *clear, *lightSelection, *darkSelection;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        clear=[UIBackgroundConfiguration clearConfiguration];
        lightSelection=[clear copy]; lightSelection.backgroundColor=[UIColor colorWithWhite:0 alpha:.15];
        darkSelection=[clear copy]; darkSelection.backgroundColor=[UIColor colorWithWhite:1 alpha:.15];
    });
    return highlighted ? (dark ? darkSelection : lightSelection) : clear;
}
void CP26CommunicationRowBackground(UITableViewCell *cell) {
    CP26CommunicationStyle *s=CP26StyleForView(cell,CP26AppForView(cell)!=CP26OtherApp);
    if (!s) return;
    BOOL dark=cell.traitCollection.userInterfaceStyle==UIUserInterfaceStyleDark;
    [s set:RowBackground(dark,cell.focused||cell.highlighted||cell.selected) key:@"backgroundConfiguration" on:cell];
    [s set:UIColor.clearColor key:@"backgroundColor" on:cell];
    [s set:UIColor.clearColor key:@"backgroundColor" on:cell.contentView];
    [s set:@NO key:@"opaque" on:cell.contentView];
}
void CP26CommunicationList(UIScrollView *list) {
    CP26CommunicationApp app=CP26AppForView(list);
    BOOL table=[list isKindOfClass:UITableView.class];
    CP26CommunicationStyle *s=CP26StyleForView(list,app!=CP26OtherApp && (table || NamedKind(list,@"CNContactListCollectionView")));
    if (!s) return;
    if (!s.field) s.field=[CP26CommunicationBackdrop new];
    [s set:s.field key:@"backgroundView" on:list];
    [s set:UIColor.clearColor key:@"backgroundColor" on:list];
    [s set:@NO key:@"opaque" on:list];
    if (table) {
        [s set:@(UITableViewCellSeparatorStyleSingleLine) key:@"separatorStyle" on:list];
        BOOL dark=list.traitCollection.userInterfaceStyle==UIUserInterfaceStyleDark;
        [s set:[UIColor colorWithWhite:dark ? 1 : 0 alpha:dark ? .21 : .24] key:@"separatorColor" on:list];
    }
}

// Collection view sizing and index navigation belong to ContactsUI. Change a native
// configuration once, when the data source supplies it; never measure or update a contact in layoutSubviews.
void CP26ConfigureContact(UICollectionReusableView *view, UICollectionView *list, BOOL sectionHeader) {
    if (![view isKindOfClass:UICollectionViewCell.class]) return;
    CP26CommunicationStyle *s=CP26StyleForView(view,CP26AppForView(list)==CP26PhoneApp);
    if (!s) return;
    UICollectionViewCell *cell=(UICollectionViewCell *)view;
    BOOL dark=list.traitCollection.userInterfaceStyle==UIUserInterfaceStyleDark;
    [s set:RowBackground(dark,cell.focused||cell.highlighted||cell.selected) key:@"backgroundConfiguration" on:cell];
    [s set:UIColor.clearColor key:@"backgroundColor" on:cell];
    if ([cell.contentConfiguration isKindOfClass:UIListContentConfiguration.class] &&
        !UIContentSizeCategoryIsAccessibilityCategory(list.traitCollection.preferredContentSizeCategory)) {
        UIListContentConfiguration *config=[(UIListContentConfiguration *)cell.contentConfiguration copy];
        config.textProperties.font=[UIFont systemFontOfSize:sectionHeader ? 11 : 12.2 weight:UIFontWeightMedium];
        NSDirectionalEdgeInsets margins=config.directionalLayoutMargins;
        margins.top=8; margins.bottom=8;
        config.directionalLayoutMargins=margins;
        [s set:config key:@"contentConfiguration" on:cell];
    }
    if (sectionHeader && NamedKind(view,@"CNContactListSectionHeaderFooterView")) {
        [s concealDrawing:[view valueForKey:@"visualEffectView"]];
    }
}

static UIView *SiriPlatter(UIView *view) {
    if (NamedKind(view,@"CNStarkHeaderPlatterView")) return view;
    for (UIView *subview in view.subviews) {
        UIView *platter=SiriPlatter(subview);
        if (platter) return platter;
    }
    return nil;
}
void CP26CommunicationSiriRow(UIView *header) {
    if (!header || CP26AppForView(header)!=CP26PhoneApp) return;
    UIView *platter=SiriPlatter(header);
    if (!platter) return;
    CP26CommunicationStyle *s=CP26StyleForView(platter,YES);
    BOOL dark=platter.traitCollection.userInterfaceStyle==UIUserInterfaceStyleDark;
    [s set:[UIColor colorWithWhite:dark ? 1 : 0 alpha:dark ? .13 : .085] key:@"backgroundColor" on:platter];
    [s set:@(MIN(16.5,platter.bounds.size.height/2)) key:@"cornerRadius" on:platter.layer];
    [s set:Primary(dark) key:@"textColor" on:[platter valueForKey:@"label"]];
}

// Place existing views in the native cell, including parts attached outside its contentView.
// An optional placeholder is the only decoration. Names, dates and accessory glyphs always come from UIKit.
static CGRect RowBox(UITableViewCell *cell, CGFloat x, CGFloat y, CGFloat w, CGFloat h) {
    if (cell.effectiveUserInterfaceLayoutDirection==UIUserInterfaceLayoutDirectionRightToLeft) x=cell.bounds.size.width-x-w;
    return CGRectMake(x,y,MAX(0,w),h);
}
static UIEdgeInsets RowInsets(UITableViewCell *cell, CGFloat screenLeading, CGFloat screenTrailing) {
    CGRect rect=[cell convertRect:cell.bounds toView:cell.window];
    BOOL rtl=cell.effectiveUserInterfaceLayoutDirection==UIUserInterfaceLayoutDirectionRightToLeft;
    CGFloat left=CGRectGetMinX(rect), right=cell.window.bounds.size.width-CGRectGetMaxX(rect);
    return UIEdgeInsetsMake(0,MAX(0,(rtl ? screenTrailing : screenLeading)-left),0,MAX(0,(rtl ? screenLeading : screenTrailing)-right));
}
static BOOL Visible(UIView *view) { return view && !view.hidden && view.alpha>.01; }
static UIImage *Placeholder(void) {
    static UIImage *image;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ image=[[UIImage systemImageNamed:@"person.crop.circle.fill"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]; });
    return image;
}
void CP26LayoutMessage(UITableViewCell *cell) {
    if (CP26AppForView(cell)!=CP26MessagesApp || ![cell respondsToSelector:@selector(primaryLabel)] ||
        ![cell respondsToSelector:@selector(primaryImageView)]) return;
    id<CP26MessageParts> parts=(id)cell;
    UILabel *title=parts.primaryLabel;
    if (!title || CGRectIsEmpty(cell.bounds)) return;
    // Larger preferred sizes keep the native geometry and UIKit's original fonts.
    if (UIContentSizeCategoryIsAccessibilityCategory(cell.traitCollection.preferredContentSizeCategory)) {
        CP26StyleForView(cell,NO); return;
    }
    CP26CommunicationStyle *s=CP26StyleForView(cell,YES);
    BOOL dark=cell.traitCollection.userInterfaceStyle==UIUserInterfaceStyleDark;
    BOOL rtl=cell.effectiveUserInterfaceLayoutDirection==UIUserInterfaceLayoutDirectionRightToLeft;
    UIEdgeInsets insets=RowInsets(cell,58,29);
    CGFloat x=rtl ? insets.right : insets.left;
    CGFloat end=cell.bounds.size.width-(rtl ? insets.left : insets.right);
    CGFloat h=cell.bounds.size.height, cy=h/2;
    [s set:[NSValue valueWithUIEdgeInsets:insets] key:@"separatorInset" on:cell];
    [s set:[UIFont systemFontOfSize:12.2 weight:UIFontWeightMedium] key:@"font" on:title];
    [s set:Primary(dark) key:@"textColor" on:title];

    UILabel *time=[parts respondsToSelector:@selector(trailingLabel)] ? parts.trailingLabel : nil;
    UILabel *detail=[parts respondsToSelector:@selector(secondaryLabel)] ? parts.secondaryLabel : nil;
    if ((!Visible(time) || !time.text.length) && Visible(detail) && detail.text.length) { time=detail; detail=nil; }
    [s set:Secondary(dark) key:@"textColor" on:time];
    [s set:[UIFont systemFontOfSize:12] key:@"font" on:time];
    [s set:@(rtl ? NSTextAlignmentLeft : NSTextAlignmentRight) key:@"textAlignment" on:time];
    CGFloat arrowX=end-16;
    UIImageView *glyph=[parts respondsToSelector:@selector(trailingGlyphView)] ? parts.trailingGlyphView : nil;
    UIImageView *status=[parts respondsToSelector:@selector(trailingImageView)] ? parts.trailingImageView : nil;
    if (Visible(glyph) && glyph.image)
        [s.positions place:glyph in:cell rect:RowBox(cell,arrowX,cy-5.5,9,11)];
    if (Visible(status) && status.image && status!=glyph) {
        if (Visible(glyph) && glyph.image) arrowX-=15;
        [s.positions place:status in:cell rect:RowBox(cell,arrowX,cy-6,12,12)];
    }
    CGFloat timeWidth=(Visible(time) && time.text.length) ? MIN(MAX(0,(end-x)*.48),ceil([time sizeThatFits:CGSizeMake(CGFLOAT_MAX,h)].width)) : 0;
    if (timeWidth>0) [s.positions place:time in:cell rect:RowBox(cell,arrowX-5-timeWidth,0,timeWidth,h)];
    CGFloat textWidth=MAX(0,arrowX-10-timeWidth-x);
    BOOL twoLines=Visible(detail) && detail.text.length>0;
    [s.positions place:title in:cell rect:RowBox(cell,x,twoLines ? cy-13 : 0,textWidth,twoLines ? 16 : h)];
    if (twoLines) {
        [s set:Secondary(dark) key:@"textColor" on:detail]; [s set:[UIFont systemFontOfSize:9.5] key:@"font" on:detail];
        [s.positions place:detail in:cell rect:RowBox(cell,x,cy+2,textWidth,12)];
    }
    UIImageView *avatar=parts.primaryImageView;
    CGFloat d=MIN(24,MAX(0,h-4));
    UIEdgeInsets avatarInsets=RowInsets(cell,27,0);
    CGRect avatarRect=RowBox(cell,rtl ? avatarInsets.right : avatarInsets.left,cy-d/2,d,d);
    BOOL hasPhoto=Visible(avatar) && avatar.image;
    if (hasPhoto) {
        [s.positions place:avatar in:cell rect:avatarRect];
        [s set:@(d/2) key:@"cornerRadius" on:avatar.layer]; [s set:@YES key:@"clipsToBounds" on:avatar];
        [s.face removeFromSuperview]; s.face=nil;
    } else {
        if (!s.face) {
            UIImageView *placeholder=[[UIImageView alloc] initWithImage:Placeholder()];
            placeholder.userInteractionEnabled=NO; placeholder.accessibilityElementsHidden=YES;
            placeholder.contentMode=UIViewContentModeScaleAspectFit; placeholder.tintColor=UIColor.whiteColor;
            placeholder.backgroundColor=[UIColor colorWithRed:.55 green:.63 blue:.80 alpha:1];
            placeholder.clipsToBounds=YES; s.face=placeholder; [cell addSubview:placeholder];
        }
        if (!CGRectEqualToRect(s.face.frame,avatarRect)) s.face.frame=avatarRect;
        if (s.face.layer.cornerRadius!=d/2) s.face.layer.cornerRadius=d/2;
    }
    UIImageView *unread=[parts respondsToSelector:@selector(unreadImageView)] ? parts.unreadImageView : nil;
    UIImageView *leading=[parts respondsToSelector:@selector(leadingGlyphView)] ? parts.leadingGlyphView : nil;
    UIEdgeInsets markInsets=RowInsets(cell,10,0); CGFloat markX=rtl ? markInsets.right : markInsets.left;
    if (Visible(unread) && unread.image) [s.positions place:unread in:cell rect:RowBox(cell,markX,cy-3.5,7,7)];
    if (Visible(leading) && leading.image) [s.positions place:leading in:cell rect:RowBox(cell,markX+(Visible(unread) && unread.image ? 8 : 0),cy-3.5,7,7)];
}
