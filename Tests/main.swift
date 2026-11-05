import Foundation

var checks: [String] = []
func expect(_ name: String, _ assertion: @autoclosure () -> Bool) {
    guard assertion() else { fputs("FAILED: \(name)\n", stderr); exit(1) }
    checks.append(name)
}
func value(_ s: String) -> Decimal { Decimal(string: s, locale: Locale(identifier: "en_US_POSIX"))! }
func result(_ x: CalculatorInputs) -> Calculation { try! Calculation.evaluate(x) }
let base = result(.baseline)
expect("baseline monthly result", base.monthlyResult == 7000)
expect("baseline contribution", base.contribution == 270)
expect("baseline break-even ceiling", base.breakEvenUnits == 75)
expect("baseline margin", base.contributionMargin == 27)
expect("cost increase", result(.higherCost).monthlyResult == -7000)
expect("cost increase break-even", result(.higherCost).breakEvenUnits == 154)
expect("price adjustment", result(.higherPrice).monthlyResult == 12400)
expect("price adjustment break-even", result(.higherPrice).breakEvenUnits == 62)
var inputs = CalculatorInputs.baseline
inputs.quantity = "0"
expect("no sales still incurs fixed expense", result(inputs).monthlyResult == -20000)
expect("no sales no commission", result(inputs).commission == 0)
inputs = .baseline; inputs.price = "700"; inputs.fee = "0"
expect("zero contribution has no finite break-even", result(inputs).breakEvenUnits == nil)
inputs.price = "500"
expect("negative contribution has no break-even", result(inputs).breakEvenUnits == nil)
inputs = CalculatorInputs(price: "0", cost: "0", quantity: "0", fixed: "0", fee: "0")
expect("all zero result", result(inputs).monthlyResult == 0)
expect("zero-price margin undefined", result(inputs).contributionMargin == nil)
expect("zero-cost zero-contribution zero-fixed break-even", result(inputs).breakEvenUnits == 0)
inputs = CalculatorInputs(price: "1000,50", cost: "700,25", quantity: "100", fixed: "20000", fee: "3")
expect("comma decimals exact", result(inputs).monthlyResult == value("7023.5"))
inputs = CalculatorInputs(price: "0.01", cost: "0", quantity: "1", fixed: "0", fee: "0.01")
expect("subcent amounts not rounded early", result(inputs).monthlyResult == value("0.009999"))
for (field, bad) in [(InputField.price,""),(.cost,"-1"),(.quantity,"1.5"),(.fee,"100.01"),(.price,"Infinity"),(.fixed,"1,234"),(.quantity,"1000001"),(.price,"10000001")] {
    do { _ = try Calculation.parse(bad, field: field); expect("reject \(field.rawValue)=\(bad)",false) }
    catch let issue as InputIssue { expect("reject \(field.rawValue)=\(bad)",issue.field == field) }
    catch { expect("typed validation error",false) }
}
for (name, scenario) in [("baseline",CalculatorInputs.baseline),("cost",.higherCost),("price",.higherPrice)] {
    let r = result(scenario)
    expect("\(name) reconciliation", r.revenue-r.variableCosts-r.commission-r.fixed == r.monthlyResult)
    let count = r.breakEvenUnits!
    expect("\(name) covers costs at ceiling", r.contribution*count-r.fixed >= 0)
    expect("\(name) does not cover at one less", r.contribution*(count-1)-r.fixed < 0)
}
let saved = SavedCalculation.encode(.higherPrice)!
expect("saved inputs restore", SavedCalculation.decode(saved) == .higherPrice)
expect("invalid JSON rejected", SavedCalculation.decode(Data("not JSON".utf8)) == nil)
let wrongSchema = Data("{\"schemaVersion\":99,\"inputs\":{\"price\":\"1000\",\"cost\":\"700\",\"quantity\":\"100\",\"fixed\":\"20000\",\"fee\":\"3\"}}".utf8)
expect("unknown schema rejected",SavedCalculation.decode(wrongSchema) == nil)
inputs = .baseline; inputs.price = ""
expect("invalid input never persisted",SavedCalculation.encode(inputs) == nil)
#if arch(arm64)
let testArchitecture = "arm64"
#else
let testArchitecture = "x86_64"
#endif
let report: [String: Any] = ["checksPassed":checks.count,"checks":checks,"architecture": testArchitecture, "scope":"calculation engine, validation, save format; not GUI acceptance"]
let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted,.sortedKeys])
FileHandle.standardOutput.write(data)
print("")
