import SwiftUI

/// Rounded app icon. Falls back to a gradient tile with the app's initial.
struct AppIconView: View {
    var image: UIImage? = nil
    var name: String
    var size: CGFloat = 60

    private var initial: String {
        name.first.map { String($0).uppercased() } ?? "?"
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
    }

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(colors: Theme.palette(for: name), startPoint: .topLeading, endPoint: .bottomTrailing)
                Text(initial)
                    .font(.system(size: size * 0.44, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.14), radius: size * 0.08, x: 0, y: size * 0.04)
        .accessibilityHidden(true)
    }
}
