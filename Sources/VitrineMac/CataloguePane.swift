import SwiftUI
import VitrineKit

/// The remote catalogue, as a pane floating over the library.
///
/// It has its own material, corner radius and shadow rather than sitting in a
/// split, so it reads as a sheet laid on the window instead of a region cut
/// out of it — and the library underneath keeps the width it had.
///
/// The list is fetched once when the window opens; there is nothing a second
/// fetch would tell you that the first didn't. ⌘R is there for the rare case.
struct CataloguePane: View {
    @EnvironmentObject private var bridge: StoreBridge
    private var store: BuildStore { bridge.store }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            content
        }
        .background {
            RoundedRectangle(cornerRadius: Theme.Metrics.sidebarCorner, style: .continuous)
                .fill(.regularMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Metrics.sidebarCorner, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.sidebarCorner, style: .continuous))
        // What separates a floating pane from a docked one: the library has
        // to look like it continues underneath.
        .shadow(color: .black.opacity(0.28), radius: 18, y: 6)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Text("Catalogue")
                .font(.system(size: 12, weight: .semibold))

            Spacer(minLength: 4)

            if store.isFetching {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
                    .frame(width: 14, height: 14)
                    .transition(.opacity)
            }

            MinimumVersionMenu()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    // MARK: - List

    @ViewBuilder
    private var content: some View {
        if store.isFetching && store.stable.isEmpty {
            VStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Loading builds…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isEmpty {
            VStack(spacing: 6) {
                Text("Nothing to show")
                    .font(.system(size: 12, weight: .semibold))
                Text("No builds at or above \(store.minVersionString) came back from blender.org.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            list
        }
    }

    private var isEmpty: Bool {
        BuildBranch.allCases.allSatisfy { store.remoteGrouped(in: $0).isEmpty }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(BuildBranch.allCases) { branch in
                    section(branch)
                }
            }
            .padding(.horizontal, Theme.Metrics.rowInset)
            .padding(.bottom, Theme.Metrics.rowInset)
            .animation(.smooth(duration: 0.28), value: store.expandedMinorKeys)
        }
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func section(_ branch: BuildBranch) -> some View {
        let groups = store.remoteGrouped(in: branch)
        if !groups.isEmpty {
            SectionHeader(title: branch.title)
            ForEach(groups) { group in
                if group.builds.count == 1 {
                    RemoteRow(build: group.builds[0], branch: branch)
                } else {
                    GroupCard(group: group, branch: branch)
                }
            }
        }
    }
}

/// How far back the stable archive is scraped.
///
/// This is the only setting the app has, and it belongs to the catalogue —
/// which is why it lives at the top of the catalogue rather than behind a
/// window of its own.
struct MinimumVersionMenu: View {
    @EnvironmentObject private var bridge: StoreBridge
    private var store: BuildStore { bridge.store }

    /// The offered floors, plus whatever is currently set if a hand-edited
    /// settings file named something off the list.
    private var options: [String] {
        var all = BuildStore.minVersionChoices
        if !all.contains(store.minVersionString) {
            all.append(store.minVersionString)
        }
        return all.sorted { (Version($0) ?? .zero) < (Version($1) ?? .zero) }
    }

    var body: some View {
        HStack(spacing: 3) {
            Text("from")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            Picker("Oldest version to list", selection: Binding(
                get: { store.minVersionString },
                set: { store.setMinVersion($0) }
            )) {
                ForEach(options, id: \.self) { version in
                    Text(version).monospacedDigit().tag(version)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
            .help("Hide every release older than this")
            .handCursor()
        }
    }
}

/// A minor series and its individual builds share one card, so an expanded
/// group reads as a single object. The children aren't indented — the card
/// already scopes them.
struct GroupCard: View {
    @EnvironmentObject private var bridge: StoreBridge
    private var store: BuildStore { bridge.store }
    let group: RemoteBuildGroup
    let branch: BuildBranch

    @State private var hovered = false

    private var isExpanded: Bool { store.isExpanded(group.minorKey) }

    var body: some View {
        VStack(spacing: 0) {
            header
            if isExpanded {
                ForEach(group.builds) { build in
                    RemoteRow(build: build, branch: branch,
                              compact: true, drawsCard: false)
                }
                .transition(.opacity)
            }
        }
        .background(RowCard(hovered: hovered, tinted: true))
        .onHover { hovered = $0 }
    }

    private var header: some View {
        HStack(spacing: 8) {
            CatalogueAction(build: group.latest, branch: branch, label: group.minorKey)

            BadgeRow(
                riskLabel: (branch == .stable && group.latest.riskId == "stable")
                    ? nil : group.latest.riskLabel,
                isLTS: store.isLTS(group.latest.version),
                accent: Theme.catalogueAccent
            )

            Spacer(minLength: 4)

            disclosure
        }
        .padding(.horizontal, Theme.Metrics.rowInset)
        .frame(height: Theme.Metrics.rowHeight)
        // Anywhere in the header works as well as the chevron does. The
        // button below is what makes the same thing reachable by keyboard
        // and readable to VoiceOver — a tap gesture alone is neither.
        .contentShape(Rectangle())
        .onTapGesture { store.toggleExpansion(group.minorKey) }
    }

    private var disclosure: some View {
        Button {
            store.toggleExpansion(group.minorKey)
        } label: {
            HStack(spacing: 5) {
                // Just the count — the chevron beside it already says what it
                // counts, and "N versions" wrapped onto two lines in here.
                Text("\(group.builds.count)")
                    .font(.system(size: 10))
                    .monospacedDigit()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 12)
            }
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .handCursor()
        .help(isExpanded ? "Collapse \(group.minorKey)" : "Show every \(group.minorKey) release")
        .accessibilityLabel(isExpanded
                            ? "Collapse Blender \(group.minorKey)"
                            : "Show all \(group.builds.count) Blender \(group.minorKey) releases")
    }
}
