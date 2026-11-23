import XCTest
@testable import ArgenticCore

final class CatalogTests: XCTestCase {
    func testFormula18HasDescriptiveNameInsteadOfGroupHeading() throws {
        let formula = try XCTUnwrap(Catalog.formulas.first { $0.id == 18 })
        XCTAssertEqual(formula.title, "Newton M-set variation (sin/exp/log)")
        XCTAssertTrue(FractalImage.isFormulaAvailable(formula.id))
    }

    func testFormulaNamesAreNonemptyAndNotGroupHeadings() {
        let headings = Set(Catalog.formulaGroups.map(\.title))
        for formula in Catalog.formulas {
            XCTAssertFalse(formula.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Formula \(formula.id)")
            XCTAssertFalse(headings.contains(formula.title), "Formula \(formula.id) has a group heading instead of a name")
        }
    }
}
