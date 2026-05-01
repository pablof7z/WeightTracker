import SwiftUI
import SwiftData

/// Half-height bottom sheet with editable macro rows. Kcal is derived from the
/// current macro grams instead of edited independently.
struct EditMacrosSheet: View {
    @Environment(\.dismiss) private var dismiss

    let cutStartDate: Date
    let initial: (kcal: Int, proteinG: Int, fatG: Int, carbsG: Int)
    let defaults: (kcal: Int, proteinG: Int, fatG: Int, carbsG: Int)
    var onSave: (_ kcal: Int, _ proteinG: Int, _ fatG: Int, _ carbsG: Int) -> Void

    @State private var proteinG: Int
    @State private var fatG: Int
    @State private var carbsG: Int

    private var computedKcal: Int {
        MacroDefaults.totalKcal(proteinG: proteinG, fatG: fatG, carbsG: carbsG)
    }

    init(
        cutStartDate: Date,
        initial: (kcal: Int, proteinG: Int, fatG: Int, carbsG: Int),
        defaults: (kcal: Int, proteinG: Int, fatG: Int, carbsG: Int),
        onSave: @escaping (Int, Int, Int, Int) -> Void
    ) {
        self.cutStartDate = cutStartDate
        self.initial = initial
        self.defaults = defaults
        self.onSave = onSave
        _proteinG = State(initialValue: initial.proteinG)
        _fatG = State(initialValue: initial.fatG)
        _carbsG = State(initialValue: initial.carbsG)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    Section {
                        calorieRow
                        stepperRow(
                            label: MacroCopy.editProtein,
                            value: $proteinG,
                            step: 5,
                            min: 0,
                            max: 500,
                            suffix: MacroCopy.editGramSuffix
                        )
                        stepperRow(
                            label: MacroCopy.editFat,
                            value: $fatG,
                            step: 5,
                            min: 0,
                            max: 300,
                            suffix: MacroCopy.editGramSuffix
                        )
                        stepperRow(
                            label: MacroCopy.editCarbs,
                            value: $carbsG,
                            step: 5,
                            min: 0,
                            max: 800,
                            suffix: MacroCopy.editGramSuffix
                        )
                    } header: {
                        Text("Daily targets")
                    } footer: {
                        Text("Calories are computed from protein, fat, and carbs (4·4·9).")
                    }

                    Section {
                        Button {
                            proteinG = defaults.proteinG
                            fatG = defaults.fatG
                            carbsG = defaults.carbsG
                        } label: {
                            Text(MacroCopy.editReset)
                        }
                    }
                }
            }
            .navigationTitle(MacroCopy.editTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(MacroCopy.editSave) {
                        onSave(computedKcal, proteinG, fatG, carbsG)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var calorieRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(MacroCopy.editCalories)
            Spacer()
            Text("\(computedKcal)")
                .font(.body.monospacedDigit())
            Text(MacroCopy.editKcal)
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func stepperRow(
        label: String,
        value: Binding<Int>,
        step: Int,
        min: Int,
        max: Int,
        suffix: String
    ) -> some View {
        HStack {
            Text(label)
            Spacer()
            HStack(spacing: 12) {
                Button {
                    let newVal = Swift.max(min, value.wrappedValue - step)
                    if newVal != value.wrappedValue {
                        value.wrappedValue = newVal
                    }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                MacroNumberField(
                    value: value,
                    min: min,
                    max: max,
                    suffix: suffix,
                    font: .body.monospacedDigit(),
                    fieldWidth: 62
                )

                Button {
                    let newVal = Swift.min(max, value.wrappedValue + step)
                    if newVal != value.wrappedValue {
                        value.wrappedValue = newVal
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .contentShape(Rectangle())
    }
}

struct MacroNumberField: View {
    @Binding var value: Int
    let min: Int
    let max: Int
    let suffix: String
    let font: Font
    let fieldWidth: CGFloat

    @State private var text: String
    @FocusState private var isFocused: Bool

    init(
        value: Binding<Int>,
        min: Int,
        max: Int,
        suffix: String,
        font: Font,
        fieldWidth: CGFloat
    ) {
        _value = value
        self.min = min
        self.max = max
        self.suffix = suffix
        self.font = font
        self.fieldWidth = fieldWidth
        _text = State(initialValue: "\(value.wrappedValue)")
    }

    var body: some View {
        HStack(spacing: 4) {
            TextField("", text: $text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .font(font)
                .monospacedDigit()
                .frame(width: fieldWidth, alignment: .trailing)
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 6))
                .focused($isFocused)
                .onChange(of: text) { _, newText in
                    applyText(newText)
                }
                .onChange(of: value) { _, newValue in
                    let normalized = "\(newValue)"
                    if text != normalized {
                        text = normalized
                    }
                }
                .onChange(of: isFocused) { _, focused in
                    if !focused, text.isEmpty {
                        text = "\(value)"
                    }
                }

            if !suffix.isEmpty {
                Text(suffix)
                    .font(font)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: fieldWidth + (suffix.isEmpty ? 12 : 28), alignment: .trailing)
    }

    private func applyText(_ newText: String) {
        let digits = newText.filter { $0.isNumber }
        if digits != newText {
            text = digits
            return
        }

        guard let parsed = Int(digits) else {
            return
        }

        let clamped = Swift.min(max, Swift.max(min, parsed))
        if clamped != value {
            value = clamped
        }

        if clamped != parsed {
            text = "\(clamped)"
        }
    }
}
