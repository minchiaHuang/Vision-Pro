#if !os(visionOS)
import Foundation
import Observation
import GameController

/// Tracks DualSense / extended gamepad connection so the USDZ world view can be
/// driven by a physical controller. Mirrors the lifecycle shape of `MotionManager`.
///
/// DualSense pairs over Bluetooth (iPadOS 16.4+) and exposes the standard
/// `GCExtendedGamepad` profile — no entitlement required. Per-frame input is read
/// by polling `gamepad` from the render loop; this object only tracks presence.
///
/// Note: the iOS Simulator cannot pair a Bluetooth controller — test on device
/// (or connect the controller to the Mac so the simulator forwards it).
@MainActor
@Observable
final class GamepadManager {

    /// Whether an extended gamepad is currently connected.
    private(set) var isConnected = false

    /// The active controller's extended gamepad profile, for per-frame polling.
    var gamepad: GCExtendedGamepad? { GCController.current?.extendedGamepad }

    private var connectObserver: NSObjectProtocol?
    private var disconnectObserver: NSObjectProtocol?

    init() {
        refreshConnected()
        connectObserver = NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshConnected() }
        }
        disconnectObserver = NotificationCenter.default.addObserver(
            forName: .GCControllerDidDisconnect, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshConnected() }
        }
    }

    private func refreshConnected() {
        isConnected = GCController.controllers().contains { $0.extendedGamepad != nil }
    }
}
#endif
