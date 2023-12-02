//
//  ContentView.swift
//  Bonfire
//
//  Created by Cristian Felipe Patiño Rojas on 02/12/2023.
//

import SwiftUI


let api = API()

struct ContentView: View {
    @ObservedObject var employees = api.employees
    @State var isLoading = true
    @State var errorMessage: String?
    
    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    ProgressView().onAppear(perform: load)
                } else {
                   loadedView()
                }
            }
            .animation(.default, value: isLoading)
            .toolbar {
                SymbolButton("arrow.counterclockwise", action: load)
            }
        }
    }
    
    @ViewBuilder
    func loadedView() -> some View {
        if let errorMessage {
            errorMessage
        } else {
            successView()
        }
    }
    
    @ViewBuilder
    func successView() -> some View {
        if employees.list.isEmpty {
            "No data found"
        } else {
            List(employees.list, id: \.id) { item in
                item.name
            }
        }
    }
    
    func load() {
        isLoading = true
        employees.load().onCompletion {
            isLoading = false
        }
    }
}
 
struct SymbolButton: View {
    let systemName: String
    let action: () -> Void
    init(_ systemName: String, action: @escaping () -> Void) {
        self.systemName = systemName
        self.action = action
    }
    
    var body: some View {
        Button(action: action, label: symbol)
    }
    
    func symbol() -> some View {
        Image(systemName: systemName)
    }
}

extension String: View {
    public var body: some View {
        Text(self)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
