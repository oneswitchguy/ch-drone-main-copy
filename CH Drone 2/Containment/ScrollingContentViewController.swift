//
//  ScrollingContentViewController.swift
//  MVCTodo
//
//  Created by Dave DeLong on 10/18/18.
//  Copyright © 2018 Syzygy. All rights reserved.
//

#if canImport(UIKit)

import UIKit

open class ScrollingContentViewController: UIViewController {

    public enum ContentMode {
        case normal
        case fill
    }

    open var scrollView: UIScrollView! { return view as? UIScrollView }

    public let content: UIViewController
    public let mode: ContentMode

    public init(content: UIViewController, mode: ContentMode = .normal) {
        self.content = content
        self.mode = mode
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    open override func loadView() {
        view = UIScrollView()

        if #available(iOS 13.0, *) {
            view.backgroundColor = .systemBackground
        }
    }

    open override func viewDidLoad() {
        super.viewDidLoad()
        updateEmbeddedContent()
    }

    private func updateEmbeddedContent() {
        embedChild(content, in: scrollView)
        switch mode {
        case .normal:
            break
        case .fill:
            let fillHeightConstraint = content.view.heightAnchor.constraint(equalTo: view.safeAreaLayoutGuide.heightAnchor)
            fillHeightConstraint.priority = .defaultLow
            fillHeightConstraint.isActive = true
        }
        content.view.widthAnchor.constraint(equalTo: scrollView.widthAnchor).isActive = true
    }

}

#endif
