import Foundation
import LoopKit
import Testing
import UserNotifications

@testable import Trio

@Suite("Trio Alerts: dismissing an alert snoozes it") struct AlertDismissalSnoozeTests {
    /// The bug this covers: tapping a High notification acknowledged it
    /// outright, and the alarm then stayed silent for the rest of the
    /// excursion. Every way of clearing an alert has to buy a snooze.
    @Test("Tapping a notification snoozes for 15 minutes") func tapSnoozes() {
        #expect(
            BaseTrioAlertManager.snoozeDuration(forActionIdentifier: UNNotificationDefaultActionIdentifier)
                == 15 * 60
        )
    }

    @Test("Swiping a notification away snoozes for 15 minutes") func swipeSnoozes() {
        #expect(
            BaseTrioAlertManager.snoozeDuration(forActionIdentifier: UNNotificationDismissActionIdentifier)
                == 15 * 60
        )
    }

    /// These buttons used to fall through to a plain acknowledgement, so
    /// picking "Snooze 3 hrs" did the same thing as picking OK.
    @Test("A chosen snooze action keeps its own duration") func chosenDurationWins() {
        #expect(BaseTrioAlertManager.snoozeDuration(forActionIdentifier: "Trio.snooze15") == 15 * 60)
        #expect(BaseTrioAlertManager.snoozeDuration(forActionIdentifier: "Trio.snooze1hr") == 60 * 60)
        #expect(BaseTrioAlertManager.snoozeDuration(forActionIdentifier: "Trio.snooze3hr") == 3 * 60 * 60)
        #expect(BaseTrioAlertManager.snoozeDuration(forActionIdentifier: "Trio.snooze6hr") == 6 * 60 * 60)
    }

    @Test("Every snooze action maps to its own duration") func everyActionMaps() {
        for action in NotificationResponseAction.allCases {
            #expect(BaseTrioAlertManager.snoozeDuration(forActionIdentifier: action.rawValue) == action.duration)
        }
    }

    /// An action Trio doesn't know still has to leave the alarm able to
    /// return, so it takes the quick snooze rather than silencing anything.
    @Test("An unknown action falls back to the quick snooze") func unknownActionFallsBack() {
        #expect(BaseTrioAlertManager.snoozeDuration(forActionIdentifier: "something.else") == 15 * 60)
    }

    @Test("The quick snooze is the 15-minute action, not a second constant") func oneSourceOfTruth() {
        #expect(BaseTrioAlertManager.quickSnooze == NotificationResponseAction.snooze15.duration)
    }

    @Test("Glucose alarms still snooze only their own type") func glucoseAlarmScope() {
        for type in GlucoseAlertType.allCases {
            let identifier = Alert.Identifier(
                managerIdentifier: "Trio.glucose",
                alertIdentifier: "glucose.\(type.rawValue).\(UUID().uuidString)"
            )
            #expect(BaseTrioAlertManager.dismissalSnoozeScope(for: identifier) == .glucoseType(type))
        }
    }

    // MARK: - Dismissal never reaches the global snooze

    private static func scope(_ manager: String, _ alert: String) -> DismissalSnoozeScope {
        BaseTrioAlertManager.dismissalSnoozeScope(for: Alert.Identifier(managerIdentifier: manager, alertIdentifier: alert))
    }

    /// Regression: this used to fall through to the global snooze.
    @Test("A pump communication error snoozes only its own tier") func commsErrorSnoozesItsTier() {
        #expect(Self.scope("trio.aps", "commsTransient") == .deviceTier(.normal))
    }

    @Test("Catalogued non-critical alerts snooze their tier") func nonCriticalSnoozesTier() {
        #expect(Self.scope("trio.aps", "bolusFailed") == .deviceTier(.timeSensitive))
        #expect(Self.scope("trio.aps", "reservoirLow") == .deviceTier(.timeSensitive))
        #expect(Self.scope("trio.aps", "algorithmError") == .deviceTier(.normal))
    }

    @Test(
        "Critical alerts are only acknowledged",
        arguments: [
            ("trio.aps", "occlusion"),
            ("trio.aps", "deliveryUncertain"),
            ("trio.aps", "loop.notActive"),
            ("Dana", "occlusion"),
            ("Medtrum", "com.nightscout.medtrumkit.patch-fault")
        ]
    ) func criticalAcknowledgesOnly(manager: String, alert: String) {
        #expect(Self.scope(manager, alert) == .acknowledgeOnly)
    }

    @Test("Not-looping warning steps are only acknowledged") func escalationStepAcknowledgesOnly() {
        for step in 1 ... 5 {
            #expect(Self.scope("trio.aps", "loop.notActive.w\(step)") == .acknowledgeOnly)
        }
    }

    @Test(
        "Uncatalogued alerts are only acknowledged",
        arguments: [
            ("trio.calibration", "glucose.stale"),
            ("trio.garmin", "connect.mobile.missing"),
            ("Trio.unknown", "unknown")
        ]
    ) func uncataloguedAcknowledgesOnly(manager: String, alert: String) {
        #expect(Self.scope(manager, alert) == .acknowledgeOnly)
    }

    @Test(
        "Every pump category APSManager issues is catalogued at its own level",
        arguments: [
            TrioAlertCategory.occlusion, .reservoirLow, .reservoirEmpty, .batteryLow, .batteryEmpty,
            .hardwareFault, .deliveryUncertain, .deviceExpirationReminder, .deviceExpired,
            .podShutdownImminent, .suspendTimeExpired, .bolusFailed, .manualTempBasalActive,
            .notLooping, .sensorFailure, .glucoseDataStale, .algorithmError, .commsTransient
        ]
    ) func everyAPSCategoryCatalogued(category: TrioAlertCategory) {
        let entry = AlertCatalogRegistry.lookup(
            Alert.Identifier(managerIdentifier: "trio.aps", alertIdentifier: category.alertIdentifier)
        )
        #expect(entry?.interruptionLevel == category.interruptionLevel)
    }
}
