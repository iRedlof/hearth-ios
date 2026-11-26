import Foundation

public enum CpOwnedAction: String, Codable, Sendable, CaseIterable {
    case join, accept, snooze, unsnooze, leave, stop, still, done, resume, legacy
}
public enum CpDesiredAutoAction: String, Codable, Sendable { case join, resume, pause }
public enum CpOperationCause: String, Codable, Sendable { case manual, explicitAuto, autoStep }
public enum CpOperationStage: String, Codable, Sendable { case claimed, preflighted, admitted, uncertain }
public enum CpFeedback: String, Codable, Sendable, Error {
    case detailsChanged, offerChanged, sessionChanged, noResponse, unavailable
    public var message: String {
        switch self {
        case .detailsChanged: "Details changed · Refresh to continue"
        case .offerChanged: "Offer changed · Refresh to check"
        case .sessionChanged: "Session changed · Refresh to check"
        case .noResponse: "No response · Refresh to check"
        case .unavailable: "Couldn't check · Refresh to retry"
        }
    }
    public var caption: String {
        switch self {
        case .detailsChanged: "Details\nchanged"
        case .offerChanged: "Offer\nchanged"
        case .sessionChanged: "Session\nchanged"
        case .noResponse: "No\nresponse"
        case .unavailable: "Check\nfailed"
        }
    }
}

/// Opaque bounded action attribution; no token, credential, device identifier, or provider body.
public struct CpRenderedOrigin: Codable, Sendable, Equatable {
    public let context: CpContextStamp
    public let queueRevision: String
    public let assignmentRevision: String
    public let actionRevision: String
    public let observationID: String?

    public func encoded() -> String? {
        guard let data = try? JSONEncoder().encode(self), data.count <= 4_096 else { return nil }
        return String(data: data, encoding: .utf8)
    }
    public static func decode(_ value: String) -> CpRenderedOrigin? {
        guard value.utf8.count <= 4_096, let data = value.data(using: .utf8),
              let origin = try? JSONDecoder().decode(Self.self, from: data),
              [origin.context.accountGeneration, origin.context.selectionRevision, origin.context.runID,
               origin.context.modeRevision, origin.context.settingsRevision, origin.queueRevision,
               origin.assignmentRevision, origin.actionRevision].allSatisfy({ UUID(uuidString: $0) != nil }),
              origin.observationID.map({ UUID(uuidString: $0) != nil }) ?? true else { return nil }
        return origin
    }
}

public struct CpOperationOwner: Codable, Sendable, Equatable {
    public let operationID: String
    public let claimRevision: String
    public let context: CpContextStamp
    public let cause: CpOperationCause
}

public struct CpOwnedOperation: Codable, Sendable, Equatable {
    public let owner: CpOperationOwner
    public let action: CpOwnedAction
    public let target: CpObservedIdentity
    public let startedAt: Date
    public let expiresAt: Date
    public var stage: CpOperationStage
    public var reconciliationAfter: Date?
    public var mutationAdmissionID: String?
    public var acknowledgementID: Int64?
}

public enum CpClaimResult: Sendable, Equatable {
    case claimed(CpOperationOwner), modeChanged(CpStoreSnapshot), rejected(CpFeedback)
}
public enum CpOperationOutcome: Sendable {
    case success, refused(String), cancelledBeforeAdmission, uncertain
}

public struct CpAutoResult: Sendable {
    public let snapshot: CpSnapshot
    public let activatedMode: CpContextStamp?
}

/// The reserved fixture envelope rejects before any production repository is opened.
public enum CpActionOriginEnvelope {
    private static let fixturePrefix = "cp-fixture-v1:"

    public static func encode(_ origin: CpRenderedOrigin, inFixture: Bool) -> String? {
        guard let encoded = origin.encoded() else { return nil }
        let value = inFixture ? fixturePrefix + encoded : encoded
        return value.utf8.count <= 4_096 ? value : nil
    }

    public static func decode(_ value: String, inFixture: Bool) -> CpRenderedOrigin? {
        guard value.utf8.count <= 4_096 else { return nil }
        let hasFixturePrefix = value.hasPrefix(fixturePrefix)
        guard hasFixturePrefix == inFixture else { return nil }
        let encoded = hasFixturePrefix ? String(value.dropFirst(fixturePrefix.count)) : value
        return CpRenderedOrigin.decode(encoded)
    }
}

public struct CpDiscoveryOwner: Codable, Sendable, Equatable {
    public let settings: CpSettingsOrigin
    public let queryID: String
    public let startedAt: Date
    public let expiresAt: Date
}

public enum CpRequestAuthority: Codable, Sendable, Equatable {
    case read(CpReadOwner), operation(CpOperationOwner), discovery(CpDiscoveryOwner), signIn(CpSignInOwner)
}

/// Purpose is checked independently of the eventual URLRequest; a read owner cannot send a mutation.
public enum CpRequestPurpose: Codable, Sendable, Equatable {
    case status, inline, allowance(String), charging(Int64), stations(CpBounds), profile, renew
    case mutation(CpOwnedAction), acknowledgement(Int64)
}

public struct CpRequestCredential: Sendable, Equatable {
    public let authority: CpRequestAuthority
    public let revision: String
    public let token: String
    public let userID: Int64
    public let location: CpLocation?
    public let udid: String
    public let target: CpObservedIdentity?
}

public struct CpDispatchAdmission: Codable, Sendable, Equatable {
    public let id: String
    public let authority: CpRequestAuthority
    public let credentialRevision: String
    public let purpose: CpRequestPurpose
    public let startedAt: Date
}

public struct CpResponseMetadata: Sendable {
    public let status: Int
    public let cookie: String?
    public init(status: Int, cookie: String? = nil) { self.status = status; self.cookie = cookie }
}

struct CpActionJournal: Codable {
    var credentialRevision = UUID().uuidString
    var queueRevision = UUID().uuidString
    var assignmentRevision = UUID().uuidString
    var actionRevision = UUID().uuidString
    var observation: CpObservation?
    var observationID: String?
    var actionable = false
    var operation: CpOwnedOperation?
    var feedback: CpFeedback?
    var discovery: CpDiscoveryOwner?
    var candidate: CpCandidateSession?
    var signInOrigin: CpSettingsOrigin?
    var lastAdmission: CpDispatchAdmission?
    var lastResponseStatus: Int?
    var autoFailureTarget: CpObservedIdentity?
}

struct CpCandidateSession: Codable {
    let owner: CpSignInOwner
    var token: String
    var userID: Int64
    var email: String
    var credentialRevision: String
    var profileVerified = false
    var expiresAt: Date
}
