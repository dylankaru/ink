//
//  ToolPalette.swift
//  ink
//
//  Created by Dylan Karunanayake on 7/11/2026.
//

import SwiftUI

enum Tool: String, CaseIterable, Identifiable {
    case pen, marker, pencil, eraser
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .pen: "pencil.tip"
        case .marker: "highlighter"
        case .pencil: "pencil"
        case .eraser: "eraser"
        }
    }

    var label: String { rawValue.capitalized }

    var widthRange: ClosedRange<CGFloat> {
        switch self {
        case .pen: 1...20
        case .marker: 6...40
        case .pencil: 1...10
        case .eraser: 8...60
        }
    }

    var presets: [Color] {
        switch self {
        case .pen: [.black, .blue, .red, .green, .purple]
        case .marker: [.yellow, .pink, .green, .orange, .cyan]
        case .pencil: [.gray, .black, .brown, .blue, .red]
        case .eraser: []
        }
    }
}

struct ToolSettings {
    var colour: Color
    var width: CGFloat
}

@Observable
final class ToolState {
    var selected: Tool = .pen
    var isExpanded = false
    var showingSettings = false
    var previous: Tool = .pen
    var recents: [Color] = []
    var settings: [Tool: ToolSettings] = [
        .pen:    ToolSettings(colour: .black,  width: 6),
        .marker: ToolSettings(colour: .yellow, width: 18),
        .pencil: ToolSettings(colour: .gray,   width: 3),
        .eraser: ToolSettings(colour: .white,  width: 24)
    ]

    var current: ToolSettings { settings[selected]! }

    var colour: Color {
        get { settings[selected]!.colour }
        set { settings[selected]?.colour = newValue }
    }
    var width: CGFloat {
        get { settings[selected]!.width }
        set { settings[selected]?.width = newValue }
    }

    func select(_ tool: Tool) {
        guard tool != selected else { return }
        commitRecent()
        previous = selected
        selected = tool
    }

    func swapEraser() {
        select(selected == .eraser ? previous : .eraser)
    }

    func commitRecent() {
        guard selected != .eraser else { return }
        let c = colour
        guard !selected.presets.contains(c), !recents.contains(c) else { return }
        recents.insert(c, at: 0)
        recents = Array(recents.prefix(4))
    }

    func collapse() {
        commitRecent()
        showingSettings = false
        isExpanded = false
    }
}

private nonisolated enum Slot: Hashable, Sendable {
    case undo, redo, tools, colour, more
}

private enum Metrics {
    static let orb: CGFloat = 60
    static let small: CGFloat = 40
    static let toolItem: CGFloat = 40
    static let pillInset: CGFloat = 4
    static let toolsLength = CGFloat(Tool.allCases.count) * toolItem + 2 * pillInset
    static let toolsThickness = toolItem + 2 * pillInset

    static let gap: CGFloat = 8
    static let endPad: CGFloat = 10
    static let panelGap: CGFloat = 14
    static let blend: CGFloat = 14
    static let margin: CGFloat = 16
    static let panel = CGSize(width: 292, height: 176)

    static let row: [(slot: Slot, length: CGFloat, thickness: CGFloat)] = [
        (.undo, small, small),
        (.redo, small, small),
        (.tools, toolsLength, toolsThickness),
        (.colour, small, small),
        (.more, small, small)
    ]

    static let centredBefore: [Slot] = [.tools, .redo, .undo]
    static let centredAfter: [Slot] = [.colour, .more]

    static func item(_ slot: Slot) -> (slot: Slot, length: CGFloat, thickness: CGFloat) {
        row.first { $0.slot == slot }!
    }

    static func extent(_ slots: [Slot]) -> CGFloat {
        guard !slots.isEmpty else { return 0 }
        return slots.reduce(0) { $0 + gap + item($1).length } + endPad
    }
}

struct ToolPalette: View {
    @Bindable var state: ToolState
    @Binding var penOnly: Bool
    var isDrawing: Bool
    var canUndo: Bool
    var canRedo: Bool
    var onUndo: () -> Void
    var onRedo: () -> Void
    var onClear: () -> Void

    @State private var physics = OrbPhysics()
    @State private var showingMore = false
    @State private var lensDrag: CGFloat?
    @State private var panelMounted = false
    @State private var panelShown = false

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let layout = layout(for: physics.position, in: size)
            let o = state.isExpanded
                ? fitted(physics.position, size: size, layout: layout)
                : physics.position
            let dir = direction(of: o, size: size, axis: layout.axis)
            let slots = rowPositions(origin: o, layout: layout, dir: dir)
            let rect = pillRect(origin: o, layout: layout, dir: dir, expanded: state.isExpanded)

            GlassEffectContainer(spacing: Metrics.blend) {
                ZStack(alignment: .topLeading) {
                    pill(rect: rect, orbOrigin: o, slots: slots, layout: layout, dir: dir, size: size)

                    if panelMounted {
                        panel(origin: o, layout: layout, size: size, slots: slots)
                    }
                }
                .frame(width: size.width, height: size.height, alignment: .topLeading)
            }
            .onChange(of: size, initial: true) { _, new in
                physics.configure(size: new, orbSize: Metrics.orb, margin: Metrics.margin)
            }
        }
        .onChange(of: state.isExpanded) { _, expanded in
            if !expanded { showingMore = false }
        }
        .onChange(of: state.showingSettings) { _, show in
            if show {
                panelMounted = true
                panelShown = false
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(16))
                    guard state.showingSettings else { return }
                    withAnimation(.smooth(duration: 0.5)) { panelShown = true }
                }
            } else {
                withAnimation(.smooth(duration: 0.35), completionCriteria: .logicallyComplete) {
                    panelShown = false
                } completion: {
                    if !state.showingSettings { panelMounted = false }
                }
            }
        }
        .opacity(isDrawing ? 0.3 : 1)
        .animation(.smooth(duration: 0.25), value: isDrawing)
        .sensoryFeedback(.selection, trigger: state.selected)
        .sensoryFeedback(.impact(weight: .light), trigger: physics.dockCount)
    }

    private func pill(rect: CGRect, orbOrigin o: CGPoint, slots: [Slot: CGPoint],
                      layout: Layout, dir: CGFloat, size: CGSize) -> some View {
        let expanded = state.isExpanded
        let arrangement = arrangement(layout: layout, dir: dir)

        func local(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x - rect.minX, y: p.y - rect.minY) }

        func delay(_ slot: Slot) -> Double {
            let rank = (arrangement.before.firstIndex(of: slot) ?? arrangement.after.firstIndex(of: slot) ?? 0) + 1
            return 0.1 + 0.05 * Double(rank)
        }

        return ZStack(alignment: .topLeading) {
            iconButton("arrow.uturn.backward", enabled: canUndo, action: onUndo)
                .revealed(expanded, delay: delay(.undo))
                .allowsHitTesting(expanded)
                .offset(local(slots[.undo] ?? .zero))

            iconButton("arrow.uturn.forward", enabled: canRedo, action: onRedo)
                .revealed(expanded, delay: delay(.redo))
                .allowsHitTesting(expanded)
                .offset(local(slots[.redo] ?? .zero))

            toolsControl(axis: layout.axis)
                .revealed(expanded, delay: delay(.tools))
                .allowsHitTesting(expanded)
                .offset(local(slots[.tools] ?? .zero))

            colourButton
                .revealed(expanded, delay: delay(.colour))
                .allowsHitTesting(expanded)
                .offset(local(slots[.colour] ?? .zero))

            moreButton
                .revealed(expanded, delay: delay(.more))
                .allowsHitTesting(expanded)
                .offset(local(slots[.more] ?? .zero))

            orbContent(size: size, layout: layout)
                .offset(local(o))
        }
        .frame(width: rect.width, height: rect.height, alignment: .topLeading)
        .clipShape(Capsule())
        .glassEffect(
            .regular.tint(state.selected == .eraser ? nil : state.colour.opacity(expanded ? 0.08 : 0.2)),
            in: .capsule
        )
        .offset(x: rect.minX, y: rect.minY)
    }

    private func orbContent(size: CGSize, layout: Layout) -> some View {
        Image(systemName: state.selected.symbol)
            .font(.title2)
            .foregroundStyle(.primary)
            .frame(width: Metrics.orb, height: Metrics.orb)
            .overlay {
                if state.selected != .eraser {
                    Circle().strokeBorder(state.colour, lineWidth: 3).padding(6)
                }
            }
            .contentShape(Circle())
            .onTapGesture {
                withAnimation(.smooth(duration: 0.5)) {
                    if state.isExpanded { state.collapse() } else { state.isExpanded = true }
                }
            }
            .gesture(
                DragGesture(minimumDistance: 6, coordinateSpace: .global)
                    .onChanged { value in
                        if state.isExpanded {
                            physics.place(fitted(physics.position, size: size, layout: layout))
                            withAnimation(.smooth(duration: 0.3)) { state.collapse() }
                        }
                        physics.drag(translation: value.translation)
                    }
                    .onEnded { value in
                        physics.release(velocity: CGVector(dx: value.velocity.width,
                                                           dy: value.velocity.height))
                    }
            )
            .accessibilityLabel("Tools")
    }

    private func iconButton(_ symbol: String, enabled: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: Metrics.small, height: Metrics.small)
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
    }

    private var colourButton: some View {
        Button(action: toggleSettings) {
            Group {
                if state.selected == .eraser {
                    Image(systemName: "circle.dashed").font(.title3)
                } else {
                    Circle()
                        .fill(state.colour)
                        .overlay(Circle().strokeBorder(.primary.opacity(0.25), lineWidth: 1))
                        .frame(width: 24, height: 24)
                }
            }
            .frame(width: Metrics.small, height: Metrics.small)
            .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("Colour and size")
    }

    private var moreButton: some View {
        Button { showingMore.toggle() } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .frame(width: Metrics.small, height: Metrics.small)
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .popover(isPresented: $showingMore) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Stylus only", isOn: $penOnly)
                Divider()
                Button("Clear canvas", systemImage: "trash", role: .destructive) {
                    showingMore = false
                    onClear()
                }
            }
            .padding(16)
        }
        .accessibilityLabel("More")
    }

    private func toggleSettings() {
        withAnimation(.smooth(duration: 0.4)) {
            if state.showingSettings { state.commitRecent() }
            state.showingSettings.toggle()
        }
    }

    private func pillSize(_ axis: Axis) -> CGSize {
        axis == .horizontal
            ? CGSize(width: Metrics.toolsLength, height: Metrics.toolsThickness)
            : CGSize(width: Metrics.toolsThickness, height: Metrics.toolsLength)
    }

    private func toolsControl(axis: Axis) -> some View {
        let item = Metrics.toolItem
        let inset = Metrics.pillInset
        let tools = Tool.allCases
        let dims = pillSize(axis)
        let selectedIndex = CGFloat(tools.firstIndex(of: state.selected) ?? 0)
        let lensMain = lensDrag ?? selectedIndex * item

        func offset(forMain main: CGFloat) -> CGSize {
            axis == .horizontal
                ? CGSize(width: inset + main, height: inset)
                : CGSize(width: inset, height: inset + main)
        }

        return ZStack(alignment: .topLeading) {
            Capsule()
                .fill(.primary.opacity(0.08))
                .frame(width: dims.width, height: dims.height)

            Capsule()
                .fill(.primary.opacity(0.16))
                .overlay(Capsule().strokeBorder(.primary.opacity(0.2), lineWidth: 0.5))
                .frame(width: item, height: item)
                .offset(offset(forMain: lensMain))

            ForEach(Array(tools.enumerated()), id: \.element) { i, tool in
                Image(systemName: tool.symbol)
                    .font(.title3)
                    .foregroundStyle(.primary)
                    .frame(width: item, height: item)
                    .offset(offset(forMain: CGFloat(i) * item))
            }
        }
        .frame(width: dims.width, height: dims.height, alignment: .topLeading)
        .contentShape(Capsule())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let along = axis == .horizontal ? value.location.x : value.location.y
                    let maxMain = CGFloat(tools.count - 1) * item
                    let main = min(max(along - inset - item / 2, 0), maxMain)
                    withAnimation(.interactiveSpring) { lensDrag = main }
                    let tool = tools[Int((main / item).rounded())]
                    if tool != state.selected { state.select(tool) }
                }
                .onEnded { _ in
                    withAnimation(.smooth(duration: 0.35)) { lensDrag = nil }
                }
        )
        .accessibilityElement()
        .accessibilityLabel("Tool")
        .accessibilityValue(state.selected.label)
        .accessibilityAdjustableAction { direction in
            let all = Tool.allCases
            guard let i = all.firstIndex(of: state.selected) else { return }
            switch direction {
            case .increment: state.select(all[min(i + 1, all.count - 1)])
            case .decrement: state.select(all[max(i - 1, 0)])
            @unknown default: break
            }
        }
    }

    private func panel(origin o: CGPoint, layout: Layout, size: CGSize, slots: [Slot: CGPoint]) -> some View {
        let colourSlot = slots[.colour] ?? .zero
        let colourRect = CGRect(x: colourSlot.x, y: colourSlot.y, width: Metrics.small, height: Metrics.small)
        let orbRect = CGRect(x: o.x, y: o.y, width: Metrics.orb, height: Metrics.orb)
        let full = CGRect(origin: panelPosition(origin: o, layout: layout, size: size, colour: colourSlot),
                          size: Metrics.panel)

        let r = panelShown ? full : (state.isExpanded ? colourRect : orbRect)
        let corner: CGFloat = panelShown ? 30 : min(r.width, r.height) / 2

        return settingsContent
            .revealed(panelShown, delay: 0.18)
            .padding(16)
            .frame(width: Metrics.panel.width, height: Metrics.panel.height)
            .frame(width: r.width, height: r.height)
            .clipShape(RoundedRectangle(cornerRadius: corner))
            .glassEffect(.regular, in: .rect(cornerRadius: corner))
            .offset(x: r.minX, y: r.minY)
    }

    private var settingsContent: some View {
        VStack(spacing: 14) {
            if state.selected != .eraser {
                HStack(spacing: 10) {
                    ForEach(state.selected.presets, id: \.self) { swatch($0) }
                }
                HStack(spacing: 10) {
                    ForEach(state.recents, id: \.self) { swatch($0) }
                    ColorPicker("Custom colour", selection: $state.colour, supportsOpacity: false)
                        .labelsHidden()
                        .frame(width: 30, height: 30)
                }
            }

            HStack(spacing: 12) {
                Circle()
                    .fill(state.selected == .eraser ? Color.primary.opacity(0.2) : state.colour)
                    .frame(width: min(state.width, 44), height: min(state.width, 44))
                    .frame(width: 44, height: 44)
                Slider(value: $state.width, in: state.selected.widthRange)
            }
        }
    }

    private func swatch(_ colour: Color) -> some View {
        Button {
            state.colour = colour
        } label: {
            Circle()
                .fill(colour)
                .frame(width: 26, height: 26)
                .overlay(Circle().strokeBorder(.primary.opacity(0.2), lineWidth: 1))
                .padding(3)
                .overlay {
                    if state.colour == colour {
                        Circle().strokeBorder(.primary, lineWidth: 2)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private struct Layout {
        var axis: Axis
        var centred: Bool
    }

    private func layout(for origin: CGPoint, in size: CGSize) -> Layout {
        let cx = origin.x + Metrics.orb / 2
        let cy = origin.y + Metrics.orb / 2
        let midY = abs(cy - size.height / 2) < size.height * 0.15
        let midX = abs(cx - size.width / 2) < size.width * 0.15
        if midY { return Layout(axis: .vertical, centred: true) }
        if midX { return Layout(axis: .horizontal, centred: true) }
        return Layout(axis: size.width < 640 ? .vertical : .horizontal, centred: false)
    }

    private func clampOrb(_ p: CGPoint, size: CGSize) -> CGPoint {
        CGPoint(x: min(max(p.x, Metrics.margin), max(size.width - Metrics.orb - Metrics.margin, Metrics.margin)),
                y: min(max(p.y, Metrics.margin), max(size.height - Metrics.orb - Metrics.margin, Metrics.margin)))
    }

    private func direction(of o: CGPoint, size: CGSize, axis: Axis) -> CGFloat {
        let main = axis == .horizontal ? o.x : o.y
        let container = axis == .horizontal ? size.width : size.height
        return main + Metrics.orb / 2 < container / 2 ? 1 : -1
    }

    private func arrangement(layout: Layout, dir: CGFloat) -> (before: [Slot], after: [Slot]) {
        if layout.centred { return (Metrics.centredBefore, Metrics.centredAfter) }
        let all = Metrics.row.map(\.slot)
        return dir > 0 ? ([], all) : (all, [])
    }

    private func extent(layout: Layout, dir: CGFloat) -> (lead: CGFloat, trail: CGFloat) {
        let a = arrangement(layout: layout, dir: dir)
        return (Metrics.extent(a.before), Metrics.extent(a.after))
    }

    private func fitted(_ o: CGPoint, size: CGSize, layout: Layout) -> CGPoint {
        let axis = layout.axis
        let dir = direction(of: o, size: size, axis: axis)
        let reach = extent(layout: layout, dir: dir)
        let container = axis == .horizontal ? size.width : size.height
        var main = axis == .horizontal ? o.x : o.y

        let lo = Metrics.margin + reach.lead
        let hi = max(container - Metrics.margin - Metrics.orb - reach.trail, lo)
        main = min(max(main, lo), hi)

        let moved = axis == .horizontal ? CGPoint(x: main, y: o.y) : CGPoint(x: o.x, y: main)
        return clampOrb(moved, size: size)
    }

    private func pillRect(origin o: CGPoint, layout: Layout, dir: CGFloat, expanded: Bool) -> CGRect {
        let orb = Metrics.orb
        guard expanded else { return CGRect(x: o.x, y: o.y, width: orb, height: orb) }

        let reach = extent(layout: layout, dir: dir)
        let length = reach.lead + orb + reach.trail
        return layout.axis == .horizontal
            ? CGRect(x: o.x - reach.lead, y: o.y, width: length, height: orb)
            : CGRect(x: o.x, y: o.y - reach.lead, width: orb, height: length)
    }

    private func rowPositions(origin o: CGPoint, layout: Layout, dir: CGFloat) -> [Slot: CGPoint] {
        let axis = layout.axis
        let orbMain = axis == .horizontal ? o.x : o.y
        let orbCross = axis == .horizontal ? o.y : o.x
        let (before, after) = arrangement(layout: layout, dir: dir)

        var result: [Slot: CGPoint] = [:]

        func point(main: CGFloat, thickness: CGFloat) -> CGPoint {
            let cross = orbCross + (Metrics.orb - thickness) / 2
            return axis == .horizontal ? CGPoint(x: main, y: cross) : CGPoint(x: cross, y: main)
        }

        var cursor = Metrics.gap
        for slot in before {
            let item = Metrics.item(slot)
            result[slot] = point(main: orbMain - cursor - item.length, thickness: item.thickness)
            cursor += item.length + Metrics.gap
        }

        cursor = Metrics.orb + Metrics.gap
        for slot in after {
            let item = Metrics.item(slot)
            result[slot] = point(main: orbMain + cursor, thickness: item.thickness)
            cursor += item.length + Metrics.gap
        }
        return result
    }

    private func panelPosition(origin o: CGPoint, layout: Layout, size: CGSize, colour: CGPoint) -> CGPoint {
        let axis = layout.axis
        let p = Metrics.panel
        let mainLen = axis == .horizontal ? p.width : p.height
        let crossLen = axis == .horizontal ? p.height : p.width
        let containerMain = axis == .horizontal ? size.width : size.height
        let containerCross = axis == .horizontal ? size.height : size.width
        let colourMain = (axis == .horizontal ? colour.x : colour.y) + Metrics.small / 2
        let orbCross = axis == .horizontal ? o.y : o.x

        var main = colourMain - mainLen / 2
        main = min(max(main, Metrics.margin), max(containerMain - Metrics.margin - mainLen, Metrics.margin))

        let roomAfter = containerCross - (orbCross + Metrics.orb)
        var cross = roomAfter >= orbCross
            ? orbCross + Metrics.orb + Metrics.panelGap
            : orbCross - Metrics.panelGap - crossLen
        cross = min(max(cross, Metrics.margin), max(containerCross - Metrics.margin - crossLen, Metrics.margin))

        return axis == .horizontal ? CGPoint(x: main, y: cross) : CGPoint(x: cross, y: main)
    }
}

private struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.5 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

private extension View {
    func offset(_ p: CGPoint) -> some View { offset(x: p.x, y: p.y) }

    func revealed(_ shown: Bool, delay: Double) -> some View {
        opacity(shown ? 1 : 0)
            .animation(shown ? .easeOut(duration: 0.22).delay(delay) : .easeIn(duration: 0.1), value: shown)
    }
}
