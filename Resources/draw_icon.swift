import AppKit

let size = 1024
let output = CommandLine.arguments.dropFirst().first ?? "icon-1024.png"
let image = NSImage(size: NSSize(width: size, height: size))

image.lockFocus()
let rect = NSRect(x: 0, y: 0, width: size, height: size)

NSColor(red: 0.035, green: 0.045, blue: 0.07, alpha: 1).setFill()
rect.fill()

let glow = NSBezierPath(ovalIn: NSRect(x: 180, y: 420, width: 680, height: 680))
NSColor(red: 0.84, green: 0.66, blue: 0.33, alpha: 0.16).setFill()
glow.fill()

let card = NSBezierPath(roundedRect: NSRect(x: 210, y: 180, width: 600, height: 680), xRadius: 72, yRadius: 72)
NSColor(red: 0.10, green: 0.13, blue: 0.18, alpha: 1).setFill()
card.fill()
NSColor(red: 0.84, green: 0.66, blue: 0.33, alpha: 0.85).setStroke()
card.lineWidth = 18
card.stroke()

func bar(_ y: CGFloat, width: CGFloat, alpha: CGFloat) {
    let path = NSBezierPath(roundedRect: NSRect(x: 290, y: y, width: width, height: 48), xRadius: 12, yRadius: 12)
    NSColor(red: 0.93, green: 0.95, blue: 0.97, alpha: alpha).setFill()
    path.fill()
}
bar(680, width: 360, alpha: 0.92)
bar(590, width: 440, alpha: 0.55)
bar(500, width: 400, alpha: 0.35)
bar(410, width: 280, alpha: 0.22)

let node = NSBezierPath(ovalIn: NSRect(x: 640, y: 230, width: 210, height: 210))
NSColor(red: 0.35, green: 0.78, blue: 0.84, alpha: 1).setFill()
node.fill()
let inner = NSBezierPath(ovalIn: NSRect(x: 692, y: 282, width: 106, height: 106))
NSColor(red: 0.035, green: 0.045, blue: 0.07, alpha: 1).setFill()
inner.fill()

let link = NSBezierPath()
link.move(to: NSPoint(x: 430, y: 360))
link.line(to: NSPoint(x: 680, y: 300))
NSColor(red: 0.35, green: 0.78, blue: 0.84, alpha: 0.7).setStroke()
link.lineWidth = 22
link.lineCapStyle = .round
link.stroke()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fputs("icon render failed\n", stderr)
    exit(1)
}
try png.write(to: URL(fileURLWithPath: output))
print("wrote \(output)")
