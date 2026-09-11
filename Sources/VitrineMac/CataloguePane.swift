import SwiftUI
import VitrineKit

/// The remote catalogue, as a second page trailing the library rather than a
/// panel laid on top of it.
///
/// It paints no background of its own — the window's own ground shows
/// straight through here too, with only each row's own card standing between
/// them, exactly like the library. `ContentView` slides this page in from
/// off the trailing edge and pushes the library most of the way out of its
/// path rather than resizing anything, so opening it never changes the
/// window's own width.
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
            .overlay(alignment: .topTrailing) {
                if store.isFetching {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                        .frame(width: 14, height: 14)
                        .padding(14)
                        .accessibilityLabel("Reloading the catalogue")
                        .transition(.opacity)
                }
            }
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
        } else if store.catalogueIsEmpty {
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

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: Theme.Metrics.rowGap) {
                ForEach(BuildBranch.allCases) { branch in
                    section(branch)
                }
            }
            // Same margin as the library's own rows keep from the window
            // edge — this page reads as a continuation of it, not a
            // narrower column floating inside it.
            .padding(.horizontal, Theme.Metrics.windowMargin)
            .padding(.bottom, Theme.Metrics.windowMargin)
            .animation(.smooth(duration: 0.28), value: store.expandedMinorKeys)
        }
        .scrollContentBackground(.hidden)
        // No scroll-edge effect here, where the library takes the soft
        // dissolve. This page is narrower than the window, so the title bar
        // has no full-width scroll view to blur against and falls back to a
        // plain hairline — the flat line that showed under the title while
        // the catalogue was open. Nothing is lost: these rows pass under an
        // opaque stretch of the window's own ground, with no artwork behind
        // them for a dissolve to reveal.
        .scrollEdgeEffectHiddenCompat(for: .top)
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
        // Folded, the card stands for the one build its header would fetch,
        // so it carries that build's progress. Open, each child row carries
        // its own and the card behind them all stays plain.
        .background(RowCard(hovered: hovered, progress: isExpanded ? nil : latestProgress))
        .onHover { hovered = $0 }
    }

    private var latestProgress: RowProgress? {
        RowProgress(store.downloadState(group.latest.id))
    }

    private var isLTS: Bool { store.isLTS(group.latest.version) }

    private var header: some View {
        HStack(spacing: Theme.Metrics.rowSpacing) {
            // Dimmed once the group opens: every build inside now has its
            // own download button, so the header's own action reads as a
            // shortcut for the latest one rather than the row's main control.
            CatalogueAction(build: group.latest, branch: branch, label: group.minorKey)
                .opacity(isExpanded ? 0.4 : 1)
                .animation(.smooth(duration: 0.2), value: isExpanded)

            BadgeRow(riskLabel: group.latest.riskLabel(besideLTS: isLTS),
                     isLTS: isLTS)

            Spacer(minLength: 4)

            disclosure
        }
        .padding(.horizontal, Theme.Metrics.rowInset)
        .frame(height: Theme.Metrics.rowHeight)
        // Anywhere in the header folds the group, not just the chevron in
        // its corner. The card behind it lights up under the pointer, which
        // is what says the whole bar is live; the button inside carries the
        // same action to the keyboard and to VoiceOver, which a tap gesture
        // reaches neither of.
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
                    .font(Theme.openDigits(size: 10))
                    .monospacedDigit()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 12)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 4)
        }
        // No highlight of its own: the whole header already folds the group,
        // so lighting this corner up promised a separate target that isn't
        // one. It stays a button for the keyboard and for VoiceOver.
        .buttonStyle(.plain)
        .help(isExpanded ? "Collapse \(group.minorKey)" : "Show every \(group.minorKey) release")
        .accessibilityLabel(isExpanded
                            ? "Collapse Blender \(group.minorKey)"
                            : "Show all \(group.builds.count) Blender \(group.minorKey) releases")
        .accessibilityAddTraits(.isToggle)
    }
}
