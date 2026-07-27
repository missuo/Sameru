//
//  SMRCleanModeController.m
//  Sameru
//

#import "SMRCleanModeController.h"

#import <ApplicationServices/ApplicationServices.h>
#import <Carbon/Carbon.h>
#import <IOKit/pwr_mgt/IOPMLib.h>
#import <os/log.h>

static NSString *const kSMRCleanModeErrorDomain = @"nz.owo.Sameru.CleanMode";

/// ⌃⌘⎋ ends the session, matching the "hard to hit by accident while wiping" bar.
static const CGKeyCode kSMRExitKeyCode = kVK_Escape;
static const CGEventFlags kSMRExitModifiers = kCGEventFlagMaskControl | kCGEventFlagMaskCommand;
static const NSInteger kSMRRightMouseHoldSeconds = 3;

static CGEventRef SMRCleanModeEventTapCallback(CGEventTapProxy proxy,
                                               CGEventType type,
                                               CGEventRef event,
                                               void *userInfo);

#pragma mark - Overlay window

@interface SMROverlayWindow : NSWindow
@end

@implementation SMROverlayWindow

- (BOOL)canBecomeKeyWindow {
    return YES;
}

- (BOOL)canBecomeMainWindow {
    return YES;
}

@end

#pragma mark - Controller

@interface SMRCleanModeController () <NSWindowDelegate>
@end

@implementation SMRCleanModeController {
    NSMutableArray<SMROverlayWindow *> *_overlayWindows;
    NSMutableArray<NSTextField *> *_hintLabels;
    CFMachPortRef _eventTap;
    CFRunLoopSourceRef _eventTapSource;
    void *_eventTapContext;
    IOPMAssertionID _displayAssertionID;
    BOOL _cursorHidden;
    BOOL _tearingDown;
    NSTimer *_rightMouseHoldTimer;
    NSInteger _rightMouseHoldRemainingSeconds;
    NSMutableArray<NSDictionary *> *_observations;
    NSMutableArray<NSDate *> *_tapDisableTimestamps;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _overlayWindows = [NSMutableArray array];
        _hintLabels = [NSMutableArray array];
        _observations = [NSMutableArray array];
        _tapDisableTimestamps = [NSMutableArray array];
        _displayAssertionID = kIOPMNullAssertionID;
    }
    return self;
}

- (void)dealloc {
    [self tearDownNotifying:NO message:nil];
}

- (BOOL)isActive {
    return _eventTap != NULL;
}

#pragma mark - Lifecycle

- (BOOL)startWithError:(NSError **)error {
    if (self.isActive) {
        return YES;
    }

    if (NSScreen.screens.count == 0) {
        [self assignError:error code:1 message:NSLocalizedString(@"No screens are available, so clean mode cannot start.", nil)];
        return NO;
    }

    if (!AXIsProcessTrusted()) {
        // Ask once; the tap cannot be created until the user grants the right.
        NSDictionary *options = @{(__bridge NSString *)kAXTrustedCheckOptionPrompt: @YES};
        AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
        [self assignError:error
                     code:2
                  message:NSLocalizedString(@"Clean mode needs Accessibility access to block keyboard and trackpad input. Enable Sameru in System Settings › Privacy & Security › Accessibility, then try again.", nil)];
        return NO;
    }

    _eventTapContext = (__bridge_retained void *)self;

    CGEventMask mask = CGEventMaskBit(kCGEventKeyDown) | CGEventMaskBit(kCGEventKeyUp) |
                       CGEventMaskBit(kCGEventFlagsChanged) | CGEventMaskBit(kCGEventMouseMoved) |
                       CGEventMaskBit(kCGEventLeftMouseDown) | CGEventMaskBit(kCGEventLeftMouseUp) |
                       CGEventMaskBit(kCGEventLeftMouseDragged) | CGEventMaskBit(kCGEventRightMouseDown) |
                       CGEventMaskBit(kCGEventRightMouseUp) | CGEventMaskBit(kCGEventRightMouseDragged) |
                       CGEventMaskBit(kCGEventOtherMouseDown) | CGEventMaskBit(kCGEventOtherMouseUp) |
                       CGEventMaskBit(kCGEventOtherMouseDragged) | CGEventMaskBit(kCGEventScrollWheel);

    _eventTap = CGEventTapCreate(kCGSessionEventTap,
                                 kCGHeadInsertEventTap,
                                 kCGEventTapOptionDefault,
                                 mask,
                                 SMRCleanModeEventTapCallback,
                                 _eventTapContext);

    if (_eventTap == NULL) {
        CFBridgingRelease(_eventTapContext);
        _eventTapContext = NULL;
        [self assignError:error
                     code:3
                  message:NSLocalizedString(@"Could not create the input tap. Check that Sameru has Accessibility access in System Settings.", nil)];
        return NO;
    }

    _eventTapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, _eventTap, 0);
    if (_eventTapSource == NULL) {
        CFMachPortInvalidate(_eventTap);
        CFRelease(_eventTap);
        _eventTap = NULL;
        CFBridgingRelease(_eventTapContext);
        _eventTapContext = NULL;
        [self assignError:error code:4 message:NSLocalizedString(@"Could not attach the input tap to the run loop.", nil)];
        return NO;
    }

    CGEventTapEnable(_eventTap, false);

    if (![self enableIdleSleepPrevention]) {
        [self tearDownNotifying:NO message:nil];
        [self assignError:error code:5 message:NSLocalizedString(@"Could not stop the display from sleeping during clean mode.", nil)];
        return NO;
    }

    [NSApp activateIgnoringOtherApps:YES];
    [self rebuildOverlayWindows];

    if (_overlayWindows.count == 0) {
        [self tearDownNotifying:NO message:nil];
        [self assignError:error code:6 message:NSLocalizedString(@"Could not create the screen overlay, so clean mode was cancelled.", nil)];
        return NO;
    }

    [self installObservers];
    [self hideCursor];

    CFRunLoopAddSource(CFRunLoopGetMain(), _eventTapSource, kCFRunLoopCommonModes);
    CGEventTapEnable(_eventTap, true);

    return YES;
}

- (void)stop {
    [self tearDownNotifying:YES message:nil];
}

- (void)emergencyStopWithMessage:(NSString *)message {
    os_log_error(OS_LOG_DEFAULT, "Sameru: clean mode emergency exit: %{public}@", message);
    [self tearDownNotifying:YES message:message];
}

- (void)tearDownNotifying:(BOOL)notify message:(NSString *)message {
    if (_tearingDown || !self.isActive) {
        return;
    }
    _tearingDown = YES;

    [self cancelRightMouseHoldCountdownResettingHint:NO];
    [self removeObservers];
    [self closeOverlayWindows];

    if (_eventTap) {
        CGEventTapEnable(_eventTap, false);
    }
    if (_eventTapSource) {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), _eventTapSource, kCFRunLoopCommonModes);
        CFRelease(_eventTapSource);
        _eventTapSource = NULL;
    }
    if (_eventTap) {
        CFMachPortInvalidate(_eventTap);
        CFRelease(_eventTap);
        _eventTap = NULL;
    }
    if (_eventTapContext) {
        CFBridgingRelease(_eventTapContext);
        _eventTapContext = NULL;
    }

    [self showCursorIfNeeded];
    [self releaseIdleSleepPrevention];
    [_tapDisableTimestamps removeAllObjects];

    _tearingDown = NO;

    if (notify && self.onEnd) {
        self.onEnd(message);
    }
}

#pragma mark - Overlay

- (void)rebuildOverlayWindows {
    NSArray<SMROverlayWindow *> *previousWindows = [_overlayWindows copy];
    [_overlayWindows removeAllObjects];
    [_hintLabels removeAllObjects];

    NSInteger level = CGWindowLevelForKey(kCGScreenSaverWindowLevelKey);

    for (NSScreen *screen in NSScreen.screens) {
        SMROverlayWindow *window = [[SMROverlayWindow alloc] initWithContentRect:screen.frame
                                                                       styleMask:NSWindowStyleMaskBorderless
                                                                         backing:NSBackingStoreBuffered
                                                                           defer:NO
                                                                          screen:screen];
        window.delegate = self;
        window.level = level;
        window.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
                                    NSWindowCollectionBehaviorFullScreenAuxiliary |
                                    NSWindowCollectionBehaviorStationary |
                                    NSWindowCollectionBehaviorIgnoresCycle;
        window.backgroundColor = NSColor.blackColor;
        window.opaque = YES;
        window.hasShadow = NO;
        window.ignoresMouseEvents = YES;
        window.movable = NO;
        window.releasedWhenClosed = NO;
        window.contentView = [self makeOverlayContentView];
        [window setFrame:screen.frame display:YES];
        [window orderFrontRegardless];

        [_overlayWindows addObject:window];
    }

    [_overlayWindows.firstObject makeKeyAndOrderFront:nil];

    for (SMROverlayWindow *window in previousWindows) {
        window.delegate = nil;
        [window close];
    }

    [self updateHintLabels];
}

- (NSView *)makeOverlayContentView {
    NSView *contentView = [[NSView alloc] initWithFrame:NSZeroRect];

    NSView *box = [[NSView alloc] initWithFrame:NSZeroRect];
    box.wantsLayer = YES;
    box.layer.cornerRadius = 14;
    box.layer.backgroundColor = [NSColor colorWithWhite:1.0 alpha:0.07].CGColor;
    box.layer.borderWidth = 1;
    box.layer.borderColor = [NSColor colorWithWhite:1.0 alpha:0.14].CGColor;
    box.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:box];

    NSTextField *label = [NSTextField labelWithString:@""];
    label.alignment = NSTextAlignmentRight;
    label.font = [NSFont systemFontOfSize:18 weight:NSFontWeightMedium];
    label.textColor = [NSColor colorWithWhite:1.0 alpha:0.78];
    label.usesSingleLineMode = NO;
    label.lineBreakMode = NSLineBreakByWordWrapping;
    label.maximumNumberOfLines = 2;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [box addSubview:label];
    [_hintLabels addObject:label];

    [NSLayoutConstraint activateConstraints:@[
        [box.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-32],
        [box.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor constant:-28],
        [label.leadingAnchor constraintEqualToAnchor:box.leadingAnchor constant:18],
        [label.trailingAnchor constraintEqualToAnchor:box.trailingAnchor constant:-18],
        [label.topAnchor constraintEqualToAnchor:box.topAnchor constant:10],
        [label.bottomAnchor constraintEqualToAnchor:box.bottomAnchor constant:-10]
    ]];

    return contentView;
}

- (void)updateHintLabels {
    NSInteger remainingSeconds = _rightMouseHoldRemainingSeconds > 0 ? _rightMouseHoldRemainingSeconds
                                                                     : kSMRRightMouseHoldSeconds;
    NSString *text = [NSString stringWithFormat:NSLocalizedString(@"Press ⌃⌘⎋ to exit\nor hold the right mouse button for %ld s", nil),
                      (long)remainingSeconds];

    for (NSTextField *label in _hintLabels) {
        label.stringValue = text;
    }
}

- (void)closeOverlayWindows {
    for (SMROverlayWindow *window in _overlayWindows) {
        window.delegate = nil;
        [window close];
    }
    [_overlayWindows removeAllObjects];
    [_hintLabels removeAllObjects];
}

- (void)windowWillClose:(NSNotification *)notification {
    if (_tearingDown || !self.isActive) {
        return;
    }
    [self emergencyStopWithMessage:NSLocalizedString(@"The clean mode overlay closed unexpectedly, so input was restored.", nil)];
}

#pragma mark - Cursor and power

- (void)hideCursor {
    if (_cursorHidden) {
        return;
    }
    [NSCursor hide];
    _cursorHidden = YES;
}

- (void)showCursorIfNeeded {
    if (!_cursorHidden) {
        return;
    }
    [NSCursor unhide];
    _cursorHidden = NO;
}

- (BOOL)enableIdleSleepPrevention {
    if (_displayAssertionID != kIOPMNullAssertionID) {
        return YES;
    }

    IOPMAssertionID assertionID = kIOPMNullAssertionID;
    IOReturn result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep,
                                                  kIOPMAssertionLevelOn,
                                                  CFSTR("Sameru Clean Mode"),
                                                  &assertionID);
    if (result != kIOReturnSuccess) {
        os_log_error(OS_LOG_DEFAULT, "Sameru: clean mode idle assertion failed 0x%08x", result);
        return NO;
    }

    _displayAssertionID = assertionID;
    return YES;
}

- (void)releaseIdleSleepPrevention {
    if (_displayAssertionID == kIOPMNullAssertionID) {
        return;
    }
    IOPMAssertionRelease(_displayAssertionID);
    _displayAssertionID = kIOPMNullAssertionID;
}

#pragma mark - Observers

- (void)installObservers {
    NSNotificationCenter *appCenter = NSNotificationCenter.defaultCenter;
    NSNotificationCenter *workspaceCenter = NSWorkspace.sharedWorkspace.notificationCenter;

    __weak typeof(self) weakSelf = self;

    [self addObserverOnCenter:appCenter
                         name:NSApplicationDidChangeScreenParametersNotification
                        block:^(NSNotification *note) {
        [weakSelf handleScreenParametersChanged];
    }];

    [self addObserverOnCenter:appCenter
                         name:NSApplicationWillTerminateNotification
                        block:^(NSNotification *note) {
        [weakSelf tearDownNotifying:NO message:nil];
    }];

    NSDictionary<NSNotificationName, NSString *> *emergencyNotifications = @{
        NSWorkspaceSessionDidResignActiveNotification: NSLocalizedString(@"The user session was locked or switched away, so clean mode exited.", nil),
        NSWorkspaceScreensDidSleepNotification: NSLocalizedString(@"The display went to sleep, so clean mode exited.", nil),
        NSWorkspaceWillSleepNotification: NSLocalizedString(@"The Mac is going to sleep, so clean mode exited.", nil)
    };

    [emergencyNotifications enumerateKeysAndObjectsUsingBlock:^(NSNotificationName name, NSString *message, BOOL *stop) {
        [self addObserverOnCenter:workspaceCenter
                             name:name
                            block:^(NSNotification *note) {
            [weakSelf emergencyStopWithMessage:message];
        }];
    }];
}

- (void)addObserverOnCenter:(NSNotificationCenter *)center
                       name:(NSNotificationName)name
                      block:(void (^)(NSNotification *note))block {
    id token = [center addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:block];
    [_observations addObject:@{@"center": center, @"token": token}];
}

- (void)removeObservers {
    for (NSDictionary *observation in _observations) {
        [observation[@"center"] removeObserver:observation[@"token"]];
    }
    [_observations removeAllObjects];
}

- (void)handleScreenParametersChanged {
    if (_tearingDown || !self.isActive) {
        return;
    }

    if (NSScreen.screens.count == 0) {
        [self emergencyStopWithMessage:NSLocalizedString(@"Every screen was disconnected, so clean mode exited.", nil)];
        return;
    }

    [self rebuildOverlayWindows];
}

#pragma mark - Right mouse hold

- (void)handleRightMouseDown {
    if (_tearingDown || !self.isActive || _rightMouseHoldTimer) {
        return;
    }

    _rightMouseHoldRemainingSeconds = kSMRRightMouseHoldSeconds;
    [self updateHintLabels];

    __weak typeof(self) weakSelf = self;
    _rightMouseHoldTimer = [NSTimer timerWithTimeInterval:1.0
                                                  repeats:YES
                                                    block:^(NSTimer *timer) {
        [weakSelf handleRightMouseHoldTick];
    }];
    [NSRunLoop.mainRunLoop addTimer:_rightMouseHoldTimer forMode:NSRunLoopCommonModes];
}

- (void)handleRightMouseUp {
    [self cancelRightMouseHoldCountdownResettingHint:YES];
}

- (void)handleRightMouseHoldTick {
    if (_rightMouseHoldRemainingSeconds > 1) {
        _rightMouseHoldRemainingSeconds -= 1;
        [self updateHintLabels];
        return;
    }

    [self cancelRightMouseHoldCountdownResettingHint:NO];
    [self stop];
}

- (void)cancelRightMouseHoldCountdownResettingHint:(BOOL)resetHint {
    [_rightMouseHoldTimer invalidate];
    _rightMouseHoldTimer = nil;
    _rightMouseHoldRemainingSeconds = 0;

    if (resetHint) {
        [self updateHintLabels];
    }
}

#pragma mark - Event tap

- (void)handleTapDisabled {
    if (_tearingDown || _eventTap == NULL) {
        return;
    }

    CGEventTapEnable(_eventTap, true);
    if (!CGEventTapIsEnabled(_eventTap)) {
        [self emergencyStopWithMessage:NSLocalizedString(@"The system disabled the input tap and it could not be restarted, so clean mode exited.", nil)];
        return;
    }

    NSDate *now = [NSDate date];
    [_tapDisableTimestamps addObject:now];
    [_tapDisableTimestamps filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDate *date, NSDictionary *bindings) {
        return [now timeIntervalSinceDate:date] <= 2.0;
    }]];

    if (_tapDisableTimestamps.count >= 3) {
        [self emergencyStopWithMessage:NSLocalizedString(@"The system kept disabling the input tap, so clean mode exited.", nil)];
    }
}

static CGEventRef SMRCleanModeEventTapCallback(CGEventTapProxy proxy,
                                               CGEventType type,
                                               CGEventRef event,
                                               void *userInfo) {
    SMRCleanModeController *controller = (__bridge SMRCleanModeController *)userInfo;
    if (controller == nil) {
        return event;
    }

    switch (type) {
        case kCGEventTapDisabledByTimeout:
        case kCGEventTapDisabledByUserInput: {
            dispatch_async(dispatch_get_main_queue(), ^{
                [controller handleTapDisabled];
            });
            return event;
        }

        case kCGEventRightMouseDown: {
            dispatch_async(dispatch_get_main_queue(), ^{
                [controller handleRightMouseDown];
            });
            return NULL;
        }

        case kCGEventRightMouseUp: {
            dispatch_async(dispatch_get_main_queue(), ^{
                [controller handleRightMouseUp];
            });
            return NULL;
        }

        case kCGEventKeyDown: {
            CGKeyCode keyCode = (CGKeyCode)CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
            CGEventFlags flags = CGEventGetFlags(event) & (kCGEventFlagMaskCommand | kCGEventFlagMaskControl |
                                                           kCGEventFlagMaskAlternate | kCGEventFlagMaskShift);
            if (keyCode == kSMRExitKeyCode && flags == kSMRExitModifiers) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [controller stop];
                });
            }
            return NULL;
        }

        default:
            // Everything else the tap was asked for is simply dropped.
            return NULL;
    }
}

#pragma mark - Errors

- (void)assignError:(NSError **)error code:(NSInteger)code message:(NSString *)message {
    if (!error) {
        return;
    }
    *error = [NSError errorWithDomain:kSMRCleanModeErrorDomain
                                 code:code
                             userInfo:@{NSLocalizedDescriptionKey: message}];
}

@end
