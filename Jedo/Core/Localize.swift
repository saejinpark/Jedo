import Foundation

/// The app is written in Korean; every string shown is looked up by its Korean
/// text, so another language is one table of translations and nothing else.
func tr(_ korean: String) -> String {
    Bundle.main.localizedString(forKey: korean, value: korean, table: nil)
}

/// A string with values set into it: `%@` in the Korean marks where each goes.
func tr(_ korean: String, _ values: String...) -> String {
    String(format: tr(korean), arguments: values)
}
