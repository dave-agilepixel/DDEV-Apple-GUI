import XCTest
@testable import DDEVUIApp

final class DDEVCustomCommandTests: XCTestCase {
    func testParseDescriptionFindsAnnotation() {
        let contents = """
        #!/usr/bin/env bash
        ## #ddev-generated: remove this line to own the file
        ## Description: Launch a browser with Mailpit
        ## Usage: mailpit
        echo hi
        """
        XCTAssertEqual(DDEVCustomCommand.parseDescription(from: contents), "Launch a browser with Mailpit")
    }

    func testParseDescriptionReturnsNilWhenAbsent() {
        XCTAssertNil(DDEVCustomCommand.parseDescription(from: "#!/bin/bash\necho hi\n"))
    }

    func testIsCommandFileSkipsDocsExamplesAndHiddenFiles() {
        XCTAssertTrue(DDEVCustomCommand.isCommandFile("phpmyadmin"))
        XCTAssertTrue(DDEVCustomCommand.isCommandFile("self-upgrade"))
        XCTAssertFalse(DDEVCustomCommand.isCommandFile("README.txt"))
        XCTAssertFalse(DDEVCustomCommand.isCommandFile("mysqlworkbench.example"))
        XCTAssertFalse(DDEVCustomCommand.isCommandFile(".gitattributes"))
        XCTAssertFalse(DDEVCustomCommand.isCommandFile(""))
    }

    func testDiscoveryScansScopesSkipsNonCommandsAndLetsProjectOverrideGlobal() async {
        let listDirectory: @Sendable (String) -> [String] = { path in
            if path == "/global/host" { return ["phpmyadmin", "README.txt"] }
            if path == "/site/.ddev/commands/host" { return ["phpmyadmin", "deploy", "foo.example"] }
            if path == "/site/.ddev/commands/web" { return ["artisan"] }
            return []
        }
        let readFile: @Sendable (String) -> String? = { path in
            switch path {
            case "/site/.ddev/commands/host/phpmyadmin": return "## Description: Project PMA\n"
            case "/site/.ddev/commands/host/deploy": return "## Description: Deploy it\n"
            case "/global/host/phpmyadmin": return "## Description: Global PMA\n"
            default: return ""
            }
        }
        let discovery = FileSystemCustomCommandDiscovery(
            globalCommandsRoot: "/global",
            listDirectory: listDirectory,
            readFile: readFile
        )

        let commands = await discovery.discoverCustomCommands(appRoot: "/site")

        XCTAssertEqual(commands.map(\.name), ["artisan", "deploy", "phpmyadmin"])
        // Project's phpmyadmin overrides the global one of the same name.
        XCTAssertEqual(commands.first { $0.name == "phpmyadmin" }?.description, "Project PMA")
        XCTAssertEqual(commands.first { $0.name == "artisan" }?.scope, .web)
    }
}
