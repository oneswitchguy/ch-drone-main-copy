//
//  ColorViewController.swift
//  Autochords
//
//  Created by Alex Robinson on 4/4/19.
//  Copyright © 2019 Alex Robinson. All rights reserved.
//

#if canImport(UIKit)

import UIKit

open class ColorViewController: UIViewController {

    public let color: UIColor

    public init(color: UIColor) {
        self.color = color
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    open override func loadView() {
        view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = true
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.backgroundColor = color
    }
}

#endif
