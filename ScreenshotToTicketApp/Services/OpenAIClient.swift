import Foundation

struct OpenAIClient {
    struct ResponseEnvelope: Decodable {
        struct OutputItem: Decodable {
            struct ContentItem: Decodable {
                let type: String
                let text: String?
            }
            let content: [ContentItem]?
        }
        let output: [OutputItem]?
    }

    let apiKey: String
    let model: String

    func draftTicket(from images: [Data], userHint: String) async throws -> TicketDraft {
        var content: [[String: Any]] = [[
            "type": "input_text",
            "text": prompt(userHint: userHint)
        ]]

        for image in images {
            let base64 = image.base64EncodedString()
            let imageURL = "data:image/jpeg;base64,\(base64)"
            content.append([
                "type": "input_image",
                "image_url": imageURL
            ])
        }

        let payload: [String: Any] = [
            "model": model,
            "input": [[
                "role": "user",
                "content": content
            ]]
        ]

        let body = try JSONSerialization.data(withJSONObject: payload)
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "OpenAI", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
        }

        let decoded = try JSONDecoder().decode(ResponseEnvelope.self, from: data)
        let text = decoded.output?
            .flatMap { $0.content ?? [] }
            .first(where: { $0.type == "output_text" })?
            .text ?? ""

        return parseDraft(text)
    }

    private func prompt(userHint: String) -> String {
        let hintSection = userHint.isEmpty ? "No extra user notes." : "User notes/instructions (must influence output): \(userHint)"
        return """
You create Jira Bug tickets from screenshot evidence.
Return ONLY valid JSON with this schema:
{"summary":"string","description":"string"}

Rules:
- Summary max 120 chars.
- Description should include: Observed behavior, Expected behavior, Steps to reproduce, Impact.
- Use user notes as instruction and include them naturally in the draft.

\(hintSection)
"""
    }

    private func parseDraft(_ text: String) -> TicketDraft {
        let cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let summary = obj["summary"],
              let description = obj["description"] else {
            return TicketDraft(summary: "Bug from screenshot", description: cleaned.isEmpty ? text : cleaned)
        }

        return TicketDraft(summary: summary, description: description)
    }
}
