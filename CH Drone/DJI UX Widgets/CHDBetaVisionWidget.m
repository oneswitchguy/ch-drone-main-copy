//
//  DUXBetaVisionWidget.m
//  UXSDKCore
//
//  MIT License
//  
//  Copyright © 2018-2020 DJI
//  
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:

//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.

//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

@import DJIUXSDKBeta;

#import "CHDBetaVisionWidget.h"

static NSString * const DUXBetaVisionWidgetWarningMessageReason = @"Obstacle Avoidance Disabled.";
static NSString * const DUXBetaVisionWidgetWarningMessageSolution = @"Fly with caution.";

@interface CHDBetaVisionWidget ()

@property (nonatomic, strong) UIImageView *visionImageView;
@property (nonatomic, strong) NSMutableDictionary <NSNumber *, UIImage *> *visionImageMapping;
@property (nonatomic) CGSize minWidgetSize;
@property (nonatomic, strong) NSLayoutConstraint *widgetAspectRatioConstraint;
@property (nonatomic, strong) UITapGestureRecognizer *tapGestureRecognizer;

@end

/**
 * VisionSignalUIState contains the hooks for UI changes in the widget class DUXBetaVisionWidget.
 * It implements the hook:
 *
 * Key: widgetTapped    Type: NSNumber - Sends a boolean YES value as an NSNumber indicating the widget was tapped.
*/
@interface CHDVisionSignalUIState : DUXBetaStateChangeBaseData

+ (instancetype)widgetTapped;

@end

/**
 * VisionWidgetModelState contains the model hooks for the DUXBetaVisionWidget.
 * It implements the hooks:
 *
 * Key: productConnected            Type: NSNumber - Sends a boolean value as an NSNumber indicating if an aircraft is connected.
 *
 * Key: visionSystemStatusUpdated   Type: NSNumber - Sends the updated DUXBetaVisionStatus value as an NSNumber whenever it changes.
 *
 * Key: userAvoidanceEnabledUpdated Type: NSNumber - Sends a boolean value as an NSNunber indicating if obstacle avoidance has
 *                                                   been enabled by the user. YES is obstacle avoidance enabled, NO is deactivated
 *
 * Key: visibilityUpdated           Type: NSNumber - Sends a boolean value as an NSNumber when the aircraft model changes (during
 *                                                   connection/disconnection) to indicate if aircraft supports vision.
*/
@interface CHDVisionModelState : DUXBetaStateChangeBaseData

+ (instancetype)productConnected:(BOOL)isConnected;
+ (instancetype)visionSystemStatusUpdated:(DUXBetaVisionStatus)visionStatus;
+ (instancetype)userAvoidanceEnabledUpdated:(BOOL)isUserAvoidanceEnabled;
+ (instancetype)visibilityUpdated:(BOOL)isVisible;

@end

@implementation CHDBetaVisionWidget

- (instancetype)init {
    self = [super init];
    if (self) {
        [self setupInstanceVariables];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self setupInstanceVariables];
    }
    return self;
}

- (void)setupInstanceVariables {
    _visionImageMapping = [[NSMutableDictionary alloc] initWithDictionary:@{
        @(DUXBetaVisionStatusNormal) : [UIImage duxbeta_imageWithAssetNamed:@"VisionEnabled"],
        @(DUXBetaVisionStatusDisabled) : [UIImage duxbeta_imageWithAssetNamed:@"VisionDisabled"],
        @(DUXBetaVisionStatusClosed) : [UIImage duxbeta_imageWithAssetNamed:@"VisionClosed"],
        @(DUXBetaVisionStatusOmniAll) : [UIImage duxbeta_imageWithAssetNamed:@"VisionAllSensorsEnabled"],
        @(DUXBetaVisionStatusOmniFrontBack) : [UIImage duxbeta_imageWithAssetNamed:@"VisionLeftRightSensorsDisabled"],
        @(DUXBetaVisionStatusOmniVertical) : [UIImage duxbeta_imageWithAssetNamed:@"VisionVertical"],
        @(DUXBetaVisionStatusOmniHorizontal) : [UIImage duxbeta_imageWithAssetNamed:@"VisionHorizontal"],
        @(DUXBetaVisionStatusOmniDisabled) : [UIImage duxbeta_imageWithAssetNamed:@"VisionAllSensorsDisabled"],
        @(DUXBetaVisionStatusOmniClosed) : [UIImage duxbeta_imageWithAssetNamed:@"VisionAllSensorsDisabled"],
        @(DUXBetaVisionStatusUnknown) : [UIImage duxbeta_imageWithAssetNamed:@"VisionDisabled"]
    }];
    
    _iconBackgroundColor = [UIColor clearColor];
    _disconnectedIconColor = [UIColor uxsdk_disabledGrayWhite58];

    _tapGestureRecognizer = [[UITapGestureRecognizer alloc] init];
    
    [self updateMinImageDimensions];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.translatesAutoresizingMaskIntoConstraints = NO;
    
    self.widgetModel = [[DUXBetaVisionWidgetModel alloc] init];
    [self.widgetModel setup];
    
    [self setupUI];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    BindRKVOModel(self, @selector(updateUI), iconBackgroundColor, disconnectedIconColor);
    BindRKVOModel(self.widgetModel, @selector(updateUI), visionSystemStatus, currentAircraftSupportVision, isProductConnected);
    
    BindRKVOModel(self.widgetModel, @selector(sendIsProductConnected), isProductConnected);
    BindRKVOModel(self.widgetModel, @selector(sendVisionSystemStatusUpdate), visionSystemStatus);
    BindRKVOModel(self.widgetModel, @selector(sendVisionDisabledWarning), isCollisionAvoidanceEnabled);
    BindRKVOModel(self.widgetModel, @selector(sendVisibilityUpdate), currentAircraftSupportVision);
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    
    UnBindRKVOModel(self);
    UnBindRKVOModel(self.widgetModel);
}

- (void)dealloc {
    [self.widgetModel cleanup];
}

- (void)setupUI {
    UIImage *image = [self.visionImageMapping objectForKey:@(self.widgetModel.visionSystemStatus)];
    self.visionImageView = [[UIImageView alloc] initWithImage:image];
    self.visionImageView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.visionImageView];
    
    CGFloat imageAspectRatio = image.size.width / image.size.height;

    self.widgetAspectRatioConstraint = [self.view.widthAnchor constraintEqualToAnchor:self.view.heightAnchor multiplier:imageAspectRatio];
    self.widgetAspectRatioConstraint.active = YES;
    [self.visionImageView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor].active = YES;
    [self.visionImageView.topAnchor constraintEqualToAnchor:self.view.topAnchor].active = YES;
    [self.visionImageView.widthAnchor constraintEqualToAnchor:self.view.widthAnchor].active = YES;
    [self.visionImageView.heightAnchor constraintEqualToAnchor:self.view.heightAnchor].active = YES;
    self.visionImageView.contentMode = UIViewContentModeScaleAspectFit;
    
    [self updateUI];

    [self.tapGestureRecognizer addTarget:self action:@selector(widgetTapped)];
    [self.view addGestureRecognizer:self.tapGestureRecognizer];
}

- (void)updateUI {
    self.visionImageView.backgroundColor = self.iconBackgroundColor;
    self.visionImageView.image = [self.visionImageMapping objectForKey:@(self.widgetModel.visionSystemStatus)];

    if (!self.widgetModel.isProductConnected) {
        UIImage *tintableImage = [self.visionImageView.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        self.visionImageView.image = tintableImage;
        [self.visionImageView setTintColor:self.disconnectedIconColor];
    }
    
    if (self.widgetModel.currentAircraftSupportVision) {
        [self.view setHidden:NO];
    } else {
        [self.view setHidden:YES];
    }
}

- (void)sendIsProductConnected {
    [[DUXBetaStateChangeBroadcaster instance] send:[CHDVisionModelState productConnected:self.widgetModel.isProductConnected]];
}

- (void)sendVisionSystemStatusUpdate {
    [[DUXBetaStateChangeBroadcaster instance] send:[CHDVisionModelState visionSystemStatusUpdated:self.widgetModel.visionSystemStatus]];
}

- (void)sendVisibilityUpdate {
    [[DUXBetaStateChangeBroadcaster instance] send:[CHDVisionModelState visibilityUpdated:self.widgetModel.currentAircraftSupportVision]];
}

- (void)sendVisionDisabledWarning {
    // Send Hook
    [[DUXBetaStateChangeBroadcaster instance] send:[CHDVisionModelState userAvoidanceEnabledUpdated:self.widgetModel.isCollisionAvoidanceEnabled]];
    // Send Warning Message
    [self.widgetModel sendWarningMessageWithReason:DUXBetaVisionWidgetWarningMessageReason andSolution:DUXBetaVisionWidgetWarningMessageSolution];
}

- (void)setImage:(UIImage *)image forVisionStatus:(DUXBetaVisionStatus)status {
    [self.visionImageMapping setObject:image forKey:@(status)];
    [self updateMinImageDimensions];
    [self updateUI];
}

- (UIImage *)imageForVisionStatus:(DUXBetaVisionStatus)status {
    return [self.visionImageMapping objectForKey:@(status)];
}

- (void)widgetTapped {
    [[DUXBetaStateChangeBroadcaster instance] send:[CHDVisionSignalUIState widgetTapped]];
}

- (void)updateMinImageDimensions {
    _minWidgetSize = [self maxSizeInImageArray:self.visionImageMapping.allValues];
    [self.widgetAspectRatioConstraint duxbeta_updateMultiplier:self.widgetSizeHint.preferredAspectRatio];
}

- (DUXBetaWidgetSizeHint)widgetSizeHint {
    DUXBetaWidgetSizeHint hint = {self.minWidgetSize.width / self.minWidgetSize.height, self.minWidgetSize.width, self.minWidgetSize.height};
    return hint;
}

@end

@implementation CHDVisionSignalUIState

+ (instancetype)widgetTapped {
    return [[CHDVisionSignalUIState alloc] initWithKey:@"widgetTapped" number:@(0)];
}

@end

@implementation CHDVisionModelState

+ (instancetype)productConnected:(BOOL)isConnected {
    return [[CHDVisionModelState alloc] initWithKey:@"productConnected" number:@(isConnected)];
}

+ (instancetype)visionSystemStatusUpdated:(DUXBetaVisionStatus)visionStatus {
    return [[CHDVisionModelState alloc] initWithKey:@"visionSystemStatusUpdated" number:@(visionStatus)];
}

+ (instancetype)userAvoidanceEnabledUpdated:(BOOL)isUserAvoidanceEnabled {
    return [[CHDVisionModelState alloc] initWithKey:@"userAvoidanceEnabledUpdated" number:@(isUserAvoidanceEnabled)];
}

+ (instancetype)visibilityUpdated:(BOOL)isVisible {
    return [[CHDVisionModelState alloc] initWithKey:@"visibilityUpdated" number:@(isVisible)];
}

@end
