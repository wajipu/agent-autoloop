import UIKit

/// 收起键盘（只在主 App 里用，扩展里用 FocusState）。
func endEditing() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}
