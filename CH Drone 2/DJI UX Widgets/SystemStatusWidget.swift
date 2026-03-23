//
//  SystemStatusWidget.swift
//  CH Drone
//
//  Created by Alex Robinson on 24/1/2022.
//

import Foundation
import DJIUXSDKBeta

@objc public class SystemStatusWidget: DUXBetaListPanelWidget {

    required public init?(coder: NSCoder) {
        super.init(coder: coder)
        let _ = self.setupSmartModel(DUXBetaSystemStatusListSmartModel())
    }

    override public init() {
        super.init()
        let _ = self.setupSmartModel(DUXBetaSystemStatusListSmartModel())
    }

    override public init(smartModel: DUXBetaSmartListModel) {
        super.init(smartModel: smartModel)
    }

    public override func defaultConfigurationSetup() {
        // Must configure this here before parent viewDidLoad since we are internally configuring
        // And must have the list type set properly
        let config = DUXBetaPanelWidgetConfiguration(type: .list, listKind: .widgets)
            .configureTitlebar(visible: true, withCloseBox: true, title: NSLocalizedString("System Status", comment: "System Status"))
            .configureColors(background: .uxsdk_blackAlpha90(), border: .uxsdk_clear(), titleBarBackground: .uxsdk_blackAlpha90())
            .configureTitlebar(visible: false)
        let _ = configure(config)
    }

}
