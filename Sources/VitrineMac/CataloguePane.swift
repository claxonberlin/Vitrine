import SwiftUI
import VitrineKit

/// The remote catalogue, as a second page trailing the library rather than a
/// panel laid on top of it.
///
/// It paints no background of its own — the same splash artwork behind the
/// library shows straight through here too, with only each row's own glass
/// standing between them, exactly like the library. A hairline divider on
/// the leading edge is the only seam between the two, the way a split view
/// would show one, even though this isn't one: `ContentView` slides this
/// page in from off the trailing edge and pushes the library most of the
/// way out of its path rather than resizing anything, so opening it never
/// changes the window's own width.
///
/// There's no title here any more — with the library pushed aside rather
/// than merely covered, the toolbar's own title stands in for it (see
/// `ContentView.titleLabel`), the way a real second page would rename the
/// window instead of relabelling itself.
///
/// The list is fetched once when the window opens; there is nothing a second
/// fetch would tell you that the first didn't. ⌘R is there for the rare case.
struct CataloguePane: View {
    @EnvironmentObject private var bridge: StoreBridge
    private var store: BuildStore { bridge.store }

    var body: some View {
        content
            .overlay(alignment: .leading) {
                Rectangle().fill(Theme.rowStroke).frame(width: 0.5)
            }
            .overlay(alignment: .topTrailing) {
                if store.isFetching {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                        .frame(width: 14, height: 14)
                        .padding(14)
                        .transition(.opacity)
                }
            }
            .clipped()
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
        // The same soft dissolve the library uses as rows pass under the
        // toolbar — see `LibraryPane`.
        .softScrollEdgeCompat(for: .top)
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
                    RemoteRow(build: build, branch: branch, drawsCard: false)
                }
                .transition(.opacity)
            }
        }
        .background(RowCard(hovered: hovered))
        .onHover { hovered = $0 }
    }

    private var header: some View {
        HStack(spacing: 8) {
            // Dimmed once the group opens: every build inside now has its
            // own download button, so the header's own action reads as a
            // shortcut for the latest one rather than the row's main control.
            CatalogueAction(build: group.latest, branch: branch, label: group.minorKey)
                .opacity(isExpanded ? 0.4 : 1)
                .animation(.smooth(duration: 0.2), value: isExpanded)

            BadgeRow(
                riskLabel: (branch == .stable && group.latest.riskId == "stable")
                    ? nil : group.latest.riskLabel,
                isLTS: store.isLTS(group.latest.version)
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
