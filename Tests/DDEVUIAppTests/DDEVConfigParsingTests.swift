import XCTest
@testable import DDEVUIApp

final class DDEVConfigParsingTests: XCTestCase {
    func testParsesOwnedConfigFieldsFromFullYAML() throws {
        let yaml = """
        name: aqua-pura
        type: wordpress
        docroot: web
        php_version: "8.4"
        nodejs_version: "24"
        webserver_type: nginx-fpm
        performance_mode: mutagen
        xdebug_enabled: false
        xhprof_mode: xhgui
        database:
          type: mariadb
          version: "11.8"
        upload_dirs:
          - web/app/uploads
          - web/sites/default/files
        additional_hostnames:
          - app
          - cms
        web_environment:
          - SECRET_TOKEN=do-not-expose
        """

        let config = try DDEVConfig.parseYAML(yaml)

        XCTAssertEqual(config.phpVersion, "8.4")
        XCTAssertEqual(config.nodeJSVersion, "24")
        XCTAssertEqual(config.databaseType, .mariadb)
        XCTAssertEqual(config.databaseVersion, "11.8")
        XCTAssertEqual(config.webserverType, .nginxFPM)
        XCTAssertEqual(config.performanceMode, .mutagen)
        XCTAssertFalse(config.xdebugEnabled)
        XCTAssertEqual(config.xhprofMode, .xhgui)
        XCTAssertEqual(config.uploadDirs, ["web/app/uploads", "web/sites/default/files"])
        XCTAssertEqual(config.additionalHostnames, ["app", "cms"])
    }

    func testParsesInlineListsAndDoesNotExposeWebEnvironment() throws {
        let yaml = """
        php_version: "8.3"
        nodejs_version: "22"
        database:
          type: mysql
          version: "8.4"
        webserver_type: apache-fpm
        performance_mode: global
        xdebug_enabled: true
        xhprof_mode: prepend
        upload_dirs: ["public/uploads", "assets"]
        additional_hostnames: [www, admin]
        web_environment:
          - API_KEY=secret
        """

        let config = try DDEVConfig.parseYAML(yaml)

        XCTAssertEqual(config.databaseType, .mysql)
        XCTAssertEqual(config.webserverType, .apacheFPM)
        XCTAssertEqual(config.performanceMode, .global)
        XCTAssertTrue(config.xdebugEnabled)
        XCTAssertEqual(config.xhprofMode, .prepend)
        XCTAssertEqual(config.uploadDirs, ["public/uploads", "assets"])
        XCTAssertEqual(config.additionalHostnames, ["www", "admin"])
        XCTAssertFalse(String(describing: config).contains("API_KEY"))
    }

    func testUsesDDEVDefaultsWhenFullYAMLOmitsDefaultFields() throws {
        let yaml = """
        additional_hostnames: []
        database:
            type: mariadb
            version: "11.8"
        nodejs_version: "24"
        php_version: "8.4"
        webserver_type: nginx-fpm
        """

        let config = try DDEVConfig.parseYAML(yaml)

        XCTAssertEqual(config.performanceMode, .global)
        XCTAssertFalse(config.xdebugEnabled)
        XCTAssertEqual(config.xhprofMode, .xhgui)
        XCTAssertEqual(config.uploadDirs, [])
        XCTAssertEqual(config.additionalHostnames, [])
    }

    func testYAMLCommentStrippingPreservesHashInsideQuotedStrings() throws {
        let yaml = """
        name: aqua-pura
        type: wordpress
        docroot: ""
        php_version: "8.3"
        nodejs_version: "22"
        database:
          type: mariadb
          version: "11.8"
        router_http_port: "80"  # real trailing comment
        router_https_port: "443"
        webserver_type: nginx-fpm
        performance_mode: none
        xdebug_enabled: false
        xhprof_mode: global
        upload_dirs: ["public/uploads#archive"]
        additional_hostnames: ["alpha", "beta # not-a-comment"]
        """

        let config = try DDEVConfig.parseYAML(yaml)

        XCTAssertEqual(config.uploadDirs, ["public/uploads#archive"])
        XCTAssertEqual(config.additionalHostnames, ["alpha", "beta # not-a-comment"])
    }

    func testConfigChangesMapToDDEVFlags() {
        XCTAssertEqual(DDEVConfigChange.phpVersion("8.3").ddevFlags, ["--php-version=8.3"])
        XCTAssertEqual(DDEVConfigChange.nodeJSVersion("22").ddevFlags, ["--nodejs-version=22"])
        XCTAssertEqual(DDEVConfigChange.database(type: .postgres, version: "17").ddevFlags, ["--database=postgres:17"])
        XCTAssertEqual(DDEVConfigChange.webserverType(.generic).ddevFlags, ["--webserver-type=generic"])
        XCTAssertEqual(DDEVConfigChange.performanceMode(.none).ddevFlags, ["--performance-mode=none"])
        XCTAssertEqual(DDEVConfigChange.xdebugEnabled(false).ddevFlags, ["--xdebug-enabled=false"])
        XCTAssertEqual(DDEVConfigChange.xhprofMode(.global).ddevFlags, ["--xhprof-mode=global"])
        XCTAssertEqual(DDEVConfigChange.uploadDirs(["public/uploads", "assets"]).ddevFlags, ["--upload-dirs=public/uploads,assets"])
        XCTAssertEqual(DDEVConfigChange.additionalHostnames(["www", "admin"]).ddevFlags, ["--additional-hostnames=www,admin"])
    }
}
