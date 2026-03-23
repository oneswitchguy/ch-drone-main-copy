//
//  DUXBetaTakeOffWidget.swift
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
import UXSDKCore

/**
 * A button that performs actions related to takeoff and landing. There are three possible states
 * for the widget: ready to take off, ready to land, and landing in progress. Clicking the
 * button in each of these states will open a dialog to confirm take off, landing, and landing
 * cancellation, respectively.
 *
 * Additionally, this widget will show a dialog if landing is in progress, but it is currently
 * unsafe to land. The dialog will prompt the user whether or not they want to cancel landing.
 *
 * NOTE: This has been adapted from `DUXBetaTakeOffWidget` to use a system alert view instead of the "slide to confirm"-style alert which is horribly inaccessible.
 */

@objcMembers public class TakeOffWidget: DUXBetaBaseWidget {
    /// The widget model that contains the underlying logic and communication.
    public var widgetModel: DUXBetaTakeOffWidgetModel!
    /// The image for the take off action.
    public var takeOffActionImage = UIImage.duxbeta_image(withAssetNamed: "TakeOff", for: DUXBetaTakeOffWidget.self) {
        didSet {
            updateMinimumSize()
            updateActionIcon(image: takeOffActionImage)
        }
    }
    /// The image for the land action.
    public var landActionImage = UIImage.duxbeta_image(withAssetNamed: "Land", for: DUXBetaTakeOffWidget.self) {
        didSet {
            updateMinimumSize()
            updateActionIcon(image: landActionImage)
        }
    }
    /// The image for the cancel landing action.
    public var cancelLandActionImage = UIImage.duxbeta_image(withAssetNamed: "TakeOff", for: DUXBetaTakeOffWidget.self) {
        didSet {
            updateMinimumSize()
            updateActionIcon(image: cancelLandActionImage)
        }
    }
    /// The image for the cancel landing action disabled.
    public var cancelLandActionDisabledImage = UIImage.duxbeta_image(withAssetNamed: "TakeOffStopDisabled", for: DUXBetaTakeOffWidget.self) {
        didSet {
            updateMinimumSize()
            updateActionIcon(image: cancelLandActionDisabledImage)
        }
    }
    /// The background color of the control.
    public var backgroundColor = UIColor.uxsdk_clear() {
        didSet {
            view.backgroundColor = backgroundColor
        }
    }
    /// The image tint color for the take off action.
    public var takeOffActionTintColor = UIColor.uxsdk_white() {
        didSet {
            updateActionIcon(tintColor: takeOffActionTintColor)
        }
    }
    /// The image tint color for the land action.
    public var landActionTintColor = UIColor.uxsdk_white() {
        didSet {
            updateActionIcon(tintColor: landActionTintColor)
        }
    }
    /// The image tint color for the cancel landing action.
    public var cancelLandActionTintColor = UIColor.uxsdk_white() {
        didSet {
            updateActionIcon(tintColor: landActionTintColor)
        }
    }
    /// The image tint color for the cancel landing action disabled.
    public var cancelLandActionDisabledTintColor = UIColor.uxsdk_grayWhite50() {
        didSet {
            updateActionIcon(tintColor: cancelLandActionDisabledTintColor)
        }
    }
    /// The image tint color for the take off alert.
    public var takeOffAlertTintColor = UIColor.uxsdk_warning()
    /// The image tint color for the land alert.
    public var landingAlertTintColor = UIColor.uxsdk_warning()
    /// The image tint color for the landing confirmation alert.
    public var landingConfirmationAlertTintColor = UIColor.uxsdk_warning()
    /// The image tint color for the unsafe to land alert.
    public var unsafeToLandAlertTintColor = UIColor.uxsdk_warning()
    /// The customization instance that controls the appearance of the dialog cancel action.
    public var alertCancelActionAppearance = DUXBetaSlideAlertView.cancelActionAppearance
    /// The standard widgetSizeHint indicating the minimum size for this widget and preferred aspect ratio.
    public override var widgetSizeHint : DUXBetaWidgetSizeHint {
        get { return DUXBetaWidgetSizeHint(preferredAspectRatio: minWidgetSize.width/minWidgetSize.height, minimumWidth: minWidgetSize.width, minimumHeight: minWidgetSize.height)}
        set {
        }
    }

    var minWidgetSize = CGSize.zero {
        didSet {
            aspectRatioConstraint?.duxbeta_updateMultiplier(widgetSizeHint.preferredAspectRatio)
        }
    }
    var aspectRatioConstraint: NSLayoutConstraint?
    lazy var button: UIButton = UIButton()
    var alertView: UIAlertController?

    /**
     * Override of viewDidLoad to set up widget model and
     * to instantiate all the user interface elements.
    */
    public override func viewDidLoad() {
        super.viewDidLoad()
        view.translatesAutoresizingMaskIntoConstraints = false

        setupUI()

        widgetModel = DUXBetaTakeOffWidgetModel()
        widgetModel.setup()
    }

    /**
     * Override of viewWillAppear to establish bindings to the widgetModel.
     */
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        bindRKVOModel(self, #selector(updateIsConnected), (\DUXBetaTakeOffWidget.widgetModel.isProductConnected).toString)
        bindRKVOModel(self, #selector(updateUI), (\DUXBetaTakeOffWidget.widgetModel.state).toString)
    }

    /**
     * Override of viewWillDisappear to clean up bindings to the widgetModel
     */
    public override func viewWillDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        unbindRKVOModel(self)
    }

    /**
     * Standard dealloc method that performs cleanup of the widget model.
     */
    deinit {
        widgetModel.cleanup()
    }

    @objc func updateIsConnected() {
        //Forward the model change
        DUXBetaStateChangeBroadcaster.send(TakeOffModelState.productConnected(widgetModel.isProductConnected))
    }

    fileprivate func setupUI() {
        updateMinimumSize()

        view.backgroundColor = backgroundColor
        view.isUserInteractionEnabled = true

        button.translatesAutoresizingMaskIntoConstraints = false
        button.backgroundColor = .clear
        button.addTarget(self, action: #selector(buttonPressed), for: .touchUpInside)
        updateActionIcon(image: cancelLandActionImage, tintColor: cancelLandActionDisabledTintColor)

        view.addSubview(button)

        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: view.topAnchor),
            button.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            button.leftAnchor.constraint(equalTo: view.leftAnchor),
            button.rightAnchor.constraint(equalTo: view.rightAnchor),
            view.widthAnchor.constraint(equalTo: view.heightAnchor, multiplier: widgetSizeHint.preferredAspectRatio)
        ])
        aspectRatioConstraint = view.widthAnchor.constraint(equalTo: view.heightAnchor, multiplier: widgetSizeHint.preferredAspectRatio)
    }

    func buttonPressed() {
        DUXBetaStateChangeBroadcaster.send(TakeOffUIState.widgetTapped())

        switch widgetModel.state {
            case .ReadyToTakeOff:
                showTakeOffDialog()
            case .ReadyToLand:
                showStartLandingDialog()
            case .AutoLanding:
                fallthrough
            case .ForcedAutoLanding:
                fallthrough
            case .WaitingForLandingConfirmation:
                performCancelLandAction()
            case .UnsafeToLand:
                showUnsafeToLandDialog()
            default:
                break
        }
    }

    func updateUI() {
        let actionEnabled = !(widgetModel.state == .TakeOffDisabled || widgetModel.state == .LandDisabled || widgetModel.state == .ForcedAutoLanding) && widgetModel.isProductConnected

        switch widgetModel.state {
            case .ReadyToTakeOff:
                fallthrough
            case .TakeOffDisabled:
                updateActionIcon(image: takeOffActionImage, tintColor: takeOffActionTintColor)
                break
            case .ReadyToLand:
                fallthrough
            case .LandDisabled:
                updateActionIcon(image: landActionImage, tintColor: landActionTintColor)
                break
            case .AutoLanding:
                fallthrough
            case .ForcedAutoLanding:
                fallthrough
            case .WaitingForLandingConfirmation:
                fallthrough
            case .UnsafeToLand:
                if actionEnabled {
                    updateActionIcon(image: cancelLandActionImage, tintColor: cancelLandActionTintColor)
                } else {
                    updateActionIcon(image: cancelLandActionDisabledImage, tintColor: cancelLandActionDisabledTintColor)
            }
            default:
                break
        }

        button.isEnabled = actionEnabled
        view.isHidden = widgetModel.state == .ReturningHome

        if widgetModel.state == .ReadyToTakeOff || widgetModel.state == .TakeOffDisabled {
            alertView?.dismiss(animated: true) { [weak self] in
                self?.alertView = nil
            }
        }

        if widgetModel.state == .WaitingForLandingConfirmation {
            showLandingConfirmationDialog()
        }

        DUXBetaStateChangeBroadcaster.send(TakeOffModelState.takeOffLandingStateUpdated(widgetModel.state))
    }

    func updateMinimumSize() {
        var images = [UIImage]()
        if let takeOffActionImage = takeOffActionImage {
            images.append(takeOffActionImage)
        }
        if let landActionImage = landActionImage {
            images.append(landActionImage)
        }
        if let cancelLandActionImage = cancelLandActionImage {
            images.append(cancelLandActionImage)
        }
        minWidgetSize = maxSize(inImageArray: images)
    }

    fileprivate func updateActionIcon(image: UIImage? = nil, tintColor: UIColor? = nil) {
        if image == cancelLandActionImage {
            button.setImage(image, for: .normal)
        } else {
            button.setImage(image?.withRenderingMode(.alwaysTemplate), for: .normal)
        }

        if let color = tintColor {
            button.tintColor = color
        }
    }

    fileprivate func showTakeOffDialog() {
        let height = widgetModel.unitModule.meters(toUnitString: widgetModel.takeOffHeight)
        var message = NSLocalizedString("Ensure that conditions are safe for takeoff. Aircraft will go to an altitude of \(height) and hover.",
            comment: "Ensure that conditions are safe for takeoff. Aircraft will go to an altitude of %1$s and hover.")
        if widgetModel.isInAttiMode {
            message = NSLocalizedString("Positioning failed. The aircraft will automatically fly to \(height) above the ground. " +
                "Do not take off in a narrow space or near crowds or buildings. Do not touch propellers.",
                                        comment: "Dialog message when precision take off is not selected in atti mode.")
        }

        alertView = UIAlertController(title: NSLocalizedString("Take off?", comment: "Take off?"), message: message, preferredStyle: .alert)
        alertView?.addAction(UIAlertAction(title: NSLocalizedString("Take off", comment: ""), style: .default) { [weak self] _ in
            self?.performTakeOffAction()
            self?.alertView = nil
            DUXBetaStateChangeBroadcaster.send(TakeOffUIState.dialogActionConfirmed(.TakeOffDialog))
        })

        alertView?.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Cancel"), style: .cancel) { [weak self] _ in
            self?.alertView = nil
            DUXBetaStateChangeBroadcaster.send(TakeOffUIState.dialogActionCancelled(.TakeOffDialog))
        })

        present(alertView!, animated: true) {
            DUXBetaStateChangeBroadcaster.send(TakeOffUIState.dialogDisplayed(.TakeOffDialog))
        }
    }

    fileprivate func showStartLandingDialog() {
        alertView = UIAlertController(
            title: NSLocalizedString("Land?", comment: "Land?"),
            message: NSLocalizedString("Aircraft will land at its current location. Check landing area is clear.",
                                       comment: "Aircraft will land at its current location. Check landing area is clear."),
            preferredStyle: .alert
        )

        alertView?.addAction(UIAlertAction(title: NSLocalizedString("Land", comment: ""), style: .default) { [weak self] _ in
            self?.performLandingAction()
            self?.alertView = nil
            DUXBetaStateChangeBroadcaster.send(TakeOffUIState.dialogActionConfirmed(.LandingDialog))
        })

        alertView?.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Cancel"), style: .cancel) { [weak self] _ in
            self?.alertView = nil
            DUXBetaStateChangeBroadcaster.send(TakeOffUIState.dialogActionCancelled(.LandingDialog))
        })

        present(alertView!, animated: true) {
            DUXBetaStateChangeBroadcaster.send(TakeOffUIState.dialogDisplayed(.LandingDialog))
        }
    }

    fileprivate func showLandingConfirmationDialog() {
        let height = widgetModel.unitModule.meters(toUnitString: widgetModel.landHeight)
        var message = NSLocalizedString("Aircraft has descended to \(height).", comment: "Aircraft has descended to \(height).")
        if widgetModel.isInspire2OrMatrice200Series {
            message = NSLocalizedString("Aircraft will land at its current location. Check landing area is clear.", comment: "Aircraft will land at its current location. Check landing area is clear.")
        }

        alertView = UIAlertController(title: NSLocalizedString("Continue Landing?", comment: "Continue Landing?"), message: message, preferredStyle: .alert)

        alertView?.addAction(UIAlertAction(title: "Continue Landing", style: .default) { [weak self] _ in
            self?.performLandingConfirmationAction()
            self?.alertView = nil
            DUXBetaStateChangeBroadcaster.send(TakeOffUIState.dialogActionConfirmed(.LandingConfirmationDialog))
        })

        alertView?.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Cancel"), style: .cancel) { [weak self] _ in
            self?.performCancelLandAction()
            self?.alertView = nil
            DUXBetaStateChangeBroadcaster.send(TakeOffUIState.dialogActionCancelled(.LandingConfirmationDialog))
        })

        present(alertView!, animated: true) {
            DUXBetaStateChangeBroadcaster.send(TakeOffUIState.dialogDisplayed(.LandingConfirmationDialog))
        }
    }

    fileprivate func showUnsafeToLandDialog() {
        alertView = UIAlertController(title: NSLocalizedString("Not suitable for landing.", comment: "Not suitable for landing."), message: NSLocalizedString("Area is not suitable for landing. Please move to a safer location.", comment: "Area is not suitable for landing. Please move to a safer location."), preferredStyle: .alert)

        alertView?.addAction(UIAlertAction(title: NSLocalizedString("Force Landing", comment: ""), style: .destructive) { [weak self] _ in
            self?.performLandingAction()
            self?.alertView = nil
            DUXBetaStateChangeBroadcaster.send(TakeOffUIState.dialogActionConfirmed(.UnsafeToLandDialog))
        })

        alertView?.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Cancel"), style: .cancel) { [weak self] _ in
            self?.performCancelLandAction()
            self?.alertView = nil
            DUXBetaStateChangeBroadcaster.send(TakeOffUIState.dialogActionCancelled(.UnsafeToLandDialog))
        })

        present(alertView!, animated: true) {
            DUXBetaStateChangeBroadcaster.send(TakeOffUIState.dialogDisplayed(.UnsafeToLandDialog))
        }
    }

    fileprivate func performTakeOffAction() {
        widgetModel.performTakeOffAction({ (error) in
            if let err = error {
                DUXBetaStateChangeBroadcaster.send(TakeOffModelState.takeOffStartedFailed(err))
            } else {
                DUXBetaStateChangeBroadcaster.send(TakeOffModelState.takeOffStartedSucceeded())
            }
        })
    }

    fileprivate func performPrecisionTakeOffAction() {
        widgetModel.performPrecisionTakeOffAction { (error) in
            if let err = error {
                DUXBetaStateChangeBroadcaster.send(TakeOffModelState.precisionTakeOffStartFailed(err))
            } else {
                DUXBetaStateChangeBroadcaster.send(TakeOffModelState.precisionTakeOffStartedSucceeded())
            }
        }
    }

    fileprivate func performLandingAction() {
        widgetModel.performLandingAction { (error) in
            if let err = error {
                DUXBetaStateChangeBroadcaster.send(TakeOffModelState.landingStartFailed(err))
            } else {
                DUXBetaStateChangeBroadcaster.send(TakeOffModelState.landingStartSucceeded())
            }
        }
    }

    fileprivate func performCancelLandAction() {
        widgetModel.performCancelLandingAction { (error) in
            if let err = error {
                DUXBetaStateChangeBroadcaster.send(TakeOffModelState.landingCancelFailed(err))
            } else {
                DUXBetaStateChangeBroadcaster.send(TakeOffModelState.landingCancelSucceeded())
            }
        }
    }

    fileprivate func performLandingConfirmationAction() {
        widgetModel.performLandingConfirmationAction { (error) in
            if let err = error {
                DUXBetaStateChangeBroadcaster.send(TakeOffModelState.landingConfirmFailed(err))
            } else {
                DUXBetaStateChangeBroadcaster.send(TakeOffModelState.landingConfirmSucceeded())
            }
        }
    }
}

/**
 * TakeOffWidgetModelState contains the hooks for the model changes in the DUXBetaTakeOffWidget implementation.
 *
 * Key: productConnected                    Type: NSNumber - Sends a boolean value as an NSNumber
 *                                          when product connection state changes.
 *
 * Key: takeOffLandingStateUpdated          Type: NSNumber - Sends an NSNumber value when widget
 *                                          state is updated.
 *
 * Key: takeOffStartedSucceeded             Type: NSNumber - Sends true as an NSNumber value when
 *                                          take off started successfully.
 *
 * Key: takeOffStartedFailed                Type: NSError - Sends an NSError as an object when
 *                                          take off has not started due to an error.
 *
 * Key: precisionTakeOffStartedSucceeded    Type: NSNumber - Sends true as an NSNumber value when
 *                                          precision take off started successfully.
 *
 * Key: precisionTakeOffStartFailed         Type: NSError - Sends an NSError as an object
 *                                          when precision take off has not started due to an error.
 *
 * Key: landingStartSucceeded               Type: NSNumber - Sends true as an NSNumber value
 *                                          when landing started successfully.
 *
 * Key: landingStartFailed                  Type: NSError - Sends an NSError as an object
 *                                          when landing has not started due to an error.
 *
 * Key: landingConfirmSucceeded             Type: NSNumber - Sends true as an NSNumber value
 *                                          when landing confirm started successfully.
 *
 * Key: landingConfirmFailed                Type: NSError - Sends an NSError as an object
 *                                          when landing confirm has not started due to an error.
 *
 * Key: landingCancelSucceeded              Type: NSNumber - Sends true as an NSNumber value when
 *                                          landing cancellation started successfully.
 *
 * Key: landingCancelFailed                 Type: NSError - Sends an NSError as an object when
 *                                          landing cancellation has not started due to an error.
*/
@objc public class TakeOffModelState: DUXBetaStateChangeBaseData {

    @objc public static func productConnected(_ isConnected: Bool) -> TakeOffModelState {
        return TakeOffModelState(key: "productConnected", number: NSNumber(value: isConnected))
    }

    @objc public static func takeOffLandingStateUpdated(_ state: DUXBetaTakeOffLandingState) -> TakeOffModelState {
        return TakeOffModelState(key: "takeOffLandingStateUpdated", number: NSNumber(value: state.rawValue))
    }

    @objc public static func takeOffStartedSucceeded() -> TakeOffModelState {
        return TakeOffModelState(key: "takeOffStartedSucceeded", number: NSNumber(value: true))
    }

    @objc public static func takeOffStartedFailed(_ error: Error) -> TakeOffModelState {
        return TakeOffModelState(key: "takeOffStartedFailed", object: error)
    }

    @objc public static func precisionTakeOffStartedSucceeded() -> TakeOffModelState {
        return TakeOffModelState(key: "precisionTakeOffStartedSucceeded", number: NSNumber(value: true))
    }

    @objc public static func precisionTakeOffStartFailed(_ error: Error) -> TakeOffModelState {
        return TakeOffModelState(key: "precisionTakeOffStartFailed", object: error)
    }

    @objc public static func landingStartSucceeded() -> TakeOffModelState {
        return TakeOffModelState(key: "landingStartSucceeded", number: NSNumber(value: true))
    }

    @objc public static func landingStartFailed(_ error: Error) -> TakeOffModelState {
        return TakeOffModelState(key: "landingStartFailed", object: error)
    }

    @objc public static func landingConfirmSucceeded() -> TakeOffModelState {
        return TakeOffModelState(key: "landingConfirmSucceeded", number: NSNumber(value: true))
    }

    @objc public static func landingConfirmFailed(_ error: Error) -> TakeOffModelState {
        return TakeOffModelState(key: "landingConfirmFailed", object: error)
    }

    @objc public static func landingCancelSucceeded() -> TakeOffModelState {
        return TakeOffModelState(key: "landingCancelSucceeded", number: NSNumber(value: true))
    }

    @objc public static func landingCancelFailed(_ error: Error) -> TakeOffModelState {
        return TakeOffModelState(key: "landingCancelFailed", object: error)
    }
}

/**
 * TakeOffUIState contains the hooks for the UI changes in the DUXBetaTakeOffWidget implementation.
 *
 * Key: widgetTapped                            Type: NSNumber - Sends true as an NSNumber when
 *                                              the widget is tapped.
 *
 * Key: dialogSDisplayed                        Type: NSNumber - Sends dialogType as an NSNumber
 *                                              when dialog is shown.
 *
 * Key: dialogActionCancelled                   Type: NSNumber - Sends dialogType as an NSNumber
 *                                              when dialog is canceled.
 *
 * Key: dialogDismissed                         Type: NSNumber - Sends dialogType as an NSNumber
 *                                              when dialog is disissed.
 *
 * Key: dialogActionConfirmed                   Type: NSNumber - Sends dialogType as an NSNumber
 *                                              when dialog sliding action is completed.
 *
 * Key: dialogCheckChanged                      Type: NSNumber - Sends boolean value as an NSNumber
 *                                              when the precision checkbox changes state.
*/
@objc public class TakeOffUIState: DUXBetaStateChangeBaseData {

    @objc public static func widgetTapped() -> TakeOffUIState {
        return TakeOffUIState(key: "widgetTapped", number: NSNumber(value: true))
    }

    @objc public static func dialogDisplayed(_ dialogType: DUXBetaTakeOffWidgetDialogType) -> TakeOffUIState {
        return TakeOffUIState(key: "dialogDisplayed", number: NSNumber(value: dialogType.rawValue))
    }

    @objc public static func dialogActionCancelled(_ dialogType: DUXBetaTakeOffWidgetDialogType) -> TakeOffUIState {
        return TakeOffUIState(key: "dialogActionCancelled", number: NSNumber(value: dialogType.rawValue))
    }

    @objc public static func dialogDismissed(_ dialogType: DUXBetaTakeOffWidgetDialogType) -> TakeOffUIState {
        return TakeOffUIState(key: "dialogDismissed", number: NSNumber(value: dialogType.rawValue))
    }

    @objc public static func dialogActionConfirmed(_ dialogType: DUXBetaTakeOffWidgetDialogType) -> TakeOffUIState {
        return TakeOffUIState(key: "dialogActionConfirmed", number: NSNumber(value: dialogType.rawValue))
    }

    @objc public static func dialogCheckChanged(_ checked: Bool) -> TakeOffUIState {
        return TakeOffUIState(key: "dialogCheckChanged", number: NSNumber(value: checked))
    }
}
