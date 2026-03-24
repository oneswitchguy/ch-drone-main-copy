//
//  ContainerViewController.swift
//  MVCTodo
//
//  Created by Dave DeLong on 10/18/18.
//  Copyright © 2018 Syzygy. All rights reserved.
//

#if canImport(UIKit)

import UIKit

private class BlankViewController: UIViewController {
    init() {
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.alpha = 0
    }
}

open class ContainerViewController: UIViewController {

    open var content: UIViewController {
        didSet {
            replaceChild(oldValue, with: content)

            setNeedsStatusBarAppearanceUpdate()
            setNeedsUpdateOfHomeIndicatorAutoHidden()
            setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
            if #available(iOS 14.0, *) {
                setNeedsUpdateOfPrefersPointerLocked()
            }
        }
    }

    public init(content: UIViewController?) {
        self.content = content ?? BlankViewController()
        super.init(nibName: nil, bundle: nil)
    }

    public convenience init() {
        self.init(content: nil)
    }

    public required init?(coder: NSCoder) {
        self.content = BlankViewController()
        super.init(coder: coder)
    }

    open override func loadView() {
        view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = true
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        if #available(iOS 13.0, *) {
            view.backgroundColor = .systemBackground
        } else {
            view.backgroundColor = .white
        }
    }

    open override var childForStatusBarStyle: UIViewController? { content }
    open override var childForStatusBarHidden: UIViewController? { content }
    open override var childForHomeIndicatorAutoHidden: UIViewController? { content }
    open override var childForScreenEdgesDeferringSystemGestures: UIViewController? { content }
    open override var childViewControllerForPointerLock: UIViewController? { content }

    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // special case for setting the initial content. works around some "unbalanced calls" to appear/disappear methods in the child.
        if !hasSetInitialContent {
            hasSetInitialContent = true
            embedChild(content)
        }
    }

    public func removeContent() {
        content = BlankViewController()
    }

    // MARK: - Private

    // flag to set the initial content only the first time the view appears.
    private var hasSetInitialContent = false

    private func replaceChild(_ oldChild: UIViewController, with newChild: UIViewController) {
        guard hasSetInitialContent else { return }

        oldChild.unembed()
        embedChild(newChild)

        UIAccessibility.post(notification: .layoutChanged, argument: nil)
    }

}

#endif
