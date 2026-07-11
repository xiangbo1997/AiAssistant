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

        return scnView
    }

    func updateNSView(_ scnView: SCNView, context: Context) {
        context.coordinator.updateCharacter(viewModel.currentCharacter)
        context.coordinator.updateAnimation(for: animationState)
        context.coordinator.updateScale(viewModel.scale)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    // MARK: - Coordinator

    class Coordinator {
        let scene: SCNScene
        private(set) var characterNode: SCNNode
        let cameraNode: SCNNode
        var currentAnimation: SpriteAnimationState = .idle

        // 当前角色标识（切换角色时据此重建 3D 模型）
        private var currentCharacterID: UUID

        // 微动作目标节点（仅恐龙套装模型存在，占位符模型时为 nil，动画自动跳过）
        private var modelNode: SCNNode?
        private var headNode: SCNNode?
        private var eyesNode: SCNNode?
        private var tailNode: SCNNode?
        private var armLNode: SCNNode?
        private var armRNode: SCNNode?
        private var footLNode: SCNNode?
        private var footRNode: SCNNode?

        init(viewModel: SpriteViewModel) {
            scene = SCNScene()

            // 创建角色节点
            currentCharacterID = viewModel.currentCharacter.id
            characterNode = Coordinator.createCharacterNode(for: viewModel.currentCharacter)
            scene.rootNode.addChildNode(characterNode)


            // 地面软阴影：静态半透明圆片替代真实阴影贴图（性能考虑不开 shadow map），
            // 随浮动节奏轻微缩放，制造"离地远近"的错觉
            let shadowGeometry = SCNCylinder(radius: 0.30, height: 0.005)
            let shadowMaterial = SCNMaterial()
            shadowMaterial.diffuse.contents = NSColor(calibratedRed: 0.25, green: 0.18, blue: 0.16, alpha: 0.22)
            shadowMaterial.lightingModel = .constant
            shadowGeometry.materials = [shadowMaterial]
            let shadow = SCNNode(geometry: shadowGeometry)
            shadow.position = SCNVector3(0, -0.72, 0)
            shadow.scale = SCNVector3(1.0, 1.0, 0.8)
            scene.rootNode.addChildNode(shadow)

            // 阴影呼吸：与待机浮动同为 1.5s 半周期，角色升高时阴影缩小变淡
            let shadowShrink = SCNAction.scale(to: 0.82, duration: 1.5)
            shadowShrink.timingMode = .easeInEaseOut
            let shadowGrow = SCNAction.scale(to: 1.0, duration: 1.5)
            shadowGrow.timingMode = .easeInEaseOut
            shadow.runAction(.repeatForever(.sequence([shadowShrink, shadowGrow])))

            // 创建相机：略微抬高并俯视，露出头顶的棘刺背脊，也让姿态更立体
            // （纯平视会把前后排列的棘刺压成一根）
            cameraNode = SCNNode()
            cameraNode.camera = SCNCamera()
            cameraNode.camera?.fieldOfView = 40  // 收窄视角减轻透视畸变，更接近贴纸的正投影观感
            cameraNode.position = SCNVector3(x: 0, y: 0.45, z: 3.1)
            cameraNode.look(at: SCNVector3(0, -0.05, 0))
            scene.rootNode.addChildNode(cameraNode)

            // 基于图像的环境光照（IBL）：程序化暖色渐变作环境贴图，
            // 让 PBR 材质表面产生柔和的环境反射与自然明暗过渡——
            // 这是软胶质感的关键，纯 diffuse 靠打光做不出这种通透感
            scene.lightingEnvironment.contents = Coordinator.makeEnvironmentImage()
            scene.lightingEnvironment.intensity = 1.15

            // 环境光：压低（IBL 已提供大部分环境照明），仅补一点暖色底光
            let ambientLight = SCNNode()
            ambientLight.light = SCNLight()
            ambientLight.light?.type = .ambient
            ambientLight.light?.color = NSColor(red: 0.42, green: 0.40, blue: 0.38, alpha: 1.0)
            scene.rootNode.addChildNode(ambientLight)

            // 主光源：柔和面光（area light）替代硬平行光，高光更柔、边缘过渡更自然
            let mainLight = SCNNode()
            mainLight.light = SCNLight()
            mainLight.light?.type = .directional
            mainLight.light?.color = NSColor(red: 1.0, green: 0.97, blue: 0.92, alpha: 1.0)
            mainLight.light?.intensity = 850
            mainLight.position = SCNVector3(x: 2.2, y: 3.2, z: 2.5)
            mainLight.look(at: SCNVector3(0, -0.1, 0))
            scene.rootNode.addChildNode(mainLight)

            // 补光（暖粉色调，衬托白色身体与粉帽兜）
            let fillLight = SCNNode()
            fillLight.light = SCNLight()
            fillLight.light?.type = .directional
            fillLight.light?.color = NSColor(red: 0.98, green: 0.85, blue: 0.83, alpha: 1.0)
            fillLight.light?.intensity = 350
            fillLight.position = SCNVector3(x: -2.2, y: 0.8, z: 2.0)
            fillLight.look(at: SCNVector3(0, 0, 0))
            scene.rootNode.addChildNode(fillLight)

            // 轮廓光：从后上方勾一道冷色边光，把角色从背景里"托"出来，增强立体
            let rimLight = SCNNode()
            rimLight.light = SCNLight()
            rimLight.light?.type = .directional
            rimLight.light?.color = NSColor(red: 0.80, green: 0.86, blue: 0.98, alpha: 1.0)
            rimLight.light?.intensity = 400
            rimLight.position = SCNVector3(x: -1.0, y: 2.0, z: -2.5)
            rimLight.look(at: SCNVector3(0, 0, 0))
            scene.rootNode.addChildNode(rimLight)

            // 设置背景透明
            scene.background.contents = NSColor.clear

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
            tailNode = characterNode.childNode(withName: "bubu-tail", recursively: true)
            armLNode = characterNode.childNode(withName: "bubu-arm-l", recursively: true)
            armRNode = characterNode.childNode(withName: "bubu-arm-r", recursively: true)
            footLNode = characterNode.childNode(withName: "bubu-foot-l", recursively: true)
            footRNode = characterNode.childNode(withName: "bubu-foot-r", recursively: true)
        }

        /// 角色切换：重建 3D 模型并重新挂载动画（此前切换角色 3D 模型不会更新）
        func updateCharacter(_ character: SpriteCharacter) {
            guard character.id != currentCharacterID else { return }
            currentCharacterID = character.id

            characterNode.removeFromParentNode()
            characterNode = Coordinator.createCharacterNode(for: character)
            scene.rootNode.addChildNode(characterNode)

            bindMicroNodes()
            applyAnimation(currentAnimation)
            startMicroAnimations()
        }

        // MARK: - 微动作（眨眼/摇尾/随机小动作）

        /// 启动所有微动作循环。全部挂在子节点上，与外层状态动画共存
        private func startMicroAnimations() {
            startBlinking()
            startTailWag()
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

        /// 眨眼：随机间隔 2.5~6 秒，偶尔连眨两次更传神
        private func startBlinking() {
            guard let eyes = eyesNode else { return }

            let close = SCNAction.customAction(duration: 0.07) { node, elapsed in
                let progress = elapsed / 0.07
                node.scale = SCNVector3(1, 1 - 0.88 * progress, 1)
            }
            let open = SCNAction.customAction(duration: 0.09) { node, elapsed in
                let progress = elapsed / 0.09
                node.scale = SCNVector3(1, 0.12 + 0.88 * progress, 1)
            }
            let blinkOnce = SCNAction.sequence([close, open])

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

        /// 尾巴摇摆：轻幅慢摆，间歇停顿，像随呼吸自然晃动
        private func startTailWag() {
            guard let tail = tailNode else { return }

            let wagLeft = SCNAction.rotateBy(x: 0, y: 0, z: 0.22, duration: 0.5)
            wagLeft.timingMode = .easeInEaseOut
            let wagRight = SCNAction.rotateBy(x: 0, y: 0, z: -0.44, duration: 0.9)
            wagRight.timingMode = .easeInEaseOut
            let wagBack = SCNAction.rotateBy(x: 0, y: 0, z: 0.22, duration: 0.5)
            wagBack.timingMode = .easeInEaseOut

            let loop = SCNAction.repeatForever(.sequence([
                wagLeft, wagRight, wagBack,
                .wait(duration: 2.5, withRange: 2.0)
            ]))
            tail.runAction(loop, forKey: "wag")
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

        /// 挥手打招呼：右臂举起晃两下再放下
        private func gestureWave() {
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

        /// 开心踢腿：双脚交替向前踢两轮，像坐着晃腿
        private func gestureKickFeet() {
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
            guard let head = headNode else { return }
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

            // 预设角色使用代码构建的恐龙套装 3D 模型（有 usdz/scn 文件时优先加载文件）
            switch character.imageName {
            case "bubu":
                return createDinoNode(style: .bubu)   // 蓝色恐龙装 + 棕色宝宝
            case "yier":
                return createDinoNode(style: .yier)   // 粉色恐龙装 + 白色宝宝
            default:
                // 自定义角色暂无 3D 模型：显示可爱占位符
                return createCutePlaceholder()
            }
        }

        // MARK: - 恐龙套装 3D 模型（布布/逸尔共用一套建模，配色与特征参数化）

        /// 恐龙套装角色外观参数。
        /// 布布 = 棕色宝宝 + 蓝色恐龙装（奶油肚皮）；逸尔 = 白色宝宝 + 粉色恐龙装（眼斑+蝴蝶结）
        struct DinoStyle {
            let hood: NSColor       // 帽兜/爪垫/尾巴
            let body: NSColor       // 身体/脸/脚
            let blush: NSColor      // 腮红
            let accent: NSColor     // 眼睛/嘴
            let belly: NSColor?     // 肚皮贴片（布布的奶油肚），nil 表示无
            let hasEyePatch: Bool   // 右眼深棕眼斑（逸尔特征）
            let hasBow: Bool        // 胸前蝴蝶结（逸尔特征）

            static let bubu = DinoStyle(
                hood: NSColor(red: 0.56, green: 0.80, blue: 0.91, alpha: 1.0),
                body: NSColor(red: 0.80, green: 0.56, blue: 0.38, alpha: 1.0),
                blush: NSColor(red: 0.99, green: 0.80, blue: 0.55, alpha: 1.0),
                accent: NSColor(red: 0.24, green: 0.16, blue: 0.12, alpha: 1.0),
                belly: NSColor(red: 0.96, green: 0.88, blue: 0.74, alpha: 1.0),
                hasEyePatch: false,
                hasBow: false
            )

            static let yier = DinoStyle(
                hood: NSColor(red: 0.96, green: 0.72, blue: 0.76, alpha: 1.0),
                body: NSColor(red: 0.99, green: 0.97, blue: 0.95, alpha: 1.0),
                blush: NSColor(red: 0.98, green: 0.62, blue: 0.62, alpha: 1.0),
                accent: NSColor(red: 0.20, green: 0.13, blue: 0.10, alpha: 1.0),
                belly: nil,
                hasEyePatch: true,
                hasBow: true
            )
        }

        /// 通用配色（两只角色共用）
        private enum SharedPalette {
            static let spikeWhite = NSColor(red: 0.99, green: 0.99, blue: 0.97, alpha: 1.0)  // 棘刺白
            static let patchBrown = NSColor(red: 0.33, green: 0.23, blue: 0.19, alpha: 1.0)  // 眼斑/蝴蝶结深棕
        }

        /// 软胶/绒毛质感 PBR 材质：高粗糙度 + 零金属度模拟毛绒公仔表面，
        /// 配合场景的环境光照产生柔和的明暗过渡，消除塑料拼接感。
        /// clearcoat 加一层极淡的透明涂层，制造软软的高光边缘
        private static func matteMaterial(_ color: NSColor) -> SCNMaterial {
            let material = SCNMaterial()
            material.lightingModel = .physicallyBased
            material.diffuse.contents = color
            material.metalness.contents = 0.0
            material.roughness.contents = 0.85          // 高粗糙 = 绒毛哑光
            material.clearCoat.contents = 0.25          // 淡涂层高光，软胶质感
            material.clearCoatRoughness.contents = 0.6
            material.diffuse.mipFilter = .linear
            return material
        }

        private static func sphereNode(radius: CGFloat, color: NSColor, segments: Int = 48) -> SCNNode {
            let geometry = SCNSphere(radius: radius)
            geometry.segmentCount = segments
            geometry.materials = [matteMaterial(color)]
            return SCNNode(geometry: geometry)
        }

        /// 构建恐龙套装角色（布布/逸尔共用建模，外观由 style 决定）。
        /// 节点分层专为动画设计：外层容器承接状态动画（浮动/跳跃等），
        /// 内层 bubu-model / bubu-head / bubu-eyes / bubu-tail 承接微动作，互不干扰
        static func createDinoNode(style: DinoStyle) -> SCNNode {
            let containerNode = SCNNode()

            // 内层模型根节点（小跳等全身微动作挂在这里，不与外层状态动画冲突）
            let model = SCNNode()
            model.name = "bubu-model"
            containerNode.addChildNode(model)

            // 身体 - 圆润连体衣
            let body = sphereNode(radius: 0.30, color: style.body, segments: 48)
            body.position = SCNVector3(0, -0.25, 0)
            body.scale = SCNVector3(1.0, 0.95, 0.9)
            model.addChildNode(body)

            // 肚皮贴片（布布的奶油肚）
            if let bellyColor = style.belly {
                let belly = sphereNode(radius: 0.22, color: bellyColor)
                belly.position = SCNVector3(0, -0.24, 0.14)
                belly.scale = SCNVector3(0.85, 0.80, 0.45)
                model.addChildNode(belly)
            }

            // 胸前蝴蝶结 - 深棕两翼 + 中心结（逸尔特征）
            if style.hasBow {
                let bow = SCNNode()
                bow.position = SCNVector3(0, -0.10, 0.25)
                for side in [Float(-1), Float(1)] {
                    let wingGeometry = SCNCone(topRadius: 0, bottomRadius: 0.042, height: 0.09)
                    wingGeometry.materials = [matteMaterial(SharedPalette.patchBrown)]
                    let wing = SCNNode(geometry: wingGeometry)
                    wing.position = SCNVector3(CGFloat(side) * 0.055, 0, 0)
                    wing.eulerAngles = SCNVector3(0, 0, side * Float.pi / 2)
                    bow.addChildNode(wing)
                }
                let knot = sphereNode(radius: 0.026, color: SharedPalette.patchBrown, segments: 16)
                bow.addChildNode(knot)
                model.addChildNode(bow)
            }

            // 头部组（歪头/张望动画的旋转轴心在这里）
            let head = SCNNode()
            head.name = "bubu-head"
            head.position = SCNVector3(0, 0.26, 0.02)
            model.addChildNode(head)

            // 恐龙帽兜 - 粉色大球包裹头部（前后略压扁，让白脸从兜口探出）
            let hood = sphereNode(radius: 0.40, color: style.hood, segments: 48)
            hood.position = SCNVector3(0, 0.02, -0.04)
            hood.scale = SCNVector3(1.0, 1.0, 0.92)
            head.addChildNode(hood)

            // 脸部 - 白色球明显探出帽兜前方，粉色兜边框住白脸
            let face = sphereNode(radius: 0.33, color: style.body, segments: 48)
            face.position = SCNVector3(0, -0.02, 0.15)
            face.scale = SCNVector3(1.0, 0.92, 0.85)
            head.addChildNode(face)

            // 右眼眼斑 - 深棕椭圆贴片（逸尔的标志特征），微微凸出脸面
            if style.hasEyePatch {
                let patch = sphereNode(radius: 0.095, color: SharedPalette.patchBrown, segments: 24)
                patch.position = SCNVector3(0.12, 0.05, 0.39)
                patch.scale = SCNVector3(1.1, 1.3, 0.3)
                head.addChildNode(patch)
            }

            // 帽兜棘刺 - 一排白色圆钝小角，从头顶前缘向后依次排列成锯齿背脊（布布恐龙装标志）。
            // 每枚沿脸朝向的斜前上方指出、间距拉开，正面能看到错落的一排尖；
            // topRadius>0 让尖端钝圆，像绒毛玩偶的软刺
            let spikeConfigs: [(position: SCNVector3, tiltX: Float, radius: CGFloat, height: CGFloat)] = [
                (SCNVector3(0, 0.47, 0.22), 0.75, 0.048, 0.14),   // 最前刺（大幅前倾，探出帽兜前额）
                (SCNVector3(0, 0.54, 0.06), 0.38, 0.054, 0.17),   // 前中刺
                (SCNVector3(0, 0.56, -0.11), 0.02, 0.052, 0.16),  // 顶刺（最高）
                (SCNVector3(0, 0.49, -0.27), -0.45, 0.044, 0.12)  // 后刺
            ]
            for config in spikeConfigs {
                let spikeGeometry = SCNCone(topRadius: config.radius * 0.3, bottomRadius: config.radius, height: config.height)
                spikeGeometry.materials = [matteMaterial(SharedPalette.spikeWhite)]
                let spike = SCNNode(geometry: spikeGeometry)
                spike.position = config.position
                spike.eulerAngles = SCNVector3(config.tiltX, 0, 0)
                head.addChildNode(spike)
            }

            // 眼睛组（眨眼动画对该组做 Y 轴压扁）
            let eyes = SCNNode()
            eyes.name = "bubu-eyes"
            eyes.position = SCNVector3(0, 0.04, 0.42)
            head.addChildNode(eyes)

            for xOffset in [CGFloat(-0.11), CGFloat(0.11)] {
                let eye = sphereNode(radius: 0.048, color: style.accent, segments: 24)
                eye.position = SCNVector3(xOffset, 0, 0)
                eyes.addChildNode(eye)

                let highlightGeometry = SCNSphere(radius: 0.016)
                let highlightMaterial = SCNMaterial()
                highlightMaterial.diffuse.contents = NSColor.white
                highlightMaterial.emission.contents = NSColor.white
                highlightGeometry.materials = [highlightMaterial]
                let highlight = SCNNode(geometry: highlightGeometry)
                highlight.position = SCNVector3(xOffset + 0.015, 0.015, 0.04)
                eyes.addChildNode(highlight)
            }

            // 腮红 - 半透明粉色圆片
            for xOffset in [CGFloat(-0.21), CGFloat(0.21)] {
                let blush = sphereNode(radius: 0.055, color: style.blush, segments: 24)
                blush.geometry?.firstMaterial?.transparency = 0.65
                blush.position = SCNVector3(xOffset, -0.06, 0.37)
                blush.scale = SCNVector3(1.0, 0.6, 0.35)
                head.addChildNode(blush)
            }

            // 嘴巴 - 小巧的深色微笑点
            let mouth = sphereNode(radius: 0.022, color: style.accent, segments: 16)
            mouth.position = SCNVector3(0, -0.09, 0.43)
            mouth.scale = SCNVector3(1.5, 0.7, 0.5)
            head.addChildNode(mouth)

            // 手臂 - 圆润短胖胶囊 + 末端圆爪，整组挂在肩部轴心节点下：
            // 挥手/摆臂动画旋转肩部组节点，手臂绕肩膀转才自然（绕自身中心会像螺旋桨）
            for side in [CGFloat(-1), CGFloat(1)] {
                let shoulder = SCNNode()
                shoulder.name = side < 0 ? "bubu-arm-l" : "bubu-arm-r"
                shoulder.position = SCNVector3(side * 0.20, -0.05, 0.05)
                model.addChildNode(shoulder)

                let armGeometry = SCNCapsule(capRadius: 0.075, height: 0.20)
                armGeometry.materials = [matteMaterial(style.body)]
                let arm = SCNNode(geometry: armGeometry)
                arm.position = SCNVector3(side * 0.07, -0.09, 0.01)
                arm.eulerAngles = SCNVector3(0, 0, Float(side) * -0.7)
                shoulder.addChildNode(arm)

                // 圆爪垫（套装手部）
                let paw = sphereNode(radius: 0.068, color: style.hood, segments: 24)
                paw.position = SCNVector3(side * 0.155, -0.155, 0.02)
                shoulder.addChildNode(paw)
            }

            // 脚 - 套装小脚丫，明显朝前伸出；踝部轴心节点承接踢腿动画
            for side in [CGFloat(-1), CGFloat(1)] {
                let ankle = SCNNode()
                ankle.name = side < 0 ? "bubu-foot-l" : "bubu-foot-r"
                ankle.position = SCNVector3(side * 0.135, -0.52, 0.04)
                model.addChildNode(ankle)

                let foot = sphereNode(radius: 0.10, color: style.body, segments: 24)
                foot.position = SCNVector3(0, -0.02, 0.07)
                foot.scale = SCNVector3(1.0, 0.5, 1.45)  // 压扁拉长成脚掌形
                ankle.addChildNode(foot)
            }

            // 尾巴 - 粉色圆钝小锥从身后翘起（待机时轻轻摇摆），尖端圆润更像玩偶尾
            let tailGeometry = SCNCone(topRadius: 0.028, bottomRadius: 0.10, height: 0.24)
            tailGeometry.materials = [matteMaterial(style.hood)]
            let tail = SCNNode(geometry: tailGeometry)
            tail.name = "bubu-tail"
            tail.position = SCNVector3(0, -0.40, -0.28)
            tail.eulerAngles = SCNVector3(-2.2, 0, 0)
            model.addChildNode(tail)

            return containerNode
        }

        // MARK: - 创建可爱的占位符模型

        static func createCutePlaceholder() -> SCNNode {
            let containerNode = SCNNode()

            // 身体 - 圆润的椭球
            let bodyGeometry = SCNSphere(radius: 0.5)
            bodyGeometry.segmentCount = 48
            let bodyMaterial = SCNMaterial()
            bodyMaterial.diffuse.contents = NSColor(red: 1.0, green: 0.85, blue: 0.7, alpha: 1.0) // 暖米色
            bodyMaterial.specular.contents = NSColor.white
            bodyMaterial.shininess = 0.3
            bodyGeometry.materials = [bodyMaterial]

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
            let whiteMaterial = SCNMaterial()
            whiteMaterial.diffuse.contents = NSColor.white
            whiteGeometry.materials = [whiteMaterial]
            let whiteNode = SCNNode(geometry: whiteGeometry)
            eyeContainer.addChildNode(whiteNode)

            // 瞳孔
            let pupilGeometry = SCNSphere(radius: 0.05)
            let pupilMaterial = SCNMaterial()
            pupilMaterial.diffuse.contents = NSColor(red: 0.2, green: 0.15, blue: 0.1, alpha: 1.0)
            pupilGeometry.materials = [pupilMaterial]
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
            let blushMaterial = SCNMaterial()
            blushMaterial.diffuse.contents = NSColor(red: 1.0, green: 0.6, blue: 0.6, alpha: 0.6)
            blushMaterial.transparency = 0.6
            blushGeometry.materials = [blushMaterial]

            let blushNode = SCNNode(geometry: blushGeometry)
            blushNode.scale = SCNVector3(1.0, 0.6, 0.3)
            return blushNode
        }

        static func createMouth() -> SCNNode {
            // 简单的微笑嘴巴用小球表示
            let mouthGeometry = SCNTorus(ringRadius: 0.06, pipeRadius: 0.015)
            let mouthMaterial = SCNMaterial()
            mouthMaterial.diffuse.contents = NSColor(red: 0.8, green: 0.4, blue: 0.4, alpha: 1.0)
            mouthGeometry.materials = [mouthMaterial]

            let mouthNode = SCNNode(geometry: mouthGeometry)
            mouthNode.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
            mouthNode.scale = SCNVector3(1.0, 1.0, 0.5)
            return mouthNode
        }

        static func createEar() -> SCNNode {
            let earGeometry = SCNSphere(radius: 0.12)
            let earMaterial = SCNMaterial()
            earMaterial.diffuse.contents = NSColor(red: 1.0, green: 0.85, blue: 0.7, alpha: 1.0)
            earGeometry.materials = [earMaterial]

            let earNode = SCNNode(geometry: earGeometry)
            earNode.scale = SCNVector3(0.8, 1.2, 0.5)

            // 内耳
            let innerEarGeometry = SCNSphere(radius: 0.06)
            let innerEarMaterial = SCNMaterial()
            innerEarMaterial.diffuse.contents = NSColor(red: 1.0, green: 0.7, blue: 0.7, alpha: 1.0)
            innerEarGeometry.materials = [innerEarMaterial]
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
            // 移除现有动画
            characterNode.removeAllActions()

            switch state {
            case .idle:
                startIdleAnimation()
            case .thinking:
                startThinkingAnimation()
            case .talking:
                startTalkingAnimation()
            case .happy:
                startHappyAnimation()
            case .sleeping:
                startSleepingAnimation()
            }
        }

        func updateScale(_ scale: CGFloat) {
            characterNode.scale = SCNVector3(Float(scale), Float(scale), Float(scale))
        }

        // MARK: - 各状态动画

        func startIdleAnimation() {
            // 轻微上下浮动
            let floatUp = SCNAction.moveBy(x: 0, y: 0.05, z: 0, duration: 1.5)
            floatUp.timingMode = .easeInEaseOut
            let floatDown = SCNAction.moveBy(x: 0, y: -0.05, z: 0, duration: 1.5)
            floatDown.timingMode = .easeInEaseOut
            let floatSequence = SCNAction.sequence([floatUp, floatDown])
            let floatForever = SCNAction.repeatForever(floatSequence)

            // 轻微旋转
            let rotateLeft = SCNAction.rotateBy(x: 0, y: 0.05, z: 0, duration: 2.0)
            let rotateRight = SCNAction.rotateBy(x: 0, y: -0.05, z: 0, duration: 2.0)
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
            let scaleUp = SCNAction.scale(by: 1.05, duration: 0.2)
            let scaleDown = SCNAction.scale(by: 1/1.05, duration: 0.2)
            let scaleSequence = SCNAction.sequence([scaleUp, scaleDown])
            let scaleForever = SCNAction.repeatForever(scaleSequence)

            characterNode.runAction(scaleForever)
        }

        func startHappyAnimation() {
            // 跳跃动画
            let jumpUp = SCNAction.moveBy(x: 0, y: 0.3, z: 0, duration: 0.2)
            jumpUp.timingMode = .easeOut
            let jumpDown = SCNAction.moveBy(x: 0, y: -0.3, z: 0, duration: 0.2)
            jumpDown.timingMode = .easeIn
            let jumpSequence = SCNAction.sequence([jumpUp, jumpDown])
            let jumpRepeat = SCNAction.repeat(jumpSequence, count: 3)

            // 旋转
            let spin = SCNAction.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 0.6)

            characterNode.runAction(SCNAction.group([jumpRepeat, spin])) { [weak self] in
                self?.startIdleAnimation()
            }
        }

        func startSleepingAnimation() {
            // 缓慢呼吸
            let breatheIn = SCNAction.scale(by: 1.03, duration: 2.0)
            breatheIn.timingMode = .easeInEaseOut
            let breatheOut = SCNAction.scale(by: 1/1.03, duration: 2.0)
            breatheOut.timingMode = .easeInEaseOut
            let breatheSequence = SCNAction.sequence([breatheIn, breatheOut])
            let breatheForever = SCNAction.repeatForever(breatheSequence)

            // 轻微倾斜
            let tilt = SCNAction.rotateTo(x: 0, y: 0, z: 0.1, duration: 1.0)

            characterNode.runAction(SCNAction.group([breatheForever, tilt]))
        }
    }
}

// MARK: - 3D 精灵视图

struct Sprite3DView: View {
    @ObservedObject var viewModel: SpriteViewModel

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
                SceneKitView(viewModel: viewModel, animationState: viewModel.animationState)
                    .frame(width: 150, height: 150)
                    .opacity(viewModel.opacity)

                // 拖拽高亮
                if viewModel.isDragOver {
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(BuBuColors.skyBlue, lineWidth: 3)
                        .frame(width: 120, height: 120)
                        .scaleEffect(1.1)
                        .animation(.easeInOut(duration: 0.2), value: viewModel.isDragOver)
                }

                // 睡眠效果
                if viewModel.animationState == .sleeping {
                    ZzzView()
                        .offset(x: 50, y: -30)
                }

                // 思考效果
                if viewModel.animationState == .thinking {
                    ThinkingDotsView()
                        .offset(x: 60, y: 0)
                }
            }
            .frame(height: 150)
        }
    }
}

// MARK: - 预览

#Preview {
    Sprite3DView(viewModel: SpriteViewModel())
        .frame(width: 280, height: 400)
        .background(BuBuColors.softCloud)
}
