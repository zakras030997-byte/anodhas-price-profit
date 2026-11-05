import Foundation

struct CalculatorInputs: Codable, Equatable {
    var price: String
    var cost: String
    var quantity: String
    var fixed: String
    var fee: String

    static let baseline = CalculatorInputs(price: "1000", cost: "700", quantity: "100", fixed: "20000", fee: "3")
    static let higherCost = CalculatorInputs(price: "1000", cost: "840", quantity: "100", fixed: "20000", fee: "3")
    static let higherPrice = CalculatorInputs(price: "1200", cost: "840", quantity: "100", fixed: "20000", fee: "3")
}

enum InputField: String, CaseIterable {
    case price, cost, quantity, fixed, fee

    var title: String {
        switch self {
        case .price: return "Цена продажи"
        case .cost: return "Переменные расходы"
        case .quantity: return "Продажи за месяц"
        case .fixed: return "Постоянные расходы"
        case .fee: return "Комиссия с выручки"
        }
    }
    var unit: String {
        switch self {
        case .price, .cost: return "₽ / шт."
        case .quantity: return "шт. / месяц"
        case .fixed: return "₽ / месяц"
        case .fee: return "%"
        }
    }
    var keyPath: WritableKeyPath<CalculatorInputs, String> {
        switch self {
        case .price: return \.price
        case .cost: return \.cost
        case .quantity: return \.quantity
        case .fixed: return \.fixed
        case .fee: return \.fee
        }
    }
    var sliderMaximum: Double {
        switch self {
        case .price: return 3000
        case .cost: return 2000
        case .quantity: return 500
        case .fixed: return 100000
        case .fee: return 100
        }
    }
    var sliderStep: Double {
        switch self { case .fee: return 0.1; case .fixed: return 100; default: return 1 }
    }
}

struct InputIssue: Error, Equatable {
    var field: InputField
    var message: String
    var description: String { "\(field.title): \(message)" }
}

struct Calculation: Equatable {
    let price: Decimal
    let cost: Decimal
    let quantity: Decimal
    let fixed: Decimal
    let feePercent: Decimal
    let revenue: Decimal
    let variableCosts: Decimal
    let commission: Decimal
    let contribution: Decimal
    let monthlyResult: Decimal
    let contributionMargin: Decimal?
    let breakEvenUnits: Decimal?

    static func parse(_ value: String, field: InputField) throws -> Decimal {
        let clean = value.filter { !$0.isWhitespace }.replacingOccurrences(of: ",", with: ".")
        let pattern = field == .quantity ? "^[0-9]+$" : "^[0-9]+(?:\\.[0-9]{1,2})?$"
        guard clean.count <= 18,
              clean.range(of: pattern, options: .regularExpression) != nil,
              let number = Decimal(string: clean, locale: Locale(identifier: "en_US_POSIX")),
              !number.isNaN else {
            throw InputIssue(field: field, message: field == .quantity ? "нужно целое неотрицательное число." : "нужно неотрицательное число, до двух знаков после запятой.")
        }
        let maximum = Decimal(field == .fee ? 100 : field == .quantity ? 1_000_000 : 10_000_000)
        guard number >= 0 && number <= maximum else {
            throw InputIssue(field: field, message: field == .fee ? "допустимо от 0 до 100%." : "значение выходит за диапазон этой версии.")
        }
        return number
    }

    static func evaluate(_ inputs: CalculatorInputs) throws -> Calculation {
        let price = try parse(inputs.price, field: .price)
        let cost = try parse(inputs.cost, field: .cost)
        let quantity = try parse(inputs.quantity, field: .quantity)
        let fixed = try parse(inputs.fixed, field: .fixed)
        let fee = try parse(inputs.fee, field: .fee)
        // Decimal arithmetic; money is rounded only for presentation, not per row.
        let revenue = price * quantity
        let variableCosts = cost * quantity
        let commission = revenue * fee / 100
        let contribution = price * (1 - fee / 100) - cost
        let monthlyResult = contribution * quantity - fixed
        let margin = price > 0 ? contribution / price * 100 : nil
        let breakEven: Decimal?
        if contribution > 0 {
            var quotient = fixed / contribution
            var rounded = Decimal.zero
            NSDecimalRound(&rounded, &quotient, 0, .up)
            breakEven = rounded
        } else {
            breakEven = fixed == 0 && contribution == 0 ? 0 : nil
        }
        return Calculation(price: price, cost: cost, quantity: quantity, fixed: fixed, feePercent: fee,
                           revenue: revenue, variableCosts: variableCosts, commission: commission,
                           contribution: contribution, monthlyResult: monthlyResult,
                           contributionMargin: margin, breakEvenUnits: breakEven)
    }
}

enum Display {
    static func number(_ value: Decimal, minimum: Int = 0, maximum: Int = 2) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = minimum
        formatter.maximumFractionDigits = maximum
        formatter.roundingMode = .halfUp
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "—"
    }
    static func money(_ value: Decimal) -> String { number(value) + " ₽" }
    static func signedMoney(_ value: Decimal) -> String { (value > 0 ? "+" : "") + money(value) }
    static func units(_ value: Decimal) -> String { number(value, maximum: 0) + " шт." }
}

struct SavedCalculation: Codable {
    let schemaVersion: Int
    let inputs: CalculatorInputs

    static func decode(_ data: Data) -> CalculatorInputs? {
        guard let saved = try? JSONDecoder().decode(SavedCalculation.self, from: data),
              saved.schemaVersion == 1,
              (try? Calculation.evaluate(saved.inputs)) != nil else { return nil }
        return saved.inputs
    }
    static func encode(_ inputs: CalculatorInputs) -> Data? {
        guard (try? Calculation.evaluate(inputs)) != nil else { return nil }
        return try? JSONEncoder().encode(SavedCalculation(schemaVersion: 1, inputs: inputs))
    }
}
