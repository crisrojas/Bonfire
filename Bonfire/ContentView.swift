//
//  ContentView.swift
//  Bonfire
//
//  Created by Cristian Felipe Patiño Rojas on 02/12/2023.
//

import SwiftUI


let api = API()
struct ContentView: View {
    @ObservedObject var profile = api.employes
    var body: some View {
        VStack {
            Text(profile.data.description)
            Button("refresh") {
                profile.load()
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
