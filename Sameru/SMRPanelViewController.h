//
//  SMRPanelViewController.h
//  Sameru
//

#import <AppKit/AppKit.h>

#import "SMRCleanModeController.h"
#import "SMRFanController.h"
#import "SMRKeepAwakeController.h"
#import "SMRLoginItemController.h"

NS_ASSUME_NONNULL_BEGIN

/// The translucent panel shown from the status item: two switches and a
/// three-way fan selector, all directly actionable.
@interface SMRPanelViewController : NSViewController

- (instancetype)initWithKeepAwakeController:(SMRKeepAwakeController *)keepAwakeController
                        cleanModeController:(SMRCleanModeController *)cleanModeController
                              fanController:(SMRFanController *)fanController
                        loginItemController:(SMRLoginItemController *)loginItemController NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithNibName:(nullable NSNibName)nibName bundle:(nullable NSBundle *)bundle NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

/// Called whenever the panel changes state the status item needs to reflect.
@property (nonatomic, copy, nullable) void (^onStateChange)(void);
/// Called when the panel wants its containing popover dismissed.
@property (nonatomic, copy, nullable) void (^onRequestClose)(void);
/// Called when the user asks Sparkle to look for a new version.
@property (nonatomic, copy, nullable) void (^onCheckForUpdates)(void);

/// Pulls fresh state into every control. Call before showing the panel.
- (void)refresh;

/// Starts/stops the live RPM readout. Driven by the popover's show/close.
- (void)startLiveUpdates;
- (void)stopLiveUpdates;

@end

NS_ASSUME_NONNULL_END
