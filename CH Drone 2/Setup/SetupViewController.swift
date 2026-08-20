//
//  SetupViewController.swift
//  SetupViewController
//
//  Created by Alex Robinson on 1/8/21.
//

import DJISDK
import UIKit

final class SetupViewController: UIViewController {

    var status: String = "" {
        didSet {
            guard isViewLoaded else { return }
            updateStatusLabel()
        }
    }

    var documentation: String? {
        didSet {
            guard isViewLoaded else { return }
            updateDocumentationLabel()
        }
    }

    var action: UIAction? {
        didSet {
            guard isViewLoaded else { return }
            updatePrimaryButton(oldValue: oldValue)
        }
    }

    /// An optional second choice, shown above the primary button.
    ///
    /// Used to offer the simulator while waiting for an aircraft that may never arrive.
    var secondaryAction: UIAction? {
        didSet {
            guard isViewLoaded else { return }
            updateSecondaryButton(oldValue: oldValue)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        setupSecondaryButton()
        setupDocumentationLabel()
        updateStatusLabel()
        updateDocumentationLabel()
        updatePrimaryButton(oldValue: nil)
        updateSecondaryButton(oldValue: nil)
    }

    // MARK: - Private stored properties

    @IBOutlet private var statusLabel: UILabel!
    @IBOutlet private var primaryButton: UIButton!
    private let documentationLabel = UILabel()
    private let secondaryButton = UIButton(type: .system)

}

// MARK: - Private

private extension SetupViewController {

    func updateStatusLabel() {
        statusLabel.text = status
    }

    func setupSecondaryButton() {
        secondaryButton.translatesAutoresizingMaskIntoConstraints = false
        secondaryButton.titleLabel?.font = .preferredFont(forTextStyle: .body)
        secondaryButton.titleLabel?.adjustsFontForContentSizeCategory = true

        view.addSubview(secondaryButton)

        NSLayoutConstraint.activate([
            secondaryButton.centerXAnchor.constraint(equalTo: primaryButton.centerXAnchor),
            secondaryButton.bottomAnchor.constraint(equalTo: primaryButton.topAnchor, constant: -12),
            secondaryButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
    }

    func setupDocumentationLabel() {
        documentationLabel.translatesAutoresizingMaskIntoConstraints = false
        documentationLabel.numberOfLines = 0
        documentationLabel.textAlignment = .center
        documentationLabel.textColor = .secondaryLabel
        documentationLabel.font = .preferredFont(forTextStyle: .body)
        documentationLabel.adjustsFontForContentSizeCategory = true

        view.addSubview(documentationLabel)

        NSLayoutConstraint.activate([
            documentationLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 24),
            documentationLabel.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            documentationLabel.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            documentationLabel.bottomAnchor.constraint(lessThanOrEqualTo: secondaryButton.topAnchor, constant: -24),
        ])
    }

    func updateSecondaryButton(oldValue: UIAction?) {
        if let oldValue = oldValue {
            secondaryButton.removeAction(oldValue, for: .touchUpInside)
        }

        if let secondaryAction = secondaryAction {
            secondaryButton.addAction(secondaryAction, for: .touchUpInside)
        }

        secondaryButton.setTitle(secondaryAction?.title, for: .normal)
        secondaryButton.isHidden = secondaryAction == nil
    }

    func updateDocumentationLabel() {
        documentationLabel.text = documentation
        documentationLabel.isHidden = documentation == nil
    }

    func updatePrimaryButton(oldValue: UIAction?) {
        if let oldValue = oldValue {
            primaryButton.removeAction(oldValue, for: .touchUpInside)
        }

        if let action = action {
            primaryButton.addAction(action, for: .touchUpInside)
        }

        primaryButton.setTitle(action?.title, for: .normal)

        primaryButton.isHidden = action == nil
    }

}
