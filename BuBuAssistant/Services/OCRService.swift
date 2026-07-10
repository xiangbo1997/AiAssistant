//
//  OCRService.swift
//  BuBuAssistant
//
//  Created by Claude Code on 2026-07-10.
//  OCR 服务 - 使用系统 Vision 框架做本地文字识别：
//  无网络往返、无 API 费用、图片数据不出设备
//

import AppKit
import Vision

enum OCRError: LocalizedError {
    case invalidImage
    case noTextFound

    var errorDescription: String? {
        switch self {
        case .invalidImage: return "无法读取截图数据"
        case .noTextFound: return "没有识别到文字"
        }
    }
}

final class OCRService {
    static let shared = OCRService()

    private init() {}

    /// 识别图片中的文字，按行拼接返回。
    /// 识别在后台线程执行；图片无文字时抛出 OCRError.noTextFound
    func recognizeText(in imageData: Data) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            guard let image = NSImage(data: imageData),
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                throw OCRError.invalidImage
            }

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            // 自动检测语言，同时给出常用语言提示提升中日韩识别率
            request.automaticallyDetectsLanguage = true
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US", "ja-JP", "ko-KR"]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try handler.perform([request])

            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            let text = lines.joined(separator: "\n")

            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw OCRError.noTextFound
            }
            return text
        }.value
    }
}
