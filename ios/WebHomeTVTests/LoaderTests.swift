import XCTest
import JavaScriptCore
@testable import WebHomeTV

final class LoaderTests: XCTestCase {

    func testSyncModuleExecution() throws {
        let context = JSContext()
        let loader = ScriptLoader(context: context, assetProvider: { _ in nil })
        let exports = try loader.loadModule(
            source: "var out = { value: 6 * 7 }; module.exports = out;",
            moduleID: "sync-test"
        )
        let value = exports.objectForKeyedSubscript("value")?.toInt32() ?? 0
        XCTAssertEqual(value, 42, "exports.value=\(value)")
    }

    func testModuleCache() throws {
        let context = JSContext()
        let loader = ScriptLoader(context: context, assetProvider: { _ in nil })
        XCTAssertNoThrow(try loader.loadModule(source: "module.exports={a:1}", moduleID: "cache-test"))
        XCTAssertNoThrow(try loader.loadModule(source: "module.exports={a:2}", moduleID: "cache-test"))
    }

    func testDefaultExportResolves() throws {
        let context = JSContext()
        let loader = ScriptLoader(context: context, assetProvider: { _ in nil })
        let exports = try loader.loadModule(
            source: "exports.default = function(){ return 'spider-ok' };",
            moduleID: "default-test"
        )
        let def = exports.objectForKeyedSubscript("default")
        XCTAssertFalse(def.isUndefined, "default undefined")
        let result = def.call(withArguments: [])
        XCTAssertEqual(result.toString(), "spider-ok")
    }
}
