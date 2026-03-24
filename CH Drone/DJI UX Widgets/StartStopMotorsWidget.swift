//
//  StartStopMotorsWidget.swift
//  CH Drone
//
//  Created by Alex Robinson on 6/2/2022.
//

import Foundation
import Logging
import UXSDKCore
import UIKit

private let logger = Logger(label: "StartStopMotorsWidget")

@objcMembers class StartStopMotorsWidget: DUXBetaBaseWidget {

    public let widgetModel: StartStopMotorsWidgetModel

    override var widgetSizeHint: DUXBetaWidgetSizeHint {
        get { DUXBetaWidgetSizeHint(preferredAspectRatio: 1, minimumWidth: 44, minimumHeight: 44) }
        set {}
    }

    init(widgetModel: StartStopMotorsWidgetModel = StartStopMotorsWidgetModel()) {
        self.widgetModel = widgetModel

        super.init(nibName: nil, bundle: nil)
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        widgetModel.cleanup()
    }

    override func loadView() {
        view = UIView()
            .assigning(\.translatesAutoresizingMaskIntoConstraints, to: false)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        setupUI()
        widgetModel.setup()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        bindRKVOModel(self, #selector(updateUI), (\StartStopMotorsWidget.widgetModel.state).toString)
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        unbindRKVOModel(self)
    }

    // MARK: - Private

    private lazy var button = UIButton(type: .system)

    private func setupUI() {
        view.embedSubview(button)
        button.contentMode = .scaleAspectFit
        button.imageView?.contentMode = .scaleAspectFit
        button.tintColor = .white

        button.addTarget(self, action: #selector(handleButtonPressed(_:)), for: .touchUpInside)
    }

    @objc private func updateUI() {
        button.isEnabled = widgetModel.state != .unableToChange

        if widgetModel.areMotorsOn {
            button.setImage(UIImage(systemName: "fanblades.fill"), for: .normal)
        } else {
            button.setImage(UIImage(systemName: "fanblades"), for: .normal)
        }

        switch widgetModel.state {
        case .readyToStopMotors:
            button.accessibilityLabel = NSLocalizedString("Stop Motors", comment: "")
        case .readyToStartMotors:
            button.accessibilityLabel = NSLocalizedString("Start Motors", comment: "")
        case .unableToChange:
            button.accessibilityLabel = NSLocalizedString("Motor Control", comment: "")
        }
    }

    @objc private func handleButtonPressed(_ sender: Any?) {
        switch widgetModel.state {
        case .unableToChange:
            break
        case .readyToStartMotors:
            confirmStartMotors()
        case .readyToStopMotors:
            confirmStopMotors()
        }
    }

    private func confirmStartMotors() {
        let alert = UIAlertController(title: NSLocalizedString("Ready to start the motors?", comment: ""), message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("Start motors", comment: ""), style: .default) { [weak self] _ in
            self?.widgetModel.performStartMotorsAction { error in
                if let error = error {
                    logger.error("Failed to start motors", metadata: ["error": .string("\(error)")])
                }
            }
        })
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil))
        present(alert, animated: true)
    }

    private func confirmStopMotors() {
        let alert = UIAlertController(title: NSLocalizedString("Ready to stop motors?", comment: ""), message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("Stop motors", comment: ""), style: .default) { [weak self] _ in
            self?.widgetModel.performStopMotorsAction { error in
                if let error = error {
                    logger.error("Failed to stop motors", metadata: ["error": .string("\(error)")])
                }
            }
        })
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil))
        present(alert, animated: true)
    }

}
