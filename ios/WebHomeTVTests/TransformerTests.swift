import XCTest
@testable import WebHomeTV

final class TransformerTests: XCTestCase {

    func testImportFrom() {
        let input = #"import * as spider from './spider.js';"#
        let out = ESModuleTransformer.transform(input)
        XCTAssertTrue(out.contains(#"require(\"./spider.js\")"#), "out=\(out)")
        XCTAssertFalse(out.contains("import"), "out=\(out)")
    }

    func testNamedExport() {
        let input = #"var a=1; var b=2; export { a, b as c };"#
        let out = ESModuleTransformer.transform(input)
        XCTAssertTrue(out.contains("exports.a = a"), "out=\(out)")
        XCTAssertTrue(out.contains("exports.c = b"), "out=\(out)")
        XCTAssertFalse(out.contains("export"), "out=\(out)")
    }

    func testDefaultExport() {
        let input = "export default { hello: 1 };"
        let out = ESModuleTransformer.transform(input)
        XCTAssertTrue(out.contains("exports.default"), "out=\(out)")
        XCTAssertFalse(out.contains("export default"), "out=\(out)")
    }

    func testDeclarationExport() {
        let input = #"export const FOO = 42; export function bar(){ return 1 }"#
        let out = ESModuleTransformer.transform(input)
        XCTAssertTrue(out.contains("const FOO = 42"), "out=\(out)")
        XCTAssertTrue(out.contains("exports.FOO = FOO"), "out=\(out)")
        XCTAssertFalse(out.contains("export"), "out=\(out)")
    }

    func testCatJSLike() {
        // cat.js ends with `export{Ch as Crypto,...}` — ensure single export{} handled
        let input = "var a=5;var b=9;export{a as Crypto,b as Uri};"
        let out = ESModuleTransformer.transform(input)
        XCTAssertTrue(out.contains("exports.Crypto = a"), "out=\(out)")
        XCTAssertTrue(out.contains("exports.Uri = b"), "out=\(out)")
    }
}
