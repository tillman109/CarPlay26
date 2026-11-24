#import "CP26PreferencesUI.h"
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSSwitchTableCell.h>
#import <UIKit/UIKit.h>
#import <math.h>

static NSString *const CP26HelpKey = @"CP26Help";
static const CGFloat CP26HelpTarget = 44;
static const CGFloat CP26SwitchGap = 8;

static UIFont *CP26SwitchFont(UITraitCollection *traits) {
    return [UIFont preferredFontForTextStyle:UIFontTextStyleBody compatibleWithTraitCollection:traits];
}

@implementation CP26SettingsListController

- (CGFloat)tableView:(UITableView *)table heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    CGFloat original = [super tableView:table heightForRowAtIndexPath:indexPath];
    PSSpecifier *item = [self specifierAtIndexPath:indexPath];
    if (![item propertyForKey:CP26HelpKey]) return original;

    // An inset-grouped row has section margins, internal cell padding and the
    // native switch. Reserve the help button's full touch target before wrapping.
    CGFloat width = CGRectGetWidth(table.safeAreaLayoutGuide.layoutFrame);
    if (width <= 0) width = CGRectGetWidth(table.bounds);
    if (width <= 0) return MAX(CP26HelpTarget,original);
    CGFloat groupWidth = width - MAX(20,table.layoutMargins.left) - MAX(20,table.layoutMargins.right);
    CGFloat readable = CGRectGetWidth(table.readableContentGuide.layoutFrame);
    if (readable > 0) groupWidth = MIN(groupWidth,readable);
    CGFloat iconWidth = [item propertyForKey:@"icon"] ? 45 : 0;
    CGFloat textWidth = MAX(24,groupWidth - 40 - 51 - CP26SwitchGap - CP26HelpTarget - iconWidth);
    CGRect text = [item.name boundingRectWithSize:CGSizeMake(textWidth,CGFLOAT_MAX)
        options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
        attributes:@{NSFontAttributeName:CP26SwitchFont(table.traitCollection)} context:nil];
    return MAX(MAX(original,CP26HelpTarget),ceil(text.size.height)+16);
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    if (previous && self.isViewLoaded &&
        ![previous.preferredContentSizeCategory isEqual:self.traitCollection.preferredContentSizeCategory])
        [self.tableView reloadData];
}
@end

// Each category link names a native specifier plist in this preference bundle.
@interface CP26CategoryController : CP26SettingsListController
@property(nonatomic,copy) NSString *loadedPane;
@end

@implementation CP26CategoryController
- (NSArray *)specifiers {
    NSString *pane = [self.specifier propertyForKey:@"CP26Pane"];
    if (pane.length && (!_specifiers || ![self.loadedPane isEqualToString:pane])) {
        _specifiers = [self loadSpecifiersFromPlistName:pane target:self];
        self.loadedPane = pane;
    }
    return _specifiers;
}
@end

@interface CP26InfoSwitchCell : PSSwitchTableCell
@property(nonatomic,strong) UILabel *nameLabel;
@property(nonatomic,strong) UIButton *infoButton;
@end

@implementation CP26InfoSwitchCell

- (void)installHelpViews {
    UILabel *label = [UILabel new];
    label.numberOfLines = 0;
    label.adjustsFontForContentSizeCategory = YES;
    label.textAlignment = NSTextAlignmentNatural;
    label.isAccessibilityElement = NO;
    self.nameLabel = label;
    [self.contentView addSubview:label];

    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImageSymbolConfiguration *symbol = [UIImageSymbolConfiguration configurationWithPointSize:18
        weight:UIImageSymbolWeightRegular];
    [button setImage:[UIImage systemImageNamed:@"info.circle" withConfiguration:symbol]
            forState:UIControlStateNormal];
    [button addTarget:self action:@selector(showSettingInfo:) forControlEvents:UIControlEventTouchUpInside];
    self.infoButton = button;
    [self.contentView addSubview:button];
}

// Let VoiceOver navigate the native switch and the independent help button.
- (BOOL)isAccessibilityElement { return NO; }

- (void)layoutSubviews {
    [super layoutSubviews];
    if (!self.infoButton) [self installHelpViews];

    PSSpecifier *item = self.specifier;
    NSString *title = item.name ?: @"";
    UIView *content = self.contentView;
    UILabel *native = self.titleLabel;
    if (!native.superview) native = self.textLabel;
    UIControl *toggle = self.control;
    BOOL rtl = self.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    CGFloat left = CGRectGetMinX(content.bounds) + content.layoutMargins.left;
    CGFloat right = CGRectGetMaxX(content.bounds) - content.layoutMargins.right;
    // Use the native title's leading edge to honour Settings' icon and layout margins.
    // The original label stays in the layout so Preferences can measure it again on reuse.
    if (native.superview && !CGRectIsEmpty(native.bounds)) {
        CGRect f = [content convertRect:native.bounds fromView:native];
        if (rtl) right = MIN(right,CGRectGetMaxX(f)); else left = MAX(left,CGRectGetMinX(f));
    }
    if (native.alpha != 0) native.alpha = 0;
    if (native.isAccessibilityElement) native.isAccessibilityElement = NO;
    if (toggle.superview && !CGRectIsEmpty(toggle.bounds)) {
        CGRect f = [content convertRect:toggle.bounds fromView:toggle];
        if (rtl) left = MAX(left,CGRectGetMaxX(f)+CP26SwitchGap);
        else right = MIN(right,CGRectGetMinX(f)-CP26SwitchGap);
    }

    if (![self.nameLabel.text isEqualToString:title]) {
        self.nameLabel.text = title;
        self.infoButton.accessibilityLabel = [NSString stringWithFormat:@"About %@",title];
    }
    UIFont *font = CP26SwitchFont(self.traitCollection);
    if (![self.nameLabel.font isEqual:font]) self.nameLabel.font = font;
    UIColor *color = toggle && !toggle.enabled ? UIColor.secondaryLabelColor : UIColor.labelColor;
    if (![self.nameLabel.textColor isEqual:color]) self.nameLabel.textColor = color;
    CGFloat available = MAX(0,right-left);
    CGFloat buttonWidth = MIN(available,CP26HelpTarget);
    CGFloat textLimit = available-buttonWidth;
    CGSize fit = [self.nameLabel sizeThatFits:CGSizeMake(textLimit,CGFLOAT_MAX)];
    CGFloat textWidth = MIN(textLimit,ceil(fit.width));
    CGFloat height = CGRectGetHeight(content.bounds);
    CGFloat textHeight = MIN(height,ceil(fit.height));
    CGFloat textX = rtl ? right-textWidth : left;
    CGFloat infoX = rtl ? textX-buttonWidth : textX+textWidth;
    CGFloat midY = CGRectGetMidY(content.bounds);
    CGRect labelFrame = CGRectMake(textX,floor(midY-textHeight/2),textWidth,textHeight);
    if (!CGRectEqualToRect(self.nameLabel.frame,labelFrame)) self.nameLabel.frame = labelFrame;
    CGFloat buttonHeight = MIN(CP26HelpTarget,height);
    CGRect infoFrame = CGRectMake(infoX,floor(midY-buttonHeight/2),buttonWidth,buttonHeight);
    if (!CGRectEqualToRect(self.infoButton.frame,infoFrame)) self.infoButton.frame = infoFrame;

    if (toggle) {
        if (!toggle.isAccessibilityElement) toggle.isAccessibilityElement = YES;
        if (![toggle.accessibilityLabel isEqualToString:title]) toggle.accessibilityLabel = title;
        NSArray *order = self.accessibilityElements;
        if (order.count != 2 || order.firstObject != toggle || order.lastObject != self.infoButton)
            self.accessibilityElements = @[toggle,self.infoButton];
    }
}

// Some Preferences cells forward row taps to their switch. Route taps inside
// the help target to its button, then leave the rest of the row to Preferences.
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIButton *info = self.infoButton;
    if (info && self.userInteractionEnabled && !self.hidden && self.alpha > .01 &&
        [self pointInside:point withEvent:event]) {
        UIView *hit = [info hitTest:[info convertPoint:point fromView:self] withEvent:event];
        if (hit) return hit;
    }
    return [super hitTest:point withEvent:event];
}

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
    [super refreshCellContentsWithSpecifier:specifier];
    [self setNeedsLayout];
}

- (void)showSettingInfo:(UIButton *)sender {
    PSSpecifier *item = self.specifier;
    NSString *help = [item propertyForKey:CP26HelpKey];
    if (!help.length || !sender.window) return;

    // Present in the Settings page which owns this specific switch. Reading
    // the specifier at tap time also covers cells reused after a list refresh.
    UIViewController *owner = item.target;
    if (![owner isKindOfClass:UIViewController.class] || owner.viewIfLoaded.window != sender.window) {
        owner = nil;
        for (UIResponder *r = self.nextResponder; r; r = r.nextResponder) {
            if ([r isKindOfClass:PSListController.class]) { owner = (UIViewController *)r; break; }
        }
    }
    if (!owner || owner.presentedViewController) return;
    UIAlertController *info = [UIAlertController alertControllerWithTitle:item.name
        message:help preferredStyle:UIAlertControllerStyleAlert];
    [info addAction:[UIAlertAction actionWithTitle:@"Done" style:UIAlertActionStyleDefault handler:nil]];
    [owner presentViewController:info animated:YES completion:nil];
}
@end
