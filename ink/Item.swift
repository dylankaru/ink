//
//  Item.swift
//  ink
//
//  Created by Dylan Karunanayake on 2/11/2026.
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
