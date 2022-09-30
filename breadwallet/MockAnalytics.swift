// 
//  MockAnalytics.swift
//  breadwallet
//
//  Created by Kuba Suder on 30/09/2022.
//

import Foundation
import os.log

extension OSLog {
    static var bread = Bundle.main.bundleIdentifier!
}

private let breadLogger = OSLog(subsystem: OSLog.bread, category: "general")

protocol Trackable {
    func saveEvent(_ eventName: String)

    func saveEvent(_ eventName: String, attributes: [String: String])

    func saveEvent(context: EventContext, event: Event)

    func saveEvent(context: EventContext, screen: Screen, event: Event)

    func saveEvent(context: EventContext, screen: Screen, event: Event, attributes: [String: String])
}

extension Trackable {
    func saveEvent(_ eventName: String) {
        os_log("Analytics: %{public}@", log: breadLogger, type: .debug, eventName)
    }

    func saveEvent(_ eventName: String, attributes: [String: String]) {
        os_log("Analytics: %{public}@, %{public}%", log: breadLogger, type: .debug,
               eventName, attributes)
    }

    func saveEvent(context: EventContext, event: Event) {
        os_log("Analytics: context = %{public}@, event = %{public}%", log: breadLogger, type: .debug,
               context.name, event.name)
    }

    func saveEvent(context: EventContext, screen: Screen, event: Event) {
        os_log("Analytics: context = %{public}@, screen = %{public}@, event = %{public}%",
               log: breadLogger, type: .debug,
               context.name, screen.name, event.name)
    }

    func saveEvent(context: EventContext, screen: Screen, event: Event, attributes: [String: String]) {
        os_log("Analytics: context = %{public}@, screen = %{public}@, event = %{public}%, %{public}@",
               log: breadLogger, type: .debug,
               context.name, screen.name, event.name, attributes)
    }

    func makeEventName(_ components: [String]) -> String {
        // This will return event strings in the format expected by the server, such as
        // "onboarding.landingPage.appeared."
        return components.filter({ return !$0.isEmpty }).joined(separator: ".")
    }
}
