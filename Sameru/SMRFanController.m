//
//  SMRFanController.m
//  Sameru
//

#import "SMRFanController.h"

#import <AppKit/AppKit.h>
#import <os/log.h>

const double kSMRCoolSpeedFraction = 0.75;

/// Absolute guard rails, in case the SMC reports nonsense limits.
static const NSInteger kSMRAbsoluteMinRPM = 500;
static const NSInteger kSMRAbsoluteMaxRPM = 8000;

static NSString *const kSMRFanModeDefaultsKey = @"SMRFanMode";

static NSString *const kSMRHelperBundledName = @"sameru-fan-helper";
static NSString *const kSMRHelperBundledSubdirectory = @"SMCHelper";
static NSString *const kSMRHelperInstallDirectory = @"/Library/PrivilegedHelperTools";
static NSString *const kSMRHelperInstallPath = @"/Library/PrivilegedHelperTools/nz.owo.Sameru.fan-helper";

static NSString *const kSMRFanErrorDomain = @"nz.owo.Sameru.FanControl";

static NSString *SMRShellQuoted(NSString *value) {
    NSString *escaped = [value stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"];
    return [NSString stringWithFormat:@"'%@'", escaped];
}

static NSString *SMRAppleScriptEscaped(NSString *value) {
    NSString *escaped = [value stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
    return [escaped stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
}

@implementation SMRFanController {
    SMRSMCReader *_reader;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _reader = [[SMRSMCReader alloc] init];
        _snapshot = [_reader readSnapshot];

        NSNumber *storedMode = [NSUserDefaults.standardUserDefaults objectForKey:kSMRFanModeDefaultsKey];
        _mode = storedMode ? (SMRFanMode)storedMode.integerValue : SMRFanModeAuto;
    }
    return self;
}

- (BOOL)hasFans {
    return self.snapshot.fanCount > 0;
}

- (SMRFanSnapshot *)refreshSnapshot {
    _snapshot = [_reader readSnapshot];
    return _snapshot;
}

+ (NSString *)titleForMode:(SMRFanMode)mode {
    switch (mode) {
        case SMRFanModeAuto:
            return NSLocalizedString(@"Automatic", nil);
        case SMRFanModeCool:
            return NSLocalizedString(@"Cool", nil);
        case SMRFanModeMax:
            return NSLocalizedString(@"Maximum", nil);
    }
    return @"";
}

- (NSString *)summaryForMode:(SMRFanMode)mode {
    if (mode == SMRFanModeAuto) {
        return NSLocalizedString(@"Automatic — macOS manages the fans", nil);
    }

    NSString *headline = (mode == SMRFanModeMax)
        ? NSLocalizedString(@"Maximum — hardware ceiling", nil)
        : [NSString stringWithFormat:NSLocalizedString(@"Cool — %.0f%% of maximum", nil),
           kSMRCoolSpeedFraction * 100];

    NSInteger fanCount = self.snapshot.fanCount;
    if (fanCount == 0) {
        return headline;
    }

    NSMutableArray<NSString *> *targets = [NSMutableArray arrayWithCapacity:fanCount];
    for (NSInteger index = 0; index < fanCount; index++) {
        [targets addObject:@([self targetRPMForMode:mode fanIndex:index]).stringValue];
    }

    return [NSString stringWithFormat:@"%@ · %@ RPM", headline, [targets componentsJoinedByString:@" / "]];
}

#pragma mark - Applying

- (BOOL)applyMode:(SMRFanMode)mode error:(NSError **)error {
    [self refreshSnapshot];

    NSString *helperPath = [self resolveHelperPathCreatingIfNeeded:YES error:error];
    if (!helperPath) {
        return NO;
    }

    if (![self applyMode:mode helperPath:helperPath error:error]) {
        return NO;
    }

    _mode = mode;
    [NSUserDefaults.standardUserDefaults setInteger:mode forKey:kSMRFanModeDefaultsKey];
    return YES;
}

- (void)restoreAutomaticControlIfNeeded {
    if (self.mode == SMRFanModeAuto) {
        return;
    }

    NSString *helperPath = [self resolveHelperPathCreatingIfNeeded:NO error:NULL];
    if (!helperPath) {
        return;
    }

    [self applyMode:SMRFanModeAuto helperPath:helperPath error:NULL];
}

- (void)reapplyCurrentModeIfNeeded {
    if (self.mode == SMRFanModeAuto) {
        return;
    }

    NSString *helperPath = [self resolveHelperPathCreatingIfNeeded:NO error:NULL];
    if (!helperPath) {
        // Without the helper the fans are whatever macOS decided, so the stored
        // mode would be a lie. Fall back to auto rather than show a stale check mark.
        _mode = SMRFanModeAuto;
        [NSUserDefaults.standardUserDefaults setInteger:SMRFanModeAuto forKey:kSMRFanModeDefaultsKey];
        return;
    }

    [self refreshSnapshot];
    [self applyMode:self.mode helperPath:helperPath error:NULL];
}

- (BOOL)applyMode:(SMRFanMode)mode helperPath:(NSString *)helperPath error:(NSError **)error {
    NSInteger fanCount = MAX((NSInteger)1, self.snapshot.fanCount);
    BOOL allSucceeded = YES;

    for (NSInteger index = 0; index < fanCount; index++) {
        NSArray<NSString *> *arguments;

        if (mode == SMRFanModeAuto) {
            arguments = @[@"auto", @(index).stringValue];
        } else {
            NSInteger target = [self targetRPMForMode:mode fanIndex:index];
            arguments = @[@"set", @(index).stringValue, @(target).stringValue];
        }

        if (![self runHelperAtPath:helperPath arguments:arguments]) {
            allSucceeded = NO;
        }
    }

    if (!allSucceeded && error) {
        *error = [NSError errorWithDomain:kSMRFanErrorDomain
                                     code:100
                                 userInfo:@{NSLocalizedDescriptionKey:
                                                NSLocalizedString(@"Some fans did not accept this mode.", nil)}];
    }

    return allSucceeded;
}

- (NSInteger)targetRPMForMode:(SMRFanMode)mode fanIndex:(NSInteger)fanIndex {
    NSArray<NSNumber *> *minSpeeds = self.snapshot.minSpeeds;
    NSArray<NSNumber *> *maxSpeeds = self.snapshot.maxSpeeds;

    NSInteger fanMin = fanIndex < (NSInteger)minSpeeds.count ? minSpeeds[fanIndex].integerValue : kSMRAbsoluteMinRPM;
    NSInteger fanMax = fanIndex < (NSInteger)maxSpeeds.count ? maxSpeeds[fanIndex].integerValue : kSMRAbsoluteMaxRPM;

    fanMin = MAX(kSMRAbsoluteMinRPM, MIN(kSMRAbsoluteMaxRPM, fanMin));
    fanMax = MAX(kSMRAbsoluteMinRPM, MIN(kSMRAbsoluteMaxRPM, fanMax));
    if (fanMax < fanMin) {
        fanMax = fanMin;
    }

    NSInteger target = (mode == SMRFanModeMax) ? fanMax : (NSInteger)lround(fanMax * kSMRCoolSpeedFraction);
    return MAX(fanMin, MIN(fanMax, target));
}

#pragma mark - Helper

- (BOOL)isHelperInstalled {
    NSURL *bundledURL = [self bundledHelperURL];
    if (!bundledURL) {
        return NO;
    }
    return [self installedHelperMatchesBundledAtURL:bundledURL];
}

- (nullable NSURL *)bundledHelperURL {
    return [NSBundle.mainBundle URLForResource:kSMRHelperBundledName
                                 withExtension:nil
                                  subdirectory:kSMRHelperBundledSubdirectory];
}

- (nullable NSString *)resolveHelperPathCreatingIfNeeded:(BOOL)installIfNeeded error:(NSError **)error {
    NSURL *bundledURL = [self bundledHelperURL];
    if (!bundledURL) {
        if (error) {
            *error = [NSError errorWithDomain:kSMRFanErrorDomain
                                         code:101
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    NSLocalizedString(@"The fan control helper is missing from the app bundle. Reinstall Sameru.", nil)}];
        }
        return nil;
    }

    if ([self installedHelperMatchesBundledAtURL:bundledURL]) {
        return kSMRHelperInstallPath;
    }

    if (!installIfNeeded) {
        if (error) {
            *error = [NSError errorWithDomain:kSMRFanErrorDomain
                                         code:102
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    NSLocalizedString(@"The fan control helper is not installed yet.", nil)}];
        }
        return nil;
    }

    if (![self verifyCodeSignatureAtPath:NSBundle.mainBundle.bundlePath]) {
        if (error) {
            *error = [NSError errorWithDomain:kSMRFanErrorDomain
                                         code:103
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    NSLocalizedString(@"Sameru failed its own code signature check, so the fan control helper was not installed.", nil)}];
        }
        return nil;
    }

    if (![self installHelperFromURL:bundledURL error:error]) {
        return nil;
    }

    if (![self installedHelperMatchesBundledAtURL:bundledURL]) {
        if (error) {
            *error = [NSError errorWithDomain:kSMRFanErrorDomain
                                         code:104
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    NSLocalizedString(@"The fan control helper is still missing after installation.", nil)}];
        }
        return nil;
    }

    return kSMRHelperInstallPath;
}

/// The installed copy is only trusted when it is byte-identical to the one shipped
/// inside the app bundle, so an app update reinstalls it instead of running a stale
/// (or tampered) root binary.
- (BOOL)installedHelperMatchesBundledAtURL:(NSURL *)bundledURL {
    NSFileManager *fileManager = NSFileManager.defaultManager;
    if (![fileManager isExecutableFileAtPath:kSMRHelperInstallPath]) {
        return NO;
    }

    NSDictionary<NSFileAttributeKey, id> *attributes =
        [fileManager attributesOfItemAtPath:kSMRHelperInstallPath error:NULL];
    if (![attributes[NSFileOwnerAccountID] isEqual:@(0)]) {
        return NO;
    }

    NSData *installed = [NSData dataWithContentsOfFile:kSMRHelperInstallPath];
    NSData *bundled = [NSData dataWithContentsOfURL:bundledURL];
    return installed != nil && bundled != nil && [installed isEqualToData:bundled];
}

- (BOOL)installHelperFromURL:(NSURL *)sourceURL error:(NSError **)error {
    NSString *command = [@[
        [NSString stringWithFormat:@"/bin/mkdir -p %@", SMRShellQuoted(kSMRHelperInstallDirectory)],
        [NSString stringWithFormat:@"/usr/bin/install -o root -g wheel -m 4755 %@ %@",
         SMRShellQuoted(sourceURL.path), SMRShellQuoted(kSMRHelperInstallPath)],
        [NSString stringWithFormat:@"/bin/chmod 4755 %@", SMRShellQuoted(kSMRHelperInstallPath)]
    ] componentsJoinedByString:@" && "];

    NSString *source = [NSString stringWithFormat:@"do shell script \"%@\" with administrator privileges",
                        SMRAppleScriptEscaped(command)];

    NSAppleScript *script = [[NSAppleScript alloc] initWithSource:source];
    if (!script) {
        if (error) {
            *error = [NSError errorWithDomain:kSMRFanErrorDomain
                                         code:105
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    NSLocalizedString(@"Could not create the authorization script.", nil)}];
        }
        return NO;
    }

    NSDictionary *scriptError = nil;
    [script executeAndReturnError:&scriptError];

    if (scriptError) {
        NSString *message = scriptError[NSAppleScriptErrorMessage] ?: scriptError.description;
        os_log_error(OS_LOG_DEFAULT, "Sameru: helper install failed: %{public}@", message);
        if (error) {
            *error = [NSError errorWithDomain:kSMRFanErrorDomain
                                         code:106
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:NSLocalizedString(@"Could not install the fan control helper: %@", nil), message]}];
        }
        return NO;
    }

    return YES;
}

- (BOOL)verifyCodeSignatureAtPath:(NSString *)path {
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/codesign"];
    task.arguments = @[@"--verify", @"--strict", @"--deep", path];
    task.standardOutput = [NSPipe pipe];
    task.standardError = [NSPipe pipe];

    NSError *launchError = nil;
    if (![task launchAndReturnError:&launchError]) {
        os_log_error(OS_LOG_DEFAULT, "Sameru: codesign launch failed: %{public}@", launchError.localizedDescription);
        return NO;
    }

    [task waitUntilExit];
    return task.terminationStatus == 0;
}

- (BOOL)runHelperAtPath:(NSString *)path arguments:(NSArray<NSString *> *)arguments {
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:path];
    task.arguments = arguments;
    task.environment = @{@"LANG": @"C"};

    NSPipe *errorPipe = [NSPipe pipe];
    task.standardOutput = [NSPipe pipe];
    task.standardError = errorPipe;

    NSError *launchError = nil;
    if (![task launchAndReturnError:&launchError]) {
        os_log_error(OS_LOG_DEFAULT, "Sameru: fan helper launch failed: %{public}@", launchError.localizedDescription);
        return NO;
    }

    NSData *errorData = [errorPipe.fileHandleForReading readDataToEndOfFile];
    [task waitUntilExit];

    if (task.terminationStatus == 0) {
        return YES;
    }

    NSString *message = [[NSString alloc] initWithData:errorData encoding:NSUTF8StringEncoding];
    os_log_error(OS_LOG_DEFAULT, "Sameru: fan helper exited %d: %{public}@",
                 task.terminationStatus, message ?: @"unknown");
    return NO;
}

@end
