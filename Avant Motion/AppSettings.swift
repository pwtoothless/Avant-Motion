enum ModePicker {
    case everyday
    case active
    case auto
    
    func getSelectedIndex() -> Int {
        switch self {
        case .everyday:
            return 0
        case .active:
            return 1
        case .auto:
            return 2
        }
    }
}
