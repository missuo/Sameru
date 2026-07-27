//
//  SMRPanelViewController.m
//  Sameru
//

#import "SMRPanelViewController.h"

static const CGFloat kSMRPanelWidth = 300;
static const CGFloat kSMRPanelPadding = 14;
static const CGFloat kSMRCardPadding = 12;
static const CGFloat kSMRCardCornerRadius = 10;

#pragma mark - Card

/// A frosted tile that floats on top of the panel's blur. Redraws itself when the
/// system flips between light and dark.
@interface SMRCardView : NSView
@end

@implementation SMRCardView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
    }
    return self;
}

- (BOOL)wantsUpdateLayer {
    return YES;
}

- (void)updateLayer {
    [self.effectiveAppearance performAsCurrentDrawingAppearance:^{
        self.layer.cornerRadius = kSMRCardCornerRadius;
        self.layer.backgroundColor = [NSColor.textColor colorWithAlphaComponent:0.05].CGColor;
        self.layer.borderWidth = 1;
        self.layer.borderColor = [NSColor.separatorColor colorWithAlphaComponent:0.6].CGColor;
    }];
}

@end

#pragma mark - Panel

@interface SMRPanelViewController ()

@property (nonatomic, strong) SMRKeepAwakeController *keepAwakeController;
@property (nonatomic, strong) SMRCleanModeController *cleanModeController;
@property (nonatomic, strong) SMRFanController *fanController;
@property (nonatomic, strong) SMRLoginItemController *loginItemController;

@property (nonatomic, strong) NSSwitch *keepAwakeSwitch;
@property (nonatomic, strong) NSSwitch *cleanModeSwitch;
@property (nonatomic, strong) NSSwitch *loginItemSwitch;
@property (nonatomic, strong) NSSegmentedControl *fanModeControl;
@property (nonatomic, strong) NSTextField *fanStatusLabel;
@property (nonatomic, strong) NSTimer *liveUpdateTimer;

@end

@implementation SMRPanelViewController

- (instancetype)initWithKeepAwakeController:(SMRKeepAwakeController *)keepAwakeController
                        cleanModeController:(SMRCleanModeController *)cleanModeController
                              fanController:(SMRFanController *)fanController
                        loginItemController:(SMRLoginItemController *)loginItemController {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _keepAwakeController = keepAwakeController;
        _cleanModeController = cleanModeController;
        _fanController = fanController;
        _loginItemController = loginItemController;
    }
    return self;
}

#pragma mark - View

- (void)loadView {
    NSVisualEffectView *root = [[NSVisualEffectView alloc] initWithFrame:NSMakeRect(0, 0, kSMRPanelWidth, 240)];
    root.material = NSVisualEffectMaterialPopover;
    root.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    root.state = NSVisualEffectStateActive;

    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 8;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:stack];

    [stack addArrangedSubview:[self makeHeaderView]];
    [stack setCustomSpacing:10 afterView:stack.arrangedSubviews.lastObject];

    NSArray<NSView *> *cards = @[
        [self makeKeepAwakeCard],
        [self makeCleanModeCard],
        [self makeFanCard],
        [self makeLoginItemCard]
    ];
    for (NSView *card in cards) {
        [stack addArrangedSubview:card];
    }

    NSView *footer = [self makeFooterView];
    [stack setCustomSpacing:10 afterView:stack.arrangedSubviews.lastObject];
    [stack addArrangedSubview:footer];

    NSMutableArray<NSLayoutConstraint *> *constraints = [@[
        [root.widthAnchor constraintEqualToConstant:kSMRPanelWidth],
        [stack.topAnchor constraintEqualToAnchor:root.topAnchor constant:kSMRPanelPadding],
        [stack.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:kSMRPanelPadding],
        [stack.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-kSMRPanelPadding],
        [stack.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-kSMRPanelPadding],
        [footer.widthAnchor constraintEqualToAnchor:stack.widthAnchor]
    ] mutableCopy];

    // Every card spans the full panel width, so their outlines line up.
    for (NSView *card in cards) {
        [constraints addObject:[card.widthAnchor constraintEqualToAnchor:stack.widthAnchor]];
    }

    [NSLayoutConstraint activateConstraints:constraints];

    self.view = root;
}

- (NSView *)makeHeaderView {
    NSTextField *title = [NSTextField labelWithString:@"Sameru"];
    title.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
    title.textColor = NSColor.labelColor;
    return title;
}

- (NSView *)makeKeepAwakeCard {
    self.keepAwakeSwitch = [[NSSwitch alloc] initWithFrame:NSZeroRect];
    self.keepAwakeSwitch.target = self;
    self.keepAwakeSwitch.action = @selector(keepAwakeSwitchChanged:);

    return [self makeCardWithSymbol:@"cup.and.saucer"
                              title:NSLocalizedString(@"Keep Awake", nil)
                           subtitle:NSLocalizedString(@"Block idle and display sleep", nil)
                          accessory:self.keepAwakeSwitch];
}

- (NSView *)makeCleanModeCard {
    self.cleanModeSwitch = [[NSSwitch alloc] initWithFrame:NSZeroRect];
    self.cleanModeSwitch.target = self;
    self.cleanModeSwitch.action = @selector(cleanModeSwitchChanged:);

    return [self makeCardWithSymbol:@"sparkles"
                              title:NSLocalizedString(@"Clean Mode", nil)
                           subtitle:NSLocalizedString(@"Black screen, input ignored", nil)
                          accessory:self.cleanModeSwitch];
}

- (NSView *)makeLoginItemCard {
    self.loginItemSwitch = [[NSSwitch alloc] initWithFrame:NSZeroRect];
    self.loginItemSwitch.target = self;
    self.loginItemSwitch.action = @selector(loginItemSwitchChanged:);

    return [self makeCardWithSymbol:@"arrow.up.forward.app"
                              title:NSLocalizedString(@"Launch at Login", nil)
                           subtitle:NSLocalizedString(@"Start Sameru when you log in", nil)
                          accessory:self.loginItemSwitch];
}

- (NSView *)makeFanCard {
    SMRCardView *card = [[SMRCardView alloc] initWithFrame:NSZeroRect];
    card.translatesAutoresizingMaskIntoConstraints = NO;

    NSImageView *icon = [self makeIconViewWithSymbol:@"fan"];
    NSTextField *title = [NSTextField labelWithString:NSLocalizedString(@"Fan Control", nil)];
    title.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    title.textColor = NSColor.labelColor;

    NSStackView *header = [NSStackView stackViewWithViews:@[icon, title]];
    header.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    header.spacing = 8;
    header.alignment = NSLayoutAttributeCenterY;

    self.fanModeControl = [NSSegmentedControl segmentedControlWithLabels:@[
        NSLocalizedString(@"Auto", nil),
        NSLocalizedString(@"Cool", nil),
        NSLocalizedString(@"Max", nil)
    ]
                                                            trackingMode:NSSegmentSwitchTrackingSelectOne
                                                                  target:self
                                                                  action:@selector(fanModeChanged:)];
    self.fanModeControl.segmentStyle = NSSegmentStyleRounded;
    self.fanModeControl.controlSize = NSControlSizeRegular;
    for (NSInteger i = 0; i < self.fanModeControl.segmentCount; i++) {
        [self.fanModeControl setWidth:0 forSegment:i];
    }

    self.fanStatusLabel = [NSTextField labelWithString:@""];
    self.fanStatusLabel.font = [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightRegular];
    self.fanStatusLabel.textColor = NSColor.secondaryLabelColor;

    NSStackView *stack = [NSStackView stackViewWithViews:@[header, self.fanModeControl, self.fanStatusLabel]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 8;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:card.topAnchor constant:kSMRCardPadding],
        [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:kSMRCardPadding],
        [stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-kSMRCardPadding],
        [stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-kSMRCardPadding],
        [self.fanModeControl.widthAnchor constraintEqualToAnchor:stack.widthAnchor]
    ]];

    return card;
}

- (NSView *)makeCardWithSymbol:(NSString *)symbolName
                         title:(NSString *)title
                      subtitle:(NSString *)subtitle
                     accessory:(NSView *)accessory {
    SMRCardView *card = [[SMRCardView alloc] initWithFrame:NSZeroRect];
    card.translatesAutoresizingMaskIntoConstraints = NO;

    NSImageView *icon = [self makeIconViewWithSymbol:symbolName];

    NSTextField *titleLabel = [NSTextField labelWithString:title];
    titleLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    titleLabel.textColor = NSColor.labelColor;

    NSTextField *subtitleLabel = [NSTextField labelWithString:subtitle];
    subtitleLabel.font = [NSFont systemFontOfSize:11];
    subtitleLabel.textColor = NSColor.secondaryLabelColor;
    subtitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;

    NSStackView *labels = [NSStackView stackViewWithViews:@[titleLabel, subtitleLabel]];
    labels.orientation = NSUserInterfaceLayoutOrientationVertical;
    labels.alignment = NSLayoutAttributeLeading;
    labels.spacing = 1;

    accessory.translatesAutoresizingMaskIntoConstraints = NO;
    [accessory setContentHuggingPriority:NSLayoutPriorityRequired
                          forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSStackView *row = [NSStackView stackViewWithViews:@[icon, labels, accessory]];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.alignment = NSLayoutAttributeCenterY;
    row.spacing = 8;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [row setVisibilityPriority:NSStackViewVisibilityPriorityMustHold forView:accessory];
    [labels setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                     forOrientation:NSLayoutConstraintOrientationHorizontal];

    [card addSubview:row];

    [NSLayoutConstraint activateConstraints:@[
        [row.topAnchor constraintEqualToAnchor:card.topAnchor constant:kSMRCardPadding - 2],
        [row.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:kSMRCardPadding],
        [row.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-kSMRCardPadding],
        [row.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-(kSMRCardPadding - 2)]
    ]];

    return card;
}

- (NSImageView *)makeIconViewWithSymbol:(NSString *)symbolName {
    NSImage *image = [NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:nil];
    NSImageSymbolConfiguration *configuration =
        [NSImageSymbolConfiguration configurationWithPointSize:15 weight:NSFontWeightRegular];

    NSImageView *view = [NSImageView imageViewWithImage:image ?: [[NSImage alloc] initWithSize:NSMakeSize(16, 16)]];
    view.symbolConfiguration = configuration;
    view.contentTintColor = NSColor.secondaryLabelColor;
    view.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [view.widthAnchor constraintEqualToConstant:20]
    ]];
    return view;
}

- (NSView *)makeFooterView {
    NSImage *quitImage = [NSImage imageWithSystemSymbolName:@"xmark"
                                   accessibilityDescription:NSLocalizedString(@"Quit Sameru", nil)];

    NSButton *quitButton = [NSButton buttonWithImage:quitImage target:self action:@selector(quit:)];
    quitButton.bordered = NO;
    quitButton.imageScaling = NSImageScaleProportionallyDown;
    quitButton.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:12
                                                                                     weight:NSFontWeightMedium];
    quitButton.contentTintColor = NSColor.secondaryLabelColor;
    quitButton.toolTip = NSLocalizedString(@"Quit Sameru", nil);
    quitButton.translatesAutoresizingMaskIntoConstraints = NO;
    [quitButton setContentHuggingPriority:NSLayoutPriorityRequired
                           forOrientation:NSLayoutConstraintOrientationHorizontal];

    // An empty leading view pushes the button to the trailing edge.
    NSView *spacer = [[NSView alloc] initWithFrame:NSZeroRect];
    spacer.translatesAutoresizingMaskIntoConstraints = NO;
    [spacer setContentHuggingPriority:NSLayoutPriorityDefaultLow
                       forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSStackView *stack = [NSStackView stackViewWithViews:@[spacer, quitButton]];
    stack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    stack.alignment = NSLayoutAttributeCenterY;
    stack.distribution = NSStackViewDistributionFill;
    stack.translatesAutoresizingMaskIntoConstraints = NO;

    [NSLayoutConstraint activateConstraints:@[
        [quitButton.widthAnchor constraintEqualToConstant:22],
        [quitButton.heightAnchor constraintEqualToConstant:22],
        [spacer.heightAnchor constraintEqualToConstant:1]
    ]];

    return stack;
}

#pragma mark - State

- (void)viewWillAppear {
    [super viewWillAppear];

    // The very first show happens after loadView, so refreshing here — rather than
    // before the popover opens — is what makes the stored fan mode reach the UI.
    [self refresh];
}

- (void)refresh {
    if (!self.isViewLoaded) {
        return;
    }

    self.keepAwakeSwitch.state = self.keepAwakeController.isActive ? NSControlStateValueOn : NSControlStateValueOff;
    self.cleanModeSwitch.state = self.cleanModeController.isActive ? NSControlStateValueOn : NSControlStateValueOff;

    self.loginItemSwitch.state = self.loginItemController.isEnabled ? NSControlStateValueOn : NSControlStateValueOff;

    BOOL hasFans = self.fanController.hasFans;
    self.fanModeControl.enabled = hasFans;
    self.fanModeControl.selectedSegment = [self segmentForMode:self.fanController.mode];

    for (NSInteger segment = 0; segment < self.fanModeControl.segmentCount; segment++) {
        [self.fanModeControl setToolTip:[self.fanController summaryForMode:[self modeForSegment:segment]]
                             forSegment:segment];
    }

    [self refreshFanStatus];
}

- (void)refreshFanStatus {
    [self.fanController refreshSnapshot];

    SMRFanSnapshot *snapshot = self.fanController.snapshot;
    if (snapshot.fanCount == 0) {
        self.fanStatusLabel.stringValue = NSLocalizedString(@"No controllable fans detected", nil);
        return;
    }

    NSMutableArray<NSString *> *speeds = [NSMutableArray arrayWithCapacity:snapshot.speeds.count];
    for (NSNumber *speed in snapshot.speeds) {
        [speeds addObject:[NSString stringWithFormat:@"%ld", (long)speed.integerValue]];
    }

    NSString *text = [NSString stringWithFormat:NSLocalizedString(@"%@ RPM", nil),
                      [speeds componentsJoinedByString:@" / "]];
    if (!isnan(snapshot.cpuTemperature)) {
        text = [text stringByAppendingFormat:@"  ·  CPU %.0f°C", snapshot.cpuTemperature];
    }

    self.fanStatusLabel.stringValue = text;
}

- (void)startLiveUpdates {
    [self stopLiveUpdates];

    if (!self.fanController.hasFans) {
        return;
    }

    __weak typeof(self) weakSelf = self;
    self.liveUpdateTimer = [NSTimer timerWithTimeInterval:2.0 repeats:YES block:^(NSTimer *timer) {
        [weakSelf refreshFanStatus];
    }];
    [NSRunLoop.mainRunLoop addTimer:self.liveUpdateTimer forMode:NSRunLoopCommonModes];
}

- (void)stopLiveUpdates {
    [self.liveUpdateTimer invalidate];
    self.liveUpdateTimer = nil;
}

- (NSInteger)segmentForMode:(SMRFanMode)mode {
    switch (mode) {
        case SMRFanModeCool: return 1;
        case SMRFanModeMax: return 2;
        default: return 0;
    }
}

- (SMRFanMode)modeForSegment:(NSInteger)segment {
    switch (segment) {
        case 1: return SMRFanModeCool;
        case 2: return SMRFanModeMax;
        default: return SMRFanModeAuto;
    }
}

#pragma mark - Actions

- (void)keepAwakeSwitchChanged:(NSSwitch *)sender {
    if (sender.state != NSControlStateValueOn) {
        [self.keepAwakeController deactivate];
    } else {
        NSError *error = nil;
        if (![self.keepAwakeController activateWithError:&error]) {
            sender.state = NSControlStateValueOff;
            [self presentError:error title:NSLocalizedString(@"Could not turn on Keep Awake", nil)];
        }
    }

    if (self.onStateChange) {
        self.onStateChange();
    }
}

- (void)cleanModeSwitchChanged:(NSSwitch *)sender {
    if (sender.state != NSControlStateValueOn) {
        [self.cleanModeController stop];
        return;
    }

    // The overlay must not come up behind the popover.
    if (self.onRequestClose) {
        self.onRequestClose();
    }

    NSError *error = nil;
    if (![self.cleanModeController startWithError:&error]) {
        sender.state = NSControlStateValueOff;
        [self presentError:error title:NSLocalizedString(@"Could not start Clean Mode", nil)];
    }
}

- (void)loginItemSwitchChanged:(NSSwitch *)sender {
    BOOL shouldEnable = sender.state == NSControlStateValueOn;

    NSError *error = nil;
    if (![self.loginItemController setEnabled:shouldEnable error:&error]) {
        sender.state = shouldEnable ? NSControlStateValueOff : NSControlStateValueOn;
        [self presentError:error title:NSLocalizedString(@"Could not update Launch at Login", nil)];
    }
}

- (void)fanModeChanged:(NSSegmentedControl *)sender {
    SMRFanMode mode = [self modeForSegment:sender.selectedSegment];

    NSError *error = nil;
    if (![self.fanController applyMode:mode error:&error]) {
        [self presentError:error title:NSLocalizedString(@"Could not apply fan mode", nil)];
    }

    sender.selectedSegment = [self segmentForMode:self.fanController.mode];
    [self refreshFanStatus];
}

- (void)quit:(id)sender {
    [NSApp terminate:nil];
}

#pragma mark - Errors

- (void)presentError:(NSError *)error title:(NSString *)title {
    if (self.onRequestClose) {
        self.onRequestClose();
    }

    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = title;
    alert.informativeText = error.localizedDescription ?: NSLocalizedString(@"Unknown error.", nil);
    [alert addButtonWithTitle:NSLocalizedString(@"OK", nil)];

    [NSApp activateIgnoringOtherApps:YES];
    [alert runModal];
}

@end
