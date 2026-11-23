#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>

// Dedicated CarPlay26 Spotify page. The action is a one-shot Darwin request;
// the template host reports completion by writing to its own sandbox.
// Sending a notification is not evidence that a report was saved.
@interface CP26SpotifyController : PSListController
- (void)captureSpotifyReport;
- (id)readSpotifyHomeStyling:(PSSpecifier *)specifier;
- (void)setSpotifyHomeStyling:(id)value specifier:(PSSpecifier *)specifier;
- (id)readSpotifyPillNavigation:(PSSpecifier *)specifier;
- (void)setSpotifyPillNavigation:(id)value specifier:(PSSpecifier *)specifier;
@end

@implementation CP26SpotifyController
- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Spotify" target:self];
    }
    return _specifiers;
}

// PSSwitchCell calls these methods explicitly from Spotify.plist. Persist the
// existing preference key before broadcasting the requested state. Darwin
// notifications have no payload, so the two names encode ON and OFF without
// requiring a synchronous cross-process preference read in the CarPlay shell.
- (id)readSpotifyHomeStyling:(__unused PSSpecifier *)specifier {
    CFPreferencesAppSynchronize(CFSTR("com.tillman109.carplay26"));
    Boolean valid = false;
    Boolean enabled = CFPreferencesGetAppBooleanValue(
        CFSTR("SpotifyHomeStyling"), CFSTR("com.tillman109.carplay26"), &valid);
    return @(valid && enabled);
}

- (void)setSpotifyHomeStyling:(id)value specifier:(PSSpecifier *)specifier {
    BOOL enabled = [value respondsToSelector:@selector(boolValue)] && [value boolValue];
    CFPreferencesSetAppValue(CFSTR("SpotifyHomeStyling"),
        enabled ? kCFBooleanTrue : kCFBooleanFalse,
        CFSTR("com.tillman109.carplay26"));
    if (!CFPreferencesAppSynchronize(CFSTR("com.tillman109.carplay26"))) {
        [self reloadSpecifier:specifier animated:NO];
        if (!self.presentedViewController) {
            UIAlertController *alert = [UIAlertController
                alertControllerWithTitle:@"Spotify setting not saved"
                message:@"CarPlay26 could not save the Spotify Home Styling setting. Try again before testing the appearance."
                preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        }
        return;
    }
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        enabled ? CFSTR("com.tillman109.carplay26.spotify.style.enable") :
                  CFSTR("com.tillman109.carplay26.spotify.style.disable"),
        NULL, NULL, TRUE);
}

// A separate, opt-in switch for the native Spotify navigation experiment.
// ON/OFF are conveyed through distinct Darwin names to the CarPlay shell;
// the template host never needs to read Settings across sandbox boundaries.
- (id)readSpotifyPillNavigation:(__unused PSSpecifier *)specifier {
    CFPreferencesAppSynchronize(CFSTR("com.tillman109.carplay26"));
    Boolean valid=false;
    Boolean enabled=CFPreferencesGetAppBooleanValue(CFSTR("SpotifyPillNavigation"),
        CFSTR("com.tillman109.carplay26"),&valid);
    return @(valid && enabled);
}
- (void)setSpotifyPillNavigation:(id)value specifier:(PSSpecifier *)specifier {
    BOOL enabled=[value respondsToSelector:@selector(boolValue)] && [value boolValue];
    CFPreferencesSetAppValue(CFSTR("SpotifyPillNavigation"),
        enabled?kCFBooleanTrue:kCFBooleanFalse,
        CFSTR("com.tillman109.carplay26"));
    if (!CFPreferencesAppSynchronize(CFSTR("com.tillman109.carplay26"))) {
        [self reloadSpecifier:specifier animated:NO];
        if (!self.presentedViewController) {
            UIAlertController *alert=[UIAlertController
                alertControllerWithTitle:@"Spotify navigation setting not saved"
                message:@"The change could not be saved, so no navigation update was sent."
                preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        }
        return;
    }
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        enabled?CFSTR("com.tillman109.carplay26.spotify.nav.enable"):
                CFSTR("com.tillman109.carplay26.spotify.nav.disable"),
        NULL,NULL,TRUE);
}

- (void)captureSpotifyReport {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.tillman109.carplay26.spotify.capture"), NULL, NULL, TRUE);
    if (self.presentedViewController) return;
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Spotify capture requested"
        message:@"A read-only request was sent to CarPlayTemplateUIHost. Keep Spotify open on the Home screen in WinPlay. If the host is running and receives the request, it saves CarPlay26-Spotify-TemplateUIHost.txt in its own cache or temporary directory. This alert does not confirm that the report was written."
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK"
        style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
@end
