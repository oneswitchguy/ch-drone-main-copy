//
//  MultiplierPickerViewController.swift
//  CH Drone
//
//  Created by Alex Robinson on 28/1/2022.
//

import Combine
import Foundation
import UIKit

final class MultiplierPickerViewController: UIViewController {

    let driver: AnyPublisher<MultiplierLevel, Never>
    let changeHandler: (MultiplierLevel) -> Void

    init(driver: AnyPublisher<MultiplierLevel, Never>, changeHandler: @escaping (MultiplierLevel) -> Void) {
        self.driver = driver
        self.changeHandler = changeHandler

        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = UIView()
        view.backgroundColor = .systemBackground.withAlphaComponent(0.75)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        segmentedControl.selectedSegmentTintColor = .systemBlue

        view.embedSubview(segmentedControl, usingSafeArea: true, margins: NSDirectionalEdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))

        driver.first().receiveOnMain().sink { [weak self] level in
            if let index = MultiplierLevel.allCases.firstIndex(of: level) {
                self?.segmentedControl.selectedSegmentIndex = index
            }
        }.store(in: &cancellables)

        preferredContentSize = CGSize(width: 450, height: 64)
    }

    // MARK: - Private

    private var cancellables: [AnyCancellable] = []

    private var hasAppeared = false

    private lazy var segmentedControl = UISegmentedControl(frame: .zero, actions: MultiplierLevel.allCases.map { level in
        UIAction(title: level.localizedName) { [weak self] _ in
            self?.changeHandler(level)
        }
    })

}
