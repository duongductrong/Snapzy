//
//  Item.swift
//  ZapShot
//
//  Created by duongductrong on 15/1/26.
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
