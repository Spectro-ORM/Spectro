import Foundation
import Testing
@testable import Spectro

@Suite("Spectro errors")
struct SpectroErrorTests {
    @Test("Error descriptions terminate and preserve their cause")
    func descriptions() {
        let error = SpectroError.invalidQuery("invalid filter")
        #expect(String(describing: error).contains("invalid filter"))
        #expect(String(reflecting: error).contains("invalid filter"))
        let wrapped = SpectroError.transactionFailed(underlying: error)
        #expect(String(describing: wrapped).contains("invalid filter"))
        #expect(wrapped.localizedDescription.contains("invalid filter"))
    }
}
