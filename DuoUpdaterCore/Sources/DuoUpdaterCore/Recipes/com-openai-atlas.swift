import Foundation

enum com_openai_atlas {
    static let set = AppRecipeSet(
        family: "com-openai-atlas",
        sunsets: [
        // ChatGPT Atlas — OpenAI's ChatGPT release notes (read 2026-10-23): "Atlas
        // is scheduled to stop working on August 9, 2026." The retirement article
        // linked here says it "has been retired and no longer receives updates".
        // History: docs/app-audits/com-openai-atlas.md#产品终止
            "com.openai.atlas": ProductSunset(
                endDate: "2026-08-09",
                announcement: URL(string: "https://help.openai.com/en/articles/20001371-chatgpt-atlas-retirement")!),
        ])
}
