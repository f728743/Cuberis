//
//  Game.swift
//  Cuberis
//

import SceneKit

protocol GameDelegate: AnyObject {
    func didSpawnNew(polycube: Polycube, at position: Vector3i, rotated rotation: SCNMatrix4)
    func didMove(by delta: Vector3i, andRotateBy rotationDelta: SCNMatrix4)
    func collision(at cells: [Vector3i], afterMoveBy delta: Vector3i, andRotate rotation: SCNMatrix4)
    func didUpdateCells(of pit: Pit)
    func gameOver()
}

extension GameDelegate {
    func didSpawnNew(polycube: Polycube, at position: Vector3i, rotated rotation: SCNMatrix4) {}
    func didMove(by delta: Vector3i, andRotateBy rotationDelta: SCNMatrix4) {}
    func collision(at cells: [Vector3i], afterMoveBy delta: Vector3i, andRotate rotation: SCNMatrix4) {}
    func didUpdateCells(of pit: Pit) {}
    func gameOver() {}
}

class Game {
    var pit = Pit(width: 5, height: 5, depth: 12)
    var polycubeCount = 0
    let allPolycubes: [Polycube]
    let currentSet: [Polycube]
    var currentPolycube: Polycube?
    var position = Vector3i()
    var rotation = SCNMatrix4Identity
    var isDropHappened = false
    weak var delegate: GameDelegate?

    init() {
        let url = Bundle.main.resourceURL!.appendingPathComponent("polycubes.json")
        allPolycubes = loadPolycubes(from: url)
        currentSet = allPolycubes.filter { $0.info.basic || $0.info.flat }
        srand48(Int(Date().timeIntervalSince1970))
    }

    func gameOver() {
        delegate?.gameOver()
    }

    func scheduleStepTimer(afterDrop: Bool) {
        let interval: TimeInterval = afterDrop ? 0.5 : 2.0
        let number = polycubeCount
        Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _  in
            guard number == self.polycubeCount else { return }
            if self.isDropHappened && !afterDrop { return }
            self.isDropHappened = false
            self.step()
        }
    }

    func newPolycube() {
        let polycube = currentSet[Int(drand48() * Double(currentSet.count))]
        position = Vector3i(pit.width - polycube.width, 0, 0)
        currentPolycube = polycube
        rotation = SCNMatrix4Identity
        delegate?.didSpawnNew(polycube: polycube, at: position, rotated: rotation)
        if isOverlapped(afterRotation: rotation, andTranslation: position) {
            gameOver()
            return
        }
        polycubeCount += 1
        isDropHappened = false
        scheduleStepTimer(afterDrop: false)
    }

    func isOverlapped(afterRotation rotation: SCNMatrix4, andTranslation translation: Vector3i) -> Bool {
        return !overlap(afterRotation: rotation, andTranslation: translation).cells.isEmpty
    }

    func overlap(afterRotation newRotation: SCNMatrix4,
                 andTranslation newTranslation: Vector3i) -> (cells: [Vector3i], excess: Vector3i) {
        var excess = Vector3i()
        var cells = [Vector3i]()
        guard let polycube = currentPolycube else {
            return (cells: [], excess: Vector3i())
        }
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
        while !isOverlapped(afterRotation: rotation, andTranslation: probe + Vector3i(0, 0, 1)) { probe.z += 1 }
        isDropHappened = true
        move(by: probe - position)
        scheduleStepTimer(afterDrop: true)
    }

    func step() {
        guard let polycube = currentPolycube else { fatalError("Current polycube fucked up") }
        let delta = Vector3i(0, 0, 1)
        if isOverlapped(afterRotation: rotation, andTranslation: position + delta) {
            pit.add(cubes: polycube.cubes(afterRotation: rotation, andTranslation: position))
            let lines = pit.removeLayers()
            delegate?.didUpdateCells(of: pit)
            accountScores(for: polycube, linesRemoved: lines)
            newPolycube()
        } else {
            move(by: delta)
            scheduleStepTimer(afterDrop: false)
        }
    }

    func accountScores(for polycube: Polycube, linesRemoved: Int) {
        print("Plus \(polycube.info.lowScore) - \(polycube.info.highScore) points")
    }
}

extension Game: GamepadProtocol {
    func rotateXClockwise() { rotate(by: SCNMatrix4MakeRotation(Float.pi / 2.0, 1.0, 0.0, 0.0)) }
    func rotateXCounterclockwise() { rotate(by: SCNMatrix4MakeRotation(Float.pi / 2.0, -1.0, 0.0, 0.0)) }
    func rotateYClockwise() { rotate(by: SCNMatrix4MakeRotation(Float.pi / 2.0, 0.0, -1.0, 0.0)) }
    func rotateYCounterclockwise() { rotate(by: SCNMatrix4MakeRotation(Float.pi / 2.0, 0.0, 1.0, 0.0)) }
    func rotateZClockwise() { rotate(by: SCNMatrix4MakeRotation(Float.pi / 2.0, 0.0, 0.0, 1.0)) }
    func rotateZCounterclockwise() { rotate(by: SCNMatrix4MakeRotation(Float.pi / 2.0, 0.0, 0.0, -1.0)) }
    func moveUp() { move(by: Vector3i(x: 0, y: 1, z: 0)) }
    func moveDown() { move(by: Vector3i(x: 0, y: -1, z: 0)) }
    func moveLeft() { move(by: Vector3i(x: 1, y: 0, z: 0)) }
    func moveRight() { move(by: Vector3i(x: -1, y: 0, z: 0)) }
    func drop() { moveDeep() }
}
