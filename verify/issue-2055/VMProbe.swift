import Foundation
@testable import DuoUpdaterCore
@main struct VMProbe {
 static func main() async throws {
 let a=CommandLine.arguments
 if a.count>1 && a[1]=="dual" {
  do { try await HomebrewInstaller().upgrade(caskToken:"duo-2055-intel",app:URL(fileURLWithPath:"/Applications/Duo2055Intel.app"),onOutput:{print($0)}) } catch { print("upgrade outcome: \(error)") }; return
 }
 if a.count>1 && a[1]=="env" {
   let file="/tmp/duo-2055/env-result.txt"
   var lines=["process HOMEBREW_NO_AUTO_UPDATE=\(ProcessInfo.processInfo.environment["HOMEBREW_NO_AUTO_UPDATE"] ?? "nil")"]
   let shell=await LoginShellEnvironment.resolveHomebrewVariables()
   lines.append("resolved HOMEBREW_NO_AUTO_UPDATE=\(shell?["HOMEBREW_NO_AUTO_UPDATE"] ?? "nil")")
   let config=await HomebrewConfig.read(environment:shell ?? [:])
   lines.append("real brew config autoUpdateDisabled=\(config?.autoUpdateDisabled.description ?? "nil") secs=\(config?.autoUpdateSeconds?.description ?? "nil")")
   let executor=BrewFormulaService.executor(brewPath:{"/tmp/duo-2055/brew-log"})
   _ = try await executor(["config"])
   try await HomebrewInstaller.$brewPathOverride.withValue("/tmp/duo-2055/brew-log") {
      try await HomebrewInstaller().fetch(caskToken:"duo-2055-full",onOutput:{_ in})
   }
   try lines.joined(separator:"\n").write(toFile:file,atomically:true,encoding:.utf8)
   return
 }
 let data=try Data(contentsOf:URL(fileURLWithPath:"/tmp/duo-2055/catalog.json"))
 let catalog=HomebrewCaskCatalog(testIndex:try HomebrewCaskCatalog.index(fromCatalogJSON:data))
 let inv=BrewLocalInventory()
 for (token,file,version) in [("duo-2055-full","Duo2055Full.app","1.0"),("duo-2055-new","Duo2055Old.app","1.0"),("duo-2055-pin","Duo2055Pin.app","1.0"),("duo-2055-intel","Duo2055Intel.app","1.0"),("duo-2055-var","Duo2055Var.app","1.0")] {
   let app=InstalledApp(name:file,bundleID:"org.duo2055.\(token)",shortVersion:version,buildVersion:"101",path:URL(fileURLWithPath:"/Applications/\(file)"),isMASApp:false,sparkleFeedURL:nil)
   let source=HomebrewCaskSource(catalog:catalog,inventory:inv)
   let r=try await source.latestVersion(for:app)
   print("\(token): remote=\(r?.shortVersion ?? "nil") build=\(r?.version ?? "nil") record=\(r?.homebrewRecordedVersion ?? "nil") sourceID=\(r?.sourceIdentifier ?? "nil")")
 }
 for file in ["formula-outdated","cask-outdated"] {
 let d=try Data(contentsOf:URL(fileURLWithPath:"/tmp/duo-2055/\(file).json"))
 print("\(file) formula parser=\(BrewFormulaService.parse(d).map{$0.name}) cask parser=\(BrewFormulaService.parseCasks(d).map{$0.name})")
 }
 print("selected brew=\(HomebrewInstaller.brewPath() ?? "nil")")
 }
}
