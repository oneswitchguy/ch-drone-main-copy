//
//  StartStopMotorsWidgetModel.swift (based on DUXBetaTakeOffWidgetModel)
//  UXSDKFlight
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

import DJIUXSDKBeta
import Foundation
import UXSDKCore

/**
 * Enum defining the state of the aircraft.
 */
@objc public enum StartStopMotorsState: Int {
    public typealias RawValue = Int

    /**
     * The aircraft is ready to start motors
     */
    case readyToStartMotors

    /**
     * The aircraft is ready to stop motors.
     */
    case readyToStopMotors

    /**
     * The aircraft is unable to start or stop motors.
     */
    case unableToChange
}


/**
 * Data model for the StartStopMotorsWidgetModel used to define
 * the underlying logic and communication.
*/
@objcMembers public class StartStopMotorsWidgetModel: DUXBetaBaseWidgetModel {
    /// The state of the model.
    dynamic public var state: StartStopMotorsState = .unableToChange

    /// The boolean value indicating if aircraft is flying.
    dynamic public var isFlying = false
    /// The boolean value indicating if aircraft has motors on.
    dynamic public var areMotorsOn = false
    /// The remote control mode of the aircraft.
    dynamic public var remoteControlMode: DJIRCMode = .unknown

    public override init() {
        super.init()
    }

    /**
     * Override of parent inSetup method that binds properties to keys
     * and attaches method callbacks on properties updates.
     */
    override public func inSetup() {
        if let key = DJIFlightControllerKey(param: DJIFlightControllerParamIsFlying) {
            bindSDKKey(key, (\StartStopMotorsWidgetModel.isFlying).toString)
        }
        if let key = DJIFlightControllerKey(param: DJIFlightControllerParamAreMotorsOn) {
            bindSDKKey(key, (\StartStopMotorsWidgetModel.areMotorsOn).toString)
        }
        if let key = DJIRemoteControllerKey(param: DJIRemoteControllerParamMode) {
            bindSDKKey(key, (\StartStopMotorsWidgetModel.remoteControlMode).toString)
        }
        bindRKVOModel(self, #selector(updateState),
                      (\StartStopMotorsWidgetModel.isFlying).toString,
                      (\StartStopMotorsWidgetModel.areMotorsOn).toString,
                      (\StartStopMotorsWidgetModel.remoteControlMode).toString,
                      (\StartStopMotorsWidgetModel.isProductConnected).toString)
    }

    /**
     * Override of parent inCleanup method that unbinds properties from keys
     * and detaches methods callbacks.
    */
    override public func inCleanup() {
        unbindSDK(self)
        unbindRKVOModel(self)
    }

    /**
     * Performs turn on motors action.
     */
    public func performStartMotorsAction(_ completion: @escaping DUXBetaWidgetModelActionCompletionBlock) {
        if let key = DJIFlightControllerKey(param: DJIFlightControllerParamTurnOnMotors) {
            DJISDKManager.keyManager()?.performAction(for: key, withArguments: nil, andCompletion: { (finished, response, error) in
                completion(error)
            })
        } else {
            completion(nil)
        }
    }

    /**
     * Performs turn off motors action.
     */
    public func performStopMotorsAction(_ completion: @escaping DUXBetaWidgetModelActionCompletionBlock) {
        if let key = DJIFlightControllerKey(param: DJIFlightControllerParamTurnOffMotors) {
            DJISDKManager.keyManager()?.performAction(for: key, withArguments: nil, andCompletion: { (finished, response, error) in
                completion(error)
            })
        } else {
            completion(nil)
        }
    }

    /**
     * Updates the state property based on several flight status properties.
     * It gets called anytime a change is detected in the underlying variables.
     */
    public func updateState() {
        let nextState: StartStopMotorsState

        if isProductConnected && remoteControlMode != .slave {
            if isFlying {
                nextState = .unableToChange
            } else if areMotorsOn {
                nextState = .readyToStopMotors
            } else {
                nextState = .readyToStartMotors
            }
        } else {
            nextState = .unableToChange
        }

        if nextState != state {
            state = nextState
        }
    }

}
