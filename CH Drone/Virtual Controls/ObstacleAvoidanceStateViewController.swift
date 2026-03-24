//
//  ObstacleAvoidanceStateViewController.swift
//  CH Drone
//
//  Created by Alex Robinson on 6/2/2022.
//

import Combine
import Foundation
import UIKit

final class AccessoryTableViewCell: UITableViewCell {

    static let reuseIdentifier = "AccessoryTableViewCell"

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .default, reuseIdentifier: Self.reuseIdentifier)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

}

final class ObstacleAvoidanceStateViewController: UITableViewController {

    enum Row: Int, CaseIterable {
        case upwardObstacleAvoidance
        case horizontalObstacleAvoidance
        case landingAssistance

        var localizedDescription: String {
            switch self {
            case .upwardObstacleAvoidance: return NSLocalizedString("Upward Obstacle Avoidance", comment: "")
            case .horizontalObstacleAvoidance: return NSLocalizedString("Horizontal Obstacle Avoidance", comment: "")
            case .landingAssistance: return NSLocalizedString("Landing Assistance", comment: "")
            }
        }
    }

    let avoidanceState: ObstacleAvoidanceState

    init(avoidanceState: ObstacleAvoidanceState) {
        self.avoidanceState = avoidanceState

        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("Obstacle Avoidance", comment: "")

        tableView.register(AccessoryTableViewCell.self, forCellReuseIdentifier: AccessoryTableViewCell.reuseIdentifier)

        dataSource = UITableViewDiffableDataSource(tableView: tableView, cellProvider: { [weak self] tableView, indexPath, itemIdentifier in
            let cell = tableView.dequeueReusableCell(withIdentifier: "AccessoryTableViewCell", for: indexPath)
            cell.textLabel?.text = itemIdentifier.localizedDescription
            let settingSwitch = UISwitch(frame: .zero, primaryAction: UIAction { [weak self] action in
                guard let sender = action.sender as? UISwitch else { return }
                self?.updateRadarState(row: itemIdentifier, sender: sender)
            })
            self?.switches[itemIdentifier] = settingSwitch
            cell.accessoryView = settingSwitch
            return cell
        })

        var snapshot = NSDiffableDataSourceSnapshot<Int, Row>()
        snapshot.appendSections([0])
        snapshot.appendItems(Row.allCases, toSection: nil)
        dataSource.apply(snapshot)

        tableView.dataSource = dataSource
        tableView.allowsSelection = false

        avoidanceState.$horizontalObstacleAvoidanceEnabled
            .receiveOnMain()
            .sink { [weak self] setting in
                guard let settingSwitch = self?.switches[.horizontalObstacleAvoidance] else { return }
                settingSwitch.isOn = setting.value
                settingSwitch.isEnabled = !setting.isPending
            }
            .store(in: &cancellables)

        avoidanceState.$upwardObstacleAvoidanceEnabled
            .receiveOnMain()
            .sink { [weak self] setting in
                guard let settingSwitch = self?.switches[.upwardObstacleAvoidance] else { return }
                settingSwitch.isOn = setting.value
                settingSwitch.isEnabled = !setting.isPending
            }
            .store(in: &cancellables)

        avoidanceState.$landingAssistanceEnabled
            .receiveOnMain()
            .sink { [weak self] setting in
                guard let settingSwitch = self?.switches[.landingAssistance] else { return }
                settingSwitch.isOn = setting.value
                settingSwitch.isEnabled = !setting.isPending
            }
            .store(in: &cancellables)

    }

    // MARK: - Private

    private var cancellables: [AnyCancellable] = []
    private var switches: [Row: UISwitch] = [:]
    private var dataSource: UITableViewDiffableDataSource<Int, Row>!

    private func updateRadarState(row: Row, sender: UISwitch) {
        switch row {
        case .upwardObstacleAvoidance:
            avoidanceState.setUpwardObstacleAvoidanceEnabled(sender.isOn)
        case .horizontalObstacleAvoidance:
            avoidanceState.setHorizontalObstacleAvoidanceEnabled(sender.isOn)
        case .landingAssistance:
            avoidanceState.setLandingAssistanceEnabled(sender.isOn)
        }
    }

}
