#import "CommunicationUI.h"
#import <objc/runtime.h>

static BOOL communicationEnabled;
static CFStringRef const prefDomain = CFSTR("com.tillman109.carplay26");
static CFStringRef const stateRequest = CFSTR("com.tillman109.carplay26.communications.request");
static CFStringRef const stateOn = CFSTR("com.tillman109.carplay26.communications.on");
static CFStringRef const stateOff = CFSTR("com.tillman109.carplay26.communications.off");

static BOOL ReadSettings(void) {
    CFPreferencesAppSynchronize(prefDomain);
    Boolean found = false;
    BOOL selected = CFPreferencesGetAppBooleanValue(CFSTR("CommunicationAppearance"), prefDomain, &found);
    return (!found || selected) && CFPreferencesGetAppBooleanValue(CFSTR("Enabled"), prefDomain, NULL);
}
static void RefreshSurfaces(UIView *view) {
    if (!communicationEnabled) CP26StyleForView(view, NO);
    if ([view isKindOfClass:UIScrollView.class] || [view isKindOfClass:UITabBar.class] ||
        [view isKindOfClass:UINavigationBar.class] || [view isKindOfClass:UISegmentedControl.class]) [view setNeedsLayout];
    for (UIView *child in view.subviews) RefreshSurfaces(child);
}
static void ReceivePreference(CFNotificationCenterRef center, void *observer, CFStringRef name,
                              const void *object, CFDictionaryRef userInfo) {
    BOOL request = CFEqual(name, stateRequest);
    BOOL enabled = CFEqual(name, stateOn);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (request) {
            CFNotificationCenterPostNotification(center, ReadSettings() ? stateOn : stateOff, NULL, NULL, true);
            return;
        }
        if (enabled == communicationEnabled) return;
        communicationEnabled = enabled;
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene.session.role isEqualToString:@"UIWindowSceneSessionRoleCarPlay"] || ![scene isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) RefreshSurfaces(window);
        }
    });
}
void CP26StartCommunicationPreferences(BOOL shell) {
    CFNotificationCenterRef center=CFNotificationCenterGetDarwinNotifyCenter();
    if (shell) {
        CFNotificationCenterAddObserver(center, NULL, ReceivePreference, stateRequest, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterPostNotification(center, ReadSettings() ? stateOn : stateOff, NULL, NULL, true);
    } else {
        communicationEnabled=ReadSettings();
        CFNotificationCenterAddObserver(center, NULL, ReceivePreference, stateOn, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(center, NULL, ReceivePreference, stateOff, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterPostNotification(center, stateRequest, NULL, NULL, true);
    }
}

@protocol CP26ProxyScene <NSObject>
- (id<CP26ProxyScene>)_scene;
- (id<CP26ProxyScene>)settings;
- (NSString *)proxiedApplicationBundleIdentifier;
- (NSString *)identifier;
@end

CP26CommunicationApp CP26AppForView(UIView *view) {
    if (!communicationEnabled) return CP26OtherApp;
    UIWindowScene *scene = view.window.windowScene;
    if (![scene.session.role isEqualToString:@"UIWindowSceneSessionRoleCarPlay"]) return CP26OtherApp;
    NSString *bundle = NSBundle.mainBundle.bundleIdentifier;
    if ([bundle isEqualToString:@"com.apple.mobilephone"]) return CP26PhoneApp;
    // CarPlayTemplateUIHost has one scene per client. A cached Spotify scene can
    // still receive layout while Messages is visible. Use this specific scene's owner.
    id<CP26ProxyScene> client = (id)scene;
    id<CP26ProxyScene> native = [client respondsToSelector:@selector(_scene)] ? client._scene : nil;
    id<CP26ProxyScene> settings = [native respondsToSelector:@selector(settings)] ? native.settings : nil;
    NSString *owner = [settings respondsToSelector:@selector(proxiedApplicationBundleIdentifier)] ? settings.proxiedApplicationBundleIdentifier : nil;
    if (owner.length) {
        if ([owner isEqualToString:@"com.apple.MobileSMS"]) return CP26MessagesApp;
        if ([owner isEqualToString:@"com.apple.mobilephone"]) return CP26PhoneApp;
        return CP26OtherApp;
    }
    // Some hosts label the scene rather than exposing the proxy settings subclass.
    // Match a complete bundle component and never infer identity from a visible tab or a contact name.
    NSString *identifier=[native respondsToSelector:@selector(identifier)] ? native.identifier : nil;
    static NSCharacterSet *delimiters;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ delimiters=[NSCharacterSet characterSetWithCharactersInString:@":/-_[] "]; });
    for (NSString *name in @[identifier ?: @"",scene.session.persistentIdentifier ?: @""]) {
        NSArray *parts=[name componentsSeparatedByCharactersInSet:delimiters];
        if ([parts containsObject:@"com.apple.MobileSMS"]) return CP26MessagesApp;
        if ([parts containsObject:@"com.apple.mobilephone"]) return CP26PhoneApp;
    }
    return CP26OtherApp;
}

@implementation CP26CommunicationStyle {
    NSMapTable<id, NSMutableDictionary *> *_edits;
}
- (instancetype)init {
    if ((self = [super init])) {
        _edits = [NSMapTable weakToStrongObjectsMapTable];
        _positions = [CP26PlacedViews new];
    }
    return self;
}
- (void)set:(id)value key:(NSString *)key on:(id)object {
    if (!object) return;
    id current = [object valueForKey:key] ?: NSNull.null;
    id next = value ?: NSNull.null;
    if ([current isEqual:next]) return;
    NSMutableDictionary *edits = [_edits objectForKey:object];
    if (!edits) { edits = [NSMutableDictionary dictionary]; [_edits setObject:edits forKey:object]; }
    NSArray *entry = edits[key];
    id original = [current isEqual:entry.lastObject] ? entry.firstObject : current;
    [object setValue:value forKey:key];
    edits[key] = @[original, [object valueForKey:key] ?: NSNull.null];
}
- (void)concealDrawing:(UIView *)view {
    if (!view || view.layer.mask) return;
    // A transparent rendering mask leaves the native control enabled for taps, focus and VoiceOver.
    [self set:[CALayer layer] key:@"mask" on:view.layer];
}
- (void)restore {
    [_positions restore];
    for (id object in _edits.keyEnumerator.allObjects) {
        NSDictionary *edits = [_edits objectForKey:object];
        for (NSString *key in edits) {
            NSArray *entry = edits[key];
            if ([([object valueForKey:key] ?: NSNull.null) isEqual:entry.lastObject])
                [object setValue:entry.firstObject == NSNull.null ? nil : entry.firstObject forKey:key];
        }
    }
    [_face removeFromSuperview];
    [_field removeFromSuperview];
}
@end

CP26CommunicationStyle *CP26StyleForView(UIView *view, BOOL active) {
    static char key;
    CP26CommunicationStyle *style = objc_getAssociatedObject(view, &key);
    if (active && !style) {
        style = [CP26CommunicationStyle new];
        objc_setAssociatedObject(view, &key, style, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else if (!active && style) {
        [style restore];
        objc_setAssociatedObject(view, &key, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return nil;
    }
    return style;
}
