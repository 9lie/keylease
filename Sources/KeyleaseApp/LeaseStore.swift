import Foundation
import Combine

struct LeaseSnapshot {
    let secret: String
    let expiresAt: Date
    let usesLeft: Int
}

final class LeaseStore: ObservableObject {
    static let shared = LeaseStore()

    static let defaultTTL: TimeInterval = 600
    static let defaultUses = 1
    static let defaultEnvName = "KEYLEASE_SECRET"

    struct Lease {
        var secret: String
        var createdAt: Date
        var expiresAt: Date
        var usesLeft: Int
    }

    private var lease: Lease?
    private let lock = NSLock()
    private var timer: Timer?

    @Published private(set) var isActive = false
    @Published private(set) var usesLeft = 0
    @Published private(set) var expiresAt: Date?

    var onChange: (() -> Void)?

    private init() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.expireIfNeeded()
        }
    }

    deinit {
        timer?.invalidate()
    }

    func activate(
        secret: String,
        ttl: TimeInterval = LeaseStore.defaultTTL
    ) {
        guard !secret.isEmpty else { return }
        let now = Date()

        lock.lock()
        lease = Lease(
            secret: secret,
            createdAt: now,
            expiresAt: now.addingTimeInterval(max(1, ttl)),
            usesLeft: LeaseStore.defaultUses
        )
        lock.unlock()

        publish()
    }

    func consume() -> LeaseSnapshot? {
        lock.lock()
        guard var current = lease else {
            lock.unlock()
            return nil
        }

        if Date() >= current.expiresAt || current.usesLeft <= 0 {
            lease = nil
            lock.unlock()
            publish()
            return nil
        }

        current.usesLeft -= 1
        let snapshot = LeaseSnapshot(
            secret: current.secret,
            expiresAt: current.expiresAt,
            usesLeft: current.usesLeft
        )

        lease = current.usesLeft > 0 ? current : nil
        lock.unlock()
        publish()
        return snapshot
    }

    func refund(_ snapshot: LeaseSnapshot) {
        lock.lock()
        if var current = lease, current.usesLeft > 0 {
            current.usesLeft += 1
            lease = current
            lock.unlock()
            publish()
            return
        }

        if lease == nil {
            lease = Lease(
                secret: snapshot.secret,
                createdAt: Date(),
                expiresAt: snapshot.expiresAt,
                usesLeft: snapshot.usesLeft + 1
            )
        }
        lock.unlock()
        publish()
    }

    func revoke() {
        lock.lock()
        lease = nil
        lock.unlock()
        publish()
    }

    func hasActiveLease() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let current = lease else { return false }
        return Date() < current.expiresAt && current.usesLeft > 0
    }

    func expireIfNeeded() {
        lock.lock()
        if let current = lease, Date() >= current.expiresAt {
            lease = nil
            lock.unlock()
            publish()
            return
        }
        lock.unlock()
    }

    private func publish() {
        let snapshot: (Bool, Int, Date?) = {
            lock.lock()
            defer { lock.unlock() }
            if let current = lease {
                return (true, current.usesLeft, current.expiresAt)
            }
            return (false, 0, nil)
        }()

        DispatchQueue.main.async {
            self.isActive = snapshot.0
            self.usesLeft = snapshot.1
            self.expiresAt = snapshot.2
            self.onChange?()
        }
    }
}
