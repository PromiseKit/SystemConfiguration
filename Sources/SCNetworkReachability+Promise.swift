import SystemConfiguration
#if !PMKCocoaPods
import PromiseKit
#endif

public extension SCNetworkReachability {

    enum PMKError: Error {
        case couldNotInitializeReachability
    }

    /// - Note: cancelling this promise will cancel the underlying task
    /// - SeeAlso: [Cancellation](http://promisekit.org/docs/)
    static func promise() -> Promise<Void> {
        do {
            if let promise = try pending()?.promise {
                return promise
            } else {
                return Promise()
            }
        } catch {
            return Promise(error: error)
        }
    }
    
    fileprivate static func pending() throws -> (promise: Promise<Void>, resolver: Resolver<Void>)? {
        var zeroAddress = sockaddr()
        zeroAddress.sa_len = UInt8(MemoryLayout<sockaddr>.size)
        zeroAddress.sa_family = sa_family_t(AF_INET)
        guard let ref = SCNetworkReachabilityCreateWithAddress(nil, &zeroAddress) else {
            throw PMKError.couldNotInitializeReachability
        }

        var flags = SCNetworkReachabilityFlags()
        if SCNetworkReachabilityGetFlags(ref, &flags), flags.contains(.reachable) {
            return nil
        }

        return try Helper(ref: ref).pending
    }
}

private func callback(reachability: SCNetworkReachability, flags: SCNetworkReachabilityFlags, info: UnsafeMutableRawPointer?) {
    if let info = info, flags.contains(.reachable) {
        Unmanaged<Helper>.fromOpaque(info).takeUnretainedValue().pending.resolver.fulfill(())
    }
}

private class Helper {
    let pending = Promise<Void>.pending()
    let ref: SCNetworkReachability

    init(ref: SCNetworkReachability) throws {
        self.ref = ref
        
        // Set 'reject' for cancellation so that the promise will be rejected if cancelled.  The 'ensure' block
        // below will automatically clean up the callback and dispatch queue when the promise is rejected.
        pending.promise.setCancellableTask(nil, reject: pending.resolver.reject)

        var context = SCNetworkReachabilityContext(version: 0, info: nil, retain: nil, release: nil, copyDescription: nil)
        context.info = UnsafeMutableRawPointer(Unmanaged<Helper>.passUnretained(self).toOpaque())

        guard SCNetworkReachabilitySetCallback(ref, callback, &context) else {
            throw SCNetworkReachability.PMKError.couldNotInitializeReachability
        }
        guard SCNetworkReachabilitySetDispatchQueue(ref, .main) else {
            SCNetworkReachabilitySetCallback(ref, nil, nil)
            throw SCNetworkReachability.PMKError.couldNotInitializeReachability
        }

        _ = pending.promise.ensure {
            SCNetworkReachabilitySetCallback(self.ref, nil, nil)
            SCNetworkReachabilitySetDispatchQueue(self.ref, nil)
        }
    }
}
