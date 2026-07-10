//
//  SpeechService.swift
//  BuBuAssistant
//
//  Created by Claude Code on 2026-07-10.
//  语音服务 - 朗读（TTS）与语音输入（STT），全部使用系统本地能力：
//  无网络往返、无 API 费用、语音数据不出设备
//

import AVFoundation
import Speech

// MARK: - 语音错误

enum SpeechError: LocalizedError {
    case recognizerUnavailable
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable: return "语音识别当前不可用"
        case .permissionDenied: return "需要「麦克风」和「语音识别」权限，请在系统设置中授权"
        }
    }
}

// MARK: - 语音服务

@MainActor
class SpeechService: NSObject, ObservableObject {
    static let shared = SpeechService()

    @Published var isSpeaking = false
    @Published var isRecording = false

    private let synthesizer = AVSpeechSynthesizer()
    private let audioEngine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    override private init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - 朗读（TTS）

    /// 朗读文本：自动清理 Markdown 标记后播报。
    /// 不指定 language 时按文本内容自动选择语音（避免中文语音念英文译文）
    func speak(_ text: String, language: String? = nil) {
        stopSpeaking()

        let cleaned = Self.stripMarkdown(text)
        guard !cleaned.isEmpty else { return }

        let utterance = AVSpeechUtterance(string: cleaned)
        let languageCode = language ?? LanguageDetector.speechLanguageCode(for: cleaned)
        utterance.voice = AVSpeechSynthesisVoice(language: languageCode)
            ?? AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate

        isSpeaking = true
        synthesizer.speak(utterance)
    }

    /// 停止朗读
    func stopSpeaking() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
    }

    /// 去除 Markdown 标记，让播报听起来自然
    static func stripMarkdown(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: "```[a-zA-Z]*", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "[`*_#>|]", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\[(.*?)\\]\\(.*?\\)", with: "$1", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - 语音输入（STT）

    /// 请求麦克风与语音识别权限
    func requestSpeechPermissions() async -> Bool {
        let speechStatus: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard speechStatus == .authorized else { return false }

        return await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    /// 开始语音识别，onPartial 实时回调当前识别文本（主线程）
    func startRecording(onPartial: @escaping (String) -> Void) throws {
        stopSpeaking()
        stopRecording()

        guard let recognizer, recognizer.isAvailable else {
            throw SpeechError.recognizerUnavailable
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // 本地识别优先（隐私 + 低延迟），设备不支持时自动走服务器
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            if let result {
                let text = result.bestTranscription.formattedString
                Task { @MainActor in
                    onPartial(text)
                }
            }
            if error != nil || (result?.isFinal ?? false) {
                Task { @MainActor in
                    self?.stopRecording()
                }
            }
        }
    }

    /// 停止语音识别
    func stopRecording() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false
    }
}

// MARK: - 朗读状态回调

extension SpeechService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
        }
    }
}
