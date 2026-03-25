extension KeyPath {
    var propertyName: String? {
        let description = String(describing: self)
        guard let dotRange = description.range(of: ".", options: .backwards) else {
            return nil
        }
        var name = String(description[dotRange.upperBound...])
        // Strip trailing ">" characters from KeyPath descriptions
        while name.hasSuffix(">") { name = String(name.dropLast()) }
        // Strip projected-value prefix
        if name.hasPrefix("$") { name = String(name.dropFirst()) }
        guard !name.isEmpty else { return nil }
        return name
    }
}
