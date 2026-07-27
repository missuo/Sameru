//
//  SMRLoginItemController.m
//  Sameru
//

#import "SMRLoginItemController.h"

#import <ServiceManagement/ServiceManagement.h>
#import <os/log.h>

static NSString *const kSMRLoginItemErrorDomain = @"nz.owo.Sameru.LoginItem";

@implementation SMRLoginItemController

- (BOOL)isEnabled {
    return SMAppService.mainAppService.status == SMAppServiceStatusEnabled;
}

- (BOOL)setEnabled:(BOOL)enabled error:(NSError **)error {
    SMAppService *service = SMAppService.mainAppService;
    NSError *serviceError = nil;
    BOOL succeeded = enabled ? [service registerAndReturnError:&serviceError]
                             : [service unregisterAndReturnError:&serviceError];

    if (succeeded) {
        return YES;
    }

    os_log_error(OS_LOG_DEFAULT, "Sameru: login item update failed: %{public}@", serviceError.localizedDescription);

    if (error) {
        NSString *message = enabled
            ? NSLocalizedString(@"Could not register Sameru as a login item. Move Sameru to your Applications folder and try again.", nil)
            : NSLocalizedString(@"Could not remove Sameru from your login items.", nil);

        if (serviceError.localizedDescription.length > 0) {
            message = [message stringByAppendingFormat:@"\n\n%@", serviceError.localizedDescription];
        }

        *error = [NSError errorWithDomain:kSMRLoginItemErrorDomain
                                     code:serviceError.code
                                 userInfo:@{NSLocalizedDescriptionKey: message}];
    }

    return NO;
}

@end
