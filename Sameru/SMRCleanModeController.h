//
//  SMRCleanModeController.h
//  Sameru
//

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Blacks out every screen and swallows all keyboard, mouse and trackpad input so
/// the machine can be wiped down. Exits on ⌃⌘⎋ or a 3 second right click hold.
@interface SMRCleanModeController : NSObject

@property (nonatomic, readonly, getter=isActive) BOOL active;

/// Called when the session ends. `message` is non-nil only for an automatic
/// (emergency) exit, and explains why input was restored.
@property (nonatomic, copy, nullable) void (^onEnd)(NSString *_Nullable message);

- (BOOL)startWithError:(NSError **)error;
- (void)stop;

@end

NS_ASSUME_NONNULL_END
