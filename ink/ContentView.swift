//
//  ContentView.swift
//  ink
//
//  Created by Dylan Karunanayake on 2/11/2026.
//

import SwiftUI

struct ContentView: View {
    private var collectedDocuments: [String] = [] // TODO: this isnt supposed to be a string
    
    private var userName: String = "lebron"
    
    var body: some View {
        Home()
    }
    
    @ViewBuilder
    private func Home() -> some View {
//        VStack() {
//            HStack() {
//                Text("Welcome back \(userName.capitalized)")
//                    .font(.system(size: 24))
//            }
//        }
//        .frame(maxWidth: .infinity, maxHeight: .infinity)
        DrawingView()
    }
    
}

// BUG i think when pen only is false it still acts as true, fix this soon pls

#Preview {
    ContentView()
}
