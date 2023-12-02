//
//  BonfireApp.swift
//  Bonfire
//
//  Created by Cristian Felipe Patiño Rojas on 02/12/2023.
//

import SwiftUI

@main
struct BonfireApp: App {
    @ObservedObject var resource = api.employeesCodable
    var body: some Scene {
        WindowGroup {
            resource
                .employes
                .onAppear(perform: {resource.load()})
                .insideNavView()
        }
    }
}
