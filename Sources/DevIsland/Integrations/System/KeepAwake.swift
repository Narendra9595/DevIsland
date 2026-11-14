import IOKit.pwr_mgt
import Observation

/// Keeps the Mac and display awake while on (like `caffeinate -d`).
@MainActor
@Observable
final class KeepAwake {
    private(set) var isOn = false
    @ObservationIgnored private var assertion = IOPMAssertionID(0)

    func toggle() {
        if isOn {
            IOPMAssertionRelease(assertion)
            isOn = false
        } else {
            isOn = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                               IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                               "DevIsland Keep Awake" as CFString, &assertion) == kIOReturnSuccess
        }
    }
}
