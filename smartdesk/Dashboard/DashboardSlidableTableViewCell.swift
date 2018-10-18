//
//  DashboardSlidableTableViewCell.swift
//  smartdesk
//
//  Created by Jing Wei Li on 10/12/18.
//  Copyright © 2018 Jing Wei Li. All rights reserved.
//

import UIKit

class DashboardSlidableTableViewCell: UITableViewCell {
    @IBOutlet weak var collectionView: UICollectionView!
    static let identifier = "DashboardSlidable"
    let hapticFeedback = UIImpactFeedbackGenerator(style: .medium)
    
    var sectionIndex: Int = 0
    
    var controllableObject: BLEControllable? {
        didSet {
            collectionView.reloadData()
        }
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.alwaysBounceHorizontal = true
        collectionView.alwaysBounceVertical = false
        
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.sectionInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 2)
        layout.itemSize = CGSize(width: 152, height: 76)
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 0
        collectionView.collectionViewLayout = layout
    }
    
    func performOperations(onCellWith indexPath: IndexPath, command: IncomingCommand) {
        if let cell = collectionView.cellForItem(at: indexPath) as? BLEControlCollectionViewCell {
            cell.adjustUI(with: command)
        }
    }
    
}

extension DashboardSlidableTableViewCell: UICollectionViewDelegate, UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return controllableObject?.controls.count ?? 0
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let identifier = BLEControlCollectionViewCell.identifier
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: identifier, for: indexPath)
        if let cell = cell as? BLEControlCollectionViewCell, let obj = controllableObject {
            let controlEntity = obj.controls[indexPath.row]
            cell.controllableObject = controlEntity
            for cmd in controlEntity.incomingCommands {
                CommandToIndex.currentTable[cmd] = CommandToIndex(cmd: cmd,
                                                                  tableViewIndex: sectionIndex,
                                                                  collecIndexPath: indexPath)
            }
        }
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        hapticFeedback.impactOccurred()
        if let cmd = controllableObject?.controls[indexPath.row].outgoingCommand {
            BLEManager.current.send(string: cmd)
        }
    }
    
}
