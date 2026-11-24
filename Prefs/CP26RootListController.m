#import "CP26PreferencesUI.h"
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <CoreFoundation/CoreFoundation.h>

// Resolve these private system APIs at runtime; no jailbreak binary paths.
@interface CP26RootListController : CP26SettingsListController
- (void)respring;
- (void)restartCarPlay;
- (void)captureWallpaperReport;
- (void)requestCarPlayRestart;
- (void)showCarPlayRestartError;
- (void)requestRespring;
- (void)showRespringError;
@end

@interface SBSRelaunchAction : NSObject
+ (instancetype)actionWithReason:(NSString *)reason
                         options:(NSUInteger)options
                       targetURL:(NSURL *)targetURL;
@end

@interface FBSSystemService : NSObject
+ (instancetype)sharedService;
- (void)sendActions:(NSSet *)actions withResult:(id)result;
@end

@implementation CP26RootListController
- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

// No shared preference read is required in the two sandboxed wallpaper apps.
// The button is a one-shot, read-only request; success is confirmed only by
// the resulting diagnostic report inside each app container.
- (void)captureWallpaperReport {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.tillman109.carplay26.wallpaper.capture"), NULL, NULL, true);
    if (self.presentedViewController) return;
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Wallpaper capture requested"
        message:@"A read-only capture request was sent to the wallpaper processes. Keep CarPlay Settings > Wallpaper open in WinPlay. The report is saved in each app's own container if it is running."
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK"
        style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)restartCarPlay {
    if (self.presentedViewController) return;
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Restart CarPlay Services?"
        message:@"Only the CarPlay interface will restart. Use while parked or in WinPlay. This may disconnect CarPlay; reconnect if needed. Your iPhone will not respring."
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
        style:UIAlertActionStyleCancel handler:nil]];
    __weak CP26RootListController *weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Restart CarPlay"
        style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
            [weakSelf requestCarPlayRestart];
        }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)requestCarPlayRestart {
    NSDictionary *request = @{@"token": NSUUID.UUID.UUIDString,
        @"time": @(NSDate.date.timeIntervalSince1970)};
    CFPreferencesSetAppValue(CFSTR("RestartRequest"), (__bridge CFPropertyListRef)request,
        CFSTR("com.tillman109.carplay26"));
    if (!CFPreferencesAppSynchronize(CFSTR("com.tillman109.carplay26"))) {
        [self showCarPlayRestartError];
        return;
    }
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.tillman109.carplay26.restart"), NULL, NULL, true);
    // Posting is not a confirmation that the receiver relaunched.
}

- (void)showCarPlayRestartError {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!self.viewIfLoaded.window || self.presentedViewController) return;
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:@"Restart request unavailable"
            message:@"Could not save the CarPlay restart request. Use Respring instead."
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    });
}

- (void)respring {
    if (self.presentedViewController) return;
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Respring?"
        message:@"Disconnect CarPlay before respringing. Your iPhone interface will briefly restart to apply your settings."
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
        style:UIAlertActionStyleCancel handler:nil]];
    __weak CP26RootListController *weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Respring"
        style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
            [weakSelf requestRespring];
        }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)requestRespring {
    // System frameworks live outside the randomized RootHide bootstrap.
    dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_LAZY | RTLD_LOCAL);
    dlopen("/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices", RTLD_LAZY | RTLD_LOCAL);
    Class actionClass = NSClassFromString(@"SBSRelaunchAction");
    Class serviceClass = NSClassFromString(@"FBSSystemService");
    if (![actionClass respondsToSelector:@selector(actionWithReason:options:targetURL:)] ||
        ![serviceClass respondsToSelector:@selector(sharedService)]) {
        [self showRespringError];
        return;
    }
    @try {
        FBSSystemService *service = [serviceClass sharedService];
        // RestartRenderServer (1) | FadeToBlackTransition (4).
        SBSRelaunchAction *action = [actionClass actionWithReason:@"RestartRenderServer"
            options:5 targetURL:nil];
        if (!action || ![service respondsToSelector:@selector(sendActions:withResult:)]) {
            [self showRespringError];
            return;
        }
        [service sendActions:[NSSet setWithObject:action] withResult:nil];
    } @catch (NSException *exception) {
        NSLog(@"CarPlay26: respring request failed: %@", exception);
        [self showRespringError];
    }
}

- (void)showRespringError {
    // Wait for the confirmation alert to dismiss before showing the error.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!self.viewIfLoaded.window || self.presentedViewController) return;
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:@"Respring unavailable"
            message:@"Please respring using your usual jailbreak utility."
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    });
}
@end

@interface CP26DiagnosticsController : CP26RootListController
@end

@implementation CP26DiagnosticsController
- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Diagnostics" target:self];
    }
    return _specifiers;
}
@end

@interface CP26ChangelogController : PSListController
@end

@implementation CP26ChangelogController
- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Changelog" target:self];
    }
    return _specifiers;
}
@end
