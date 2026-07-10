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
        scnView.antialiasingMode = .multisampling2X

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
        context.coordinator.updateAnimation(for: animationState)
        context.coordinator.updateScale(viewModel.scale)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    // MARK: - Coordinator

    class Coordinator {
        let scene: SCNScene
        let characterNode: SCNNode
        let cameraNode: SCNNode
        var currentAnimation: SpriteAnimationState = .idle

        init(viewModel: SpriteViewModel) {
            scene = SCNScene()

            // 创建角色节点
            characterNode = Coordinator.createCharacterNode(for: viewModel.currentCharacter)
            scene.rootNode.addChildNode(characterNode)

            // 创建相机
            cameraNode = SCNNode()
            cameraNode.camera = SCNCamera()
            cameraNode.position = SCNVector3(x: 0, y: 0, z: 3)
            scene.rootNode.addChildNode(cameraNode)

            // 添加环境光
            let ambientLight = SCNNode()
            ambientLight.light = SCNLight()
            ambientLight.light?.type = .ambient
            ambientLight.light?.color = NSColor(white: 0.6, alpha: 1.0)
            scene.rootNode.addChildNode(ambientLight)

            // 添加主光源
            let mainLight = SCNNode()
            mainLight.light = SCNLight()
            mainLight.light?.type = .directional
            mainLight.light?.color = NSColor(white: 0.8, alpha: 1.0)
            mainLight.light?.castsShadow = true
            mainLight.position = SCNVector3(x: 2, y: 3, z: 2)
            mainLight.look(at: SCNVector3(0, 0, 0))
            scene.rootNode.addChildNode(mainLight)

            // 添加补光
            let fillLight = SCNNode()
            fillLight.light = SCNLight()
            fillLight.light?.type = .directional
            fillLight.light?.color = NSColor(red: 0.4, green: 0.6, blue: 0.9, alpha: 0.5)
            fillLight.position = SCNVector3(x: -2, y: 1, z: 2)
            fillLight.look(at: SCNVector3(0, 0, 0))
            scene.rootNode.addChildNode(fillLight)

            // 设���背景透明
            scene.background.contents = NSColor.clear

            // 启动待机动画
            startIdleAnimation()
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

            // 布布使用代码构建的恐龙套装 3D 模型（有 usdz/scn 文件时优先加载文件）
            if character.imageName == "bubu" {
                return createBubuDinoNode()
            }

            // 其他角色：创建可爱的占位符
            return createCutePlaceholder()
        }

        // MARK: - 布布恐龙套装 3D 模型

        /// 布布配色（取自 2D 贴纸形象）
        private enum BubuPalette {
            static let bodyBrown = NSColor(red: 0.80, green: 0.56, blue: 0.38, alpha: 1.0)   // 身体棕
            static let hoodBlue = NSColor(red: 0.56, green: 0.80, blue: 0.91, alpha: 1.0)    // 恐龙帽兜蓝
            static let bellyCream = NSColor(red: 0.96, green: 0.88, blue: 0.74, alpha: 1.0)  // 肚皮奶油色
            static let spikeWhite = NSColor(red: 0.97, green: 0.97, blue: 0.95, alpha: 1.0)  // 棘刺白
            static let blushPink = NSColor(red: 0.98, green: 0.63, blue: 0.63, alpha: 1.0)   // 腮红粉
            static let eyeBrown = NSColor(red: 0.24, green: 0.16, blue: 0.12, alpha: 1.0)    // 眼睛深棕
        }

        /// 柔和哑光材质（低高光，贴合绘本质感）
        private static func matteMaterial(_ color: NSColor) -> SCNMaterial {
            let material = SCNMaterial()
            material.diffuse.contents = color
            material.specular.contents = NSColor(white: 1.0, alpha: 0.15)
            material.shininess = 0.15
            return material
        }

        private static func sphereNode(radius: CGFloat, color: NSColor, segments: Int = 36) -> SCNNode {
            let geometry = SCNSphere(radius: radius)
            geometry.segmentCount = segments
            geometry.materials = [matteMaterial(color)]
            return SCNNode(geometry: geometry)
        }

        /// 构建穿蓝色恐龙套装的布布：棕色身体 + 蓝帽兜白棘刺 + 奶油肚皮 + 大眼腮红 + 尾巴
        static func createBubuDinoNode() -> SCNNode {
            let containerNode = SCNNode()

            // 身体 - 圆润棕色椭球
            let body = sphereNode(radius: 0.30, color: BubuPalette.bodyBrown, segments: 48)
            body.position = SCNVector3(0, -0.25, 0)
            body.scale = SCNVector3(1.0, 0.95, 0.9)
            containerNode.addChildNode(body)

            // 肚皮 - 奶油色贴片
            let belly = sphereNode(radius: 0.22, color: BubuPalette.bellyCream)
            belly.position = SCNVector3(0, -0.24, 0.14)
            belly.scale = SCNVector3(0.85, 0.80, 0.45)
            containerNode.addChildNode(belly)

            // 恐龙帽兜 - 蓝色大球包裹头部
            let hood = sphereNode(radius: 0.40, color: BubuPalette.hoodBlue, segments: 48)
            hood.position = SCNVector3(0, 0.28, -0.02)
            containerNode.addChildNode(hood)

            // 脸部 - 棕色球从帽兜前方露出
            let face = sphereNode(radius: 0.33, color: BubuPalette.bodyBrown, segments: 48)
            face.position = SCNVector3(0, 0.24, 0.12)
            face.scale = SCNVector3(1.0, 0.92, 0.78)
            containerNode.addChildNode(face)

            // 帽兜棘刺 - 三枚白色小角沿头顶向后排列
            let spikeConfigs: [(position: SCNVector3, tiltX: Float, size: CGFloat)] = [
                (SCNVector3(0, 0.68, 0.04), -0.15, 0.065),
                (SCNVector3(0, 0.62, -0.18), -0.65, 0.058),
                (SCNVector3(0, 0.48, -0.33), -1.10, 0.050)
            ]
            for config in spikeConfigs {
                let spikeGeometry = SCNCone(topRadius: 0, bottomRadius: config.size, height: config.size * 2.2)
                spikeGeometry.materials = [matteMaterial(BubuPalette.spikeWhite)]
                let spike = SCNNode(geometry: spikeGeometry)
                spike.position = config.position
                spike.eulerAngles = SCNVector3(config.tiltX, 0, 0)
                containerNode.addChildNode(spike)
            }

            // 眼睛 - 大而圆的深棕眼珠 + 高光
            for xOffset in [CGFloat(-0.11), CGFloat(0.11)] {
                let eye = sphereNode(radius: 0.048, color: BubuPalette.eyeBrown, segments: 24)
                eye.position = SCNVector3(xOffset, 0.30, 0.36)
                containerNode.addChildNode(eye)

                let highlightGeometry = SCNSphere(radius: 0.016)
                let highlightMaterial = SCNMaterial()
                highlightMaterial.diffuse.contents = NSColor.white
                highlightMaterial.emission.contents = NSColor.white
                highlightGeometry.materials = [highlightMaterial]
                let highlight = SCNNode(geometry: highlightGeometry)
                highlight.position = SCNVector3(xOffset + 0.015, 0.315, 0.40)
                containerNode.addChildNode(highlight)
            }

            // 腮红 - 半透明粉色圆片
            for xOffset in [CGFloat(-0.20), CGFloat(0.20)] {
                let blush = sphereNode(radius: 0.055, color: BubuPalette.blushPink, segments: 24)
                blush.geometry?.firstMaterial?.transparency = 0.65
                blush.position = SCNVector3(xOffset, 0.21, 0.30)
                blush.scale = SCNVector3(1.0, 0.6, 0.35)
                containerNode.addChildNode(blush)
            }

            // 嘴巴 - 小巧的深色微笑点
            let mouth = sphereNode(radius: 0.022, color: BubuPalette.eyeBrown, segments: 16)
            mouth.position = SCNVector3(0, 0.17, 0.38)
            mouth.scale = SCNVector3(1.5, 0.7, 0.5)
            containerNode.addChildNode(mouth)

            // 手臂 - 棕色小胶囊，微微外张
            for (xOffset, zRotation) in [(CGFloat(-0.29), Float(0.5)), (CGFloat(0.29), Float(-0.5))] {
                let armGeometry = SCNCapsule(capRadius: 0.06, height: 0.20)
                armGeometry.materials = [matteMaterial(BubuPalette.bodyBrown)]
                let arm = SCNNode(geometry: armGeometry)
                arm.position = SCNVector3(xOffset, -0.16, 0.04)
                arm.eulerAngles = SCNVector3(0, 0, zRotation)
                containerNode.addChildNode(arm)
            }

            // 脚 - 蓝色套装小脚
            for xOffset in [CGFloat(-0.13), CGFloat(0.13)] {
                let foot = sphereNode(radius: 0.09, color: BubuPalette.hoodBlue, segments: 24)
                foot.position = SCNVector3(xOffset, -0.55, 0.04)
                foot.scale = SCNVector3(1.0, 0.55, 1.25)
                containerNode.addChildNode(foot)
            }

            // 尾巴 - 蓝色小锥体从身后翘起
            let tailGeometry = SCNCone(topRadius: 0, bottomRadius: 0.09, height: 0.26)
            tailGeometry.materials = [matteMaterial(BubuPalette.hoodBlue)]
            let tail = SCNNode(geometry: tailGeometry)
            tail.position = SCNVector3(0, -0.40, -0.28)
            tail.eulerAngles = SCNVector3(-2.2, 0, 0)
            containerNode.addChildNode(tail)

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
                })
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
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
        .background(Color.gray.opacity(0.1))
}
