import SwiftUI

struct OptionalDetailsRow: View {
    @Binding var hipsValue: String
    @Binding var waistValue: String
    @Binding var note: String
    let bodyUnitSymbol: String

    @AppStorage("today.stickyExpand") private var stickyExpand: Bool = false
    @State private var expanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expanded.toggle()
                    stickyExpand = expanded
                }
            } label: {
                HStack {
                    Image(systemName: "ruler")
                    Text("Optional details")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 10)

            if expanded {
                VStack(spacing: 12) {
                    field("Hips", text: $hipsValue, suffix: bodyUnitSymbol, keyboard: .decimalPad)
                    field("Waist", text: $waistValue, suffix: bodyUnitSymbol, keyboard: .decimalPad)

                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Note (optional)", text: $note, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(1...3)
                            .onChange(of: note) { _, newValue in
                                if newValue.count > 140 {
                                    note = String(newValue.prefix(140))
                                }
                            }
                        Text("\(note.count)/140")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 12)
        .glass(in: RoundedRectangle(cornerRadius: 14))
        .onAppear { expanded = stickyExpand }
    }

    @ViewBuilder
    private func field(_ title: String, text: Binding<String>, suffix: String, keyboard: UIKeyboardType) -> some View {
        HStack {
            Text(title)
                .frame(width: 64, alignment: .leading)
                .font(.subheadline)
            TextField("0", text: text)
                .keyboardType(keyboard)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
            Text(suffix)
                .foregroundStyle(.secondary)
                .font(.subheadline)
        }
    }
}
