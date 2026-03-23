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

    override func viewDidLoad() {
        super.viewDidLoad()

        setupDocumentationLabel()
        updateStatusLabel()
        updateDocumentationLabel()
        updatePrimaryButton(oldValue: nil)
    }

    // MARK: - Private stored properties

    @IBOutlet private var statusLabel: UILabel!
    @IBOutlet private var primaryButton: UIButton!
    private let documentationLabel = UILabel()

}

// MARK: - Private

private extension SetupViewController {

    func updateStatusLabel() {
        statusLabel.text = status
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
            documentationLabel.bottomAnchor.constraint(lessThanOrEqualTo: primaryButton.topAnchor, constant: -24),
        ])
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
