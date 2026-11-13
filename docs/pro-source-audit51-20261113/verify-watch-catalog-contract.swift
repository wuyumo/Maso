import Foundation
struct Fixture {
    static func marketingName(_ id: String, language: String) -> String? {
        guard id == "bench_press_machine" else { return nil }
        if language.hasPrefix("zh-Hant") || language.hasPrefix("zh-TW") || language.hasPrefix("zh-HK") {
            return "推胸（器械）"
        }
        if language.hasPrefix("zh") { return "推胸（器械）" }
        // DEBUG marketing previews mirror the real phone catalog, including intentional mixed-language names.
        if language.hasPrefix("ja") { return "チェストプレス (マシン · 機械)" }
        if language.hasPrefix("ko") { return "가슴 압박 (머신)" }
        if language.hasPrefix("es") { return "Chest Press (Máquina)" }
        if language.hasPrefix("fr") { return "Presse thoracique (Machine)" }
        if language.hasPrefix("de") { return "Brustpresse (Maschine)" }
        if language.hasPrefix("it") { return "Chest Press (Macchina)" }
        if language.hasPrefix("pt-BR") { return "Prensa do tórax (Máquina)" }
        if language.hasPrefix("ru") { return "Чест-пресс (Тренажёр · машина)" }
        if language.hasPrefix("ar") { return "Chest Press (جهاز)" }
        return "Chest Press (Machine)"
    }
}
let rows = try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))) as! [[String:Any]]
let exercise=rows.first{$0["id"] as? String == "bench_press_machine"}!
let names=exercise["name"] as! [String:String]
var count=0
for (locale, expected) in names {
 precondition(Fixture.marketingName("bench_press_machine",language:locale)==expected,"Catalog mismatch: \(locale)")
 count+=1
}
for (locale,key) in [("zh-TW","zh-Hant"),("zh-HK","zh-Hant"),("en-US","en"),("ja-JP","ja"),("ar-SA","ar")] {
 precondition(Fixture.marketingName("bench_press_machine",language:locale)==names[key]);count+=1
}
precondition(Fixture.marketingName("unrelated_exercise",language:"en")==nil)
print("PASS \(count) exact catalog-name/region contracts plus unrelated-ID nil; extracted actual Swift fixture function. Not a UI test.")
