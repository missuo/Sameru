//
//  SMRSMCReader.m
//  Sameru
//

#import "SMRSMCReader.h"

#import <IOKit/IOKitLib.h>
#import <os/log.h>

#pragma mark - SMC types

typedef struct {
    uint32_t dataSize;
    uint32_t dataType;
    uint8_t dataAttributes;
} SMRKeyInfo;

typedef struct {
    uint8_t major;
    uint8_t minor;
    uint8_t build;
    uint8_t reserved;
    uint16_t release;
} SMRVersion;

typedef struct {
    uint16_t version;
    uint16_t length;
    uint32_t cpuPLimit;
    uint32_t gpuPLimit;
    uint32_t memPLimit;
} SMRPLimit;

typedef struct {
    uint32_t key;
    SMRVersion vers;
    SMRPLimit pLimit;
    SMRKeyInfo keyInfo;
    uint8_t result;
    uint8_t status;
    uint8_t data8;
    uint32_t data32;
    uint8_t bytes[32];
} SMRParam;

static const uint32_t kSMCKernelIndex = 2;
static const uint8_t kSMCCmdReadBytes = 5;
static const uint8_t kSMCCmdReadKeyInfo = 9;

/// Fallbacks for Macs that do not report per-fan limits.
static const NSInteger kSMRFallbackMinRPM = 1000;
static const NSInteger kSMRFallbackMaxRPM = 5200;

/// CPU temperature keys, most reliable first (Intel then Apple silicon).
static NSString *const kSMRCPUTemperatureKeys[] = {
    @"TC0P", @"TCXC", @"TC0E", @"TC0F", @"TC0D",
    @"Tp09", @"Tp0T", @"Tp01", @"Tp05"
};

static uint32_t SMRFourCC(NSString *key) {
    uint32_t result = 0;
    const char *bytes = key.UTF8String;
    for (int i = 0; i < 4 && bytes[i] != '\0'; i++) {
        result |= (uint32_t)(uint8_t)bytes[i] << (8 * (3 - i));
    }
    return result;
}

#pragma mark - SMRFanSnapshot

@implementation SMRFanSnapshot

- (instancetype)initWithFanCount:(NSInteger)fanCount
                          speeds:(NSArray<NSNumber *> *)speeds
                       minSpeeds:(NSArray<NSNumber *> *)minSpeeds
                       maxSpeeds:(NSArray<NSNumber *> *)maxSpeeds
                  cpuTemperature:(double)cpuTemperature {
    self = [super init];
    if (self) {
        _fanCount = fanCount;
        _speeds = [speeds copy];
        _minSpeeds = [minSpeeds copy];
        _maxSpeeds = [maxSpeeds copy];
        _cpuTemperature = cpuTemperature;
    }
    return self;
}

+ (instancetype)emptySnapshot {
    return [[self alloc] initWithFanCount:0 speeds:@[] minSpeeds:@[] maxSpeeds:@[] cpuTemperature:NAN];
}

- (BOOL)isEmpty {
    return self.fanCount == 0;
}

@end

#pragma mark - SMRSMCReader

@implementation SMRSMCReader {
    io_connect_t _connection;
    NSMutableDictionary<NSNumber *, NSValue *> *_keyInfoCache;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _keyInfoCache = [NSMutableDictionary dictionary];
        [self openConnection];
    }
    return self;
}

- (void)dealloc {
    if (_connection != 0) {
        IOServiceClose(_connection);
        _connection = 0;
    }
}

- (BOOL)isConnected {
    return _connection != 0;
}

- (void)openConnection {
    if (_connection != 0) {
        return;
    }

    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (service == 0) {
        os_log_error(OS_LOG_DEFAULT, "Sameru: AppleSMC service not found");
        return;
    }

    kern_return_t result = IOServiceOpen(service, mach_task_self(), 0, &_connection);
    IOObjectRelease(service);

    if (result != kIOReturnSuccess) {
        os_log_error(OS_LOG_DEFAULT, "Sameru: IOServiceOpen failed 0x%08x", result);
        _connection = 0;
    }
}

#pragma mark - Snapshot

- (SMRFanSnapshot *)readSnapshot {
    [self openConnection];
    if (_connection == 0) {
        return [SMRFanSnapshot emptySnapshot];
    }

    NSInteger count = [self readFanCount];
    if (count <= 0) {
        return [SMRFanSnapshot emptySnapshot];
    }

    NSMutableArray<NSNumber *> *speeds = [NSMutableArray arrayWithCapacity:count];
    NSMutableArray<NSNumber *> *minSpeeds = [NSMutableArray arrayWithCapacity:count];
    NSMutableArray<NSNumber *> *maxSpeeds = [NSMutableArray arrayWithCapacity:count];

    for (NSInteger i = 0; i < count; i++) {
        double value = 0;

        BOOL ok = [self readDouble:[NSString stringWithFormat:@"F%ldAc", (long)i] into:&value];
        [speeds addObject:@(ok && value >= 0 ? (NSInteger)value : 0)];

        ok = [self readDouble:[NSString stringWithFormat:@"F%ldMn", (long)i] into:&value];
        [minSpeeds addObject:@(ok && value > 0 ? (NSInteger)value : kSMRFallbackMinRPM)];

        ok = [self readDouble:[NSString stringWithFormat:@"F%ldMx", (long)i] into:&value];
        [maxSpeeds addObject:@(ok && value > 0 ? (NSInteger)value : -1)];
    }

    // Fans whose max is unreadable inherit the highest max that did read.
    NSInteger bestMax = 0;
    for (NSNumber *maxSpeed in maxSpeeds) {
        bestMax = MAX(bestMax, maxSpeed.integerValue);
    }
    if (bestMax <= 0) {
        bestMax = kSMRFallbackMaxRPM;
    }
    for (NSInteger i = 0; i < maxSpeeds.count; i++) {
        if (maxSpeeds[i].integerValue <= 0) {
            maxSpeeds[i] = @(bestMax);
        }
    }

    double cpuTemperature = NAN;
    for (size_t i = 0; i < sizeof(kSMRCPUTemperatureKeys) / sizeof(kSMRCPUTemperatureKeys[0]); i++) {
        double value = 0;
        if ([self readDouble:kSMRCPUTemperatureKeys[i] into:&value] && value > 0 && value < 150) {
            cpuTemperature = value;
            break;
        }
    }

    return [[SMRFanSnapshot alloc] initWithFanCount:count
                                             speeds:speeds
                                          minSpeeds:minSpeeds
                                          maxSpeeds:maxSpeeds
                                     cpuTemperature:cpuTemperature];
}

- (NSInteger)readFanCount {
    double value = 0;
    if (![self readDouble:@"FNum" into:&value] || value <= 0) {
        return 0;
    }
    return (NSInteger)value;
}

#pragma mark - Low level

- (BOOL)readDouble:(NSString *)key into:(double *)outValue {
    if (_connection == 0) {
        return NO;
    }

    uint32_t keyCode = SMRFourCC(key);

    SMRKeyInfo info = {0};
    NSValue *cached = _keyInfoCache[@(keyCode)];
    if (cached) {
        [cached getValue:&info size:sizeof(info)];
    } else {
        SMRParam input = {0};
        input.key = keyCode;
        input.data8 = kSMCCmdReadKeyInfo;

        SMRParam output = {0};
        size_t outputSize = sizeof(SMRParam);
        kern_return_t result = IOConnectCallStructMethod(_connection, kSMCKernelIndex,
                                                         &input, sizeof(SMRParam),
                                                         &output, &outputSize);
        if (result != kIOReturnSuccess || output.result != 0 ||
            output.keyInfo.dataSize == 0 || output.keyInfo.dataSize > 32) {
            return NO;
        }

        info = output.keyInfo;
        _keyInfoCache[@(keyCode)] = [NSValue valueWithBytes:&info objCType:@encode(SMRKeyInfo)];
    }

    SMRParam input = {0};
    input.key = keyCode;
    input.keyInfo.dataSize = info.dataSize;
    input.data8 = kSMCCmdReadBytes;

    SMRParam output = {0};
    size_t outputSize = sizeof(SMRParam);
    kern_return_t result = IOConnectCallStructMethod(_connection, kSMCKernelIndex,
                                                     &input, sizeof(SMRParam),
                                                     &output, &outputSize);
    if (result != kIOReturnSuccess || output.result != 0) {
        return NO;
    }

    return [self parseBytes:output.bytes dataType:info.dataType dataSize:info.dataSize into:outValue];
}

- (BOOL)parseBytes:(const uint8_t *)bytes
          dataType:(uint32_t)dataType
          dataSize:(uint32_t)dataSize
              into:(double *)outValue {
    if (dataType == SMRFourCC(@"flt ") && dataSize == 4) {
        float parsed = 0;
        memcpy(&parsed, bytes, sizeof(parsed));
        *outValue = parsed;
        return YES;
    }
    if (dataType == SMRFourCC(@"sp78") && dataSize == 2) {
        int16_t raw = (int16_t)(((uint16_t)bytes[0] << 8) | bytes[1]);
        *outValue = (double)raw / 256.0;
        return YES;
    }
    if (dataType == SMRFourCC(@"fpe2") && dataSize == 2) {
        *outValue = (double)(((int)bytes[0] << 6) + ((int)bytes[1] >> 2));
        return YES;
    }
    if (dataType == SMRFourCC(@"ui8 ") && dataSize == 1) {
        *outValue = bytes[0];
        return YES;
    }
    if (dataType == SMRFourCC(@"ui16") && dataSize == 2) {
        *outValue = ((int)bytes[0] << 8) | bytes[1];
        return YES;
    }
    if (dataType == SMRFourCC(@"ui32") && dataSize == 4) {
        uint32_t raw = ((uint32_t)bytes[0] << 24) | ((uint32_t)bytes[1] << 16) |
                       ((uint32_t)bytes[2] << 8) | (uint32_t)bytes[3];
        *outValue = raw;
        return YES;
    }
    if (dataSize == 2) {
        *outValue = ((int)bytes[0] << 8) | bytes[1];
        return YES;
    }

    return NO;
}

@end
