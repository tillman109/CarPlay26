// Simulator fixtures preserve the iOS 16 cell structure, including trailing
// content owned by the cell rather than contentView. No actual contacts are used.
#import "../CommunicationUI.h"
#import <assert.h>
#define T9_ROUTING_TEST 1
#import "../T9Compatibility/T9CarPlaySupport.m"

static CP26CommunicationApp fixtureApp;
CP26CommunicationApp CP26FixtureAppForView(UIView *view) { return fixtureApp; }

@interface ExampleConversation : UITableViewCell
@property(nonatomic,strong) UILabel *primaryLabel;
@property(nonatomic,strong) UILabel *trailingLabel;
@property(nonatomic,strong) UIImageView *primaryImageView;
@property(nonatomic,strong) UIImageView *unreadImageView;
@property(nonatomic,strong) UIImageView *trailingGlyphView;
@end
@implementation ExampleConversation @end

static NSUInteger CountText(UIView *view, NSString *text) {
    NSUInteger count = [view isKindOfClass:UILabel.class] && [((UILabel *)view).text isEqualToString:text];
    for (UIView *child in view.subviews) count += CountText(child, text);
    return count;
}

static void CheckConversation(void) {
    fixtureApp = CP26MessagesApp;
    UIWindow *window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 395, 415)];
    ExampleConversation *cell = [[ExampleConversation alloc] initWithFrame:CGRectMake(0, 0, 375, 33.5)];
    [window addSubview:cell];
    cell.primaryLabel = [UILabel new]; cell.primaryLabel.text = @"Example";
    cell.trailingLabel = [UILabel new]; cell.trailingLabel.text = @"10:25 am";
    cell.primaryImageView = [UIImageView new];
    cell.unreadImageView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"circle.fill"]];
    cell.trailingGlyphView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.forward"]];
    [cell.contentView addSubview:cell.primaryLabel];
    for (UIView *v in @[cell.trailingLabel, cell.primaryImageView, cell.unreadImageView, cell.trailingGlyphView]) [cell addSubview:v];
    for (unsigned i=0; i<20; i++) CP26LayoutMessage(cell);
    CP26CommunicationStyle *style = CP26StyleForView(cell, YES);
    assert(style.face.superview==cell);
    assert(CountText(cell, @"Example")==1 && CountText(cell, @"10:25 am")==1);
    assert(CGRectGetMaxX([cell.primaryLabel convertRect:cell.primaryLabel.bounds toView:cell]) <= CGRectGetMinX(cell.trailingLabel.frame));
    assert(CGRectGetMaxX(cell.trailingLabel.frame) <= CGRectGetMinX(cell.trailingGlyphView.frame));
    NSUInteger placeholderCount = cell.subviews.count;
    cell.primaryImageView.image=[UIImage systemImageNamed:@"person.circle"];
    CP26LayoutMessage(cell);
    assert(style.face==nil && cell.subviews.count+1==placeholderCount && cell.primaryImageView.image);
    cell.primaryImageView.image=nil; CP26LayoutMessage(cell); assert(cell.subviews.count==placeholderCount);
    CP26StyleForView(cell,NO); // same cleanup as prepareForReuse
    assert(cell.subviews.count+1==placeholderCount);
    cell.primaryLabel.text=@"Second"; cell.trailingLabel.text=@"Yesterday";
    CP26LayoutMessage(cell);
    assert(CountText(cell,@"Second")==1 && CountText(cell,@"Example")==0 && CountText(cell,@"Yesterday")==1);
    cell.semanticContentAttribute=UISemanticContentAttributeForceRightToLeft;
    CP26LayoutMessage(cell);
    assert(CGRectGetMinX([cell.primaryLabel convertRect:cell.primaryLabel.bounds toView:cell]) >= CGRectGetMaxX(cell.trailingLabel.frame));
}

static void CheckContact(void) {
    fixtureApp = CP26PhoneApp;
    UICollectionViewFlowLayout *layout = [UICollectionViewFlowLayout new];
    UICollectionView *list = [[UICollectionView alloc] initWithFrame:CGRectMake(0,0,395,415) collectionViewLayout:layout];
    UICollectionViewListCell *cell = [[UICollectionViewListCell alloc] initWithFrame:CGRectMake(0,0,360,50)];
    UIListContentConfiguration *config = [cell defaultContentConfiguration];
    config.text = @"First contact"; cell.contentConfiguration=config;
    CP26ConfigureContact(cell,list,NO);
    for (unsigned i=0; i<20; i++) { [cell setNeedsLayout]; [cell layoutIfNeeded]; }
    assert(list.collectionViewLayout==layout && [((UIListContentConfiguration *)cell.contentConfiguration).text isEqual:@"First contact"]);
    CP26StyleForView(cell,NO);
    config.text=@"Second contact"; cell.contentConfiguration=config; CP26ConfigureContact(cell,list,NO);
    assert([((UIListContentConfiguration *)cell.contentConfiguration).text isEqual:@"Second contact"]);
}

@interface PHHandsetDialerView : UIView @end
@implementation PHHandsetDialerView @end
@interface PHEmergencyHandsetDialerView : PHHandsetDialerView @end
@implementation PHEmergencyHandsetDialerView @end
@interface PHCarPlayTestParent : UIViewController @end
@implementation PHCarPlayTestParent @end
@interface DialerController : UIViewController
@property(nonatomic,strong) UIView *dialerView;
@end
@implementation DialerController @end
@interface TPDialerNumberPad : UIView @end
@implementation TPDialerNumberPad @end
static IMP installed, original, nativeFixture;
static unsigned nativeLoads, handsetLoads, nativeEvents, handsetEvents;
static void FakeRegister(Class cls, SEL selector, IMP imp, IMP *previous) { installed=imp; *previous=nativeFixture; }
static void NativeLoad(DialerController *vc, SEL selector) { nativeLoads++; vc.view=vc.dialerView; }
static void HandsetLoad(id vc, SEL selector) { handsetLoads++; ((LoadMethod)original)(vc,selector); }
static void NativeEvent(id obj, SEL selector, id event) { nativeEvents++; }
static void HandsetEvent(id obj, SEL selector, id event) { handsetEvents++; ((ButtonMethod)original)(obj,selector,event); }
static void NativeTouches(id obj, SEL selector, id touches, id event) { nativeEvents++; }
static void HandsetTouches(id obj, SEL selector, id touches, id event) { handsetEvents++; ((TouchMethod)original)(obj,selector,touches,event); }

static void CheckKeypad(void) {
    DialerController *phone=[DialerController new]; phone.dialerView=[PHHandsetDialerView new];
    DialerController *car=[DialerController new]; car.dialerView=[UIView new];
    DialerController *nested=[DialerController new]; nested.dialerView=[PHHandsetDialerView new];
    PHCarPlayTestParent *parent=[PHCarPlayTestParent new]; [parent addChildViewController:nested];
    DialerController *emergency=[DialerController new]; emergency.dialerView=[PHEmergencyHandsetDialerView new];
    SEL load=@selector(loadView); nativeFixture=(IMP)NativeLoad;
    RegisterT9Method(FakeRegister,DialerController.class,load,(IMP)HandsetLoad,&original);
    for (DialerController *vc in @[car,phone,nested,emergency]) ((LoadMethod)installed)(vc,load);
    assert(nativeLoads==4 && handsetLoads==1);
    assert(UsesT9(phone) && !UsesT9(car) && !UsesT9(nested) && !UsesT9(emergency));
    SEL touch=@selector(touchesBegan:withEvent:); nativeFixture=(IMP)NativeTouches;
    RegisterT9Method(FakeRegister,DialerController.class,touch,(IMP)HandsetTouches,&original);
    for (DialerController *vc in @[phone,car,phone,nested]) ((TouchMethod)installed)(vc,touch,nil,nil);
    assert(nativeEvents==4 && handsetEvents==2);
    TPDialerNumberPad *handsetPad=[TPDialerNumberPad new], *carPad=[TPDialerNumberPad new];
    [phone.dialerView addSubview:handsetPad]; [car.dialerView addSubview:carPad];
    for (NSString *name in @[@"buttonDown:",@"buttonUp:"]) {
        SEL button=NSSelectorFromString(name); nativeFixture=(IMP)NativeEvent;
        RegisterT9Method(FakeRegister,TPDialerNumberPad.class,button,(IMP)HandsetEvent,&original);
        ((ButtonMethod)installed)(carPad,button,nil); ((ButtonMethod)installed)(handsetPad,button,nil);
    }
    assert(nativeEvents==8 && handsetEvents==4);
}

int main(void) {
    @autoreleasepool {
        CheckConversation(); CheckContact(); CheckKeypad();
        puts("Passed conversation layout, cell reuse, native contact configuration and handset/CarPlay keypad routing");
    }
    return 0;
}
