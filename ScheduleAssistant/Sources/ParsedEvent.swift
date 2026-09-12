import Foundation

/// LLM 解析出的日程结构（与 Prompt 约定的 JSON Schema 对应）
struct ParsedEvent: Codable, Equatable {
    var title: String
    /// 日程主题 emoji（单字符），用于卡片展示
    var emoji: String?
    /// ISO8601 字符串，如 2026-09-10T14:00:00+08:00
    var startDate: String?
    var endDate: String?
    var location: String?
    var notes: String?
    var isAllDay: Bool?
    /// 仅当用户明确说“每天/每周/每月”等时填写；习惯可在 App 中另存为系统提醒事项。
    var recurrence: RecurrenceSpec?
    /// 模型对识别结果的置信度 0-1
    var confidence: Double?

    var resolvedStartDate: Date? { ParsedEvent.parseDate(startDate) }
    var resolvedEndDate: Date? { ParsedEvent.parseDate(endDate) }

    static func parseDate(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: s) { return d }
        let frac = ISO8601DateFormatter()
        frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = frac.date(from: s) { return d }
        // 无时区的情况，按本地时间解析
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        for pattern in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd"] {
            fmt.dateFormat = pattern
            if let d = fmt.date(from: s) { return d }
        }
        return nil
    }
}

enum LLMError: LocalizedError {
    case noAPIKey
    case noInput
    case invalidResponse(String)
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "请先在设置中填写 API Key"
        case .noInput: return "请输入文字或选择图片"
        case .invalidResponse(let raw): return "模型返回无法解析：\(raw.prefix(300))"
        case .http(let code, let body): return "请求失败(\(code))：\(body.prefix(300))"
        }
    }
}
