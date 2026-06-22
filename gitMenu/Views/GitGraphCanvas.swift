import SwiftUI

struct GitGraphCanvas: View {
    let commits: [GitCommit]
    let workingTreeStatus: WorkingTreeStatus?
    let rowHeight: CGFloat

    private let laneSpacing: CGFloat = 24
    private let lineWidth: CGFloat = 3
    private let dotRadius: CGFloat = 5.5
    private let dashedLinePattern: [CGFloat] = [5, 4]

    var body: some View {
        Canvas { context, size in
            drawGraphTopology(in: &context)
            drawCommitDots(in: &context)
        }
    }

    private func laneX(for index: Int) -> CGFloat {
        20 + (CGFloat(index) * laneSpacing)
    }

    private func graphColumnX(for characterOffset: Int) -> CGFloat {
        laneX(for: 0) + (CGFloat(characterOffset) * laneSpacing * 0.5)
    }

    private func rowCenterY(for index: Int) -> CGFloat {
        (CGFloat(index) * rowHeight) + (rowHeight * 0.5)
    }

    private var commitRowOffset: Int {
        workingTreeStatus == nil ? 0 : 1
    }

    private func commitPoint(for commit: GitCommit, at index: Int) -> CGPoint {
        let starOffset = commit.graphPrefix.firstIndex(of: "*")
            .map { commit.graphPrefix.distance(from: commit.graphPrefix.startIndex, to: $0) }

        return CGPoint(
            x: starOffset.map(graphColumnX(for:)) ?? laneX(for: commit.lane),
            y: rowCenterY(for: index + commitRowOffset)
        )
    }

    private func drawGraphTopology(in context: inout GraphicsContext) {
        if workingTreeStatus != nil {
            drawWorkingTreeTopology(in: &context)
        }

        guard !commits.isEmpty else { return }

        let lines = graphLines()
        guard !lines.isEmpty else { return }

        for index in lines.indices {
            let line = lines[index]
            let topY = index == lines.startIndex
                ? line.y
                : (lines[index - 1].y + line.y) * 0.5
            let bottomY = index == lines.index(before: lines.endIndex)
                ? line.y
                : (line.y + lines[index + 1].y) * 0.5

            for (offset, character) in line.prefix.enumerated() {
                switch character {
                case "|":
                    drawVertical(
                        atX: graphColumnX(for: offset),
                        from: topY,
                        to: bottomY,
                        color: line.color(at: offset),
                        in: &context
                    )
                case "*":
                    let hasIncomingPath = index > lines.startIndex
                        && lines[index - 1].bottomEndpointOffsets.contains(offset)
                    let hasOutgoingPath = index < lines.index(before: lines.endIndex)
                        && lines[index + 1].topEndpointOffsets.contains(offset)

                    drawVertical(
                        atX: graphColumnX(for: offset),
                        from: hasIncomingPath ? topY : line.y,
                        to: hasOutgoingPath ? bottomY : line.y,
                        color: line.color(at: offset),
                        in: &context
                    )
                case "/":
                    drawDiagonal(
                        from: CGPoint(x: graphColumnX(for: offset + 1), y: topY),
                        to: CGPoint(x: graphColumnX(for: max(offset - 1, 0)), y: bottomY),
                        color: line.color(at: offset),
                        in: &context
                    )
                case "\\":
                    drawDiagonal(
                        from: CGPoint(x: graphColumnX(for: max(offset - 1, 0)), y: topY),
                        to: CGPoint(x: graphColumnX(for: offset + 1), y: bottomY),
                        color: line.color(at: offset),
                        in: &context
                    )
                case "_", "-":
                    var path = Path()
                    path.move(to: CGPoint(x: graphColumnX(for: offset) - (laneSpacing * 0.5), y: line.y))
                    path.addLine(to: CGPoint(x: graphColumnX(for: offset) + (laneSpacing * 0.5), y: line.y))
                    context.stroke(
                        path,
                        with: .color(line.color(at: offset)),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                default:
                    continue
                }
            }
        }
    }

    private func drawWorkingTreeTopology(in context: inout GraphicsContext) {
        guard let firstCommit = commits.first else { return }

        let topCenterY = rowCenterY(for: 0)
        let firstCommitCenterY = rowCenterY(for: commitRowOffset)
        let x = commitPoint(for: firstCommit, at: 0).x

        drawVertical(
            atX: x,
            from: topCenterY,
            to: firstCommitCenterY,
            color: GitLaneColor.slate.color,
            dash: dashedLinePattern,
            in: &context
        )
    }

    private func drawVertical(
        atX x: CGFloat,
        from topY: CGFloat,
        to bottomY: CGFloat,
        color: Color,
        dash: [CGFloat] = [],
        in context: inout GraphicsContext
    ) {
        guard bottomY > topY else { return }

        var path = Path()
        path.move(to: CGPoint(x: x, y: topY))
        path.addLine(to: CGPoint(x: x, y: bottomY))
        context.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: dash)
        )
    }

    private func drawDiagonal(
        from start: CGPoint,
        to end: CGPoint,
        color: Color,
        in context: inout GraphicsContext
    ) {
        guard end.y > start.y else { return }

        let controlDistance = max((end.y - start.y) * 0.42, 1)
        var path = Path()
        path.move(to: start)
        path.addCurve(
            to: end,
            control1: CGPoint(x: start.x, y: start.y + controlDistance),
            control2: CGPoint(x: end.x, y: end.y - controlDistance)
        )
        context.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        )
    }

    private func drawCommitDots(in context: inout GraphicsContext) {
        let commitLines = Dictionary(
            uniqueKeysWithValues: graphLines().compactMap { line in
                line.commitIndex.map { ($0, line) }
            }
        )

        if workingTreeStatus != nil, let firstCommit = commits.first {
            let center = CGPoint(
                x: commitPoint(for: firstCommit, at: 0).x,
                y: rowCenterY(for: 0)
            )
            let dot = Path(ellipseIn: CGRect(
                x: center.x - dotRadius,
                y: center.y - dotRadius,
                width: dotRadius * 2,
                height: dotRadius * 2
            ))

            context.fill(dot, with: .color(Color(nsColor: .windowBackgroundColor)))
            context.stroke(
                dot,
                with: .color(GitLaneColor.slate.color),
                style: StrokeStyle(lineWidth: 2, dash: [3, 2])
            )
        }

        for (index, commit) in commits.enumerated() {
            let starOffset = commit.graphPrefix.firstIndex(of: "*")
                .map { commit.graphPrefix.distance(from: commit.graphPrefix.startIndex, to: $0) }
            let center = commitPoint(for: commit, at: index)
            let dot = Path(ellipseIn: CGRect(
                x: center.x - dotRadius,
                y: center.y - dotRadius,
                width: dotRadius * 2,
                height: dotRadius * 2
            ))

            let color = starOffset
                .flatMap { commitLines[index]?.laneColor(at: $0) }?
                .color ?? GitLaneColor.main.color
            context.fill(dot, with: .color(color.opacity(0.95)))
            context.stroke(dot, with: .color(.black.opacity(0.55)), lineWidth: 1.2)
        }
    }

    private func laneColor(for laneIndex: Int) -> Color {
        GitLaneColor.allCases[laneIndex % GitLaneColor.allCases.count].color
    }

    private func graphLines() -> [GraphLine] {
        var rawLines: [GraphLine] = []

        for index in commits.indices {
            let commit = commits[index]
            let commitCenterY = rowCenterY(for: index + commitRowOffset)
            rawLines.append(GraphLine(prefix: commit.graphPrefix, y: commitCenterY, commitIndex: index))

            guard index < commits.count - 1 else { continue }

            let nextCommitCenterY = rowCenterY(for: index + 1 + commitRowOffset)
            let connectorPrefixes = commit.connectorPrefixesAfter

            guard !connectorPrefixes.isEmpty else { continue }

            let step = (nextCommitCenterY - commitCenterY) / CGFloat(connectorPrefixes.count + 1)
            for (connectorIndex, prefix) in connectorPrefixes.enumerated() {
                let y = commitCenterY + (CGFloat(connectorIndex + 1) * step)
                rawLines.append(GraphLine(prefix: prefix, y: y))
            }
        }

        return colorized(rawLines)
    }

    private func colorized(_ lines: [GraphLine]) -> [GraphLine] {
        var activeColors: [GitLaneColor] = []
        var nextColorIndex = 0
        var result: [GraphLine] = []

        func nextColor() -> GitLaneColor {
            defer { nextColorIndex += 1 }
            return GitLaneColor.allCases[nextColorIndex % GitLaneColor.allCases.count]
        }

        func ensureLane(_ lane: Int) {
            while activeColors.count <= lane {
                activeColors.append(nextColor())
            }
        }

        for line in lines {
            let characters = Array(line.prefix)
            var colorsByOffset: [Int: GitLaneColor] = [:]

            for (offset, character) in characters.enumerated()
            where offset.isMultiple(of: 2) && (character == "|" || character == "*") {
                let lane = offset / 2
                ensureLane(lane)
                colorsByOffset[offset] = activeColors[lane]
            }

            for (offset, character) in characters.enumerated() {
                guard character == "\\" || character == "/" else { continue }

                if character == "\\" {
                    let sourceLane = max((offset - 1) / 2, 0)
                    ensureLane(sourceLane)
                    let newColor = nextColor()
                    colorsByOffset[offset] = newColor
                    activeColors.insert(newColor, at: min(sourceLane + 1, activeColors.count))
                } else {
                    let sourceLane = max((offset + 1) / 2, 0)
                    ensureLane(sourceLane)
                    colorsByOffset[offset] = activeColors[sourceLane]
                    activeColors.remove(at: sourceLane)
                }
            }

            for (offset, character) in characters.enumerated()
            where character == "_" || character == "-" {
                let lane = max(Int(round(Double(offset) / 2.0)), 0)
                ensureLane(lane)
                colorsByOffset[offset] = activeColors[lane]
            }

            result.append(line.with(colorsByOffset: colorsByOffset))
        }

        return result
    }
}

private struct GraphLine {
    let prefix: String
    let y: CGFloat
    let commitIndex: Int?
    let colorsByOffset: [Int: GitLaneColor]

    init(
        prefix: String,
        y: CGFloat,
        commitIndex: Int? = nil,
        colorsByOffset: [Int: GitLaneColor] = [:]
    ) {
        self.prefix = prefix
        self.y = y
        self.commitIndex = commitIndex
        self.colorsByOffset = colorsByOffset
    }

    func color(at offset: Int) -> Color {
        laneColor(at: offset)?.color ?? GitLaneColor.main.color
    }

    func laneColor(at offset: Int) -> GitLaneColor? {
        colorsByOffset[offset]
    }

    func with(colorsByOffset: [Int: GitLaneColor]) -> GraphLine {
        GraphLine(
            prefix: prefix,
            y: y,
            commitIndex: commitIndex,
            colorsByOffset: colorsByOffset
        )
    }

    var topEndpointOffsets: Set<Int> {
        endpointOffsets(atTop: true)
    }

    var bottomEndpointOffsets: Set<Int> {
        endpointOffsets(atTop: false)
    }

    private func endpointOffsets(atTop: Bool) -> Set<Int> {
        var offsets: Set<Int> = []

        for (offset, character) in prefix.enumerated() {
            switch character {
            case "|", "*":
                offsets.insert(offset)
            case "/":
                offsets.insert(atTop ? offset + 1 : max(offset - 1, 0))
            case "\\":
                offsets.insert(atTop ? max(offset - 1, 0) : offset + 1)
            case "_", "-":
                offsets.insert(offset - 1)
                offsets.insert(offset + 1)
            default:
                continue
            }
        }

        return offsets
    }
}
