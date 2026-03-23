//
//  ControlRowViewController.swift
//  CH Drone
//
//  Created by Alex Robinson on 24/11/21.
//

import Combine
import UIKit

final class ControlRowViewController: UIViewController {

    struct ControlRow {
        let accessibilityID: String
        let accessibilityLabel: String
        let cells: [ControlCell]
    }

    struct ControlCell {
        let command: Command
        let driver: AnyPublisher<CommandState, Never>
        let handler: (Bool) -> Void
    }

    let row: ControlRow

    @ValueSubject var isCustomAccessibilityFocused = false

    init(row: ControlRow) {
        self.row = row

        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        self.view = accessibilityView
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Accessibility

        view.accessibilityIdentifier = row.accessibilityID

        // Layout

        stackView.axis = .horizontal
        stackView.distribution = .fillEqually
        stackView.spacing = 10

        view.embedSubview(stackView, margins: .init(top: 10, leading: 10, bottom: 10, trailing: 10))

        row.cells.enumerated()
            .map { i, cell -> UIButton in
                let button = UIButton(type: .system)
                button.setTitle(cell.command.type.localizedName, for: .normal)

                let activate = UIAction { [weak self] _ in
                    self?.row.cells[i].handler(true)
                }

                let deactivate = UIAction { [weak self] _ in
                    self?.row.cells[i].handler(false)
                }

                // activate on touch down
                button.addAction(activate, for: .touchDown)

                // deactivate on any other touch up or cancel action
                button.addAction(deactivate, for: .touchUpInside)
                button.addAction(deactivate, for: .touchUpOutside)
                button.addAction(deactivate, for: .touchCancel)

                cell.driver.combineLatest($isCustomAccessibilityFocused)
                    .receiveOnMain()
                    .sink { cellState, isCustomAccessibilityFocused in
                        if cellState == .inactive && isCustomAccessibilityFocused {
                            button.backgroundColor = .white
                            button.tintColor = .black
                        } else {
                            button.backgroundColor = cellState.buttonColor
                            button.tintColor = .white
                        }
                        button.isEnabled = cellState != .disabled
                    }
                    .store(in: &cancellables)

                $isCustomAccessibilityFocused
                    .receiveOnMain()
                    .map { $0 ? .black : .clear }
                    .assign(to: \.view.backgroundColor, onWeak: self)
                    .store(in: &cancellables)

                return button
            }
            .forEach(stackView.addArrangedSubview(_:))

        NSLayoutConstraint.activate([
            stackView.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
    }

    // MARK: - Private

    private(set) lazy var accessibilityView = AccessibilityView()
    private var cancellables: [AnyCancellable] = []
    private lazy var stackView: UIStackView = UIStackView(arrangedSubviews: [])

}

private extension CommandState {

    var buttonColor: UIColor {
        switch self {
        case .inactive:
            return .darkGray
        case .pending:
            return .systemOrange
        case .active:
            return .systemGreen
        case .disabled:
            return .darkGray
        }
    }

}
