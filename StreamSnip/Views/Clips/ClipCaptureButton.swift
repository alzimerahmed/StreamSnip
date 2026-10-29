//
//  ClipCaptureButton.swift
//  StreamSnip
//
//  Player control button for marking clip in/out points.
//

import SwiftUI

#if os(iOS) || os(macOS)
/// Clip capture control for the player: marks the in-point, then the
/// out-point, then offers save/clear through a menu.
struct ClipCaptureButton: View {
    @Environment(\.appEnvironment) private var appEnvironment

    /// Styled like the surrounding control buttons when provided.
    var iconSize: CGFloat = 17
    var frameSize: CGFloat = 28
    var tint: Color = .white

    private var controller: ClipCaptureController? {
        appEnvironment?.clipCaptureController
    }

    var body: some View {
        Menu {
            Button {
                controller?.markIn()
            } label: {
                Label(String(localized: "clip.markIn", defaultValue: "Mark In"), systemImage: "arrow.down.to.line")
            }
            Button {
                controller?.markOut()
            } label: {
                Label(String(localized: "clip.markOut", defaultValue: "Mark Out"), systemImage: "arrow.up.to.line")
            }
            Divider()
            Button {
                saveWithFeedback()
            } label: {
                Label(String(localized: "clip.save", defaultValue: "Save Clip"), systemImage: "checkmark")
            }
            .disabled(controller?.canSave != true)
            Button(role: .destructive) {
                controller?.clear()
            } label: {
                Label(String(localized: "clip.clear", defaultValue: "Clear Marks"), systemImage: "xmark")
            }
        } label: {
            Image(systemName: iconName)
                .font(.system(size: iconSize))
                .foregroundStyle(controller?.inPoint != nil ? .yellow : tint)
                .frame(width: frameSize, height: frameSize)
                .contentShape(Rectangle())
        } primaryAction: {
            // Tap advances the marking: no in-point → mark in, in-point set → mark out.
            if controller?.inPoint == nil {
                controller?.markIn()
            } else if controller?.outPoint == nil {
                controller?.markOut()
            } else {
                saveWithFeedback()
            }
        }
        .disabled(controller?.canCapture != true)
        .help(String(localized: "clip.capture", defaultValue: "Capture Clip"))
        .accessibilityLabel(String(localized: "clip.capture", defaultValue: "Capture Clip"))
    }

    /// Saves the marked clip and confirms it with a toast — the control bar
    /// gives no other visible feedback that the marks became a library entry.
    private func saveWithFeedback() {
        guard let controller else { return }
        if let clip = controller.saveClip() {
            appEnvironment?.toastManager.showSuccess(
                String(localized: "clip.saved.title", defaultValue: "Clip Saved"),
                subtitle: clip.displayTitle
            )
        } else if let message = controller.errorMessage {
            appEnvironment?.toastManager.showError(message)
        }
    }

    private var iconName: String {
        if controller?.inPoint != nil, controller?.outPoint != nil {
            return "scissors.circle.fill"
        }
        return "scissors"
    }
}
#endif
