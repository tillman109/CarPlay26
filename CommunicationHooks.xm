#import "CommunicationUI.h"
#import <objc/runtime.h>

static const CGFloat referenceRowHeight = 33.5;
static const CGFloat referenceHeaderHeight = 34;

@protocol CP26StarkContacts <NSObject>
- (UIView *)siriHeaderView;
@end

static void InstallTemplateHooks(void);

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
- (void)didMoveToWindow {
    %orig;
    if (self.window) {
        if (CP26AppForView(self)==CP26MessagesApp) InstallTemplateHooks();
        CP26CommunicationList(self);
    }
}
- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    %orig;
    if (self.window && [self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previous]) CP26CommunicationList(self);
}
%end
%hook UITableViewCell
- (void)didMoveToWindow {
    %orig;
    if (self.window && CP26AppForView(self)!=CP26OtherApp) CP26CommunicationRowBackground(self);
}
- (void)prepareForReuse { CP26StyleForView(self,NO); %orig; }
- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    %orig; if (CP26AppForView(self)!=CP26OtherApp) CP26CommunicationRowBackground(self);
}
- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    %orig; if (CP26AppForView(self)!=CP26OtherApp) CP26CommunicationRowBackground(self);
}
%end
%end

%group MessageCells
%hook CPUIMessageCell
- (void)layoutSubviews { %orig; CP26LayoutMessage((UITableViewCell *)self); }
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
    if ([cell isKindOfClass:NSClassFromString(@"CNContactListCollectionViewCell")]) CP26ConfigureContact(cell,list,NO);
    return cell;
}
- (UICollectionReusableView *)collectionView:(UICollectionView *)list viewForSupplementaryElementOfKind:(NSString *)kind atIndexPath:(NSIndexPath *)path {
    UICollectionReusableView *header=%orig;
    if ([kind isEqualToString:UICollectionElementKindSectionHeader]) CP26ConfigureContact(header,list,YES);
    return header;
}
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    UICollectionViewController *vc=(UICollectionViewController *)self;
    if (CP26AppForView(vc.viewIfLoaded)!=CP26PhoneApp) return;
    UICollectionView *list=vc.collectionView;
    CP26CommunicationList(list);
    for (UICollectionViewCell *cell in list.visibleCells) {
        if ([cell isKindOfClass:NSClassFromString(@"CNContactListCollectionViewCell")]) CP26ConfigureContact(cell,list,NO);
    }
    if ([vc respondsToSelector:@selector(siriHeaderView)]) CP26CommunicationSiriRow([(id<CP26StarkContacts>)self siriHeaderView]);
}
%end
%end
%group ContactReuse
%hook CNContactListCollectionViewCell
- (void)prepareForReuse { CP26StyleForView((UIView *)self,NO); %orig; }
%end
%end

static void InstallTemplateHooks(void) {
    static dispatch_once_t cells, heights;
    if (NSClassFromString(@"CPUIMessageCell")) dispatch_once(&cells, ^{ %init(MessageCells); });
    Class controller=NSClassFromString(@"CPSListTemplateViewController");
    if (class_getInstanceMethod(controller,@selector(tableView:heightForRowAtIndexPath:)))
        dispatch_once(&heights, ^{ %init(MessageTemplate); });
}

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
            if (NSClassFromString(@"CNContactListCollectionViewCell")) { %init(ContactReuse); }
        }
        if (templates) InstallTemplateHooks();
    }
}
