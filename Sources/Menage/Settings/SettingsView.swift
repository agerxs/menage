import AppKit
import MenageCore
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Bindable var monitor: MonitorModel
    @Bindable var cleaner: CleanerModel
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Disque de démarrage") {
                Stepper(value: $monitor.thresholds.diskAttentionGB, in: (monitor.thresholds.diskCritiqueGB + 5)...200, step: 5) {
                    LabeledContent("Attention sous", value: "\(Int(monitor.thresholds.diskAttentionGB)) Go libres")
                }
                Stepper(value: $monitor.thresholds.diskCritiqueGB, in: 5...(monitor.thresholds.diskAttentionGB - 5), step: 5) {
                    LabeledContent("Critique sous", value: "\(Int(monitor.thresholds.diskCritiqueGB)) Go libres")
                }
            }

            Section {
                Stepper(value: $monitor.thresholds.swapAttentionGB, in: 1...(monitor.thresholds.swapCritiqueGB - 1), step: 1) {
                    LabeledContent("Attention au-delà de", value: "\(Int(monitor.thresholds.swapAttentionGB)) Go")
                }
                Stepper(value: $monitor.thresholds.swapCritiqueGB, in: (monitor.thresholds.swapAttentionGB + 1)...max(64, monitor.thresholds.swapCritiqueGB), step: 1) {
                    LabeledContent("Critique au-delà de", value: "\(Int(monitor.thresholds.swapCritiqueGB)) Go")
                }
            } header: {
                Text("Swap")
            } footer: {
                Text("Par défaut, un quart puis la moitié de la RAM. Le swap, c'est la mémoire que macOS décharge sur le disque quand la RAM ne suffit plus.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Stepper(value: $cleaner.inactivityDays, in: 15...365, step: 15) {
                    LabeledContent("Projet inactif après", value: "\(cleaner.inactivityDays) jours")
                }
                ForEach(cleaner.projectRoots, id: \.self) { root in
                    HStack {
                        Image(systemName: "folder").foregroundStyle(.secondary)
                        Text(root.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        Spacer()
                        Button {
                            cleaner.projectRoots.removeAll { $0 == root }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Ne plus chercher de projets ici")
                    }
                }
                Button("Ajouter un dossier de projets…", action: addProjectRoot)
            } header: {
                Text("Nettoyeur")
            } footer: {
                Text("Ménage cherche les projets dans ces dossiers, jusqu'à 4 niveaux de profondeur.")
                    .foregroundStyle(.secondary)
            }

            Section("Général") {
                Toggle("Ouvrir Ménage à l'ouverture de session", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
                LabeledContent("Notifications") {
                    Button("Envoyer une notification de test") { monitor.sendTestNotification() }
                }
                LabeledContent("Seuils") {
                    Button("Revenir aux valeurs par défaut") {
                        monitor.thresholds = .standard(physicalMemory: Int64(ProcessInfo.processInfo.physicalMemory))
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func addProjectRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Ajouter"
        guard panel.runModal() == .OK, let url = panel.url, !cleaner.projectRoots.contains(url) else { return }
        cleaner.projectRoots.append(url)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = "Impossible de modifier l'ouverture automatique : \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
