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
                .background(glassFill)
            Divider().opacity(0.5)
            content
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

    /// The pane's glass, applied separately to the header and to whatever's
    /// below the divider rather than once behind the whole pane. The list's
    /// own copy is what a scroll-edge effect can actually reach — a fill
    /// painted on some ancestor of the scroll view never dissolves with it,
    /// it just sits there unaffected once the scrolled copy fades, which
    /// looks like the glass failing rather than blurring. A plain
    /// `Rectangle` is enough either place: the outer `clipShape` on the
    /// whole pane already trims everything to the rounded corners.
    @ViewBuilder
    private var glassFill: some View {
        if #available(macOS 26.0, *) {
            Rectangle().fill(.clear).glassEffect(.regular, in: Rectangle())
        } else {
            Rectangle().fill(.ultraThinMaterial)
        }
    }

    // MARK: - Header

    private var header: some View {
        // The title is centred over the whole header regardless of the
        // spinner beside it — a trailing-aligned sibling in the same HStack
        // would have pushed it off-centre only while fetching.
        ZStack {
            Text("Catalogue")
                .font(.system(size: 12, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .center)

            HStack {
                Spacer()
                if store.isFetching {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                        .frame(width: 14, height: 14)
                        .transition(.opacity)
                }
            }
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
            .background(glassFill)
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
            .background(glassFill)
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
        .background(glassFill)
        // The real, scroll-position-aware soft dissolve where rows pass
        // under the pane's own header — reaches the glass right above,
        // since it's this scroll view's own background rather than the
        // pane's.
        .softScrollEdgeCompat(for: .top)
    }

    @ViewBuilder
    private func section(_ branch: BuildBranch) -> some View {
        let groups = store.remoteGrouped(in: branch)
        if !groups.isEmpty {
            SectionHeader(title: branch.title, tinted: true)
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
        // Tinted: this card sits on the catalogue pane's own glass.
        .background(RowCard(hovered: hovered, tinted: true))
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
