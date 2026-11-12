from pathlib import Path
import plistlib,shutil
source=Path('App/Sources/Settings/AutomaticUpdatesSettingsPage.swift').read_text()
root=Path('/tmp/duo-setup-header-renderer');resources=root/'HeaderRenderer.app/Contents/Resources';macos=root/'HeaderRenderer.app/Contents/MacOS'
resources.mkdir(parents=True,exist_ok=True);macos.mkdir(parents=True,exist_ok=True)
def block(marker,offset=0):
 start=source.index(marker,offset);begin=source.index('{',start);level=1;end=begin+1
 while level:
  level += (source[end]=='{')-(source[end]=='}');end+=1
 return source[start:end]
header=block('VStack(alignment: .leading, spacing: 4)',source.index('private func column(_ mode: Mode)'))
title=block('static func title(_ mode: Mode)')
explanation=block('private static func explanation(_ mode: Mode)')
for name in ['de','en','es','fr','it','ja','pt-BR','ru','tr','zh-Hans','zh-Hant']:
 src=Path('/Applications/DuoUpdater.app/Contents/Resources')/(name+'.lproj')
 shutil.copytree(src,resources/src.name,dirs_exist_ok=True)
(root/'HeaderRenderer.app/Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'com.duoupdater.header-renderer','CFBundleExecutable':'HeaderRenderer','CFBundleName':'HeaderRenderer','LSUIElement':True,'CFBundleDevelopmentRegion':'en'}))
base='''import AppKit
import SwiftUI

enum Mode: CaseIterable { case alsoWhenRunning, whenClosed, never }
'''
for name,body in [('HeaderProbe',header),('UncappedHeaderProbe',header.replace('.lineLimit(2)','.lineLimit(nil)'))]:
 base += f'''\nstruct {name}: View {{
 let mode: Mode
 let minHeight: CGFloat
 func count(in mode: Mode) -> Int {{ switch mode {{ case .alsoWhenRunning: 51; case .whenClosed: 219; case .never: 0 }} }}
 {title}
 {explanation}
 var body: some View {{
 {body}
 .fixedSize(horizontal: false, vertical: true)
 .frame(minHeight: minHeight, alignment: .topLeading)
 .padding(.horizontal, 10)
 .padding(.vertical, 8)
 }}
}}
'''
base+='''
@main struct RenderHeaders {
 @MainActor static func main() throws {
  let app = NSApplication.shared
  app.setActivationPolicy(.prohibited)
  app.appearance = NSAppearance(named: .darkAqua)
  let language = CommandLine.arguments[1]
  let locale = Locale(identifier: language)
  let columnWidth = (CGFloat(820) - 40 - 20) / 3
  var heights: [CGFloat] = []
  for mode in Mode.allCases {
   let limited = ImageRenderer(content: HeaderProbe(mode: mode, minHeight: 0).frame(width: columnWidth).environment(\\.locale, locale).environment(\\.colorScheme, .dark))
   let full = ImageRenderer(content: UncappedHeaderProbe(mode: mode, minHeight: 0).frame(width: columnWidth).environment(\\.locale, locale).environment(\\.colorScheme, .dark))
   guard let image = limited.nsImage, let uncapped = full.nsImage else { fatalError("Missing header image") }
   guard abs(image.size.height - uncapped.size.height) < 0.5 else { fatalError("Truncated explanation: \\(language), \\(mode): \\(image.size.height) / \\(uncapped.size.height)") }
   heights.append(image.size.height)
  }
  let maxHeight = heights.max()!
  let row = HStack(alignment: .top, spacing: 10) {
   ForEach(Array(Mode.allCases.enumerated()), id: \\.offset) { _, mode in
    VStack(spacing: 0) {
     HeaderProbe(mode: mode, minHeight: maxHeight - 16)
     Divider()
    }
    .frame(width: columnWidth)
    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
   }
  }
  .padding(20)
  .background(Color(white: 0.14))
  .environment(\\.locale, locale)
  .environment(\\.colorScheme, .dark)
  let renderer = ImageRenderer(content: row)
  renderer.scale = 2
  guard let image = renderer.nsImage, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else { fatalError("No PNG") }
  let path = "/tmp/duo-setup-locales-20261112/headers-\\(language).png"
  try png.write(to: URL(fileURLWithPath: path))
  print("\\(language): PASS, natural heights=\\(heights), aligned height=\\(maxHeight), \\(path)")
 }
}
'''
(root/'main.swift').write_text(base)
print(root/'main.swift')
