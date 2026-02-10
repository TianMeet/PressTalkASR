import Foundation

enum PopoverMessageFormatter {
    static func shortError(_ message: String) -> String {
        if message.lowercased().contains("network") || message.contains("网络") {
            return "网络异常"
        }
        if message.contains("未识别") || message.contains("太短") {
            return "未识别语音"
        }
        return "请重试"
    }

    static func shortWarning(_ message: String) -> String {
        if message.contains("自动粘贴") || message.lowercased().contains("paste") {
            return "粘贴失败"
        }
        return "警告"
    }
}
