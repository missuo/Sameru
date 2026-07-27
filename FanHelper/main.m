//
//  main.m
//  sameru-fan-helper
//
//  Privileged command line tool that reads and writes AppleSMC fan keys.
//  Installed setuid root into /Library/PrivilegedHelperTools by Sameru.app,
//  because writing F<n>Md / F<n>Tg requires root.
//
//  Usage:
//    sameru-fan-helper info
//    sameru-fan-helper read <KEY>
//    sameru-fan-helper set <FAN#> <RPM>
//    sameru-fan-helper auto <FAN#>
//

#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>

#pragma mark - SMC types

typedef struct {
    uint32_t dataSize;
    uint32_t dataType;
    uint8_t dataAttributes;
} SMCKeyInfo;

typedef struct {
    uint8_t major;
    uint8_t minor;
    uint8_t build;
    uint8_t reserved;
    uint16_t release;
} SMCVersion;

typedef struct {
    uint16_t version;
    uint16_t length;
    uint32_t cpuPLimit;
    uint32_t gpuPLimit;
    uint32_t memPLimit;
} SMCPLimit;

typedef struct {
    uint32_t key;
    SMCVersion vers;
    SMCPLimit pLimit;
    SMCKeyInfo keyInfo;
    uint8_t result;
    uint8_t status;
    uint8_t data8;
    uint32_t data32;
    uint8_t bytes[32];
} SMCParam;

typedef struct {
    uint32_t dataSize;
    uint32_t dataType;
    uint8_t bytes[32];
} SMCValue;

static const uint32_t kSMCKernelIndex = 2;
static const uint8_t kSMCCmdReadBytes = 5;
static const uint8_t kSMCCmdWriteBytes = 6;
static const uint8_t kSMCCmdReadKeyInfo = 9;

static io_connect_t gConnection = 0;

static uint32_t SMRFourCC(const char *key) {
    uint32_t result = 0;
    for (int i = 0; i < 4 && key[i] != '\0'; i++) {
        result |= (uint32_t)(uint8_t)key[i] << (8 * (3 - i));
    }
    return result;
}

static NSString *SMRFourCCString(uint32_t value) {
    char buffer[5] = {
        (char)((value >> 24) & 0xff),
        (char)((value >> 16) & 0xff),
        (char)((value >> 8) & 0xff),
        (char)(value & 0xff),
        '\0'
    };
    return [NSString stringWithUTF8String:buffer] ?: @(value).stringValue;
}

#pragma mark - Connection

static BOOL SMROpenConnection(NSError **error) {
    if (gConnection != 0) {
        return YES;
    }

    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (service == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"SameruFanHelper"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"AppleSMC service not found"}];
        }
        return NO;
    }

    kern_return_t result = IOServiceOpen(service, mach_task_self(), 0, &gConnection);
    IOObjectRelease(service);

    if (result != kIOReturnSuccess) {
        gConnection = 0;
        if (error) {
            *error = [NSError errorWithDomain:@"SameruFanHelper"
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:@"Failed to open SMC connection: 0x%08x", result]}];
        }
        return NO;
    }

    return YES;
}

static void SMRCloseConnection(void) {
    if (gConnection != 0) {
        IOServiceClose(gConnection);
        gConnection = 0;
    }
}

#pragma mark - Read / write

static BOOL SMRReadKeyInfo(const char *key, SMCKeyInfo *outInfo, NSError **error) {
    SMCParam input = {0};
    input.key = SMRFourCC(key);
    input.data8 = kSMCCmdReadKeyInfo;

    SMCParam output = {0};
    size_t outputSize = sizeof(SMCParam);
    kern_return_t result = IOConnectCallStructMethod(gConnection, kSMCKernelIndex,
                                                     &input, sizeof(SMCParam),
                                                     &output, &outputSize);

    if (result != kIOReturnSuccess || output.result != 0 ||
        output.keyInfo.dataSize == 0 || output.keyInfo.dataSize > 32) {
        if (error) {
            *error = [NSError errorWithDomain:@"SameruFanHelper"
                                         code:3
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:@"Failed to read key info for %s: 0x%08x", key, result]}];
        }
        return NO;
    }

    *outInfo = output.keyInfo;
    return YES;
}

static BOOL SMRReadValue(const char *key, SMCValue *outValue, NSError **error) {
    SMCKeyInfo info = {0};
    if (!SMRReadKeyInfo(key, &info, error)) {
        return NO;
    }

    SMCParam input = {0};
    input.key = SMRFourCC(key);
    input.keyInfo.dataSize = info.dataSize;
    input.data8 = kSMCCmdReadBytes;

    SMCParam output = {0};
    size_t outputSize = sizeof(SMCParam);
    kern_return_t result = IOConnectCallStructMethod(gConnection, kSMCKernelIndex,
                                                     &input, sizeof(SMCParam),
                                                     &output, &outputSize);

    if (result != kIOReturnSuccess || output.result != 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"SameruFanHelper"
                                         code:4
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:@"Failed to read %s: 0x%08x", key, result]}];
        }
        return NO;
    }

    outValue->dataSize = info.dataSize;
    outValue->dataType = info.dataType;
    memcpy(outValue->bytes, output.bytes, sizeof(output.bytes));
    return YES;
}

static BOOL SMRWriteValue(const char *key, const SMCValue *value, NSError **error) {
    SMCParam input = {0};
    input.key = SMRFourCC(key);
    input.keyInfo.dataSize = value->dataSize;
    input.data8 = kSMCCmdWriteBytes;
    memcpy(input.bytes, value->bytes, sizeof(input.bytes));

    SMCParam output = {0};
    size_t outputSize = sizeof(SMCParam);
    kern_return_t result = IOConnectCallStructMethod(gConnection, kSMCKernelIndex,
                                                     &input, sizeof(SMCParam),
                                                     &output, &outputSize);

    if (result != kIOReturnSuccess || output.result != 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"SameruFanHelper"
                                         code:5
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:@"Failed to write %s: 0x%08x", key, result]}];
        }
        return NO;
    }

    return YES;
}

static BOOL SMRParseDouble(const SMCValue *value, double *outValue) {
    const uint8_t *bytes = value->bytes;

    if (value->dataType == SMRFourCC("flt ") && value->dataSize == 4) {
        float parsed = 0;
        memcpy(&parsed, bytes, sizeof(parsed));
        *outValue = parsed;
        return YES;
    }
    if (value->dataType == SMRFourCC("sp78") && value->dataSize == 2) {
        int16_t raw = (int16_t)(((uint16_t)bytes[0] << 8) | bytes[1]);
        *outValue = (double)raw / 256.0;
        return YES;
    }
    if (value->dataType == SMRFourCC("fpe2") && value->dataSize == 2) {
        *outValue = (double)(((int)bytes[0] << 6) + ((int)bytes[1] >> 2));
        return YES;
    }
    if (value->dataType == SMRFourCC("ui8 ") && value->dataSize == 1) {
        *outValue = bytes[0];
        return YES;
    }
    if (value->dataType == SMRFourCC("ui16") && value->dataSize == 2) {
        *outValue = ((int)bytes[0] << 8) | bytes[1];
        return YES;
    }
    if (value->dataType == SMRFourCC("ui32") && value->dataSize == 4) {
        uint32_t raw = ((uint32_t)bytes[0] << 24) | ((uint32_t)bytes[1] << 16) |
                       ((uint32_t)bytes[2] << 8) | (uint32_t)bytes[3];
        *outValue = raw;
        return YES;
    }
    if (value->dataSize == 2) {
        // Unknown type — big endian 16 bit is the best guess.
        *outValue = ((int)bytes[0] << 8) | bytes[1];
        return YES;
    }

    return NO;
}

#pragma mark - Fan operations

/// Writes F<n>Md. Some Macs do not expose the key at all; F<n>Tg still works there,
/// so a missing key is not treated as a failure.
static BOOL SMRSetFanMode(uint8_t mode, int fanIndex, NSError **error) {
    char key[8];
    snprintf(key, sizeof(key), "F%dMd", fanIndex);

    SMCValue value = {0};
    if (!SMRReadValue(key, &value, NULL)) {
        return YES;
    }
    if (value.dataSize != 1) {
        return YES;
    }

    value.bytes[0] = mode;
    return SMRWriteValue(key, &value, error);
}

static BOOL SMRSetFanSpeed(int rpm, int fanIndex, NSError **error) {
    if (!SMRSetFanMode(1, fanIndex, error)) {
        return NO;
    }

    char key[8];
    snprintf(key, sizeof(key), "F%dTg", fanIndex);

    SMCValue value = {0};
    if (!SMRReadValue(key, &value, error)) {
        return NO;
    }

    if (value.dataType == SMRFourCC("flt ") && value.dataSize == 4) {
        float target = (float)rpm;
        memcpy(value.bytes, &target, sizeof(target));
    } else if (value.dataType == SMRFourCC("fpe2") && value.dataSize == 2) {
        uint16_t encoded = (uint16_t)(rpm << 2);
        value.bytes[0] = (uint8_t)((encoded >> 8) & 0xff);
        value.bytes[1] = (uint8_t)(encoded & 0xff);
    } else {
        if (error) {
            *error = [NSError errorWithDomain:@"SameruFanHelper"
                                         code:6
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:@"Unsupported SMC type for %s: %@/%u",
                                                     key, SMRFourCCString(value.dataType), value.dataSize]}];
        }
        return NO;
    }

    return SMRWriteValue(key, &value, error);
}

static int SMRFanCount(void) {
    SMCValue value = {0};
    double count = 0;
    if (!SMRReadValue("FNum", &value, NULL) || !SMRParseDouble(&value, &count)) {
        return 0;
    }
    return (int)count;
}

static void SMRPrintFanInfo(void) {
    int count = SMRFanCount();
    printf("Total fans: %d\n", count);

    const char *suffixes[] = {"Ac", "Mn", "Mx", "Tg", "Md"};
    for (int index = 0; index < count; index++) {
        printf("\nFan #%d:\n", index);
        for (size_t i = 0; i < sizeof(suffixes) / sizeof(suffixes[0]); i++) {
            char key[8];
            snprintf(key, sizeof(key), "F%d%s", index, suffixes[i]);

            SMCValue value = {0};
            double parsed = 0;
            if (SMRReadValue(key, &value, NULL) && SMRParseDouble(&value, &parsed)) {
                printf("  %s: %d\n", key, (int)parsed);
            }
        }
    }
}

static BOOL SMRPrintKey(const char *key, NSError **error) {
    SMCValue value = {0};
    if (!SMRReadValue(key, &value, error)) {
        return NO;
    }

    printf("Key: %s\n", key);
    printf("Type: %s\n", SMRFourCCString(value.dataType).UTF8String);
    printf("Size: %u\n", value.dataSize);

    double parsed = 0;
    if (SMRParseDouble(&value, &parsed)) {
        printf("Value: %g\n", parsed);
    }
    return YES;
}

#pragma mark - Entry point

static void SMRPrintUsage(void) {
    fprintf(stderr,
            "Sameru fan SMC helper\n"
            "Usage:\n"
            "  sameru-fan-helper info\n"
            "  sameru-fan-helper read <KEY>\n"
            "  sameru-fan-helper set <FAN#> <RPM>\n"
            "  sameru-fan-helper auto <FAN#>\n");
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 2) {
            SMRPrintUsage();
            return 1;
        }

        NSError *error = nil;
        if (!SMROpenConnection(&error)) {
            fprintf(stderr, "%s\n", error.localizedDescription.UTF8String);
            return 1;
        }

        BOOL ok = YES;
        const char *command = argv[1];

        if (strcmp(command, "info") == 0) {
            SMRPrintFanInfo();
        } else if (strcmp(command, "read") == 0 && argc >= 3) {
            ok = SMRPrintKey(argv[2], &error);
        } else if (strcmp(command, "set") == 0 && argc >= 4) {
            ok = SMRSetFanSpeed(atoi(argv[3]), atoi(argv[2]), &error);
        } else if (strcmp(command, "auto") == 0 && argc >= 3) {
            ok = SMRSetFanMode(0, atoi(argv[2]), &error);
        } else {
            SMRPrintUsage();
            ok = NO;
        }

        SMRCloseConnection();

        if (!ok) {
            if (error) {
                fprintf(stderr, "%s\n", error.localizedDescription.UTF8String);
            }
            return 1;
        }
    }
    return 0;
}
