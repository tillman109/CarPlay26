// Loaded only as a private dependency of the user's T9Dialer 1.14 library.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>

@protocol T9NativeDialer <NSObject>
- (UIView *)dialerView;
@end

typedef void (*RegisterMethod)(Class, SEL, IMP, IMP *);
typedef void (*LoadMethod)(id, SEL);
typedef void (*ButtonMethod)(id, SEL, id);
typedef void (*AppearanceMethod)(id, SEL, BOOL);
typedef void (*TouchMethod)(id, SEL, id, id);
typedef void (*ObserverMethod)(id, SEL, id, id, id, void *);
static char handsetControllerKey;

static BOOL IsHandsetDialer(UIView *view) {
    return [view isKindOfClass:NSClassFromString(@"PHHandsetDialerView")] &&
          ![view isKindOfClass:NSClassFromString(@"PHEmergencyHandsetDialerView")];
}

static BOOL OutsideHandset(UIView *view) {
    UIWindowScene *scene = view.window.windowScene;
    return (scene && ![scene.session.role isEqualToString:UIWindowSceneSessionRoleApplication]) ||
           view.traitCollection.userInterfaceIdiom == UIUserInterfaceIdiomCarPlay;
}

static BOOL IsCarOrEmergencyOwner(UIViewController *vc) {
    for (UIViewController *owner = vc; owner; owner = owner.parentViewController) {
        if (OutsideHandset(owner.viewIfLoaded) || owner.traitCollection.userInterfaceIdiom == UIUserInterfaceIdiomCarPlay)
            return YES;
        for (Class cls = object_getClass(owner); cls && cls != UIViewController.class; cls = class_getSuperclass(cls)) {
            NSString *name = NSStringFromClass(cls);
            if ([name hasPrefix:@"PHCarPlay"] || [name hasPrefix:@"PHEmergency"]) return YES;
        }
    }
    return NO;
}

static BOOL HasHandsetDialer(UIView *view) {
    if (IsHandsetDialer(view)) return YES;
    for (UIView *child in view.subviews) if (HasHandsetDialer(child)) return YES;
    return NO;
}

static BOOL LoadedHandset(UIViewController *vc) {
    if (!vc.viewIfLoaded || IsCarOrEmergencyOwner(vc)) return NO;
    if ([vc respondsToSelector:@selector(dialerView)]) {
        UIView *dialer = [(id<T9NativeDialer>)vc dialerView];
        if (dialer) return IsHandsetDialer(dialer) && !OutsideHandset(dialer);
    }
    return HasHandsetDialer(vc.viewIfLoaded);
}

static BOOL UsesT9(UIViewController *vc) {
    return objc_getAssociatedObject(vc, &handsetControllerKey) && !IsCarOrEmergencyOwner(vc);
}

static BOOL HandsetNumberPad(UIView *pad) {
    if (OutsideHandset(pad)) return NO;
    BOOL handset = NO;
    for (UIResponder *owner = pad; owner; owner = owner.nextResponder) {
        if ([owner isKindOfClass:UIViewController.class])
            return handset && !IsCarOrEmergencyOwner((UIViewController *)owner);
        if ([owner isKindOfClass:UIView.class] && IsHandsetDialer((UIView *)owner)) handset = YES;
    }
    return handset;
}

// Both slices of 1.14 start their loadView replacement by calling its saved
// predecessor. The router runs that predecessor once before inspecting the actual
// dialer UIKit created, even when the view is not yet attached to a scene.
static void AlreadyLoaded(id receiver, SEL selector) {}

static void RegisterT9Method(RegisterMethod install, Class cls, SEL selector, IMP t9, IMP *saved) {
    if (!cls || !selector || !t9) return;
    __block IMP native = NULL;
    IMP routed = NULL;
    BOOL load = NO;
    if (cls == NSClassFromString(@"DialerController")) {
        if (selector == @selector(loadView)) {
            load = YES;
            routed = imp_implementationWithBlock(^(UIViewController *vc) {
                objc_setAssociatedObject(vc, &handsetControllerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                ((LoadMethod)native)(vc, selector);
                if (LoadedHandset(vc)) {
                    objc_setAssociatedObject(vc, &handsetControllerKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    ((LoadMethod)t9)(vc, selector);
                }
            });
        } else if (selector == @selector(touchesBegan:withEvent:) || selector == @selector(touchesMoved:withEvent:) ||
                   selector == @selector(touchesEnded:withEvent:)) {
            routed = imp_implementationWithBlock(^(UIViewController *vc, NSSet *touches, UIEvent *event) {
                ((TouchMethod)(UsesT9(vc) ? t9 : native))(vc, selector, touches, event);
            });
        } else if (selector == @selector(observeValueForKeyPath:ofObject:change:context:)) {
            routed = imp_implementationWithBlock(^(UIViewController *vc, NSString *key, id object, NSDictionary *change, void *context) {
                ((ObserverMethod)(UsesT9(vc) ? t9 : native))(vc, selector, key, object, change, context);
            });
        }
    } else if (cls == NSClassFromString(@"TPDialerNumberPad") &&
               (sel_isEqual(selector, NSSelectorFromString(@"buttonDown:")) || sel_isEqual(selector, NSSelectorFromString(@"buttonUp:")))) {
        routed = imp_implementationWithBlock(^(UIView *pad, id button) {
            ((ButtonMethod)(HandsetNumberPad(pad) ? t9 : native))(pad, selector, button);
        });
    } else if (cls == NSClassFromString(@"PhoneTabBarController") && selector == @selector(viewWillAppear:)) {
        routed = imp_implementationWithBlock(^(UIViewController *vc, BOOL animated) {
            UIView *view = vc.viewIfLoaded;
            BOOL handset = !IsCarOrEmergencyOwner(vc) && (view.window.windowScene ||
                           vc.traitCollection.userInterfaceIdiom == UIUserInterfaceIdiomPhone);
            ((AppearanceMethod)(handset ? t9 : native))(vc, selector, animated);
        });
    }
    if (!routed) {
        install(cls, selector, t9, saved);
        return;
    }
    install(cls, selector, routed, &native);
    if (saved) *saved = load ? (IMP)AlreadyLoaded : native;
}

#ifndef T9_ROUTING_TEST
// Resolve the genuine registrar from Substrate's own image. No global symbol
// interposition or change to another tweak's registrations is involved.
extern void *MSGetImageByName(const char *);
__attribute__((visibility("default")))
void MSHookMessageEx(Class cls, SEL selector, IMP replacement, IMP *original) {
    static RegisterMethod substrate;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Dl_info info = {0};
        if (dladdr((const void *)&MSGetImageByName, &info) && info.dli_fname) {
            void *handle = dlopen(info.dli_fname, RTLD_LAZY | RTLD_LOCAL);
            if (handle) substrate = (RegisterMethod)dlsym(handle, "MSHookMessageEx");
        }
        if (!substrate || substrate == &MSHookMessageEx) {
            void *handle = dlopen("@rpath/CydiaSubstrate.framework/CydiaSubstrate", RTLD_LAZY | RTLD_LOCAL);
            substrate = handle ? (RegisterMethod)dlsym(handle, "MSHookMessageEx") : NULL;
        }
    });
    if (substrate && substrate != &MSHookMessageEx) RegisterT9Method(substrate, cls, selector, replacement, original);
}
#endif
