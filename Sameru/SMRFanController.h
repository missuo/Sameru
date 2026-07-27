//
//  SMRFanController.h
//  Sameru
//

#import <Foundation/Foundation.h>

#import "SMRSMCReader.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SMRFanMode) {
    /// Hand the fans back to macOS.
    SMRFanModeAuto = 0,
    /// Pin every fan at kSMRCoolSpeedFraction of its own maximum.
    SMRFanModeCool = 1,
    /// Pin every fan at its hardware maximum.
    SMRFanModeMax = 2
};

/// "Cool" is a fraction of each fan's own maximum rather than a fixed RPM, because
/// the hardware ceiling differs per Mac model (5779 and 6241 RPM on one machine,
/// well under 4000 on others).
extern const double kSMRCoolSpeedFraction;

@interface SMRFanController : NSObject

@property (nonatomic, readonly) SMRFanMode mode;
/// Last snapshot read from the SMC. Refreshed by -refreshSnapshot.
@property (nonatomic, readonly) SMRFanSnapshot *snapshot;
/// NO when the machine exposes no fans (most Apple silicon laptops, Mac mini M1…).
@property (nonatomic, readonly) BOOL hasFans;
/// YES once the privileged helper is installed, i.e. applying a mode is prompt-free.
@property (nonatomic, readonly) BOOL isHelperInstalled;

- (SMRFanSnapshot *)refreshSnapshot;

/// Applies `mode` to every fan, installing the privileged helper first if needed
/// (which shows the system authorization prompt).
- (BOOL)applyMode:(SMRFanMode)mode error:(NSError **)error;

/// Restores automatic control without installing anything. Used on quit.
- (void)restoreAutomaticControlIfNeeded;

/// Re-applies the current mode. The SMC forgets forced targets across some sleep
/// cycles, so this runs on wake.
- (void)reapplyCurrentModeIfNeeded;

+ (NSString *)titleForMode:(SMRFanMode)mode;

/// Human readable description of what `mode` would do to this machine's fans,
/// e.g. "75% of maximum · 4334 / 4681 RPM". Used for the mode tooltips.
- (NSString *)summaryForMode:(SMRFanMode)mode;

@end

NS_ASSUME_NONNULL_END
