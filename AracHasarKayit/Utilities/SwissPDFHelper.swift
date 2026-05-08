import UIKit

/// Helper for Swiss Design PDF styling
struct SwissPDFHelper {
    // MARK: - Helvetica Fonts (Swiss Design standard)
    
    static func helvetica(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        switch weight {
        case .bold:
            return UIFont(name: "Helvetica-Bold", size: size) ?? UIFont.systemFont(ofSize: size, weight: .bold)
        case .semibold, .medium:
            return UIFont(name: "Helvetica-Bold", size: size) ?? UIFont.systemFont(ofSize: size, weight: weight)
        default:
            return UIFont(name: "Helvetica", size: size) ?? UIFont.systemFont(ofSize: size, weight: weight)
        }
    }
    
    static func helveticaBold(size: CGFloat) -> UIFont {
        return UIFont(name: "Helvetica-Bold", size: size) ?? UIFont.systemFont(ofSize: size, weight: .bold)
    }
    
    static func helveticaThin(size: CGFloat) -> UIFont {
        return helvetica(size: size, weight: .thin)
    }
    
    static func helveticaLight(size: CGFloat) -> UIFont {
        return helvetica(size: size, weight: .light)
    }
    
    // MARK: - Colors (Swiss Design: Black, White, Grays only)
    
    static var black: UIColor { .black }
    static var darkGray: UIColor { UIColor(white: 0.2, alpha: 1.0) }
    static var mediumGray: UIColor { UIColor(white: 0.4, alpha: 1.0) }
    static var lightGray: UIColor { UIColor(white: 0.6, alpha: 1.0) }
    static var veryLightGray: UIColor { UIColor(white: 0.9, alpha: 1.0) }
    static var white: UIColor { .white }
    
    // MARK: - Drawing Helpers
    
    static func drawHorizontalLine(context: CGContext, from: CGPoint, to: CGPoint, width: CGFloat = 0.5) {
        context.setStrokeColor(black.cgColor)
        context.setLineWidth(width)
        context.move(to: from)
        context.addLine(to: to)
        context.strokePath()
    }
    
    static func drawVerticalLine(context: CGContext, from: CGPoint, to: CGPoint, width: CGFloat = 0.5) {
        context.setStrokeColor(black.cgColor)
        context.setLineWidth(width)
        context.move(to: from)
        context.addLine(to: to)
        context.strokePath()
    }
    
    static func drawGridLine(context: CGContext, x: CGFloat, yStart: CGFloat, yEnd: CGFloat, width: CGFloat = 0.25) {
        drawVerticalLine(context: context, from: CGPoint(x: x, y: yStart), to: CGPoint(x: x, y: yEnd), width: width)
    }
}

