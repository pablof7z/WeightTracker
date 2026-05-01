import SwiftUI

struct ConfirmationCard: View {
    let confirmation: TodayViewModel.SavedConfirmation
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Saved")
                    .font(.headline)
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .background(.thinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss confirmation")
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(format: "%.1f", confirmation.displayWeight))
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(confirmation.weightUnitSymbol)
                    .font(.title3)
                    .foregroundStyle(.secondary)

                if let delta = confirmation.deltaDisplay {
                    Spacer()
                    Label {
                        Text(String(format: "%+.1f", delta))
                            .monospacedDigit()
                    } icon: {
                        Image(systemName: delta < 0 ? "arrow.down" : (delta > 0 ? "arrow.up" : "minus"))
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(delta < 0 ? .green : (delta > 0 ? .red : .secondary))
                }
            }

            HStack {
                Image(systemName: "calendar")
                    .foregroundStyle(.secondary)
                Text(confirmation.date, style: .date)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if let clusterNote = confirmation.clusterNote {
                    Text(clusterNote)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.tint.opacity(0.15), in: Capsule())
                }
            }
        }
        .padding(14)
        .glass(in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.green.opacity(0.4), lineWidth: 1)
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
