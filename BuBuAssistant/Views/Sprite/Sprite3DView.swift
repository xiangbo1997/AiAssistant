//
//  Sprite3DView.swift
//  BuBuAssistant
//
//  Created by Claude Code on 2026-01-02.
//  3D 精灵视图 - 使用 SceneKit 渲染 3D 模型
//

import SwiftUI
import SceneKit

// MARK: - SceneKit 视图包装器

struct SceneKitView: NSViewRepresentable {
    @ObservedObject var viewModel: SpriteViewModel
    var animationState: SpriteAnimationState
    var facingDirection: CGFloat
    /// 点击未命中角色部位时的回落行为（由外层注入：取词/打开面板）
    var onBackgroundTap: (() -> Void)? = nil
    var onBodyPartTap: ((SpriteBodyPart) -> Void)? = nil
    var onDoubleTap: (() -> Void)? = nil

    func makeNSView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.scene = context.coordinator.scene
        scnView.allowsCameraControl = false
        scnView.autoenablesDefaultLighting = false
        // 4X 多重采样让软胶造型的曲面边缘更平滑（精灵尺寸小，开销可控）
        scnView.antialiasingMode = .multisampling4X

        // 完全透明背景：仅设 backgroundColor 不够，必须显式声明图层非不透明，
        // 否则 SCNView 会渲染出一块不透明的深色矩形背景
        scnView.backgroundColor = .clear
        scnView.wantsLayer = true
        scnView.layer?.isOpaque = false
        scnView.layer?.backgroundColor = NSColor.clear.cgColor

        // 性能：精灵是小尺寸待机动画，30fps 足够流畅，可显著降低 GPU 占用
        scnView.preferredFramesPerSecond = 30

        // 部位点击互动：命中检测由 Coordinator 处理（点头歪头、点耳抖耳、点肚子弹一弹…），
        // 未命中角色时回落到原有的单击行为（取词/打开面板）
        let click = SceneSingleClickGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleSceneClick(_:))
        )
        click.numberOfClicksRequired = 1
        click.delaysPrimaryMouseButtonEvents = false  // 不拦截按下事件，保持窗口可拖动

        let doubleClick = NSClickGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleSceneDoubleClick(_:))
        )
        doubleClick.numberOfClicksRequired = 2
        doubleClick.delaysPrimaryMouseButtonEvents = false
        scnView.addGestureRecognizer(doubleClick)
        scnView.addGestureRecognizer(click)

        return scnView
    }

    func updateNSView(_ scnView: SCNView, context: Context) {
        context.coordinator.updateCharacter(viewModel.currentCharacter)
        context.coordinator.updateFacingDirection(facingDirection)
        context.coordinator.updateAnimation(for: animationState)
        context.coordinator.onBackgroundTap = onBackgroundTap
        context.coordinator.onBodyPartTap = onBodyPartTap
        context.coordinator.onDoubleTap = onDoubleTap
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject {
        let scene: SCNScene
        private(set) var characterNode: SCNNode
        let cameraNode: SCNNode
        var currentAnimation: SpriteAnimationState = .idle

        // 部位点击互动的依赖：气泡/睡眠计时走 viewModel，未命中角色时回落原单击行为
        private weak var viewModel: SpriteViewModel?
        var onBackgroundTap: (() -> Void)?
        var onBodyPartTap: ((SpriteBodyPart) -> Void)?
        var onDoubleTap: (() -> Void)?

        // 当前角色标识（切换角色时据此重建 3D 模型）
        private var currentCharacterID: UUID

        // 微动作目标节点（仅熊猫/小熊模型存在，占位符模型时为 nil，动画自动跳过）
        private var modelNode: SCNNode?
        private var headNode: SCNNode?
        private var eyesNode: SCNNode?
        private var earLNode: SCNNode?
        private var earRNode: SCNNode?
        private var armLNode: SCNNode?
        private var armRNode: SCNNode?
        private var footLNode: SCNNode?
        private var footRNode: SCNNode?
        private var illustratedSpriteNode: SCNNode?
        private var illustratedMorpher: SCNMorpher?
        private var illustratedBaseImage: NSImage?
        private var illustratedSleepImage: NSImage?
        private var illustratedBaseAspect: CGFloat = 1
        private var illustratedWaveFrames: [NSImage] = []
        private var facingDirection: CGFloat = 1

        private enum IllustratedMorphTarget: Int, CaseIterable {
            case waveRaised
            case waveSide
            case leftStep
            case rightStep
            case blink
            case talk
        }

        init(viewModel: SpriteViewModel) {
            self.viewModel = viewModel
            scene = SCNScene()

            // 创建角色节点
            currentCharacterID = viewModel.currentCharacter.id
            characterNode = Coordinator.createCharacterNode(for: viewModel.currentCharacter)
            scene.rootNode.addChildNode(characterNode)


            // 地面软阴影：静态半透明圆片替代真实阴影贴图（性能考虑不开 shadow map），
            // 随浮动节奏轻微缩放，制造"离地远近"的错觉
            let shadowGeometry = SCNCylinder(radius: 0.40, height: 0.005)
            let shadowMaterial = SCNMaterial()
            shadowMaterial.diffuse.contents = NSColor(calibratedRed: 0.25, green: 0.18, blue: 0.16, alpha: 0.15)
            shadowMaterial.lightingModel = .constant
            shadowGeometry.materials = [shadowMaterial]
            let shadow = SCNNode(geometry: shadowGeometry)
            shadow.position = SCNVector3(0, -1.04, 0)
            shadow.scale = SCNVector3(1.0, 1.0, 0.72)
            scene.rootNode.addChildNode(shadow)

            // 阴影呼吸：与待机浮动同为 1.5s 半周期，角色升高时阴影缩小变淡
            let shadowShrink = SCNAction.scale(to: 0.82, duration: 1.5)
            shadowShrink.timingMode = .easeInEaseOut
            let shadowGrow = SCNAction.scale(to: 1.0, duration: 1.5)
            shadowGrow.timingMode = .easeInEaseOut
            shadow.runAction(.repeatForever(.sequence([shadowShrink, shadowGrow])))

            // 正交相机消除近大远小，让角色更像参考图里的正面软萌公仔。
            // orthographicScale 表示半高；1.18 让角色占满 150pt 精灵区，同时覆盖跳跃余量。
            cameraNode = SCNNode()
            cameraNode.camera = SCNCamera()
            cameraNode.camera?.usesOrthographicProjection = true
            cameraNode.camera?.orthographicScale = 1.18
            cameraNode.position = SCNVector3(x: 0, y: 0.02, z: 3.5)
            cameraNode.look(at: SCNVector3(0, -0.02, 0))
            scene.rootNode.addChildNode(cameraNode)

            // 基于图像的环境光照（IBL）：程序化暖色渐变作环境贴图，
            // 让 PBR 材质表面产生柔和的环境反射与自然明暗过渡——
            // 这是软胶质感的关键，纯 diffuse 靠打光做不出这种通透感
            scene.lightingEnvironment.contents = Coordinator.makeEnvironmentImage()
            scene.lightingEnvironment.intensity = 0.70

            // 环境光：压低（IBL 已提供大部分环境照明），仅补一点暖色底光
            let ambientLight = SCNNode()
            ambientLight.light = SCNLight()
            ambientLight.light?.type = .ambient
            ambientLight.light?.color = NSColor(red: 1.0, green: 0.96, blue: 0.92, alpha: 1.0)
            ambientLight.light?.intensity = 650
            scene.rootNode.addChildNode(ambientLight)

            // 主光源：柔和面光（area light）替代硬平行光，高光更柔、边缘过渡更自然
            let mainLight = SCNNode()
            mainLight.light = SCNLight()
            mainLight.light?.type = .directional
            mainLight.light?.color = NSColor(red: 1.0, green: 0.97, blue: 0.92, alpha: 1.0)
            mainLight.light?.intensity = 450
            mainLight.position = SCNVector3(x: 2.2, y: 3.2, z: 2.5)
            mainLight.look(at: SCNVector3(0, -0.1, 0))
            scene.rootNode.addChildNode(mainLight)

            // 补光（暖粉色调，衬托白色身体与粉帽兜）
            let fillLight = SCNNode()
            fillLight.light = SCNLight()
            fillLight.light?.type = .directional
            fillLight.light?.color = NSColor(red: 0.98, green: 0.85, blue: 0.83, alpha: 1.0)
            fillLight.light?.intensity = 220
            fillLight.position = SCNVector3(x: -2.2, y: 0.8, z: 2.0)
            fillLight.look(at: SCNVector3(0, 0, 0))
            scene.rootNode.addChildNode(fillLight)

            // 轮廓光：从后上方勾一道冷色边光，把角色从背景里"托"出来，增强立体
            let rimLight = SCNNode()
            rimLight.light = SCNLight()
            rimLight.light?.type = .directional
            rimLight.light?.color = NSColor(red: 0.80, green: 0.86, blue: 0.98, alpha: 1.0)
            rimLight.light?.intensity = 80
            rimLight.position = SCNVector3(x: -1.0, y: 2.0, z: -2.5)
            rimLight.look(at: SCNVector3(0, 0, 0))
            scene.rootNode.addChildNode(rimLight)

            // 设置背景透明
            scene.background.contents = NSColor.clear

            // NSObject 子类（点击手势 selector 需要）：存储属性就绪后先完成父类初始化
            super.init()

            // 提取微动作子节点（状态动画在外层容器上 removeAllActions，
            // 挂在子节点上的微动作不受影响）
            bindMicroNodes()

            // 启动待机动画与微动作
            startIdleAnimation()
            startMicroAnimations()
        }

        /// 提取微动作目标子节点引用
        private func bindMicroNodes() {
            modelNode = characterNode.childNode(withName: "bubu-model", recursively: true)
            headNode = characterNode.childNode(withName: "bubu-head", recursively: true)
            eyesNode = characterNode.childNode(withName: "bubu-eyes", recursively: true)
            earLNode = characterNode.childNode(withName: "bubu-ear-l", recursively: true)
            earRNode = characterNode.childNode(withName: "bubu-ear-r", recursively: true)
            armLNode = characterNode.childNode(withName: "bubu-arm-l", recursively: true)
            armRNode = characterNode.childNode(withName: "bubu-arm-r", recursively: true)
            footLNode = characterNode.childNode(withName: "bubu-foot-l", recursively: true)
            footRNode = characterNode.childNode(withName: "bubu-foot-r", recursively: true)
            illustratedSpriteNode = characterNode.childNode(withName: "bubu-sprite", recursively: true)
            illustratedMorpher = illustratedSpriteNode?.morpher
            illustratedBaseImage = illustratedSpriteNode?.geometry?.firstMaterial?.diffuse.contents as? NSImage
            if let size = illustratedBaseImage?.size, size.height > 0 {
                illustratedBaseAspect = size.width / size.height
            } else {
                illustratedBaseAspect = 1
            }
            illustratedSleepImage = currentCharacterID == SpriteCharacter.bubu.id
                ? NSImage(named: "bubu_sleep")
                : nil
            illustratedWaveFrames = currentCharacterID == SpriteCharacter.bubu.id
                ? (1...4).compactMap { NSImage(named: "bubu_wave_\(String(format: "%02d", $0))") }
                : []
        }

        func updateFacingDirection(_ direction: CGFloat) {
            let normalized: CGFloat = direction < 0 ? -1 : 1
            guard normalized != facingDirection else { return }
            facingDirection = normalized
            applyFacingDirection(animated: true)
        }

        private func applyFacingDirection(animated: Bool) {
            let facingNode = modelNode ?? characterNode
            facingNode.removeAction(forKey: "edge-turn")
            // 原始立绘的视觉朝向与屏幕 X 正方向相反，渲染时需要反向映射。
            let targetY = facingDirection > 0 ? CGFloat.pi : 0
            if animated {
                let turn = SCNAction.rotateTo(
                    x: 0,
                    y: targetY,
                    z: 0,
                    duration: 0.28,
                    usesShortestUnitArc: true
                )
                turn.timingMode = .easeInEaseOut
                facingNode.runAction(turn, forKey: "edge-turn")
            } else {
                facingNode.eulerAngles.y = targetY
            }
        }

        // MARK: - 部位点击互动

        /// 场景单击：命中角色部位则触发对应互动，否则回落到原有单击行为
        @objc func handleSceneClick(_ recognizer: NSClickGestureRecognizer) {
            guard let scnView = recognizer.view as? SCNView else { return }

            let point = recognizer.location(in: scnView)
            let hits = scnView.hitTest(point, options: nil)  // 默认按距离由近到远排序

            if let illustratedHit = hits.first(where: { Self.isIllustratedSpriteNode($0.node) }),
               let part = SpriteBodyPart.hitTest(
                   normalized: illustratedHit.textureCoordinates(withMappingChannel: 0),
                   character: viewModel?.currentCharacter ?? .bubu
               ) {
                react(to: part)
            } else if let part = hits.lazy.compactMap({ Self.interactivePart(for: $0.node) }).first {
                react(to: part)
            } else {
                onBackgroundTap?()
            }
        }

        @objc func handleSceneDoubleClick(_ recognizer: NSClickGestureRecognizer) {
            onDoubleTap?()
        }

        private static func isIllustratedSpriteNode(_ node: SCNNode) -> Bool {
            var current: SCNNode? = node
            while let n = current {
                if n.name == "bubu-sprite" { return true }
                current = n.parent
            }
            return false
        }

        /// 沿命中节点向上找已命名的部位节点（几何体挂在无名子节点上，名字在轴心节点上）
        private static func interactivePart(for node: SCNNode) -> SpriteBodyPart? {
            var current: SCNNode? = node
            while let n = current {
                switch n.name {
                case "bubu-eyes": return .eyes
                case "bubu-ear-l", "bubu-ear-r": return .ear
                case "bubu-head": return .head
                case "bubu-arm-l", "bubu-arm-r": return .arm
                case "bubu-foot-l", "bubu-foot-r": return .foot
                case "bubu-model": return .belly  // 躯干/领巾等未细分的部位都算肚子
                default: current = n.parent
                }
            }
            return nil
        }

        /// 触发部位互动：对应的小动作 + 一句短气泡（睡着时先被戳醒）
        private func react(to part: SpriteBodyPart) {
            switch part {
            case .head:
                gestureHeadTilt()
            case .ear:
                wiggleEarsOnce()
            case .eyes:
                blinkNow()
            case .cheek:
                bellyJiggle()
            case .belly:
                bellyJiggle()
            case .arm:
                gestureWave()
            case .foot:
                gestureKickFeet()
            case .phone:
                gestureHeadTilt()
            }
            onBodyPartTap?(part)
        }

        /// 点眼睛：立即眨一次眼
        private func blinkNow() {
            if let sprite = illustratedSpriteNode,
               let blink = illustratedMorphTransition(.blink, from: 0, to: 1, duration: 0.07),
               let open = illustratedMorphTransition(.blink, from: 1, to: 0, duration: 0.10) {
                sprite.runAction(.sequence([blink, open]), forKey: "blink-now")
                return
            }
            eyesNode?.runAction(Coordinator.makeBlinkOnce(), forKey: "blink-now")
        }

        /// 点耳朵：双耳同时抖动一轮
        private func wiggleEarsOnce() {
            if earLNode == nil, earRNode == nil, let sprite = illustratedSpriteNode {
                let left = SCNAction.rotateBy(x: 0, y: 0, z: 0.055, duration: 0.10)
                let right = SCNAction.rotateBy(x: 0, y: 0, z: -0.11, duration: 0.18)
                let center = SCNAction.rotateBy(x: 0, y: 0, z: 0.055, duration: 0.10)
                sprite.runAction(.sequence([left, right, center, left, right, center]), forKey: "wiggle-once")
                return
            }
            for (ear, side) in [(earLNode, CGFloat(1)), (earRNode, CGFloat(-1))] {
                guard let ear else { continue }

                let tilt = SCNAction.rotateBy(x: 0, y: 0, z: 0.28 * side, duration: 0.14)
                tilt.timingMode = .easeOut
                let back = SCNAction.rotateBy(x: 0, y: 0, z: -0.28 * side, duration: 0.22)
                back.timingMode = .easeInEaseOut
                ear.runAction(.sequence([tilt, back, tilt, back]), forKey: "wiggle-once")
            }
        }

        /// 点肚子：果冻式的挤压回弹（挤扁 → 拉伸 → 轻微再挤，模拟软胶弹性）
        private func bellyJiggle() {
            guard let model = modelNode else { return }

            func bounce(amount: CGFloat, duration: TimeInterval, squash: Bool) -> SCNAction {
                SCNAction.customAction(duration: duration) { node, elapsed in
                    let progress = elapsed / CGFloat(duration)
                    let a = amount * sin(progress * .pi) * (squash ? 1 : -1)
                    node.scale = SCNVector3(1 + a, 1 - a, 1 + a)
                }
            }

            model.runAction(.sequence([
                bounce(amount: 0.10, duration: 0.16, squash: true),
                bounce(amount: 0.06, duration: 0.16, squash: false),
                bounce(amount: 0.03, duration: 0.14, squash: true)
            ]), forKey: "belly-jiggle")
        }

        /// 角色切换：重建 3D 模型并重新挂载动画（此前切换角色 3D 模型不会更新）
        func updateCharacter(_ character: SpriteCharacter) {
            guard character.id != currentCharacterID else { return }
            currentCharacterID = character.id

            characterNode.removeFromParentNode()
            characterNode = Coordinator.createCharacterNode(for: character)
            scene.rootNode.addChildNode(characterNode)

            bindMicroNodes()
            applyFacingDirection(animated: false)
            applyAnimation(currentAnimation)
            startMicroAnimations()
        }

        // MARK: - 微动作（眨眼/耳朵抖动/摆臂/随机小动作）

        /// 启动所有微动作循环。全部挂在子节点上，与外层状态动画共存
        private func startMicroAnimations() {
            startBlinking()
            startEarWiggle()
            startArmSway()
            startRandomGestures()
        }

        /// 待机摆臂：双臂随呼吸节奏轻微开合（左右反相更自然）
        private func startArmSway() {
            for (arm, phase) in [(armLNode, 0.0), (armRNode, 0.75)] {
                guard let arm else { continue }

                let direction: CGFloat = arm === armLNode ? 1 : -1
                let swayOut = SCNAction.rotateBy(x: 0, y: 0, z: 0.10 * direction, duration: 1.5)
                swayOut.timingMode = .easeInEaseOut
                let swayIn = SCNAction.rotateBy(x: 0, y: 0, z: -0.10 * direction, duration: 1.5)
                swayIn.timingMode = .easeInEaseOut

                arm.runAction(.sequence([
                    .wait(duration: phase),
                    .repeatForever(.sequence([swayOut, swayIn]))
                ]), forKey: "sway")
            }
        }

        /// 单次眨眼动作（闭眼-睁眼），供随机眨眼循环与点眼互动复用
        private static func makeBlinkOnce() -> SCNAction {
            let close = SCNAction.customAction(duration: 0.07) { node, elapsed in
                let progress = elapsed / 0.07
                node.scale = SCNVector3(1, 1 - 0.88 * progress, 1)
            }
            let open = SCNAction.customAction(duration: 0.09) { node, elapsed in
                let progress = elapsed / 0.09
                node.scale = SCNVector3(1, 0.12 + 0.88 * progress, 1)
            }
            return SCNAction.sequence([close, open])
        }

        /// 眨眼：随机间隔 2.5~6 秒，偶尔连眨两次更传神
        private func startBlinking() {
            if let sprite = illustratedSpriteNode, illustratedMorpher != nil,
               let blink = illustratedMorphTransition(.blink, from: 0, to: 1, duration: 0.07),
               let open = illustratedMorphTransition(.blink, from: 1, to: 0, duration: 0.10) {
                let loop = SCNAction.repeatForever(.sequence([
                    .wait(duration: 4.0, withRange: 3.5),
                    blink,
                    open
                ]))
                sprite.runAction(loop, forKey: "illustrated-blink")
                return
            }

            guard let eyes = eyesNode else { return }

            let blinkOnce = Coordinator.makeBlinkOnce()

            let loop = SCNAction.repeatForever(.sequence([
                .wait(duration: 4.0, withRange: 3.5),
                blinkOnce,
                // 30% 概率补一次连眨
                .run { node in
                    if Int.random(in: 0..<10) < 3 {
                        node.runAction(.sequence([.wait(duration: 0.18), blinkOnce]))
                    }
                }
            ]))
            eyes.runAction(loop, forKey: "blink")
        }

        /// Morph 权重使用平滑插值，动作结束时精确落到目标值，避免长时间运行后的姿态漂移。
        private func illustratedMorphTransition(
            _ target: IllustratedMorphTarget,
            from: CGFloat,
            to: CGFloat,
            duration: TimeInterval
        ) -> SCNAction? {
            guard let morpher = illustratedMorpher else { return nil }
            return SCNAction.customAction(duration: duration) { [weak morpher] _, elapsed in
                let raw = min(max(elapsed / CGFloat(duration), 0), 1)
                let eased = raw * raw * (3 - 2 * raw)
                morpher?.setWeight(from + (to - from) * eased, forTargetAt: target.rawValue)
            }
        }

        private func illustratedMorphCrossfade(
            from source: IllustratedMorphTarget,
            to destination: IllustratedMorphTarget,
            duration: TimeInterval
        ) -> SCNAction? {
            guard let morpher = illustratedMorpher else { return nil }
            return SCNAction.customAction(duration: duration) { [weak morpher] _, elapsed in
                let raw = min(max(elapsed / CGFloat(duration), 0), 1)
                let eased = raw * raw * (3 - 2 * raw)
                morpher?.setWeight(1 - eased, forTargetAt: source.rawValue)
                morpher?.setWeight(eased, forTargetAt: destination.rawValue)
            }
        }

        private func resetIllustratedStateMorphs() {
            illustratedSpriteNode?.removeAction(forKey: "illustrated-state")
            illustratedSpriteNode?.removeAction(forKey: "illustrated-wave")
            illustratedSpriteNode?.removeAction(forKey: "illustrated-kick")
            if let base = illustratedBaseImage {
                illustratedSpriteNode?.geometry?.firstMaterial?.diffuse.contents = base
            }
            illustratedSpriteNode?.scale = SCNVector3(1, 1, 1)
            illustratedSpriteNode?.position = SCNVector3(0, -0.03, 0)
            for target in [
                IllustratedMorphTarget.waveRaised,
                .waveSide,
                .leftStep,
                .rightStep,
                .talk
            ] {
                illustratedMorpher?.setWeight(0, forTargetAt: target.rawValue)
            }
        }

        /// 耳朵抖动：间歇性轻轻抽动一下双耳，像有点小情绪，两耳向外倾再回正
        private func startEarWiggle() {
            for (ear, side) in [(earLNode, CGFloat(1)), (earRNode, CGFloat(-1))] {
                guard let ear else { continue }

                let tilt = SCNAction.rotateBy(x: 0, y: 0, z: 0.28 * side, duration: 0.14)
                tilt.timingMode = .easeOut
                let back = SCNAction.rotateBy(x: 0, y: 0, z: -0.28 * side, duration: 0.22)
                back.timingMode = .easeInEaseOut
                let wiggleOnce = SCNAction.sequence([tilt, back, tilt, back])

                let loop = SCNAction.repeatForever(.sequence([
                    .wait(duration: 5.0, withRange: 4.0),
                    wiggleOnce
                ]))
                ear.runAction(loop, forKey: "wiggle")
            }
        }

        /// 随机小动作：待机时每 7~15 秒做一个（歪头 / 左右张望 / 原地小跳）
        private func startRandomGestures() {
            guard let model = modelNode else { return }

            let loop = SCNAction.repeatForever(.sequence([
                .wait(duration: 10, withRange: 7),
                .run { [weak self] _ in
                    self?.performRandomGesture()
                }
            ]))
            model.runAction(loop, forKey: "gestures")
        }

        private func performRandomGesture() {
            // 睡眠/思考等状态有自己的身体语言，小动作只在待机与开心时插入
            guard currentAnimation == .idle || currentAnimation == .happy else { return }

            switch Int.random(in: 0..<5) {
            case 0: gestureHeadTilt()
            case 1: gestureLookAround()
            case 2: gestureWave()
            case 3: gestureKickFeet()
            default: gestureHop()
            }
        }

        /// 挥手打招呼：单侧手臂举起晃动后放下
        private func gestureWave() {
            if let sprite = illustratedSpriteNode,
               let textureWave = illustratedTextureWaveAction() {
                sprite.runAction(textureWave, forKey: "illustrated-wave")
                return
            }

            if let sprite = illustratedSpriteNode,
               let raise = illustratedMorphTransition(.waveRaised, from: 0, to: 1, duration: 0.32),
               let waveOut = illustratedMorphCrossfade(from: .waveRaised, to: .waveSide, duration: 0.16),
               let waveIn = illustratedMorphCrossfade(from: .waveSide, to: .waveRaised, duration: 0.16),
               let lower = illustratedMorphTransition(.waveRaised, from: 1, to: 0, duration: 0.34) {
                sprite.runAction(.sequence([
                    raise,
                    waveOut, waveIn, waveOut, waveIn,
                    .wait(duration: 0.10),
                    lower
                ]), forKey: "illustrated-wave")
                return
            }

            guard let arm = armRNode else { return }

            let raise = SCNAction.rotateBy(x: 0, y: 0, z: 1.7, duration: 0.3)
            raise.timingMode = .easeOut
            let waveOut = SCNAction.rotateBy(x: 0, y: 0, z: -0.35, duration: 0.18)
            waveOut.timingMode = .easeInEaseOut
            let waveIn = SCNAction.rotateBy(x: 0, y: 0, z: 0.35, duration: 0.18)
            waveIn.timingMode = .easeInEaseOut
            let lower = SCNAction.rotateBy(x: 0, y: 0, z: -1.7, duration: 0.35)
            lower.timingMode = .easeInEaseOut

            arm.runAction(.sequence([
                raise,
                waveOut, waveIn, waveOut, waveIn,
                .wait(duration: 0.15),
                lower
            ]), forKey: "wave")
        }

        /// 布布使用完整纹理帧挥手：身体、手机和头颈肩不参与网格形变。
        private func illustratedTextureWaveAction() -> SCNAction? {
            guard let base = illustratedBaseImage,
                  illustratedWaveFrames.count == 4 else { return nil }

            func show(_ image: NSImage, for duration: TimeInterval) -> SCNAction {
                .sequence([
                    .run { node in node.geometry?.firstMaterial?.diffuse.contents = image },
                    .wait(duration: duration)
                ])
            }

            let raised = illustratedWaveFrames[1]
            let waveLeft = illustratedWaveFrames[2]
            let waveRight = illustratedWaveFrames[3]
            let wavePairs = (0..<6).flatMap { _ in [
                show(waveLeft, for: 0.14),
                show(waveRight, for: 0.14)
            ] }

            return .sequence([
                show(illustratedWaveFrames[0], for: 0.16),
                show(raised, for: 0.20),
                .sequence(wavePairs),
                show(raised, for: 0.20),
                show(illustratedWaveFrames[0], for: 0.16),
                .run { node in node.geometry?.firstMaterial?.diffuse.contents = base }
            ])
        }

        /// 开心踢腿：双脚交替向前踢两轮，像坐着晃腿
        private func gestureKickFeet() {
            if let sprite = illustratedSpriteNode,
               let leftUp = illustratedMorphTransition(.leftStep, from: 0, to: 1, duration: 0.15),
               let leftDown = illustratedMorphTransition(.leftStep, from: 1, to: 0, duration: 0.18),
               let rightUp = illustratedMorphTransition(.rightStep, from: 0, to: 1, duration: 0.15),
               let rightDown = illustratedMorphTransition(.rightStep, from: 1, to: 0, duration: 0.18) {
                sprite.runAction(.sequence([
                    leftUp, leftDown,
                    .wait(duration: 0.08),
                    rightUp, rightDown,
                    .wait(duration: 0.08),
                    leftUp, leftDown,
                    rightUp, rightDown
                ]), forKey: "illustrated-kick")
                return
            }

            guard let footL = footLNode, let footR = footRNode else { return }

            func kick(_ foot: SCNNode, delay: TimeInterval) {
                let kickUp = SCNAction.rotateBy(x: -0.55, y: 0, z: 0, duration: 0.16)
                kickUp.timingMode = .easeOut
                let kickDown = SCNAction.rotateBy(x: 0.55, y: 0, z: 0, duration: 0.20)
                kickDown.timingMode = .easeInEaseOut

                foot.runAction(.sequence([
                    .wait(duration: delay),
                    kickUp, kickDown,
                    .wait(duration: 0.1),
                    kickUp, kickDown
                ]), forKey: "kick")
            }

            kick(footL, delay: 0)
            kick(footR, delay: 0.22)
        }

        /// 歪头：侧倾片刻再回正，好奇的样子
        private func gestureHeadTilt() {
            guard let head = headNode ?? illustratedSpriteNode else { return }
            let direction: CGFloat = Bool.random() ? 1 : -1

            let tilt = SCNAction.rotateBy(x: 0, y: 0, z: 0.20 * direction, duration: 0.28)
            tilt.timingMode = .easeOut
            let back = SCNAction.rotateBy(x: 0, y: 0, z: -0.20 * direction, duration: 0.35)
            back.timingMode = .easeInEaseOut

            head.runAction(.sequence([tilt, .wait(duration: 0.9), back]))
        }

        /// 左右张望：先看一侧，再看另一侧，回正
        private func gestureLookAround() {
            guard let head = headNode else { return }

            let lookLeft = SCNAction.rotateBy(x: 0, y: 0.38, z: 0, duration: 0.35)
            lookLeft.timingMode = .easeInEaseOut
            let lookRight = SCNAction.rotateBy(x: 0, y: -0.76, z: 0, duration: 0.6)
            lookRight.timingMode = .easeInEaseOut
            let lookBack = SCNAction.rotateBy(x: 0, y: 0.38, z: 0, duration: 0.35)
            lookBack.timingMode = .easeInEaseOut

            head.runAction(.sequence([lookLeft, .wait(duration: 0.4), lookRight, .wait(duration: 0.4), lookBack]))
        }

        /// 原地小跳：起跳时拉伸、落地时压扁，经典的挤压拉伸让跳跃有弹性
        private func gestureHop() {
            guard let model = modelNode else { return }

            let jumpUp = SCNAction.moveBy(x: 0, y: 0.14, z: 0, duration: 0.18)
            jumpUp.timingMode = .easeOut
            let jumpDown = SCNAction.moveBy(x: 0, y: -0.14, z: 0, duration: 0.16)
            jumpDown.timingMode = .easeIn

            let stretch = SCNAction.customAction(duration: 0.18) { node, elapsed in
                let progress = elapsed / 0.18
                let amount = 0.06 * sin(progress * .pi)
                node.scale = SCNVector3(1 - amount * 0.7, 1 + amount, 1 - amount * 0.7)
            }
            let squash = SCNAction.customAction(duration: 0.2) { node, elapsed in
                let progress = elapsed / 0.2
                let amount = 0.08 * sin(progress * .pi)
                node.scale = SCNVector3(1 + amount, 1 - amount, 1 + amount)
            }

            model.runAction(.sequence([
                .group([jumpUp, stretch]),
                jumpDown,
                squash
            ]))

            // 起跳时双臂欢快上扬，落地放下
            for arm in [armLNode, armRNode] {
                guard let arm else { continue }
                let direction: CGFloat = arm === armLNode ? -1 : 1

                let flapUp = SCNAction.rotateBy(x: 0, y: 0, z: 0.9 * direction, duration: 0.18)
                flapUp.timingMode = .easeOut
                let flapDown = SCNAction.rotateBy(x: 0, y: 0, z: -0.9 * direction, duration: 0.25)
                flapDown.timingMode = .easeInEaseOut

                arm.runAction(.sequence([flapUp, .wait(duration: 0.1), flapDown]), forKey: "flap")
            }
        }

        // MARK: - 程序化环境贴图（IBL）

        /// 生成一张竖直渐变图作 PBR 环境光照：顶部暖白（天光）→ 中部柔粉 → 底部暖褐（地面反射）。
        /// 用作 lightingEnvironment，为软胶材质提供通透的环境反射
        static func makeEnvironmentImage() -> NSImage {
            let size = NSSize(width: 8, height: 256)
            let image = NSImage(size: size)
            image.lockFocus()

            let gradient = NSGradient(colorsAndLocations:
                (NSColor(red: 1.0, green: 0.98, blue: 0.95, alpha: 1.0), 0.0),   // 顶部天光
                (NSColor(red: 0.99, green: 0.90, blue: 0.90, alpha: 1.0), 0.45), // 中上柔粉
                (NSColor(red: 0.85, green: 0.80, blue: 0.82, alpha: 1.0), 0.7),  // 中下微冷
                (NSColor(red: 0.55, green: 0.48, blue: 0.46, alpha: 1.0), 1.0)   // 底部地面暖褐
            )
            gradient?.draw(in: NSRect(origin: .zero, size: size), angle: -90)

            image.unlockFocus()
            return image
        }

        // MARK: - 创建角色节点

        static func createCharacterNode(for character: SpriteCharacter) -> SCNNode {
            let containerNode = SCNNode()

            // 尝试加载 3D 模型文件
            if let modelURL = Bundle.main.url(forResource: character.imageName, withExtension: "usdz") ??
                              Bundle.main.url(forResource: character.imageName, withExtension: "scn") {
                if let modelScene = try? SCNScene(url: modelURL, options: nil) {
                    for child in modelScene.rootNode.childNodes {
                        containerNode.addChildNode(child.clone())
                    }
                    return containerNode
                }
            }

            // 桌面精灵只有 150pt 左右：优先把高质量角色立绘作为 2.5D 平面放进 SceneKit，
            // 保留整体浮动/跳跃/缩放动画，同时避免基础球体在小尺寸下产生零件拼装感。
            let illustratedImage: NSImage? = {
                if character.isCustom, let path = character.customImagePath {
                    return NSImage(contentsOfFile: path)
                }
                return NSImage(named: character.imageName)
            }()
            if let illustratedImage {
                return createIllustratedCharacterNode(image: illustratedImage, character: character)
            }

            // 资源异常时才使用代码构建的软胶熊猫/小熊占位模型。
            switch character.imageName {
            case "bubu":
                return createBuddyNode(style: .brownBear)   // 棕小熊（布布）
            case "yier":
                return createBuddyNode(style: .whitePanda)  // 白熊猫（一二/伊尔）
            default:
                // 自定义角色暂无 3D 模型：显示可爱占位符
                return createCutePlaceholder()
            }
        }

        /// 不同立绘的五官和四肢位置不同，Morph 区域按角色单独标定。
        private struct IllustratedRigProfile {
            let waveCenter: CGPoint
            let waveRadius: CGVector
            let wavePivot: CGPoint
            let waveAngle: CGFloat
            let waveLift: CGVector
            let leftFootCenter: CGPoint
            let rightFootCenter: CGPoint
            let footRadius: CGVector
            let leftFootOffset: CGVector
            let rightFootOffset: CGVector
            let eyeCenters: [CGPoint]
            let eyeRadius: CGVector
            let mouthCenter: CGPoint
            let mouthRadius: CGVector

            static func make(for character: SpriteCharacter) -> IllustratedRigProfile {
                switch character.imageName {
                case "yier":
                    return IllustratedRigProfile(
                        waveCenter: CGPoint(x: 0.86, y: 0.42),
                        waveRadius: CGVector(dx: 0.13, dy: 0.15),
                        wavePivot: CGPoint(x: 0.73, y: 0.36),
                        waveAngle: 0.32,
                        waveLift: .zero,
                        leftFootCenter: CGPoint(x: 0.34, y: 0.075),
                        rightFootCenter: CGPoint(x: 0.66, y: 0.075),
                        footRadius: CGVector(dx: 0.17, dy: 0.14),
                        leftFootOffset: CGVector(dx: -0.018, dy: 0.075),
                        rightFootOffset: CGVector(dx: 0.018, dy: 0.075),
                        eyeCenters: [CGPoint(x: 0.29, y: 0.55), CGPoint(x: 0.66, y: 0.55)],
                        eyeRadius: CGVector(dx: 0.075, dy: 0.065),
                        mouthCenter: CGPoint(x: 0.50, y: 0.49),
                        mouthRadius: CGVector(dx: 0.08, dy: 0.075)
                    )
                case "bubu", "yier_phone":
                    return IllustratedRigProfile(
                        waveCenter: CGPoint(x: 0.68, y: 0.31),
                        waveRadius: CGVector(dx: 0.17, dy: 0.17),
                        wavePivot: CGPoint(x: 0.78, y: 0.39),
                        waveAngle: -0.88,
                        waveLift: .zero,
                        leftFootCenter: CGPoint(x: 0.29, y: 0.055),
                        rightFootCenter: CGPoint(x: 0.69, y: 0.055),
                        footRadius: CGVector(dx: 0.17, dy: 0.13),
                        leftFootOffset: CGVector(dx: -0.015, dy: 0.072),
                        rightFootOffset: CGVector(dx: 0.015, dy: 0.072),
                        eyeCenters: [CGPoint(x: 0.27, y: 0.55), CGPoint(x: 0.58, y: 0.55)],
                        eyeRadius: CGVector(dx: 0.085, dy: 0.065),
                        mouthCenter: CGPoint(x: 0.42, y: 0.49),
                        mouthRadius: CGVector(dx: 0.075, dy: 0.07)
                    )
                default:
                    return IllustratedRigProfile(
                        waveCenter: CGPoint(x: 0.78, y: 0.38),
                        waveRadius: CGVector(dx: 0.22, dy: 0.25),
                        wavePivot: CGPoint(x: 0.67, y: 0.38),
                        waveAngle: 0.45,
                        waveLift: CGVector(dx: 0.01, dy: 0.035),
                        leftFootCenter: CGPoint(x: 0.34, y: 0.08),
                        rightFootCenter: CGPoint(x: 0.66, y: 0.08),
                        footRadius: CGVector(dx: 0.18, dy: 0.15),
                        leftFootOffset: CGVector(dx: -0.015, dy: 0.065),
                        rightFootOffset: CGVector(dx: 0.015, dy: 0.065),
                        eyeCenters: [CGPoint(x: 0.34, y: 0.57), CGPoint(x: 0.66, y: 0.57)],
                        eyeRadius: CGVector(dx: 0.09, dy: 0.07),
                        mouthCenter: CGPoint(x: 0.50, y: 0.49),
                        mouthRadius: CGVector(dx: 0.09, dy: 0.08)
                    )
                }
            }
        }

        /// 用透明立绘构建可变形 2.5D 网格。基础顶点不改变，所以 idle 正面与原 PNG 一致。
        private static func createIllustratedCharacterNode(
            image: NSImage,
            character: SpriteCharacter
        ) -> SCNNode {
            let container = SCNNode()
            let model = SCNNode()
            model.name = "bubu-model"
            container.addChildNode(model)

            let aspect = max(image.size.width / max(image.size.height, 1), 0.1)
            let height: CGFloat = 1.90
            let width = height * aspect
            let columns = 40
            let rows = 52
            var vertices: [SCNVector3] = []
            var textureCoordinates: [CGPoint] = []
            var rigCoordinates: [CGPoint] = []
            var indices: [UInt32] = []
            vertices.reserveCapacity((columns + 1) * (rows + 1))
            textureCoordinates.reserveCapacity((columns + 1) * (rows + 1))
            rigCoordinates.reserveCapacity((columns + 1) * (rows + 1))
            indices.reserveCapacity(columns * rows * 6)

            for row in 0...rows {
                let v = CGFloat(row) / CGFloat(rows)
                for column in 0...columns {
                    let u = CGFloat(column) / CGFloat(columns)
                    vertices.append(SCNVector3(
                        (u - 0.5) * width,
                        (v - 0.5) * height,
                        0
                    ))
                    // SceneKit 对 NSImage 的纹理原点在左上；网格/骨骼坐标仍使用左下原点。
                    textureCoordinates.append(CGPoint(x: u, y: 1 - v))
                    rigCoordinates.append(CGPoint(x: u, y: v))
                }
            }

            for row in 0..<rows {
                for column in 0..<columns {
                    let topLeft = UInt32(row * (columns + 1) + column)
                    let topRight = topLeft + 1
                    let bottomLeft = UInt32((row + 1) * (columns + 1) + column)
                    let bottomRight = bottomLeft + 1
                    indices.append(contentsOf: [topLeft, bottomLeft, topRight, topRight, bottomLeft, bottomRight])
                }
            }

            let vertexSource = SCNGeometrySource(vertices: vertices)
            let textureSource = SCNGeometrySource(textureCoordinates: textureCoordinates)
            let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
            let geometry = SCNGeometry(sources: [vertexSource, textureSource], elements: [element])

            let material = SCNMaterial()
            material.lightingModel = .constant
            material.diffuse.contents = image
            material.diffuse.magnificationFilter = .linear
            material.diffuse.minificationFilter = .linear
            material.diffuse.mipFilter = .linear
            material.diffuse.wrapS = .clamp
            material.diffuse.wrapT = .clamp
            material.blendMode = .alpha
            material.transparencyMode = .dualLayer
            material.writesToDepthBuffer = false
            material.isDoubleSided = true
            geometry.materials = [material]

            let profile = IllustratedRigProfile.make(for: character)
            let waveRaisedVertices = makeWaveVertices(
                base: vertices,
                textureCoordinates: rigCoordinates,
                width: width,
                height: height,
                profile: profile,
                angle: profile.waveAngle
            )
            let sideDelta: CGFloat = profile.waveAngle < 0 ? -0.18 : 0.18
            let waveSideVertices = makeWaveVertices(
                base: vertices,
                textureCoordinates: rigCoordinates,
                width: width,
                height: height,
                profile: profile,
                angle: profile.waveAngle + sideDelta
            )
            let leftStepVertices = makeTranslatedVertices(
                base: vertices,
                textureCoordinates: rigCoordinates,
                width: width,
                height: height,
                center: profile.leftFootCenter,
                radius: profile.footRadius,
                offset: profile.leftFootOffset
            )
            let rightStepVertices = makeTranslatedVertices(
                base: vertices,
                textureCoordinates: rigCoordinates,
                width: width,
                height: height,
                center: profile.rightFootCenter,
                radius: profile.footRadius,
                offset: profile.rightFootOffset
            )
            let blinkVertices = makeBlinkVertices(
                base: vertices,
                textureCoordinates: rigCoordinates,
                height: height,
                profile: profile
            )
            let talkVertices = makeTalkVertices(
                base: vertices,
                textureCoordinates: rigCoordinates,
                height: height,
                profile: profile
            )

            func morphGeometry(name: String, vertices: [SCNVector3]) -> SCNGeometry {
                let target = SCNGeometry(
                    sources: [SCNGeometrySource(vertices: vertices)],
                    elements: [element]
                )
                target.name = name
                return target
            }

            let morpher = SCNMorpher()
            morpher.calculationMode = .normalized
            morpher.targets = [
                morphGeometry(name: "wave-raised", vertices: waveRaisedVertices),
                morphGeometry(name: "wave-side", vertices: waveSideVertices),
                morphGeometry(name: "left-step", vertices: leftStepVertices),
                morphGeometry(name: "right-step", vertices: rightStepVertices),
                morphGeometry(name: "blink", vertices: blinkVertices),
                morphGeometry(name: "talk", vertices: talkVertices)
            ]

            let sprite = SCNNode(geometry: geometry)
            sprite.name = "bubu-sprite"
            sprite.morpher = morpher
            sprite.position = SCNVector3(0, -0.03, 0)
            model.addChildNode(sprite)
            return container
        }

        private static func smoothEllipseWeight(
            point: CGPoint,
            center: CGPoint,
            radius: CGVector
        ) -> CGFloat {
            let dx = (point.x - center.x) / max(radius.dx, 0.001)
            let dy = (point.y - center.y) / max(radius.dy, 0.001)
            let distance = sqrt(dx * dx + dy * dy)
            let linear = max(0, min(1, 1 - distance))
            return linear * linear * (3 - 2 * linear)
        }

        private static func makeTranslatedVertices(
            base: [SCNVector3],
            textureCoordinates: [CGPoint],
            width: CGFloat,
            height: CGFloat,
            center: CGPoint,
            radius: CGVector,
            offset: CGVector
        ) -> [SCNVector3] {
            var result: [SCNVector3] = []
            result.reserveCapacity(base.count)
            for index in base.indices {
                let vertex = base[index]
                let uv = textureCoordinates[index]
                let weight = smoothEllipseWeight(point: uv, center: center, radius: radius)
                result.append(SCNVector3(
                    vertex.x + offset.dx * width * weight,
                    vertex.y + offset.dy * height * weight,
                    vertex.z
                ))
            }
            return result
        }

        private static func makeWaveVertices(
            base: [SCNVector3],
            textureCoordinates: [CGPoint],
            width: CGFloat,
            height: CGFloat,
            profile: IllustratedRigProfile,
            angle: CGFloat
        ) -> [SCNVector3] {
            let cosine = cos(angle)
            let sine = sin(angle)

            return zip(base, textureCoordinates).map { vertex, uv in
                let weight = smoothEllipseWeight(
                    point: uv,
                    center: profile.waveCenter,
                    radius: profile.waveRadius
                )
                let localX = uv.x - profile.wavePivot.x
                let localY = uv.y - profile.wavePivot.y
                // 肩关节附近权重强制归零：颈部和肩膀保持不动，只有肩关节以下抬起。
                let shoulderDistance = sqrt(localX * localX + localY * localY)
                let distal = min(max((shoulderDistance - 0.025) / 0.14, 0), 1)
                let anchoredWeight = weight * distal * distal * (3 - 2 * distal)
                let rotatedX = cosine * localX - sine * localY
                let rotatedY = sine * localX + cosine * localY
                let deltaU = (rotatedX - localX + profile.waveLift.dx) * anchoredWeight
                let deltaV = (rotatedY - localY + profile.waveLift.dy) * anchoredWeight

                return SCNVector3(
                    vertex.x + deltaU * width,
                    vertex.y + deltaV * height,
                    vertex.z
                )
            }
        }

        private static func makeBlinkVertices(
            base: [SCNVector3],
            textureCoordinates: [CGPoint],
            height: CGFloat,
            profile: IllustratedRigProfile
        ) -> [SCNVector3] {
            zip(base, textureCoordinates).map { vertex, uv in
                var deltaV: CGFloat = 0
                for center in profile.eyeCenters {
                    let weight = smoothEllipseWeight(point: uv, center: center, radius: profile.eyeRadius)
                    deltaV += (center.y - uv.y) * 0.82 * weight
                }
                return SCNVector3(vertex.x, vertex.y + deltaV * height, vertex.z)
            }
        }

        private static func makeTalkVertices(
            base: [SCNVector3],
            textureCoordinates: [CGPoint],
            height: CGFloat,
            profile: IllustratedRigProfile
        ) -> [SCNVector3] {
            zip(base, textureCoordinates).map { vertex, uv in
                let weight = smoothEllipseWeight(
                    point: uv,
                    center: profile.mouthCenter,
                    radius: profile.mouthRadius
                )
                let deltaV = (uv.y - profile.mouthCenter.y) * 0.28 * weight
                return SCNVector3(vertex.x, vertex.y + deltaV * height, vertex.z)
            }
        }

        // MARK: - 软胶熊猫/小熊 3D 模型（布布/一二共用一套建模，配色与特征参数化）

        /// 角色外观参数（对照参考图采样）。
        /// 布布 = 棕小熊（深棕描边耳 + 橘黄腮红 + 深棕脚尖）；
        /// 一二/伊尔 = 白熊猫（深棕实心圆耳 + 粉腮红 + 深棕领巾 + 深棕脚垫）
        struct BuddyStyle {
            let body: NSColor       // 身体/头
            let ear: NSColor        // 耳朵主色
            let earRim: NSColor?    // 耳朵描边环（棕熊有，白熊猫是实心深耳）
            let blush: NSColor      // 腮红
            let accent: NSColor     // 眼/眉/嘴/领巾/脚垫
            let tongue: NSColor     // 张嘴笑时的舌头
            let hasBrows: Bool      // 可选眉毛；默认角色关闭，避免小尺寸下显得凶
            let hasScarf: Bool      // 深棕领巾 + 胸前三瓣结（白熊猫特征）
            let hasToeCaps: Bool    // 深棕脚垫（白熊猫特征）

            /// 棕小熊（布布）
            static let brownBear = BuddyStyle(
                body: NSColor(red: 0.84, green: 0.635, blue: 0.50, alpha: 1.0),    // 奶茶焦糖棕
                ear: NSColor(red: 0.70, green: 0.48, blue: 0.35, alpha: 1.0),      // 焦糖内耳
                earRim: NSColor(red: 0.33, green: 0.21, blue: 0.15, alpha: 1.0),   // 深棕描边环
                blush: NSColor(red: 1.0, green: 0.72, blue: 0.33, alpha: 1.0),     // 橘黄腮红
                accent: NSColor(red: 0.21, green: 0.14, blue: 0.12, alpha: 1.0),   // 深棕五官
                tongue: NSColor(red: 1.0, green: 0.43, blue: 0.50, alpha: 1.0),
                hasBrows: false,
                hasScarf: false,
                hasToeCaps: true
            )

            /// 白熊猫（一二/伊尔）
            static let whitePanda = BuddyStyle(
                body: NSColor(red: 0.995, green: 0.99, blue: 0.98, alpha: 1.0),    // 亮白微暖
                ear: NSColor(red: 0.24, green: 0.155, blue: 0.125, alpha: 1.0),    // 深巧克力耳
                earRim: nil,
                blush: NSColor(red: 0.99, green: 0.66, blue: 0.72, alpha: 1.0),    // 粉腮红
                accent: NSColor(red: 0.21, green: 0.14, blue: 0.12, alpha: 1.0),   // 深棕五官
                tongue: NSColor(red: 1.0, green: 0.43, blue: 0.50, alpha: 1.0),
                hasBrows: false,
                hasScarf: true,
                hasToeCaps: true
            )
        }

        /// 光滑搪胶质感 PBR 材质：中等粗糙度 + 零金属度模拟搪胶公仔表面
        /// （参考图是光滑软胶而非绒毛），配合环境光照产生柔和的明暗过渡。
        /// clearcoat 加一层极淡的透明涂层，制造柔和的高光边缘
        private static func matteMaterial(_ color: NSColor) -> SCNMaterial {
            let material = SCNMaterial()
            material.lightingModel = .physicallyBased
            material.diffuse.contents = color
            material.metalness.contents = 0.0
            material.roughness.contents = 0.90          // 高粗糙度压掉塑料反光，接近软陶/绒面公仔
            material.clearCoat.contents = 0.02          // 只保留极淡的轮廓高光
            material.clearCoatRoughness.contents = 0.90
            material.diffuse.mipFilter = .linear
            return material
        }

        /// 五官和腮红使用不受灯光影响的平涂材质，避免小尺寸下出现脏黑反光。
        private static func featureMaterial(_ color: NSColor) -> SCNMaterial {
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.diffuse.contents = color
            return material
        }

        private static func sphereNode(radius: CGFloat, color: NSColor, segments: Int = 48) -> SCNNode {
            let geometry = SCNSphere(radius: radius)
            geometry.segmentCount = segments
            geometry.materials = [matteMaterial(color)]
            return SCNNode(geometry: geometry)
        }

        /// 构建软胶熊猫/小熊角色（布布/一二共用建模，外观由 style 决定）。
        /// 对照参考图（正面全身软胶公仔）：面包型大头、黑豆小圆眼、倔强怒眉（布布）、
        /// "ω"小嘴、大圆腮红、梨形壮身体、粗短腿、深棕脚垫（布布）、脖围领巾+三瓣结（布布）。
        /// 节点分层专为动画设计：外层容器承接状态动画，
        /// 内层 bubu-model / bubu-head / bubu-eyes / 四肢节点承接微动作
        static func createBuddyNode(style: BuddyStyle) -> SCNNode {
            let containerNode = SCNNode()

            // 内层模型根节点（小跳等全身微动作挂在这里，不与外层状态动画冲突）
            let model = SCNNode()
            model.name = "bubu-model"
            containerNode.addChildNode(model)

            // 身体 - 梨形壮躯干：单个 Y 拉长椭球（完整立体，不压扁），
            // 顶部埋进头底消除"脖子缝"，底部盖住腿根
            let torso = sphereNode(radius: 0.35, color: style.body, segments: 72)
            torso.position = SCNVector3(0, -0.52, 0)
            torso.scale = SCNVector3(1.50, 1.42, 0.92)
            model.addChildNode(torso)

            // 头部组（歪头/张望动画的旋转轴心）。头占全身一大半的 baby 比例
            let head = SCNNode()
            head.name = "bubu-head"
            head.position = SCNVector3(0, 0.34, 0.0)
            model.addChildNode(head)

            // 头 - 宽阔面包型：横向宽、纵向略高、Z 只微收（参考图是饱满立体不是浮雕）
            let face = sphereNode(radius: 0.55, color: style.body, segments: 80)
            face.scale = SCNVector3(1.20, 1.08, 0.78)
            head.addChildNode(face)

            // 耳朵 - 头顶两角的圆耳：布布=实心深棕；一二=深棕描边环+焦糖内耳。
            // 各挂在可动耳根节点下（承接耳朵抖动微动作）
            for side in [CGFloat(-1), CGFloat(1)] {
                let earPivot = SCNNode()
                earPivot.name = side < 0 ? "bubu-ear-l" : "bubu-ear-r"
                earPivot.position = SCNVector3(side * 0.54, 0.50, 0.0)
                head.addChildNode(earPivot)

                if let rimColor = style.earRim {
                    // 描边耳：深色底盘 + 前置焦糖内耳，正面露出一圈描边
                    let rim = sphereNode(radius: 0.17, color: rimColor, segments: 40)
                    rim.scale = SCNVector3(1.0, 0.95, 0.72)
                    earPivot.addChildNode(rim)

                    let inner = sphereNode(radius: 0.115, color: style.ear, segments: 40)
                    inner.position = SCNVector3(0, 0, 0.07)
                    inner.scale = SCNVector3(1.0, 0.95, 0.72)
                    earPivot.addChildNode(inner)
                } else {
                    // 实心深棕圆耳（布布）
                    let ear = sphereNode(radius: 0.17, color: style.ear, segments: 44)
                    ear.scale = SCNVector3(1.0, 0.95, 0.72)
                    earPivot.addChildNode(ear)
                }
            }

            // 眼睛组（眨眼动画对该组做 Y 轴压扁）。
            // 参考图是小而实的黑豆眼：不贴白高光片，靠材质光泽自然出高光点
            let eyes = SCNNode()
            eyes.name = "bubu-eyes"
            eyes.position = SCNVector3(0, -0.07, 0.44)
            head.addChildNode(eyes)

            for xOffset in [CGFloat(-0.21), CGFloat(0.21)] {
                let eye = sphereNode(radius: 0.072, color: style.accent, segments: 40)
                eye.position = SCNVector3(xOffset, 0, 0)
                eye.scale = SCNVector3(1.0, 1.0, 0.26)
                eye.geometry?.materials = [featureMaterial(style.accent)]
                eyes.addChildNode(eye)
            }

            // 眉毛 - 倔强怒眉（布布特征）：粗短、倾角大（0.48 rad ≈ 27°）、紧贴眼睛上方
            if style.hasBrows {
                for side in [CGFloat(-1), CGFloat(1)] {
                    let brow = SCNNode(geometry: {
                        let g = SCNCapsule(capRadius: 0.018, height: 0.11)
                        g.materials = [featureMaterial(style.accent)]
                        return g
                    }())
                    brow.position = SCNVector3(side * 0.21, 0.09, 0.47)
                    brow.eulerAngles = SCNVector3(0, 0, Float(side) * 0.48 - Float.pi / 2)
                    head.addChildNode(brow)
                }
            }

            // 嘴 - 深色椭圆包住粉色舌头。小尺寸下比闭口 ω 更容易读成开心，而不是严肃。
            let mouth = SCNNode()
            mouth.name = "bubu-mouth"
            mouth.position = SCNVector3(0, -0.17, 0.46)
            let opening = SCNNode(geometry: {
                let g = SCNSphere(radius: 0.055)
                g.segmentCount = 32
                g.materials = [featureMaterial(style.accent)]
                return g
            }())
            opening.scale = SCNVector3(0.72, 1.0, 0.20)
            mouth.addChildNode(opening)

            let tongue = SCNNode(geometry: {
                let g = SCNSphere(radius: 0.036)
                g.segmentCount = 28
                g.materials = [featureMaterial(style.tongue)]
                return g
            }())
            tongue.position = SCNVector3(0, -0.014, 0.014)
            tongue.scale = SCNVector3(0.72, 0.58, 0.16)
            mouth.addChildNode(tongue)
            head.addChildNode(mouth)

            // 腮红 - 脸颊外缘大圆斑（X 放大补偿脸面弧度的视觉收窄）
            for xOffset in [CGFloat(-0.40), CGFloat(0.40)] {
                let blushGeo = SCNSphere(radius: 0.15)
                blushGeo.segmentCount = 32
                blushGeo.materials = [featureMaterial(style.blush)]
                let blush = SCNNode(geometry: blushGeo)
                blush.position = SCNVector3(xOffset, -0.21, 0.42)
                blush.scale = SCNVector3(1.12, 1.0, 0.18)
                head.addChildNode(blush)
            }

            // 领巾（布布特征）- 贴胸两段近水平斜带模拟绕颈 + 胸前三瓣结
            if style.hasScarf {
                for side in [CGFloat(-1), CGFloat(1)] {
                    let strap = SCNNode(geometry: {
                        let g = SCNCapsule(capRadius: 0.028, height: 0.26)
                        g.materials = [matteMaterial(style.accent)]
                        return g
                    }())
                    strap.position = SCNVector3(side * 0.17, -0.25, 0.24)
                    strap.eulerAngles = SCNVector3(-0.15, Float(side) * 0.55, Float(side) * 1.48)
                    model.addChildNode(strap)
                }

                // 三瓣结：两瓣在上、一尖垂下
                for side in [CGFloat(-1), CGFloat(1)] {
                    let lobe = sphereNode(radius: 0.065, color: style.accent, segments: 24)
                    lobe.position = SCNVector3(side * 0.055, -0.27, 0.32)
                    lobe.scale = SCNVector3(1.0, 1.15, 0.6)
                    model.addChildNode(lobe)
                }
                let tip = sphereNode(radius: 0.05, color: style.accent, segments: 24)
                tip.position = SCNVector3(0, -0.355, 0.31)
                tip.scale = SCNVector3(1.0, 1.3, 0.55)
                model.addChildNode(tip)
            }

            // 手臂 - 粗短垂臂：顶端埋进躯干侧面（消除方肩），微微内收下垂
            for side in [CGFloat(-1), CGFloat(1)] {
                let shoulder = SCNNode()
                shoulder.name = side < 0 ? "bubu-arm-l" : "bubu-arm-r"
                shoulder.position = SCNVector3(side * 0.43, -0.39, 0.18)
                model.addChildNode(shoulder)

                let armGeometry = SCNCapsule(capRadius: 0.12, height: 0.38)
                armGeometry.materials = [matteMaterial(style.body)]
                let arm = SCNNode(geometry: armGeometry)
                arm.position = SCNVector3(side * 0.01, -0.11, 0.12)
                arm.eulerAngles = SCNVector3(-0.06, 0, Float(side) * -0.08)
                shoulder.addChildNode(arm)
            }

            // 腿脚 - 粗短腿柱大半藏在躯干里 + 前伸圆脚；髋部轴心承接踢腿。
            // 布布脚前端叠深棕脚垫
            for side in [CGFloat(-1), CGFloat(1)] {
                let hip = SCNNode()
                hip.name = side < 0 ? "bubu-foot-l" : "bubu-foot-r"
                hip.position = SCNVector3(side * 0.21, -0.82, 0.18)
                model.addChildNode(hip)

                let legGeometry = SCNCapsule(capRadius: 0.14, height: 0.25)
                legGeometry.materials = [matteMaterial(style.body)]
                let leg = SCNNode(geometry: legGeometry)
                leg.position = SCNVector3(0, 0, 0.02)
                hip.addChildNode(leg)

                // 脚掌（身体同色，向前探出）
                let foot = sphereNode(radius: 0.135, color: style.body, segments: 32)
                foot.position = SCNVector3(0, -0.09, 0.16)
                foot.scale = SCNVector3(1.08, 0.66, 1.18)
                hip.addChildNode(foot)

                // 深棕脚垫（布布特征）
                if style.hasToeCaps {
                    let toe = sphereNode(radius: 0.075, color: style.accent, segments: 24)
                    toe.position = SCNVector3(0, -0.10, 0.32)
                    toe.scale = SCNVector3(1.15, 0.72, 0.48)
                    hip.addChildNode(toe)
                }
            }

            return containerNode
        }

        // MARK: - 创建可爱的占位符模型

        static func createCutePlaceholder() -> SCNNode {
            let containerNode = SCNNode()

            // 身体 - 圆润的椭球（与预设角色统一的软胶 PBR 材质，旧 Blinn 材质在 IBL 场景里显塑料感）
            let bodyGeometry = SCNSphere(radius: 0.5)
            bodyGeometry.segmentCount = 48
            bodyGeometry.materials = [matteMaterial(NSColor(red: 1.0, green: 0.85, blue: 0.7, alpha: 1.0))] // 暖米色

            let bodyNode = SCNNode(geometry: bodyGeometry)
            bodyNode.scale = SCNVector3(1.0, 1.1, 0.9)
            containerNode.addChildNode(bodyNode)

            // 左眼
            let leftEye = createEye()
            leftEye.position = SCNVector3(x: -0.15, y: 0.15, z: 0.4)
            containerNode.addChildNode(leftEye)

            // 右眼
            let rightEye = createEye()
            rightEye.position = SCNVector3(x: 0.15, y: 0.15, z: 0.4)
            containerNode.addChildNode(rightEye)

            // 腮红 - 左
            let leftBlush = createBlush()
            leftBlush.position = SCNVector3(x: -0.28, y: 0.0, z: 0.35)
            containerNode.addChildNode(leftBlush)

            // 腮红 - 右
            let rightBlush = createBlush()
            rightBlush.position = SCNVector3(x: 0.28, y: 0.0, z: 0.35)
            containerNode.addChildNode(rightBlush)

            // 嘴巴
            let mouth = createMouth()
            mouth.position = SCNVector3(x: 0, y: -0.08, z: 0.45)
            containerNode.addChildNode(mouth)

            // 左耳
            let leftEar = createEar()
            leftEar.position = SCNVector3(x: -0.35, y: 0.45, z: 0)
            leftEar.eulerAngles = SCNVector3(0, 0, Float.pi / 6)
            containerNode.addChildNode(leftEar)

            // 右耳
            let rightEar = createEar()
            rightEar.position = SCNVector3(x: 0.35, y: 0.45, z: 0)
            rightEar.eulerAngles = SCNVector3(0, 0, -Float.pi / 6)
            containerNode.addChildNode(rightEar)

            return containerNode
        }

        static func createEye() -> SCNNode {
            let eyeContainer = SCNNode()

            // 眼白
            let whiteGeometry = SCNSphere(radius: 0.08)
            whiteGeometry.materials = [matteMaterial(.white)]
            let whiteNode = SCNNode(geometry: whiteGeometry)
            eyeContainer.addChildNode(whiteNode)

            // 瞳孔
            let pupilGeometry = SCNSphere(radius: 0.05)
            pupilGeometry.materials = [matteMaterial(NSColor(red: 0.2, green: 0.15, blue: 0.1, alpha: 1.0))]
            let pupilNode = SCNNode(geometry: pupilGeometry)
            pupilNode.position = SCNVector3(0, 0, 0.04)
            eyeContainer.addChildNode(pupilNode)

            // 高光
            let highlightGeometry = SCNSphere(radius: 0.02)
            let highlightMaterial = SCNMaterial()
            highlightMaterial.diffuse.contents = NSColor.white
            highlightMaterial.emission.contents = NSColor.white
            highlightGeometry.materials = [highlightMaterial]
            let highlightNode = SCNNode(geometry: highlightGeometry)
            highlightNode.position = SCNVector3(0.02, 0.02, 0.07)
            eyeContainer.addChildNode(highlightNode)

            return eyeContainer
        }

        static func createBlush() -> SCNNode {
            let blushGeometry = SCNSphere(radius: 0.06)
            blushGeometry.segmentCount = 24
            let blushMaterial = matteMaterial(NSColor(red: 1.0, green: 0.6, blue: 0.6, alpha: 1.0))
            blushMaterial.transparency = 0.6
            blushGeometry.materials = [blushMaterial]

            let blushNode = SCNNode(geometry: blushGeometry)
            blushNode.scale = SCNVector3(1.0, 0.6, 0.3)
            return blushNode
        }

        static func createMouth() -> SCNNode {
            // 简单的微笑嘴巴用小球表示
            let mouthGeometry = SCNTorus(ringRadius: 0.06, pipeRadius: 0.015)
            mouthGeometry.materials = [matteMaterial(NSColor(red: 0.8, green: 0.4, blue: 0.4, alpha: 1.0))]

            let mouthNode = SCNNode(geometry: mouthGeometry)
            mouthNode.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
            mouthNode.scale = SCNVector3(1.0, 1.0, 0.5)
            return mouthNode
        }

        static func createEar() -> SCNNode {
            let earGeometry = SCNSphere(radius: 0.12)
            earGeometry.materials = [matteMaterial(NSColor(red: 1.0, green: 0.85, blue: 0.7, alpha: 1.0))]

            let earNode = SCNNode(geometry: earGeometry)
            earNode.scale = SCNVector3(0.8, 1.2, 0.5)

            // 内耳
            let innerEarGeometry = SCNSphere(radius: 0.06)
            innerEarGeometry.materials = [matteMaterial(NSColor(red: 1.0, green: 0.7, blue: 0.7, alpha: 1.0))]
            let innerEarNode = SCNNode(geometry: innerEarGeometry)
            innerEarNode.position = SCNVector3(0, 0, 0.05)
            innerEarNode.scale = SCNVector3(0.8, 1.0, 0.3)
            earNode.addChildNode(innerEarNode)

            return earNode
        }

        // MARK: - 动画控制

        func updateAnimation(for state: SpriteAnimationState) {
            guard state != currentAnimation else { return }
            currentAnimation = state
            applyAnimation(state)
        }

        /// 应用状态动画（角色重建后也用它把当前状态重新挂到新节点上）
        private func applyAnimation(_ state: SpriteAnimationState) {
            // 移除现有动画并复位姿态：moveBy/rotate 型动画被中途打断会残留位移和倾斜
            // （如睡眠的侧倾、待机浮动的高度），不复位会越切越歪、越飘越高
            characterNode.removeAllActions()
            characterNode.position = SCNVector3Zero
            characterNode.scale = SCNVector3(1, 1, 1)
            characterNode.eulerAngles = SCNVector3Zero
            footLNode?.removeAction(forKey: "state-gait")
            footRNode?.removeAction(forKey: "state-gait")
            modelNode?.removeAction(forKey: "sleep-breathe")
            modelNode?.scale = SCNVector3(1, 1, 1)
            modelNode?.position = SCNVector3Zero
            modelNode?.eulerAngles = SCNVector3Zero
            resetIllustratedStateMorphs()

            switch state {
            case .idle:
                startIdleAnimation()
            case .thinking:
                startThinkingAnimation()
            case .talking:
                startTalkingAnimation()
            case .happy:
                startHappyAnimation()
            case .walking:
                startWalkingAnimation()
            case .running:
                startRunningAnimation()
            case .waving:
                startWavingAnimation()
            case .sleeping:
                startSleepingAnimation()
            }
        }

        // MARK: - 各状态动画

        func startIdleAnimation() {
            // 轻微上下浮动
            let distance: CGFloat = illustratedSpriteNode == nil ? 0.05 : 0.025
            let floatUp = SCNAction.moveBy(x: 0, y: distance, z: 0, duration: 1.5)
            floatUp.timingMode = .easeInEaseOut
            let floatDown = SCNAction.moveBy(x: 0, y: -distance, z: 0, duration: 1.5)
            floatDown.timingMode = .easeInEaseOut
            let floatSequence = SCNAction.sequence([floatUp, floatDown])
            let floatForever = SCNAction.repeatForever(floatSequence)

            // 轻微旋转
            let yRotation: CGFloat = illustratedSpriteNode == nil ? 0.05 : 0
            let zRotation: CGFloat = illustratedSpriteNode == nil ? 0 : 0.018
            let rotateLeft = SCNAction.rotateBy(x: 0, y: yRotation, z: zRotation, duration: 2.0)
            let rotateRight = SCNAction.rotateBy(x: 0, y: -yRotation, z: -zRotation, duration: 2.0)
            let rotateSequence = SCNAction.sequence([rotateLeft, rotateRight])
            let rotateForever = SCNAction.repeatForever(rotateSequence)

            characterNode.runAction(SCNAction.group([floatForever, rotateForever]))
        }

        func startThinkingAnimation() {
            // 左右摇摆
            let tiltLeft = SCNAction.rotateBy(x: 0, y: 0, z: 0.1, duration: 0.4)
            tiltLeft.timingMode = .easeInEaseOut
            let tiltRight = SCNAction.rotateBy(x: 0, y: 0, z: -0.2, duration: 0.8)
            tiltRight.timingMode = .easeInEaseOut
            let tiltBack = SCNAction.rotateBy(x: 0, y: 0, z: 0.1, duration: 0.4)
            tiltBack.timingMode = .easeInEaseOut
            let tiltSequence = SCNAction.sequence([tiltLeft, tiltRight, tiltBack])
            let tiltForever = SCNAction.repeatForever(tiltSequence)

            characterNode.runAction(tiltForever)
        }

        func startTalkingAnimation() {
            // 轻微缩放模拟说话
            let scaleUp = SCNAction.scale(by: 1.025, duration: 0.2)
            let scaleDown = SCNAction.scale(by: 1/1.025, duration: 0.2)
            let scaleSequence = SCNAction.sequence([scaleUp, scaleDown])
            let scaleForever = SCNAction.repeatForever(scaleSequence)

            characterNode.runAction(scaleForever)
            if let sprite = illustratedSpriteNode,
               let open = illustratedMorphTransition(.talk, from: 0, to: 1, duration: 0.12),
               let close = illustratedMorphTransition(.talk, from: 1, to: 0, duration: 0.16) {
                sprite.runAction(.repeatForever(.sequence([
                    open, close, .wait(duration: 0.08)
                ])), forKey: "illustrated-state")
            }
        }

        func startHappyAnimation() {
            // 跳跃动画（高度控制在相机可视范围内，避免头顶出画）
            let jumpUp = SCNAction.moveBy(x: 0, y: 0.2, z: 0, duration: 0.2)
            jumpUp.timingMode = .easeOut
            let jumpDown = SCNAction.moveBy(x: 0, y: -0.2, z: 0, duration: 0.2)
            jumpDown.timingMode = .easeIn
            let jumpSequence = SCNAction.sequence([jumpUp, jumpDown])
            let jumpRepeat = SCNAction.repeat(jumpSequence, count: 3)

            let celebrate: SCNAction
            if illustratedSpriteNode != nil {
                let tiltLeft = SCNAction.rotateBy(x: 0, y: 0, z: 0.10, duration: 0.15)
                let tiltRight = SCNAction.rotateBy(x: 0, y: 0, z: -0.20, duration: 0.30)
                let center = SCNAction.rotateBy(x: 0, y: 0, z: 0.10, duration: 0.15)
                celebrate = .sequence([tiltLeft, tiltRight, center])
            } else {
                celebrate = SCNAction.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 0.6)
            }

            characterNode.runAction(SCNAction.group([jumpRepeat, celebrate])) { [weak self] in
                self?.startIdleAnimation()
            }
        }

        func startWalkingAnimation() {
            startGaitAnimation(stepDuration: 0.20, lift: 0.038, tilt: 0.025)
        }

        func startRunningAnimation() {
            startGaitAnimation(stepDuration: 0.105, lift: 0.07, tilt: 0.045)
        }

        private func startGaitAnimation(
            stepDuration: TimeInterval,
            lift: CGFloat,
            tilt: CGFloat
        ) {
            let up = SCNAction.moveBy(x: 0, y: lift, z: 0, duration: stepDuration)
            up.timingMode = .easeOut
            let down = SCNAction.moveBy(x: 0, y: -lift, z: 0, duration: stepDuration)
            down.timingMode = .easeIn
            let lean = SCNAction.rotateBy(x: 0, y: 0, z: tilt, duration: stepDuration)
            let leanBack = SCNAction.rotateBy(x: 0, y: 0, z: -tilt, duration: stepDuration)
            characterNode.runAction(.group([
                .repeatForever(.sequence([up, down])),
                .repeatForever(.sequence([lean, leanBack]))
            ]))

            if let sprite = illustratedSpriteNode,
               let leftUp = illustratedMorphTransition(.leftStep, from: 0, to: 1, duration: stepDuration),
               let leftDown = illustratedMorphTransition(.leftStep, from: 1, to: 0, duration: stepDuration),
               let rightUp = illustratedMorphTransition(.rightStep, from: 0, to: 1, duration: stepDuration),
               let rightDown = illustratedMorphTransition(.rightStep, from: 1, to: 0, duration: stepDuration) {
                sprite.runAction(.repeatForever(.sequence([
                    leftUp, leftDown, rightUp, rightDown
                ])), forKey: "illustrated-state")
            } else {
                startFallbackLimbGait(stepDuration: stepDuration)
            }
        }

        private func startFallbackLimbGait(stepDuration: TimeInterval) {
            func run(on foot: SCNNode?, delayed: Bool) {
                guard let foot else { return }
                let forward = SCNAction.rotateBy(x: -0.48, y: 0, z: 0, duration: stepDuration)
                let backward = SCNAction.rotateBy(x: 0.48, y: 0, z: 0, duration: stepDuration)
                let gait = SCNAction.repeatForever(.sequence([forward, backward]))
                foot.runAction(delayed ? .sequence([.wait(duration: stepDuration), gait]) : gait,
                               forKey: "state-gait")
            }
            run(on: footLNode, delayed: false)
            run(on: footRNode, delayed: true)
        }

        func startWavingAnimation() {
            let rise = SCNAction.moveBy(x: 0, y: 0.035, z: 0, duration: 0.25)
            let settle = SCNAction.moveBy(x: 0, y: -0.035, z: 0, duration: 0.25)
            characterNode.runAction(.repeat(.sequence([rise, settle]), count: 4))
            gestureWave()
        }

        func startSleepingAnimation() {
            let settle: SCNAction
            if let sprite = illustratedSpriteNode,
               let sleepImage = illustratedSleepImage {
                // 专用趴睡帧：头伏在手机/前爪上，身体横在后方，不再旋转整张立绘。
                sprite.geometry?.firstMaterial?.diffuse.contents = sleepImage
                let sleepAspect = sleepImage.size.width / max(sleepImage.size.height, 1)
                sprite.scale = SCNVector3(sleepAspect / max(illustratedBaseAspect, 0.01), 1, 1)
                settle = .group([
                    .move(to: SCNVector3(0, -0.34, 0), duration: 0.58),
                    .scale(to: 0.92, duration: 0.58)
                ])
            } else {
                // 没有专用姿态的角色先采用伏低、横向舒展的回退，而不是整图旋转 90°。
                settle = .group([
                    .move(to: SCNVector3(0.12, -0.40, 0), duration: 0.58),
                    .rotateTo(x: 0, y: 0, z: -0.10, duration: 0.58),
                    .customAction(duration: 0.58) { node, elapsed in
                        let p = min(max(elapsed / 0.58, 0), 1)
                        let eased = p * p * (3 - 2 * p)
                        node.scale = SCNVector3(1 + 0.10 * eased, 1 - 0.28 * eased, 1)
                    }
                ])
            }
            settle.timingMode = .easeInEaseOut
            characterNode.runAction(settle, forKey: "sleep-pose")

            // 独立驱动身体呼吸：胸腹上下起伏并略微扩张，每个周期精确回到基准。
            let breathe = SCNAction.customAction(duration: 2.6) { node, elapsed in
                let phase = elapsed / 2.6 * .pi * 2
                let inhale = (sin(phase - .pi / 2) + 1) / 2
                node.scale = SCNVector3(1 + 0.012 * inhale, 1 + 0.038 * inhale, 1)
                node.position.y = 0.018 * inhale
            }
            breathe.timingMode = .easeInEaseOut
            modelNode?.runAction(.repeatForever(breathe), forKey: "sleep-breathe")
        }
    }
}

/// AppKit 没有 UIKit 的 `require(toFail:)` 设置方法，需通过可覆写关系声明
/// 让双击识别优先，避免第一次单击提前触发身体互动。
private final class SceneSingleClickGestureRecognizer: NSClickGestureRecognizer {
    override func shouldRequireFailure(of otherGestureRecognizer: NSGestureRecognizer) -> Bool {
        guard let click = otherGestureRecognizer as? NSClickGestureRecognizer else { return false }
        return click.numberOfClicksRequired > numberOfClicksRequired
    }
}

// MARK: - 3D 精灵视图

struct Sprite3DView: View {
    @ObservedObject var viewModel: SpriteViewModel
    /// 点击未命中角色部位时的回落行为（取词/打开面板），由 SpriteContainerView 注入
    var onBackgroundTap: (() -> Void)? = nil
    var onBodyPartTap: ((SpriteBodyPart) -> Void)? = nil
    var onDoubleTap: (() -> Void)? = nil

    /// 精灵区域尺寸：跟 2D 模式一致，缩放靠放大视图而不是放大场景节点
    /// （放大节点会超出相机视野截掉头顶）；上限对齐窗口宽度 280
    private var spriteSize: CGFloat {
        min(150 * viewModel.scale, 280)
    }

    private var characterHasPhone: Bool {
        ["bubu", "yier_phone"].contains(viewModel.currentCharacter.imageName)
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            // 气泡区域 - 紧贴精灵上方，内容自动撑开高度
            if viewModel.showBubble, let bubble = viewModel.currentBubble {
                BubbleView(bubble: bubble, onDismiss: {
                    viewModel.hideBubble()
                }, onRetranslate: { lang in
                    viewModel.retranslate(to: lang)
                })
                // 从尾巴处弹出，像对白框从嘴边冒出来
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.1, anchor: .bottom).combined(with: .opacity),
                    removal: .opacity
                ))
                .padding(.horizontal, 8)
            }

            // 3D 精灵区域（底部固定）
            ZStack {
                SceneKitView(
                    viewModel: viewModel,
                    animationState: viewModel.animationState,
                    facingDirection: viewModel.facingDirection,
                    onBackgroundTap: onBackgroundTap,
                    onBodyPartTap: onBodyPartTap,
                    onDoubleTap: onDoubleTap
                )
                .frame(width: spriteSize, height: spriteSize)
                .opacity(viewModel.opacity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(viewModel.currentCharacter.name)角色")
                .accessibilityHint(characterHasPhone ? "点击手机和布布聊天；点击其他部位会有不同反应" : "点击角色互动")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction {
                    onBodyPartTap?(characterHasPhone ? .phone : .head)
                }

                // 拖拽高亮
                if viewModel.isDragOver {
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(BuBuColors.skyBlue, lineWidth: 3)
                        .frame(width: spriteSize * 0.8, height: spriteSize * 0.8)
                        .scaleEffect(1.1)
                        .animation(.easeInOut(duration: 0.2), value: viewModel.isDragOver)
                }

                // 睡眠效果
                if viewModel.animationState == .sleeping {
                    ZzzView()
                        .offset(x: -48, y: -28)
                }

                // 思考效果
                if viewModel.animationState == .thinking {
                    ThinkingDotsView()
                        .offset(x: 60, y: 0)
                }

            }
            .frame(height: spriteSize)
        }
    }
}

// MARK: - 预览

#Preview {
    Sprite3DView(viewModel: SpriteViewModel())
        .frame(width: 280, height: 400)
        .background(BuBuColors.softCloud)
}
