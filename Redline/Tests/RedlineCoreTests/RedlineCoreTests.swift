import Testing
@testable import RedlineCore

@Test func greeting() {
    #expect(Redline.greeting(for: "iPad") == "Hello, iPad!")
}
