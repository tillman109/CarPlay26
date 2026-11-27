#import "CommunicationUI.h"
#import <objc/runtime.h>

static char contactSizingKey;
static const CGFloat referenceRowHeight = 33.5;
static const CGFloat referenceHeaderHeight = 34;

@protocol CP26StarkContacts <NSObject>
- (UIView *)siriHeaderView;
@end

%group CommunicationBars
%hook UITabBar
- (void)layoutSubviews { %orig; CP26CommunicationTabs(self); }
- (void)setSelectedItem:(UITabBarItem *)item { %orig; if (CP26AppForView(self)==CP26PhoneApp) [self setNeedsLayout]; }
- (CGSize)sizeThatFits:(CGSize)size {
    CGSize original=%orig;
    if (CP26AppForView(self)==CP26PhoneApp && self.items.count>=3 && self.items.count<=5) original.height=MIN(original.height,referenceHeaderHeight);
    return original;
}
- (void)didUpdateFocusInContext:(UIFocusUpdateContext *)context withAnimationCoordinator:(UIFocusAnimationCoordinator *)coordinator {
    %orig; if (CP26AppForView(self)==CP26PhoneApp) [self setNeedsLayout];
}
%end
%hook UINavigationBar
- (void)layoutSubviews { %orig; CP26CommunicationNavigation(self); }
- (CGSize)sizeThatFits:(CGSize)size {
    CGSize original=%orig;
    if (CP26AppForView(self)==CP26MessagesApp && !self.backItem) original.height=MIN(original.height,referenceHeaderHeight);
    return original;
}
%end
%end

%group PhoneSegments
%hook UISegmentedControl
- (void)layoutSubviews { %orig; CP26CommunicationSegments(self); }
- (void)setSelectedSegmentIndex:(NSInteger)index { %orig; if (CP26AppForView(self)==CP26PhoneApp) [self setNeedsLayout]; }
%end
%end

%group CommunicationTables
%hook UITableView
- (void)layoutSubviews { %orig; CP26CommunicationList(self); }
%end
%hook UITableViewCell
- (void)prepareForReuse { CP26StyleForView(self,NO); %orig; }
- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    %orig; if (CP26AppForView(self)!=CP26OtherApp) CP26CommunicationCell(self);
}
- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    %orig; if (CP26AppForView(self)!=CP26OtherApp) CP26CommunicationCell(self);
}
%end
%end

%group MessageTemplate
%hook CPSListTemplateViewController
- (CGFloat)tableView:(UITableView *)table heightForRowAtIndexPath:(NSIndexPath *)path {
    CGFloat original=%orig;
    if (CP26AppForView(table)==CP26MessagesApp && !UIContentSizeCategoryIsAccessibilityCategory(table.traitCollection.preferredContentSizeCategory)) return referenceRowHeight;
    return original;
}
%end
%end

%group PhoneContacts
%hook CNStarkContactsListViewController
- (UICollectionViewCell *)collectionView:(UICollectionView *)list cellForItemAtIndexPath:(NSIndexPath *)path {
    UICollectionViewCell *cell=%orig;
    if (CP26AppForView(list)==CP26PhoneApp) objc_setAssociatedObject(cell,&contactSizingKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return cell;
}
- (void)viewDidLayoutSubviews {
    %orig;
    UICollectionViewController *vc=(UICollectionViewController *)self;
    if (CP26AppForView(vc.viewIfLoaded)!=CP26PhoneApp) return;
    CP26CommunicationList(vc.collectionView);
    if ([vc respondsToSelector:@selector(siriHeaderView)]) CP26CommunicationSiriRow([(id<CP26StarkContacts>)self siriHeaderView]);
}
%end
%end
%group ContactCells
%hook CNContactListCollectionViewCell
- (UICollectionViewLayoutAttributes *)preferredLayoutAttributesFittingAttributes:(UICollectionViewLayoutAttributes *)input {
    UICollectionViewLayoutAttributes *result=%orig;
    UIView *view=(UIView *)self;
    if (!result || (view.window ? CP26AppForView(view)!=CP26PhoneApp : !objc_getAssociatedObject(self,&contactSizingKey))) return result;
    UICollectionViewCell *cell=(UICollectionViewCell *)self;
    if (UIContentSizeCategoryIsAccessibilityCategory(cell.traitCollection.preferredContentSizeCategory)) return result;
    UICollectionViewLayoutAttributes *fitting=[result copy];
    fitting.size=CGSizeMake(result.size.width,referenceRowHeight);
    return fitting;
}
- (void)layoutSubviews { %orig; CP26CommunicationCell((UIView *)self); }
- (void)prepareForReuse {
    CP26StyleForView((UIView *)self,NO);
    objc_setAssociatedObject(self,&contactSizingKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    %orig;
}
%end
%end
%group ContactListLayout
%hook CNContactListCollectionView
- (void)layoutSubviews { %orig; CP26CommunicationList((UIScrollView *)self); }
%end
%end

%ctor {
    @autoreleasepool {
        NSString *process=NSProcessInfo.processInfo.processName;
        BOOL phone=[process isEqualToString:@"MobilePhone"];
        BOOL templates=[process isEqualToString:@"CarPlayTemplateUIHost"];
        if ([process isEqualToString:@"CarPlay"]) { CP26StartCommunicationPreferences(YES); return; }
        if (!phone && !templates) return;
        CP26StartCommunicationPreferences(NO);
        %init(CommunicationBars);
        %init(CommunicationTables);
        if (phone) {
            %init(PhoneSegments);
            if (NSClassFromString(@"CNStarkContactsListViewController")) { %init(PhoneContacts); }
            if (NSClassFromString(@"CNContactListCollectionViewCell")) { %init(ContactCells); }
            if (NSClassFromString(@"CNContactListCollectionView")) { %init(ContactListLayout); }
        }
        if (templates && NSClassFromString(@"CPSListTemplateViewController")) { %init(MessageTemplate); }
    }
}
