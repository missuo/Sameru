//
//  SMRSMCReader.h
//  Sameru
//
//  Read-only AppleSMC access. Reading does not need root, so the app does it
//  in-process; writes go through the privileged helper (see SMRFanController).
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// One sample of the fan subsystem.
@interface SMRFanSnapshot : NSObject

@property (nonatomic, readonly) NSInteger fanCount;
/// Current RPM per fan.
@property (nonatomic, readonly) NSArray<NSNumber *> *speeds;
/// Hardware minimum RPM per fan.
@property (nonatomic, readonly) NSArray<NSNumber *> *minSpeeds;
/// Hardware maximum RPM per fan.
@property (nonatomic, readonly) NSArray<NSNumber *> *maxSpeeds;
/// CPU temperature in °C, or NAN when no known sensor answered.
@property (nonatomic, readonly) double cpuTemperature;

@property (nonatomic, readonly, getter=isEmpty) BOOL empty;

+ (instancetype)emptySnapshot;

@end

@interface SMRSMCReader : NSObject

@property (nonatomic, readonly) BOOL isConnected;

- (SMRFanSnapshot *)readSnapshot;

@end

NS_ASSUME_NONNULL_END
