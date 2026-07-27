//
//  AppDelegate.m
//  Sameru
//
//  Created by Vincent Yang  on 7/27/26.
//

#import "AppDelegate.h"

#import "SMRCleanModeController.h"
#import "SMRFanController.h"
#import "SMRKeepAwakeController.h"
#import "SMRLoginItemController.h"
#import "SMRPanelViewController.h"

#import <Sparkle/Sparkle.h>

@interface AppDelegate () <NSPopoverDelegate>

@property (nonatomic, strong) NSStatusItem *statusItem;
@property (nonatomic, strong) NSPopover *popover;
@property (nonatomic, strong) SMRPanelViewController *panelViewController;

@property (nonatomic, strong) SMRKeepAwakeController *keepAwakeController;
@property (nonatomic, strong) SMRCleanModeController *cleanModeController;
@property (nonatomic, strong) SMRFanController *fanController;
@property (nonatomic, strong) SMRLoginItemController *loginItemController;
@property (nonatomic, strong) SPUStandardUpdaterController *updaterController;

@end

@implementation AppDelegate

#pragma mark - Lifecycle

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    self.keepAwakeController = [[SMRKeepAwakeController alloc] init];
    self.fanController = [[SMRFanController alloc] init];
    self.cleanModeController = [[SMRCleanModeController alloc] init];
    self.loginItemController = [[SMRLoginItemController alloc] init];

    __weak typeof(self) weakSelf = self;
    self.cleanModeController.onEnd = ^(NSString *message) {
        [weakSelf handleCleanModeEndedWithMessage:message];
    };

    // startingUpdater:YES begins the scheduled background check described by
    // SUEnableAutomaticChecks / SUScheduledCheckInterval in Info.plist.
    self.updaterController = [[SPUStandardUpdaterController alloc] initWithStartingUpdater:YES
                                                                          updaterDelegate:nil
                                                                       userDriverDelegate:nil];

    [self buildStatusItem];
    [self buildPopover];

    // Quitting restores automatic control, so re-arm the remembered mode here.
    // This is prompt-free: it is skipped unless the helper is already installed.
    [self.fanController reapplyCurrentModeIfNeeded];

    // A forced fan target does not always survive a sleep cycle.
    [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self
                                                       selector:@selector(handleSystemDidWake:)
                                                           name:NSWorkspaceDidWakeNotification
                                                         object:nil];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    [self.cleanModeController stop];
    [self.keepAwakeController deactivate];
    [self.fanController restoreAutomaticControlIfNeeded];
}

- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
    return YES;
}

#pragma mark - Status item

- (void)buildStatusItem {
    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.toolTip = @"Sameru";
    self.statusItem.button.target = self;
    self.statusItem.button.action = @selector(togglePopover:);

    [self updateStatusItemImage];
}

- (void)buildPopover {
    self.panelViewController =
        [[SMRPanelViewController alloc] initWithKeepAwakeController:self.keepAwakeController
                                               cleanModeController:self.cleanModeController
                                                     fanController:self.fanController
                                               loginItemController:self.loginItemController];

    __weak typeof(self) weakSelf = self;
    self.panelViewController.onStateChange = ^{
        [weakSelf updateStatusItemImage];
    };
    self.panelViewController.onRequestClose = ^{
        [weakSelf closePopover];
    };
    self.panelViewController.onCheckForUpdates = ^{
        [weakSelf closePopover];
        [weakSelf.updaterController checkForUpdates:nil];
    };

    self.popover = [[NSPopover alloc] init];
    self.popover.contentViewController = self.panelViewController;
    self.popover.behavior = NSPopoverBehaviorTransient;
    self.popover.animates = YES;
    self.popover.delegate = self;
}

- (void)updateStatusItemImage {
    // The cup fills in while the Mac is being kept awake.
    NSString *symbolName = self.keepAwakeController.isActive ? @"cup.and.saucer.fill" : @"cup.and.saucer";
    NSImage *image = [NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:@"Sameru"];
    image.template = YES;
    self.statusItem.button.image = image;
}

#pragma mark - Popover

- (void)togglePopover:(id)sender {
    if (self.popover.isShown) {
        [self closePopover];
        return;
    }

    // The panel refreshes itself in -viewWillAppear.
    NSStatusBarButton *button = self.statusItem.button;
    [self.popover showRelativeToRect:button.bounds ofView:button preferredEdge:NSRectEdgeMinY];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)closePopover {
    [self.popover performClose:nil];
}

- (void)popoverDidShow:(NSNotification *)notification {
    [self.panelViewController startLiveUpdates];
}

- (void)popoverDidClose:(NSNotification *)notification {
    [self.panelViewController stopLiveUpdates];
}

#pragma mark - Events

- (void)handleSystemDidWake:(NSNotification *)notification {
    [self.fanController reapplyCurrentModeIfNeeded];
}

- (void)handleCleanModeEndedWithMessage:(NSString *)message {
    [self.panelViewController refresh];

    if (message.length == 0) {
        return;
    }

    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = NSLocalizedString(@"Clean Mode ended", nil);
    alert.informativeText = message;
    [alert addButtonWithTitle:NSLocalizedString(@"OK", nil)];

    [NSApp activateIgnoringOtherApps:YES];
    [alert runModal];
}

@end
