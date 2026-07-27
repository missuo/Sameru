//
//  SMRLoginItemController.h
//  Sameru
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Thin wrapper around SMAppService for the "launch at login" switch.
@interface SMRLoginItemController : NSObject

@property (nonatomic, readonly, getter=isEnabled) BOOL enabled;

- (BOOL)setEnabled:(BOOL)enabled error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
