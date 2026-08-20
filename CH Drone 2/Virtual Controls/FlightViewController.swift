//
//  FlightViewController.swift
//  CH Drone
//
//  Created by Alex Robinson on 13/1/2022.
//

import DJIUXSDKBeta
import UIKit

final class FlightViewController: UIViewController, ControlsBackgroundViewController {

    var topBarLayoutGuide: UILayoutGuide {
        loadViewIfNeeded()
        return topBar!.view.safeAreaLayoutGuide
    }

    let rootView = UIView()
    let videoFeedEnabled: Bool
    var topBar: DUXBetaBarPanelWidget?
    var remainingFlightTimeWidget: DUXBetaRemainingFlightTimeWidget?
    var fpvWidget: DUXBetaFPVWidget?
    var compassWidget: DUXBetaCompassWidget?
    var telemetryPanel: DUXBetaTelemetryPanelWidget?
    private let photoFlashView = UIView()

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    init(videoFeedEnabled: Bool) {
        self.videoFeedEnabled = videoFeedEnabled

        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.addSubview(rootView)
        view.backgroundColor = UIColor.uxsdk_black()

        rootView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            rootView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            rootView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            rootView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            rootView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
        ])

        setupTopBar()

        if videoFeedEnabled {
            setupFPVWidget()
        }

        setupTelemetryPanel()
        setupRemainingFlightTimeWidget()
        setupRTKWidget()

        NotificationCenter.default.addObserver(self, selector: #selector(handleCameraDidTakePhoto), name: .cameraDidTakePhoto, object: nil)
    }

    override func viewDidDisappear(_ animated: Bool) {
        DUXBetaStateChangeBroadcaster.instance().unregisterListener(self)

        super.viewDidDisappear(animated)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        DJISDKManager.keyManager()?.stopAllListening(ofListeners: self)
    }

    // MARK: - Private

    private var topBarWidgetHeightConstraint: NSLayoutConstraint!
}

private extension FlightViewController {

    // Method for setting up the top bar. We may want to refactor this into another file at some point
    // but for now, let's use this as out basic playground file. We are designing for lower complexity
    // if possible than having multiple view containers defined in other classes and getting attached.
    func setupTopBar() {
        let topBarWidget = DUXBetaTopBarWidget()
        topBarWidget.install(in: self) // need to do this to load the initial left widget array before replacing it with an accessible one

        let systemStatusWidget = DUXBetaSystemStatusWidget()
        systemStatusWidget.view.isAccessibilityElement = true
        systemStatusWidget.view.accessibilityTraits.insert(.button)

        topBarWidget.removeLeftWidgets()
        topBarWidget.addLeftWidgetArray([systemStatusWidget])

        topBarWidgetHeightConstraint = topBarWidget.view.heightAnchor.constraint(equalToConstant: 44)

        NSLayoutConstraint.activate([
            topBarWidget.view.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            topBarWidget.view.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            topBarWidget.view.topAnchor.constraint(equalTo: rootView.topAnchor),
            topBarWidgetHeightConstraint,
        ])

        let margin: CGFloat = 5.0
        topBar = topBarWidget
        topBar?.topMargin = margin
        topBar?.rightMargin = margin
        topBar?.bottomMargin = margin
        topBar?.leftMargin = margin

        DUXBetaStateChangeBroadcaster.instance().registerListener(self, analyticsClassName: "SystemStatusUIState") { [weak self] (analyticsData) in
            DispatchQueue.main.async {
                self?.presentSystemStatusPopover()
            }
        }
    }

    func setupRemainingFlightTimeWidget() {
        let remainingFlightTimeWidget = DUXBetaRemainingFlightTimeWidget()

        remainingFlightTimeWidget.install(in: self)

        NSLayoutConstraint.activate([
            remainingFlightTimeWidget.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            remainingFlightTimeWidget.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            remainingFlightTimeWidget.view.centerYAnchor.constraint(equalTo: topBar?.view.bottomAnchor ?? rootView.topAnchor, constant: 3.0)
        ])

        self.remainingFlightTimeWidget = remainingFlightTimeWidget
    }

    func presentSystemStatusPopover() {
        let widget = SystemStatusWidget()
        widget.preferredContentSize.width = 600
        widget.modalPresentationStyle = .popover
        widget.popoverPresentationController?.sourceView = topBar?.view ?? view
        widget.popoverPresentationController?.sourceRect = CGRect(x: view.safeAreaInsets.top, y: view.safeAreaInsets.left, width: topBar?.view.frame.height ?? 0, height: topBar?.view.frame.height ?? 0)
        present(widget, animated: true)
    }

    func setupMainViewConstraints(widget: DUXBetaBaseWidget) {
        NSLayoutConstraint.activate([
            widget.view.topAnchor.constraint(equalTo: topBar?.view.bottomAnchor ?? view.topAnchor),
            widget.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            widget.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            widget.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    func setupFPVWidget() {
        let fpvWidget = DUXBetaFPVWidget()

        fpvWidget.install(in: self)

        setupMainViewConstraints(widget: fpvWidget)

        photoFlashView.translatesAutoresizingMaskIntoConstraints = false
        photoFlashView.backgroundColor = .white
        photoFlashView.alpha = 0
        photoFlashView.isUserInteractionEnabled = false
        fpvWidget.view.addSubview(photoFlashView)

        NSLayoutConstraint.activate([
            photoFlashView.topAnchor.constraint(equalTo: fpvWidget.view.topAnchor),
            photoFlashView.leadingAnchor.constraint(equalTo: fpvWidget.view.leadingAnchor),
            photoFlashView.trailingAnchor.constraint(equalTo: fpvWidget.view.trailingAnchor),
            photoFlashView.bottomAnchor.constraint(equalTo: fpvWidget.view.bottomAnchor),
        ])

        self.fpvWidget = fpvWidget
    }

    @objc func handleCameraDidTakePhoto() {
        guard videoFeedEnabled else {
            return
        }

        fpvWidget?.view.bringSubviewToFront(photoFlashView)
        photoFlashView.layer.removeAllAnimations()
        photoFlashView.alpha = 0

        UIView.animate(withDuration: 0.08, animations: {
            self.photoFlashView.alpha = 0.85
        }) { _ in
            UIView.animate(withDuration: 0.18) {
                self.photoFlashView.alpha = 0
            }
        }
    }

    func setupRTKWidget() {
        let rtkWidget = DUXBetaRTKWidget()
        rtkWidget.view.translatesAutoresizingMaskIntoConstraints = false
        rtkWidget.install(in: self)

        if let topBar = topBar {
            rtkWidget.view.topAnchor.constraint(equalTo: topBar.view.bottomAnchor).isActive = true
        } else {
            rtkWidget.view.topAnchor.constraint(equalTo: view.topAnchor, constant: 44.0).isActive = true
        }
        if let telemetryPanel = telemetryPanel {
            if UIDevice.current.userInterfaceIdiom == .phone {
                rtkWidget.view.bottomAnchor.constraint(equalTo: telemetryPanel.view.bottomAnchor).isActive = true
            } else {
                rtkWidget.view.bottomAnchor.constraint(equalTo: telemetryPanel.view.topAnchor).isActive = true
            }
        } else {
            rtkWidget.view.bottomAnchor.constraint(equalTo: view.topAnchor).isActive = true
        }
        rtkWidget.view.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
    }

    func setupTelemetryPanel() {
        let compassWidget = DUXBetaCompassWidget()
        let telemetryPanel = DUXBetaTelemetryPanelWidget()
        var configuration = DUXBetaPanelWidgetConfiguration(type: .freeform, variant: .freeform)
        configuration = configuration.configureColors(background: .uxsdk_clear())
        _ = telemetryPanel.configure(configuration)

        let leftMarginLayoutGuide = UILayoutGuide.init()
        view.addLayoutGuide(leftMarginLayoutGuide)

        let bottomMarginLayoutGuide = UILayoutGuide.init()
        view.addLayoutGuide(bottomMarginLayoutGuide)

        compassWidget.install(in: self)
        telemetryPanel.install(in: self)

        let backgroundView = telemetryPanel.backgroundViewForPane(0)
        backgroundView?.backgroundColor = .uxsdk_blackAlpha50()
        backgroundView?.layer.cornerRadius = 5.0

        NSLayoutConstraint.activate([
            leftMarginLayoutGuide.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.015),
            leftMarginLayoutGuide.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            leftMarginLayoutGuide.trailingAnchor.constraint(equalTo: compassWidget.view.leadingAnchor),

            bottomMarginLayoutGuide.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.04),
            bottomMarginLayoutGuide.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomMarginLayoutGuide.topAnchor.constraint(equalTo: compassWidget.view.bottomAnchor),

            compassWidget.view.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.116),
            compassWidget.view.widthAnchor.constraint(equalTo: compassWidget.view.heightAnchor, multiplier: compassWidget.widgetSizeHint.preferredAspectRatio),

            telemetryPanel.view.leadingAnchor.constraint(equalTo: compassWidget.view.trailingAnchor),
            telemetryPanel.view.centerYAnchor.constraint(equalTo: compassWidget.view.centerYAnchor),
            telemetryPanel.view.heightAnchor.constraint(equalTo: compassWidget.view.heightAnchor, multiplier: 1.2),
            telemetryPanel.view.widthAnchor.constraint(equalTo: telemetryPanel.view.heightAnchor,
                                                     multiplier: telemetryPanel.widgetSizeHint.preferredAspectRatio)
        ])

        self.compassWidget = compassWidget
        self.telemetryPanel = telemetryPanel
    }

}
