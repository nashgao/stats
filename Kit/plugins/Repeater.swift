//
//  Repeater.swift
//  Kit
//
//  Created by Serhiy Mytrovtsiy on 27/06/2022.
//  Using Swift 5.0.
//  Running on macOS 10.15.
//
//  Copyright © 2022 Serhiy Mytrovtsiy. All rights reserved.
//

import Foundation

private enum RepeaterState {
    case paused
    case running
}

internal class Repeater {
    private var callback: (() -> Void)
    private var state: RepeaterState = .paused
    private let label: String
    
    private var timer: DispatchSourceTimer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "eu.exelban.Stats.Repeater", qos: .default))
    
    internal init(seconds: Int, label: String = "", callback: @escaping (() -> Void)) {
        self.label = label
        self.callback = callback
        self.setupTimer(seconds)
    }
    
    deinit {
        self.timer.setEventHandler {}
        self.timer.cancel()
        if self.state == .paused {
            self.timer.resume()
            self.state = .running
        }
    }
    
    private func setupTimer(_ interval: Int) {
        if ProcessInfo.processInfo.environment["STATS_QA_SENSOR_TICK"] == "1" {
            NSLog("[QA] repeater(%@): setup %ds", self.label, interval)
        }
        self.timer.schedule(
            deadline: DispatchTime.now() + Double(interval),
            repeating: .seconds(interval),
            leeway: .milliseconds(200)
        )
        var fireCount = 0
        self.timer.setEventHandler { [weak self] in
            if ProcessInfo.processInfo.environment["STATS_QA_SENSOR_TICK"] == "1", fireCount < 5 {
                fireCount += 1
                NSLog("[QA] repeater(%@): fire %d", self?.label ?? "?", fireCount)
            }
            self?.callback()
        }
    }
    
    internal func start() {
        guard self.state == .paused else { return }
        if ProcessInfo.processInfo.environment["STATS_QA_SENSOR_TICK"] == "1" {
            NSLog("[QA] repeater: start")
        }
        self.timer.resume()
        self.state = .running
    }
    
    internal func pause() {
        guard self.state == .running else { return }
        if ProcessInfo.processInfo.environment["STATS_QA_SENSOR_TICK"] == "1" {
            NSLog("[QA] repeater: pause")
        }
        self.timer.suspend()
        self.state = .paused
    }
    
    internal func reset(seconds: Int, restart: Bool = false) {
        if self.state == .running {
            self.pause()
        }
        
        self.setupTimer(seconds)
        
        if restart {
            self.callback()
            self.start()
        }
    }
}
