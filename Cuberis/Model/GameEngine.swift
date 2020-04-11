//
//  GameEngine.swift
//  Cuberis
//

import SceneKit

protocol GameEngineDelegate: AnyObject {
    func didSpawnNew(polycube: Polycube, at position: Vector3i, rotated rotation: SCNMatrix4)
    func didMove(by delta: Vector3i, andRotateBy rotationDelta: SCNMatrix4)
    func didUpdateContent(of pit: Pit)
    func levelDidChanged(to level: Int)
    func collision(at cells: [Vector3i], afterMoveBy delta: Vector3i, andRotate rotation: SCNMatrix4)
    func gameOver()
}

extension GameEngineDelegate {
    func didSpawnNew(polycube: Polycube, at position: Vector3i, rotated rotation: SCNMatrix4) {}
    func didMove(by delta: Vector3i, andRotateBy rotationDelta: SCNMatrix4) {}
    func levelDidChanged(to level: Int) {}
    func didUpdateContent(of pit: Pit) {}
    func collision(at cells: [Vector3i], afterMoveBy delta: Vector3i, andRotate rotation: SCNMatrix4) {}
    func gameOver() {}
}

class GameEngine {
    let polycubeSet: PolycubeSet
    var statistics: Statistics
    let maxLevel = 9                            // TODO: Extract to separete class 
    let timeBase: TimeInterval = 2051.0         // Step Time base (seconds)
    let timeLevelFactor = 0.64
    var stepTime: TimeInterval
    let cubesPerLevel: Int
    var level: Int
    var dropPos = 0

    var pit: Pit
    var polycubeCount = 0
    let allPolycubes: [Polycube]
    let currentSet: [Polycube]
    var currentPolycube: Polycube?
    var position = Vector3i()
    var rotation = SCNMatrix4Identity
    var isDropHappened = false
    weak var delegate: GameEngineDelegate?

    init(pitSize: Size3i, polycubeSet: PolycubeSet, level: Int) {
        self.polycubeSet = polycubeSet
        self.level = min(level, maxLevel)
        statistics = Statistics(polycubeSet: polycubeSet, pitDepth: pitSize.depth)
        stepTime = timeBase * pow(timeLevelFactor, Double(self.level))
        cubesPerLevel = pitSize.height * 15 + pitSize.width * 15

        pit = Pit(size: pitSize)
        let url = Bundle.main.resourceURL!.appendingPathComponent("polycubes.json")
        allPolycubes = loadPolycubes(from: url)
        currentSet = allPolycubes.filter { $0.info.basic || $0.info.flat }
        srand48(Int(Date().timeIntervalSince1970))
    }

    func gameOver() {
        delegate?.gameOver()
    }

    func scheduleStepTimer(afterDrop: Bool) {
        let interval: TimeInterval = afterDrop ? 0.6 : 2.0
        let number = polycubeCount
        Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            guard let self = self, number == self.polycubeCount else { return }
            if self.isDropHappened && !afterDrop { return }
            self.isDropHappened = false
            self.step()
        }
    }

    func start() {
    }

    func newPolycube() {
        let polycube = currentSet[Int(drand48() * Double(currentSet.count))]
        position = Vector3i()
        currentPolycube = polycube
        rotation = SCNMatrix4Identity
        delegate?.didSpawnNew(polycube: polycube, at: position, rotated: rotation)
        if isOverlapped(afterRotation: rotation, andTranslation: position) {
            gameOver()
            return
        }
        polycubeCount += 1
        isDropHappened = false
        dropPos = pit.depth - 1
        scheduleStepTimer(afterDrop: false)
    }

    func isOverlapped(afterRotation rotation: SCNMatrix4, andTranslation translation: Vector3i) -> Bool {
        return !overlap(afterRotation: rotation, andTranslation: translation).cells.isEmpty
    }

    func overlap(afterRotation newRotation: SCNMatrix4,
                 andTranslation newTranslation: Vector3i) -> (cells: [Vector3i], excess: Vector3i) {
        var excess = Vector3i()
        var cells = [Vector3i]()
        guard let polycube = currentPolycube else { return (cells: [], excess: Vector3i()) }
        for cell in polycube.cubes(afterRotation: newRotation, andTranslation: newTranslation) {
            if !pit.includes(cell: cell) || pit.isOccupied(at: cell) { cells.append(cell) }
            let cellExcess = pit.excess(of: cell)
            if abs(cellExcess.x) > abs(excess.x) { excess.x = cellExcess.x }
            if abs(cellExcess.y) > abs(excess.y) { excess.y = cellExcess.y }
            if abs(cellExcess.z) > abs(excess.z) { excess.z = cellExcess.z }
        }
        return (cells: cells, excess: excess)
    }

    func move(by delta: Vector3i) {
        let newPosition = position + delta
        if !isOverlapped(afterRotation: rotation, andTranslation: newPosition) {
            position = newPosition
            delegate?.didMove(by: delta, andRotateBy: SCNMatrix4Identity)
        }
    }

    func rotate(by rotationDelta: SCNMatrix4) {
        let newRotation = (rotation.transposed() * rotationDelta).transposed()
        let overlap = self.overlap(afterRotation: newRotation, andTranslation: position)
        if !overlap.cells.isEmpty {
            let overlapAfterCorrection = self.overlap(afterRotation: newRotation,
                                                      andTranslation: position + overlap.excess)
            if !overlapAfterCorrection.cells.isEmpty {
                delegate?.collision(at: overlapAfterCorrection.cells,
                                    afterMoveBy: overlap.excess,
                                    andRotate: newRotation)
            } else {
                let newPosition = position + overlap.excess
                rotation = newRotation
                position = newPosition
                delegate?.didMove(by: overlap.excess, andRotateBy: rotationDelta)
            }
        } else {
            rotation = newRotation
            delegate?.didMove(by: Vector3i(), andRotateBy: rotationDelta)
        }
    }

    func moveDeep() {
        if isDropHappened { return }
        var probe = position
        let delta = Vector3i(0, 0, -1)
        while !isOverlapped(afterRotation: rotation, andTranslation: probe + delta) { probe += delta }
        isDropHappened = true
        move(by: probe - position)
        scheduleStepTimer(afterDrop: true)
    }

    func step() {
        guard let polycube = currentPolycube else { fatalError("Current polycube fucked up") }
        let delta = Vector3i(0, 0, -1)
        dropPos -= 1
        if isOverlapped(afterRotation: rotation, andTranslation: position + delta) {
            pit.add(cubes: polycube.cubes(afterRotation: rotation, andTranslation: position))
            let removeResult = pit.removeLayers()
            delegate?.didUpdateContent(of: pit)
            statistics.accountScores(for: polycube,
                                     onLevel: level,
                                     layersRemoved: removeResult.layers,
                                     isPitEmpty: removeResult.isPitEmpty,
                                     droppedFrom: isDropHappened ? dropPos : nil)
            if level <= maxLevel {
                if statistics.cubesPlayed >= cubesPerLevel * (level + 1) {
                    level += 1
                    delegate?.levelDidChanged(to: level)
                    stepTime *= timeLevelFactor
                }
            }
            newPolycube()
        } else {
            move(by: delta)
            scheduleStepTimer(afterDrop: false)
        }
    }
}

extension GameEngine: GamepadProtocol {
    func rotateXClockwise() { rotate(by: SCNMatrix4MakeRotation(Float.pi / 2.0, -1.0, 0.0, 0.0)) }
    func rotateXCounterclockwise() { rotate(by: SCNMatrix4MakeRotation(Float.pi / 2.0, 1.0, 0.0, 0.0)) }
    func rotateYClockwise() { rotate(by: SCNMatrix4MakeRotation(Float.pi / 2.0, 0.0, -1.0, 0.0)) }
    func rotateYCounterclockwise() { rotate(by: SCNMatrix4MakeRotation(Float.pi / 2.0, 0.0, 1.0, 0.0)) }
    func rotateZClockwise() { rotate(by: SCNMatrix4MakeRotation(Float.pi / 2.0, 0.0, 0.0, -1.0)) }
    func rotateZCounterclockwise() { rotate(by: SCNMatrix4MakeRotation(Float.pi / 2.0, 0.0, 0.0, 1.0)) }
    func moveUp() { move(by: Vector3i(x: 0, y: 1, z: 0)) }
    func moveDown() { move(by: Vector3i(x: 0, y: -1, z: 0)) }
    func moveLeft() { move(by: Vector3i(x: -1, y: 0, z: 0)) }
    func moveRight() { move(by: Vector3i(x: 1, y: 0, z: 0)) }
    func drop() { moveDeep() }
}
