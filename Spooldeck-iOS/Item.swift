//
//  Item.swift
//  Spooldeck-iOS
//
//  Created by Oliver Steiner on 23.10.2026.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
