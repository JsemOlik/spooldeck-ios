//
//  Spooldeck_iOSApp.swift
//  Spooldeck-iOS
//
//  Created by Oliver Steiner on 23.10.2026.
//

import SwiftUI

@main
struct Spooldeck_iOSApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
        }
    }
}
