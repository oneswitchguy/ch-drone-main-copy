//
//  MultipliersRowViewController.swift
//  CH Drone
//
//  Created by Alex Robinson on 28/1/2022.
//

import Combine
import Foundation
import UIKit

final class MultiplierCellViewController: UIViewController {

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
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        button.backgroundColor = .black
        button.tintColor = .white
        button.addAction(UIAction { [weak self] _ in
            self?.presentInputPopover()
        }, for: .touchUpInside)

        driver.receiveOnMain().sink { [weak self] value in
            self?.button.setTitle(value.localizedName, for: .normal)
        }.store(in: &cancellables)

        view?.embedSubview(button)
    }

    // MARK: - Private

    private var cancellables: [AnyCancellable] = []

    private lazy var button = UIButton(type: .system)

    private func presentInputPopover() {
        let vc = MultiplierPickerViewController(driver: driver, changeHandler: changeHandler)
        vc.modalPresentationStyle = .popover
        vc.popoverPresentationController?.permittedArrowDirections = [.up, .down]
        vc.popoverPresentationController?.sourceView = button
        vc.popoverPresentationController?.sourceRect = button.bounds
        present(vc, animated: true, completion: nil)
    }

}
