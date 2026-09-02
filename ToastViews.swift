import SwiftUI
import SwiftData

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct StatusToast: View {
    let message: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
            Text(message)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(maxWidth: 520)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule().stroke(Color.primary.opacity(0.1), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.16), radius: 16, y: 7)
        .accessibilityElement(children: .combine)
    }
}


struct UndoToast: View {
    let message: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)

            Text(message)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)

            Spacer(minLength: 8)

            Button("Undo", action: onUndo)
                .font(.subheadline.weight(.bold))
                .buttonStyle(.plain)
                .foregroundStyle(.indigo)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(maxWidth: 520)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.16), radius: 16, y: 7)
        .accessibilityElement(children: .contain)
    }
}

