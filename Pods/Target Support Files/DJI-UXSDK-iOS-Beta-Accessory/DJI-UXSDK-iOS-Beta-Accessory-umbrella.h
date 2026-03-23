#ifdef __OBJC__
#import <UIKit/UIKit.h>
#else
#ifndef FOUNDATION_EXPORT
#if defined(__cplusplus)
#define FOUNDATION_EXPORT extern "C"
#else
#define FOUNDATION_EXPORT extern
#endif
#endif
#endif

#import "UXSDKAccessory.h"
#import "DUXBetaRTKWidget.h"
#import "DUXBetaRTKEnabledWidget.h"
#import "DUXBetaRTKEnabledWidgetModel.h"
#import "DUXBetaRTKSatelliteStatusWidget.h"
#import "DUXBetaRTKSatelliteStatusWidgetModel.h"

FOUNDATION_EXPORT double UXSDKAccessoryVersionNumber;
FOUNDATION_EXPORT const unsigned char UXSDKAccessoryVersionString[];

