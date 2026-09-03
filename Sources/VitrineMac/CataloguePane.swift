import SwiftUI
import VitrineKit

/// The remote catalogue, shown as a trailing inspector.
///
/// The list is fetched once when the window opens; there is no refresh button
/// because there is nothing a second fetch would tell you that the first
/// didn't. ⌘R is there for the rare case.
struct CataloguePane: View {
    @EnvironmentObject private var bridge: StoreBridge
    private var store: BuildStore { bridge.store }

    var body: some View {
        Group {
            if store.isFetching && store.stable.isEmpty {
                VStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Loading builds…")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.remoteGrouped(in: .stable).isEmpty
                        && store.remoteGrouped(in: .daily).isEmpty
                        && store.remoteGrouped(in: .experimental).isEmpty {
                ContentUnavailableView(
                    "Catalogue Unavailable",
                    systemImage: "wifi.slash",
                    description: Text("No builds came back from blender.org. Press ⌘R to try again.")
                )
            } else {
                list
            }
        }
        .toolbar {
            // Sits above the inspector, so the spinner reads as belonging to
            // the catalogue rather than to the library beside it.
            ToolbarItem {
                if store.isFetching {
                    ProgressView()
                        .controlSize(.small)
                        .transition(.opacity)
                }
            }
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(BuildBranch.allCases) { branch in
                    section(branch)
                }
            }
            .padding(.horizontal, Theme.Metrics.rowInset)
            .padding(.bottom, Theme.Metrics.windowMargin)
            .animation(.smooth(duration: 0.28), value: store.expandedMinorKeys)
        }
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
        .background(RowCard(hovered: hovered))
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
            .foregroundStyle(.tertiary)
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
