import SwiftUI
import AppKit

@MainActor
final class CalculatorStore: ObservableObject {
    private let defaults: UserDefaults
    private static let storageKey = "lastValidCalculation.v1"
    @Published var inputs: CalculatorInputs {
        didSet {
            if let data = SavedCalculation.encode(inputs) { defaults.set(data, forKey: Self.storageKey) }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.inputs = defaults.data(forKey: Self.storageKey).flatMap(SavedCalculation.decode) ?? .baseline
    }
    var evaluation: Result<Calculation, InputIssue> {
        do { return .success(try Calculation.evaluate(inputs)) }
        catch let issue as InputIssue { return .failure(issue) }
        catch { return .failure(InputIssue(field: .price, message: "не удалось выполнить расчёт.")) }
    }
    func binding(_ field: InputField) -> Binding<String> {
        Binding(get: { self.inputs[keyPath: field.keyPath] }, set: { self.inputs[keyPath: field.keyPath] = $0 })
    }
    func slider(_ field: InputField) -> Binding<Double> {
        Binding(get: { (try? Calculation.parse(self.inputs[keyPath: field.keyPath], field: field)).map { NSDecimalNumber(decimal: $0).doubleValue } ?? 0 },
                set: { value in
            self.inputs[keyPath: field.keyPath] = field == .fee ? String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value) : String(Int(value.rounded()))
        })
    }
    func range(_ field: InputField) -> ClosedRange<Double> {
        let value = slider(field).wrappedValue
        return 0...(field == .fee ? 100 : max(field.sliderMaximum, ceil(value * 1.2)))
    }
}

struct InputControl: View {
    let field: InputField
    @ObservedObject var store: CalculatorStore
    let invalid: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(field.title).font(.system(size: 14, weight: .medium))
                Spacer()
                Text(field.unit).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            TextField(field.title, text: store.binding(field))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 20, weight: .medium, design: .rounded).monospacedDigit())
                .accessibilityLabel(field.title)
                .accessibilityIdentifier("input-" + field.rawValue)
                .accessibilityHint(invalid ? "Проверьте введённое значение" : field.unit)
            Slider(value: store.slider(field), in: store.range(field), step: field.sliderStep)
                .accessibilityLabel("Изменить: " + field.title)
                .accessibilityIdentifier("slider-" + field.rawValue)
        }
    }
}

struct Metric: View {
    let title: String
    let value: String
    let detail: String
    var negative = false
    var prominent = false
    var identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: prominent ? 40 : 27, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(negative ? Color.red : Color.primary)
                .textSelection(.enabled)
                .accessibilityIdentifier(identifier)
                .minimumScaleFactor(0.65)
                .lineLimit(1)
            Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: prominent ? 112 : 108, alignment: .topLeading)
        .padding(18)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 15))
        .accessibilityElement(children: .contain)
    }
}

struct CalculatorView: View {
    @StateObject private var store = CalculatorStore()
    @State private var showDetails = false
    private let base = try! Calculation.evaluate(.baseline)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top, spacing: 13) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 27, weight: .medium))
                        .foregroundStyle(Color.orange)
                        .padding(12)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Цена и прибыль").font(.system(size: 26, weight: .semibold))
                        Text("Одна позиция. Понятные расходы. Решение в цифрах.")
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Label("Офлайн", systemImage: "lock.shield")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                        .padding(.top, 8)
                }

                HStack(spacing: 9) {
                    preset("Исходный пример", .baseline, "1")
                    preset("Расходы +20%", .higherCost, "2")
                    preset("Цена 1 200 ₽", .higherPrice, "3")
                }
                HStack(alignment: .top, spacing: 28) {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(InputField.allCases, id: \.rawValue) { field in
                            InputControl(field: field, store: store, invalid: issue?.field == field)
                        }
                    }
                    .frame(width: 330)

                    VStack(alignment: .leading, spacing: 15) {
                        if let result = calculation {
                            Metric(title: "Результат месяца · до налогов", value: Display.money(result.monthlyResult),
                                   detail: delta(result), negative: result.monthlyResult < 0,
                                   prominent: true, identifier: "result-month")
                            HStack(alignment: .top, spacing: 12) {
                                Metric(title: "С одной продажи", value: Display.money(result.contribution),
                                       detail: result.contributionMargin.map { Display.number($0) + "% от цены после расходов и комиссии" } ?? "При нулевой цене процент не определён",
                                       negative: result.contribution < 0, identifier: "result-unit")
                                Metric(title: "Безубыточность", value: result.breakEvenUnits.map(Display.units) ?? "Недостижима",
                                       detail: breakEvenDetail(result), identifier: "result-breakeven")
                            }
                            VStack(alignment: .leading, spacing: 13) {
                                Text("За месяц").font(.system(size: 15, weight: .semibold))
                                row("Выручка", result.revenue, "revenue")
                                row("Переменные расходы", result.variableCosts, "variable")
                                row("Комиссия", result.commission, "commission")
                                row("Постоянные расходы", result.fixed, "fixed")
                            }.padding(.top, 9)
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                Label("Проверьте значение", systemImage: "exclamationmark.circle")
                                    .font(.headline).foregroundStyle(.red)
                                Text(issue?.description ?? "Расчёт недоступен.")
                                    .accessibilityIdentifier("input-error")
                                Text("После исправления результат появится сразу.")
                                    .foregroundStyle(.secondary)
                            }.padding(20)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 15))
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                Divider()
                DisclosureGroup("Что входит в расчёт", isExpanded: $showDetails) {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("С продажи = цена − переменные расходы − комиссия. За месяц = остаток с продажи × количество − постоянные расходы.")
                        Text("Переменные расходы: закупка, упаковка, доставка и другие затраты на единицу. Для услуги — время работы и подрядчики. Не включайте одну статью одновременно сюда и в постоянные расходы.")
                        Text("Модель без НДС, других налогов, процентов, амортизации, возвратов и фиксированных комиссий за заказ. Это результат по введённым расходам, не бухгалтерская чистая прибыль. Объём продаж задаёте вы — спрос не прогнозируется.")
                        Text("Денежные значения считаются десятичной арифметикой и округляются при показе до копеек. Числа принимаются с точкой или запятой. Последний корректный расчёт сохраняется только на этом Mac.")
                    }.font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 9)
                }
                HStack {
                    Text("ANODHAS AI · версия 1.0.0").font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Text("Последний корректный расчёт сохраняется автоматически")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }.padding(26)
        }
        .frame(minWidth: 900, minHeight: 715)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(.orange)
    }

    private var calculation: Calculation? { try? store.evaluation.get() }
    private var issue: InputIssue? { if case .failure(let value) = store.evaluation { return value }; return nil }

    private func preset(_ title: String, _ inputs: CalculatorInputs, _ key: KeyEquivalent) -> some View {
        Button(title) { store.inputs = inputs }
            .buttonStyle(.bordered)
            .tint(store.inputs == inputs ? .orange : .gray)
            .keyboardShortcut(key, modifiers: .command)
            .accessibilityIdentifier(inputs == .baseline ? "preset-base" : inputs == .higherCost ? "preset-cost" : "preset-price")
    }
    private func row(_ title: String, _ value: Decimal, _ key: String) -> some View {
        HStack {
            Text(title).font(.system(size: 13)).foregroundStyle(.secondary)
            Spacer()
            Text(Display.money(value)).font(.system(size: 14, weight: .medium).monospacedDigit())
                .textSelection(.enabled).accessibilityIdentifier("breakdown-" + key)
        }
    }
    private func delta(_ r: Calculation) -> String {
        let difference = r.monthlyResult - base.monthlyResult
        return difference == 0 ? "К исходному примеру: без изменений" : "К исходному примеру: " + Display.signedMoney(difference)
    }
    private func breakEvenDetail(_ r: Calculation) -> String {
        guard let threshold = r.breakEvenUnits else {
            return r.contribution < 0 ? "Каждая продажа увеличивает убыток" : "Продажи не покрывают постоянные расходы"
        }
        guard r.contribution > 0 else { return "Нулевой результат при любом объёме" }
        let difference = r.quantity - threshold
        if difference == 0 { return "План равен порогу" }
        return difference > 0 ? "План выше на " + Display.units(difference) : "До порога ещё " + Display.units(-difference)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct PriceProfitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        WindowGroup("Цена и прибыль") { CalculatorView() }
            .defaultSize(width: 1020, height: 780)
            .commands { CommandGroup(replacing: .newItem) {} }
    }
}
