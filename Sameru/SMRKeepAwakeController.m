//
//  SMRKeepAwakeController.m
//  Sameru
//

#import "SMRKeepAwakeController.h"

#import <IOKit/pwr_mgt/IOPMLib.h>
#import <os/log.h>

static NSString *const kSMRKeepAwakeErrorDomain = @"nz.owo.Sameru.KeepAwake";

@implementation SMRKeepAwakeController {
    IOPMAssertionID _systemAssertionID;
    IOPMAssertionID _displayAssertionID;
}

- (void)dealloc {
    [self deactivate];
}

- (BOOL)isActive {
    return _systemAssertionID != kIOPMNullAssertionID;
}

- (BOOL)activateWithError:(NSError **)error {
    if (self.isActive) {
        return YES;
    }

    IOPMAssertionID systemAssertionID = kIOPMNullAssertionID;
    IOReturn result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep,
                                                  kIOPMAssertionLevelOn,
                                                  CFSTR("Sameru Keep Awake"),
                                                  &systemAssertionID);
    if (result != kIOReturnSuccess) {
        os_log_error(OS_LOG_DEFAULT, "Sameru: failed to create system sleep assertion 0x%08x", result);
        if (error) {
            *error = [NSError errorWithDomain:kSMRKeepAwakeErrorDomain
                                         code:result
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:NSLocalizedString(@"Could not keep the Mac awake. The system returned error %d.", nil), result]}];
        }
        return NO;
    }
    _systemAssertionID = systemAssertionID;

    // Keeping the display awake is best effort — losing it should not undo the
    // system assertion the user actually asked for.
    IOPMAssertionID displayAssertionID = kIOPMNullAssertionID;
    result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep,
                                         kIOPMAssertionLevelOn,
                                         CFSTR("Sameru Keep Display Awake"),
                                         &displayAssertionID);
    if (result == kIOReturnSuccess) {
        _displayAssertionID = displayAssertionID;
    } else {
        os_log_error(OS_LOG_DEFAULT, "Sameru: failed to create display sleep assertion 0x%08x", result);
    }

    return YES;
}

- (void)deactivate {
    if (_displayAssertionID != kIOPMNullAssertionID) {
        IOReturn result = IOPMAssertionRelease(_displayAssertionID);
        if (result != kIOReturnSuccess) {
            os_log_error(OS_LOG_DEFAULT, "Sameru: failed to release display assertion 0x%08x", result);
        }
        _displayAssertionID = kIOPMNullAssertionID;
    }

    if (_systemAssertionID != kIOPMNullAssertionID) {
        IOReturn result = IOPMAssertionRelease(_systemAssertionID);
        if (result != kIOReturnSuccess) {
            os_log_error(OS_LOG_DEFAULT, "Sameru: failed to release system assertion 0x%08x", result);
        }
        _systemAssertionID = kIOPMNullAssertionID;
    }
}

- (BOOL)toggleWithError:(NSError **)error {
    if (self.isActive) {
        [self deactivate];
        return YES;
    }
    return [self activateWithError:error];
}

@end
