//
//  MainMenuScene.swift
//  Cuberis
//

import SpriteKit

enum MainMenuOption {
   case start
   case setup
}

func createButton(title: String) -> ButtonNode {
    let button = ButtonNode(buttonImageName: "GreenButton", title: title)
    button.fontName = "GillSans-Light"
    button.fontColor = .black
    button.fontSize = 26
    return button
}

class MainMenuScene: SKScene {
    var animatedAppearance = false
    var completion: ((MainMenuOption) -> Void)?

    let panel = SKSpriteNode(texture: SKTexture(imageNamed: "Panel"))
    let startButton = createButton(title: "START")
    let setupButton = createButton(title: "SETUP")
    let speedControl: NumericUpDownNode

    override init(size: CGSize) {
        speedControl = NumericUpDownNode(label: "Speed:", value: 3, range: 1...10)
        super.init(size: size)
        addChild(panel)
        panel.addChild(speedControl)
        startButton.action = { [unowned self] in self.completion?(.start) }
        panel.addChild(startButton)
        setupButton.action = { [unowned self] in self.completion?(.setup) }
        panel.addChild(setupButton)

        setupPickerFont(control: speedControl)

        let spacing: CGFloat = 20
        let anchor = CGPoint(0, panel.size.midH - (startButton.size.midH + spacing))
        let step = -(startButton.size.height + spacing)
        startButton.position = anchor + CGPoint(0, 0 * step)
        setupButton.position = anchor + CGPoint(0, 1 * step)
        speedControl.position = anchor + CGPoint(0, 2 * step)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func layoutSubnodes() {
        panel.position = CGPoint(safeAreaInsets.left + panel.size.midW + 10, frame.midY)
    }

    override func didMove(to view: SKView) {
        layoutSubnodes()
        if animatedAppearance {
            alpha = 0.0
            run(SKAction.fadeIn(withDuration: SceneConstants.scenePresentDuration * 2))
        } else {
            alpha = 1.0
        }
    }
}
