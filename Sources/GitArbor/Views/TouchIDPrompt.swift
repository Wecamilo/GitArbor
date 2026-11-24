import AppKit
import LocalAuthentication
import LocalAuthenticationEmbeddedUI
import SwiftUI

/// Digital desenhada dentro da janela (componente oficial do macOS). Enquanto ela está na tela,
/// o sistema não abre a janela padrão do Touch ID por cima do app.
struct TouchIDGlyph: NSViewRepresentable {
    let context: LAContext

    func makeNSView(context: Context) -> LAAuthenticationView {
        let view = LAAuthenticationView(context: self.context, controlSize: .regular)
        view.translatesAutoresizingMaskIntoConstraints = true
        return view
    }

    func updateNSView(_ view: LAAuthenticationView, context: Context) {}
}

/// "✓" desenhado em traço contínuo (anima com `trim`).
nonisolated struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.minY + rect.height * 0.54))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.40, y: rect.minY + rect.height * 0.80))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.90, y: rect.minY + rect.height * 0.22))
        return path
    }
}

/// Tremida curta para digital não reconhecida.
nonisolated struct Shake: GeometryEffect {
    var travel: CGFloat = 7
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: travel * sin(animatableData * .pi * 4), y: 0))
    }
}

/// Entrada com Touch ID na própria tela: digital no centro, cancelar discreto e um ✓ animado ao reconhecer.
struct TouchIDPrompt: View {
    @Environment(AppModel.self) private var model
    /// Leva para a entrada com a senha do Mac (cancelar, Touch ID indisponível etc.).
    var onUsePassword: (String?) -> Void

    private enum Stage: Equatable {
        case waiting
        case paused          // o macOS interrompeu (ex.: a janela perdeu o foco); toque para tentar de novo
        case failed(String)  // digital não reconhecida
        case success
    }

    @ViewState private var context = TouchIDAuthentication.context()
    @ViewState private var attempt = 0
    @ViewState private var stage: Stage = .waiting
    @ViewState private var checkProgress: CGFloat = 0
    @ViewState private var shakes: CGFloat = 0
    @ViewState private var cancelled = false

    private let diameter: CGFloat = 176

    private var ringMode: NodeRing.Mode {
        switch stage {
        case .waiting: .waiting
        case .paused: .paused
        case .failed: .failed
        case .success: .success
        }
    }

    private var caption: String {
        switch stage {
        case .waiting: "Encoste o dedo no Touch ID"
        case .paused: "Clique na digital para tentar de novo"
        case .failed(let message): message
        case .success: "Pronto"
        }
    }

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                NodeRing(mode: ringMode)
                Circle()
                    .fill(Theme.accentSoft)
                    .padding(26)
                if stage == .success {
                    Circle()
                        .fill(Theme.gradient)
                        .padding(26)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                    CheckmarkShape()
                        .trim(from: 0, to: checkProgress)
                        .stroke(.white, style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                        .frame(width: 50, height: 50)
                } else {
                    TouchIDGlyph(context: context)
                        .frame(width: 84, height: 84)
                        .clipShape(Circle())
                        .id(attempt)
                        .opacity(stage == .paused ? 0.45 : 1)
                        .transition(.opacity)
                }
            }
            .frame(width: diameter, height: diameter)
            .modifier(Shake(animatableData: shakes))
            .contentShape(Circle())
            .onTapGesture { if stage == .paused || isFailed { retry() } }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(caption)
            .accessibilityAddTraits(.isButton)

            Text(caption)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isFailed ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.2), value: caption)

            if stage != .success {
                Button { cancel() } label: {
                    Text("Cancelar")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 16).padding(.vertical, 6)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .keyboardShortcut(.cancelAction)
            }
        }
        .task(id: attempt) { await authenticate() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if stage == .paused { retry() }
        }
    }

    private var isFailed: Bool { if case .failed = stage { true } else { false } }

    private func authenticate() async {
        // A digital só é pedida com o app em primeiro plano; a janela precisa existir antes.
        try? await Task.sleep(for: .milliseconds(250))
        guard !cancelled else { return }
        guard NSApp.isActive else { stage = .paused; return }
        let current = context
        do {
            try await TouchIDAuthentication.verify(current, reason: "abrir o Git Arbor")
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { stage = .success }
            withAnimation(.easeInOut(duration: 0.45)) { model.ownerConfirmed = true }
            withAnimation(.easeOut(duration: 0.35).delay(0.12)) { checkProgress = 1 }
            try? await Task.sleep(for: .milliseconds(650))
            do {
                try await model.unlockAfterVerification()
            } catch {
                onUsePassword(error.localizedDescription)
            }
        } catch let error as LAError {
            switch error.code {
            case .userCancel, .appCancel:
                if !cancelled { onUsePassword(nil) }
            case .systemCancel:
                stage = .paused
            case .authenticationFailed:
                stage = .failed("Digital não reconhecida. Clique para tentar de novo.")
                withAnimation(.linear(duration: 0.4)) { shakes += 1 }
            default:
                onUsePassword(TouchIDAuthentication.message(for: error))
            }
        } catch {
            onUsePassword(error.localizedDescription)
        }
    }

    private func retry() {
        context.invalidate()
        context = TouchIDAuthentication.context()
        stage = .waiting
        attempt += 1
    }

    private func cancel() {
        cancelled = true
        context.invalidate()
        onUsePassword(nil)
    }
}
