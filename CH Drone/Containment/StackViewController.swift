//
//  StackViewController.swift
//  Autochords
//
//  Created by Alex Robinson on 19/3/19.
//  Copyright © 2019 Alex Robinson. All rights reserved.
//

#if canImport(UIKit)

import UIKit

open class StackViewController: UIViewController {

    private var stackView = UIStackView(arrangedSubviews: [])

    open var axis: NSLayoutConstraint.Axis {
        get { return stackView.axis }
        set { stackView.axis = newValue }
    }

    open var margins: NSDirectionalEdgeInsets {
        didSet {
            view.embedSubview(stackView, margins: margins)
        }
    }

    open var distribution: UIStackView.Distribution {
        get { return stackView.distribution }
        set { stackView.distribution = newValue }
    }

    open var alignment: UIStackView.Alignment {
        get { return stackView.alignment }
        set { stackView.alignment = newValue }
    }

    open var spacing: CGFloat {
        get { return stackView.spacing }
        set { stackView.spacing = newValue }
    }

    public init(axis: NSLayoutConstraint.Axis, spacing: CGFloat = 0, distribution: UIStackView.Distribution = .fill, margins: NSDirectionalEdgeInsets = .zero) {
        self.margins = margins
        super.init(nibName: nil, bundle: nil)
        stackView.axis = axis
        stackView.spacing = spacing
        stackView.distribution = distribution
    }

    @available(*, unavailable)
    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    open override func loadView() {
        view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = true
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }

    open override func viewDidLoad() {
        super.viewDidLoad()
        view.embedSubview(stackView, margins: margins)
    }

    open func addArrangedChild(_ newChild: UIViewController) {
        newChild.view.translatesAutoresizingMaskIntoConstraints = false
        newChild.beginAppearanceTransition(true, animated: false)
        addChild(newChild)
        newChild.didMove(toParent: self)
        stackView.addArrangedSubview(newChild.view)
        newChild.endAppearanceTransition()
    }
}

#endif
