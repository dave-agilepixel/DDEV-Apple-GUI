import Foundation

/// A tool DDEV wraps for in-container passthrough (A10): `ddev composer …`, `ddev npm …`,
/// `ddev drush …`, `ddev wp …`. Which tools are relevant is derived from the project type, the
/// way DDEV only registers framework commands when the `type` matches.
public enum DDEVTool: String, CaseIterable, Identifiable, Sendable {
    case composer
    case npm
    case drush
    case wp

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .composer: "Composer"
        case .npm: "npm"
        case .drush: "Drush"
        case .wp: "WP-CLI"
        }
    }

    /// Example arguments shown as the field's placeholder.
    public var placeholder: String {
        switch self {
        case .composer: "require monolog/monolog"
        case .npm: "install"
        case .drush: "cache:rebuild"
        case .wp: "plugin list"
        }
    }

    /// Tools relevant to a project type. Composer and npm apply to every PHP/Node project; Drush is
    /// Drupal-only and WP-CLI is WordPress-only.
    public static func tools(for type: DDEVProjectType) -> [DDEVTool] {
        var tools: [DDEVTool] = [.composer, .npm]
        switch type {
        case .wordpress, .wpBedrock:
            tools.append(.wp)
        case .drupal, .drupal6, .drupal7, .drupal8, .drupal9, .drupal10, .drupal11, .drupal12, .backdrop:
            tools.append(.drush)
        default:
            break
        }
        return tools
    }

    /// Splits a free-text argument string into argv tokens, honouring single and double quotes so
    /// arguments containing spaces (`"a b"`) survive. `Process` runs without a shell, so this is the
    /// only place quoting is interpreted; empty tokens are dropped.
    public static func tokenizeArguments(_ string: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var hasCurrent = false
        var quote: Character?

        for char in string {
            if let active = quote {
                if char == active {
                    quote = nil
                } else {
                    current.append(char)
                }
                hasCurrent = true
            } else if char == "\"" || char == "'" {
                quote = char
                hasCurrent = true
            } else if char == " " || char == "\t" || char == "\n" {
                if hasCurrent {
                    tokens.append(current)
                    current = ""
                    hasCurrent = false
                }
            } else {
                current.append(char)
                hasCurrent = true
            }
        }

        if hasCurrent {
            tokens.append(current)
        }
        return tokens.filter { !$0.isEmpty }
    }
}
