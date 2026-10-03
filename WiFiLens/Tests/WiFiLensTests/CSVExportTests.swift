import Testing
@testable import WiFi_Lens

struct CSVExportTests {
    @Test func textFieldsQuoteLocalizedTextAndEmbeddedNewlines() {
        #expect(CSVExportFieldEncoder.text("2,4 GHz, bande Wi-Fi") == "\"2,4 GHz, bande Wi-Fi\"")
        #expect(CSVExportFieldEncoder.text("2,4 ГГц, диапазон Wi-Fi") == "\"2,4 ГГц, диапазон Wi-Fi\"")
        #expect(CSVExportFieldEncoder.text("line one\r\nline two") == "\"line one\r\nline two\"")
        #expect(CSVExportFieldEncoder.text("Réseau \"maison\"") == "\"Réseau \"\"maison\"\"\"")
    }

    @Test(arguments: ["=1+1", "+SUM(A1:A2)", "-1+2", "@SUM(A1:A2)", "  =1+1"])
    func ssidFormulaPrefixesAreNeutralized(_ ssid: String) {
        let encoded = CSVExportFieldEncoder.text(ssid, protectSpreadsheetFormula: true)
        #expect(encoded.hasPrefix("\"'"))
        #expect(encoded.hasSuffix("\""))
    }

    @Test func ordinarySSIDAndNonSSIDTextAreNotChanged() {
        #expect(CSVExportFieldEncoder.text("Home Wi-Fi", protectSpreadsheetFormula: true) == "\"Home Wi-Fi\"")
        #expect(CSVExportFieldEncoder.text("-", protectSpreadsheetFormula: false) == "\"-\"")
    }
}
