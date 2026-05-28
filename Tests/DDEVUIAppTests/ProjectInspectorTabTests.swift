import Testing
@testable import DDEVUIApp

@Suite("InspectorTab")
struct InspectorTabTests {
    @Test("has exactly three cases in display order")
    func casesInOrder() {
        #expect(InspectorTab.allCases == [.overview, .manage, .logs])
    }

    @Test("display names match the design spec")
    func displayNames() {
        #expect(InspectorTab.overview.displayName == "Overview")
        #expect(InspectorTab.manage.displayName == "Manage")
        #expect(InspectorTab.logs.displayName == "Logs")
    }

    @Test("system images are populated for each case")
    func systemImages() {
        for tab in InspectorTab.allCases {
            #expect(!tab.systemImage.isEmpty)
        }
    }
}
