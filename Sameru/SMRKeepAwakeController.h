//
//  SMRKeepAwakeController.h
//  Sameru
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Holds IOKit power assertions that stop the Mac (and its display) from idling
/// into sleep. Equivalent to `caffeinate -di` for as long as it is active.
@interface SMRKeepAwakeController : NSObject

@property (nonatomic, readonly, getter=isActive) BOOL active;

- (BOOL)activateWithError:(NSError **)error;
- (void)deactivate;
- (BOOL)toggleWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
