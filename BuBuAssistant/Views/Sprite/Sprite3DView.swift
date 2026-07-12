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
            earLNode = characterNode.childNode(withName: "bubu-ear-l", recursively: true)
            earRNode = characterNode.childNode(withName: "bubu-ear-r", recursively: true)
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

            // 预设角色使用代码构建的软胶熊猫/小熊 3D 模型（有 usdz/scn 文件时优先加载文件）
            switch character.imageName {
            case "bubu":
                return createBuddyNode(style: .bubu)   // 白熊猫（布布）
            case "yier":
                return createBuddyNode(style: .dudu)   // 棕小熊（一二/嘟嘟）
            default:
                // 自定义角色暂无 3D 模型：显示可爱占位符
                return createCutePlaceholder()
            }
        }

        // MARK: - 软胶熊猫/小熊 3D 模型（布布/一二共用一套建模，配色与特征参数化）

        /// 角色外观参数（对照参考图采样）。
        /// 布布 = 白色熊猫（深棕圆耳 + 粉腮红 + 倔强眉 + 深棕小领结）；
        /// 一二 = 棕色小熊（深棕圆耳 + 橘黄腮红）
        struct BuddyStyle {
            let body: NSColor       // 身体/头
            let ear: NSColor        // 圆耳朵
            let blush: NSColor      // 腮红
            let accent: NSColor     // 眼睛/嘴/眉/脚尖
            let hasBrows: Bool      // 倔强眉毛（布布特征）
            let hasCollar: Bool     // 胸前深棕小领结（布布特征）

            static let bubu = BuddyStyle(
                body: NSColor(red: 0.995, green: 0.985, blue: 0.975, alpha: 1.0),  // 纯白略暖
                ear: NSColor(red: 0.30, green: 0.20, blue: 0.17, alpha: 1.0),      // 深棕耳
                blush: NSColor(red: 0.97, green: 0.68, blue: 0.72, alpha: 1.0),    // 粉腮红
                accent: NSColor(red: 0.26, green: 0.17, blue: 0.14, alpha: 1.0),   // 深棕五官
                hasBrows: true,
                hasCollar: true
            )

            static let dudu = BuddyStyle(
                body: NSColor(red: 0.74, green: 0.53, blue: 0.40, alpha: 1.0),     // 焦糖棕
                ear: NSColor(red: 0.34, green: 0.23, blue: 0.18, alpha: 1.0),      // 深棕耳
                blush: NSColor(red: 0.99, green: 0.78, blue: 0.42, alpha: 1.0),    // 橘黄腮红
                accent: NSColor(red: 0.24, green: 0.16, blue: 0.13, alpha: 1.0),   // 深棕五官
                hasBrows: false,
                hasCollar: false
            )
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

        /// 半透明腮红材质（叠加在脸上不遮挡轮廓）
        private static func blushMaterial(_ color: NSColor) -> SCNMaterial {
            let material = matteMaterial(color)
            material.transparency = 0.55
            material.clearCoat.contents = 0.0
            return material
        }

        /// 构建软胶熊猫/小熊角色（布布/一二共用建模，外观由 style 决定）。
        /// 对照参考图：扁圆软胶身体、头身近乎连一体、顶部两只圆耳、大圆眼、
        /// "w"形小嘴、圆腮红、连身小短手短脚、深棕脚尖。
        /// 节点分层专为动画设计：外层容器承接状态动画，
        /// 内层 bubu-model / bubu-head / bubu-eyes / 四肢节点承接微动作
        static func createBuddyNode(style: BuddyStyle) -> SCNNode {
            let containerNode = SCNNode()

            // 内层模型根节点（小跳等全身微动作挂在这里，不与外层状态动画冲突）
            let model = SCNNode()
            model.name = "bubu-model"
            containerNode.addChildNode(model)

            // 身体 - 蛋形小躯干，下半更饱满圆胖、上移贴头（参考图身体像颗圆润的蛋）
            let body = sphereNode(radius: 0.28, color: style.body, segments: 72)
            body.position = SCNVector3(0, -0.36, 0)
            body.scale = SCNVector3(1.08, 0.98, 0.88)
            model.addChildNode(body)

            // 胸前深棕小领结（布布特征）：两枚小圆点叠成蝴蝶结轮廓
            if style.hasCollar {
                for side in [CGFloat(-1), CGFloat(1)] {
                    let loop = sphereNode(radius: 0.028, color: style.accent, segments: 20)
                    loop.position = SCNVector3(side * 0.032, -0.19, 0.25)
                    loop.scale = SCNVector3(1.0, 1.2, 0.5)
                    model.addChildNode(loop)
                }
                let center = sphereNode(radius: 0.02, color: style.accent, segments: 16)
                center.position = SCNVector3(0, -0.19, 0.27)
                center.scale = SCNVector3(1.0, 1.0, 0.6)
                model.addChildNode(center)
            }

            // 头部组（歪头/张望动画的旋转轴心）。参考图头极大、下沿与身体重叠成一团
            let head = SCNNode()
            head.name = "bubu-head"
            head.position = SCNVector3(0, 0.16, 0.0)
            model.addChildNode(head)

            // 头 - 超大软胶头（参考图头占身高一大半），略横椭圆 + 脸颊鼓、下巴饱满
            let face = sphereNode(radius: 0.48, color: style.body, segments: 72)
            face.scale = SCNVector3(1.10, 0.98, 0.92)
            head.addChildNode(face)

            // 脸颊鼓包 - 在两侧下方叠一层同色球，让脸颊更饱满圆润（参考图脸鼓鼓的）
            for side in [CGFloat(-1), CGFloat(1)] {
                let cheek = sphereNode(radius: 0.26, color: style.body, segments: 48)
                cheek.position = SCNVector3(side * 0.19, -0.10, 0.10)
                cheek.scale = SCNVector3(1.0, 0.92, 0.72)
                head.addChildNode(cheek)
            }

            // 耳朵 - 顶部两只深棕圆耳，各挂在可动耳根节点下（承接耳朵抖动微动作）
            for side in [CGFloat(-1), CGFloat(1)] {
                let earPivot = SCNNode()
                earPivot.name = side < 0 ? "bubu-ear-l" : "bubu-ear-r"
                earPivot.position = SCNVector3(side * 0.265, 0.335, -0.03)  // 耳根更贴头顶内侧
                head.addChildNode(earPivot)

                let ear = sphereNode(radius: 0.145, color: style.ear, segments: 44)
                ear.position = SCNVector3(0, 0.12, 0)  // 耳球在耳根之上
                ear.scale = SCNVector3(1.0, 0.94, 0.78)
                earPivot.addChildNode(ear)
            }

            // 眼睛组（眨眼动画对该组做 Y 轴压扁）。参考图双眼又大又圆、间距宽、水汪汪
            let eyes = SCNNode()
            eyes.name = "bubu-eyes"
            eyes.position = SCNVector3(0, 0.0, 0.42)
            head.addChildNode(eyes)

            for xOffset in [CGFloat(-0.195), CGFloat(0.195)] {
                // 眼珠 - 又大又圆的黑亮眼，明显凸出脸面（参考图眼睛靠脸颊两侧、间距宽）
                let eye = sphereNode(radius: 0.088, color: style.accent, segments: 40)
                eye.position = SCNVector3(xOffset, 0, 0)
                eye.scale = SCNVector3(0.96, 1.10, 0.74)
                // 眼珠自带一点光泽（降低粗糙度），更像参考图黑亮的果冻眼
                eye.geometry?.firstMaterial?.roughness.contents = 0.45
                eye.geometry?.firstMaterial?.clearCoat.contents = 0.6
                eyes.addChildNode(eye)

                // 大高光 - 白色亮斑（自发光，始终明亮），水汪汪的关键
                let highlightGeometry = SCNSphere(radius: 0.033)
                let highlightMaterial = SCNMaterial()
                highlightMaterial.lightingModel = .constant
                highlightMaterial.diffuse.contents = NSColor.white
                highlightGeometry.materials = [highlightMaterial]
                let highlight = SCNNode(geometry: highlightGeometry)
                highlight.position = SCNVector3(xOffset + 0.028, 0.035, 0.075)
                eyes.addChildNode(highlight)

                // 小副高光（下方一小点，让眼睛更灵动透亮）
                let subGeo = SCNSphere(radius: 0.015)
                let subMat = SCNMaterial()
                subMat.lightingModel = .constant
                subMat.diffuse.contents = NSColor.white
                subGeo.materials = [subMat]
                let sub = SCNNode(geometry: subGeo)
                sub.position = SCNVector3(xOffset - 0.022, -0.035, 0.075)
                eyes.addChildNode(sub)
            }

            // 眉毛 - 呆萌小斜眉（布布特征）：短、平、只微微内低，是"倔强呆萌"不是"凶"。
            // 随加宽的眼睛外移到眼睛正上方
            if style.hasBrows {
                for side in [CGFloat(-1), CGFloat(1)] {
                    let brow = SCNNode(geometry: {
                        let g = SCNCapsule(capRadius: 0.0125, height: 0.058)
                        g.materials = [matteMaterial(style.accent)]
                        return g
                    }())
                    brow.position = SCNVector3(side * 0.185, 0.135, 0.44)
                    // 只微微内低（0.22 rad ≈ 12.6°），呆萌不凶
                    brow.eulerAngles = SCNVector3(0, 0, Float(side) * 0.22 - Float.pi / 2)
                    head.addChildNode(brow)
                }
            }

            // 嘴 - 柔和上扬的 "ω" 小猫嘴（参考图的嘴是呆萌笑，不是瘪嘴）：
            // 中间一个小圆凸 + 两侧各一道向上外翘的短弧，形成 ω 轮廓
            let mouth = SCNNode()
            mouth.position = SCNVector3(0, -0.15, 0.45)
            let mouthMat = matteMaterial(style.accent)

            // 中间小圆凸（ω 的中峰）
            let bump = SCNNode(geometry: {
                let g = SCNSphere(radius: 0.011)
                g.materials = [mouthMat]
                return g
            }())
            bump.scale = SCNVector3(1.4, 1.0, 0.6)
            mouth.addChildNode(bump)

            // 两侧上翘短弧
            for side in [CGFloat(-1), CGFloat(1)] {
                let seg = SCNNode(geometry: {
                    let g = SCNCapsule(capRadius: 0.0072, height: 0.05)
                    g.materials = [mouthMat]
                    return g
                }())
                seg.position = SCNVector3(side * 0.028, 0.006, 0)
                // 外端上扬（负角度让弧朝上翘），呆萌笑
                seg.eulerAngles = SCNVector3(0, 0, Float(side) * -1.25)
                mouth.addChildNode(seg)
            }
            head.addChildNode(mouth)

            // 腮红 - 大而柔和的圆色斑，位于眼睛正下方偏外，半透明贴脸（参考图腮红明显圆润）
            for xOffset in [CGFloat(-0.33), CGFloat(0.33)] {
                let blushGeo = SCNSphere(radius: 0.10)
                blushGeo.segmentCount = 32
                blushGeo.materials = [blushMaterial(style.blush)]
                let blush = SCNNode(geometry: blushGeo)
                blush.position = SCNVector3(xOffset, -0.11, 0.33)
                blush.scale = SCNVector3(1.0, 0.92, 0.28)
                head.addChildNode(blush)
            }

            // 手臂 - 短圆胖小胳膊，贴在身侧（参考图手很短小），挂在肩部轴心节点下
            for side in [CGFloat(-1), CGFloat(1)] {
                let shoulder = SCNNode()
                shoulder.name = side < 0 ? "bubu-arm-l" : "bubu-arm-r"
                shoulder.position = SCNVector3(side * 0.245, -0.24, 0.05)
                model.addChildNode(shoulder)

                let armGeometry = SCNCapsule(capRadius: 0.06, height: 0.15)
                armGeometry.materials = [matteMaterial(style.body)]
                let arm = SCNNode(geometry: armGeometry)
                arm.position = SCNVector3(side * 0.015, -0.05, 0.0)
                arm.eulerAngles = SCNVector3(0, 0, Float(side) * -0.28)
                shoulder.addChildNode(arm)
            }

            // 脚 - 连身小短脚，脚尖深棕（参考图脚底一小撮深色）；踝部轴心承接踢腿
            for side in [CGFloat(-1), CGFloat(1)] {
                let ankle = SCNNode()
                ankle.name = side < 0 ? "bubu-foot-l" : "bubu-foot-r"
                ankle.position = SCNVector3(side * 0.135, -0.585, 0.05)
                model.addChildNode(ankle)

                // 脚掌（身体同色）
                let foot = sphereNode(radius: 0.10, color: style.body, segments: 32)
                foot.position = SCNVector3(0, 0.0, 0.03)
                foot.scale = SCNVector3(0.95, 0.6, 1.2)
                ankle.addChildNode(foot)

                // 脚尖深棕小块
                let toe = sphereNode(radius: 0.048, color: style.accent, segments: 24)
                toe.position = SCNVector3(0, -0.01, 0.095)
                toe.scale = SCNVector3(1.0, 0.7, 0.7)
                ankle.addChildNode(toe)
            }

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
