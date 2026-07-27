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
    /// Pin every fan kSMRCoolRangeFraction of the way up its own usable range.
    SMRFanModeCool = 1,
    /// Pin every fan at its hardware maximum.
    SMRFanModeMax = 2
};

/// "Cool" sits a fraction of the way along each fan's usable range (min → max),
/// not a fraction of the maximum and not a fixed RPM. Both ends of that range vary
/// a lot per model — 1200–5779 RPM on an M1 Pro, 2317–7826 on an M4 Pro. A fraction
/// of the maximum ignores the floor and lands near full speed wherever the ceiling
/// is high (0.75 × 7826 is 5870 RPM, which is not "cool"), while a fixed RPM is
/// barely above idle on a machine whose fans never drop below 2317.
extern const double kSMRCoolRangeFraction;

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
