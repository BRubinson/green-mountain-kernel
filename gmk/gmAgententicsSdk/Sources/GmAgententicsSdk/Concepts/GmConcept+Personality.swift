import Foundation

let GM_CONCEPT_PERSONALITY: String = {
    let lenses =
        AgentGmkPersonality.allCases
        .map { personality in
            personality.text
                .replacingOccurrences(of: GM_AGENT_PERSONALITY_HEADER, with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .joined(separator: "\n\n")

    let party = AgentGmkPersonality.lenses
        .map(\.rawValue)
        .joined(separator: "`, `")

    return """
        # Personality — the methodology lenses

        A fan-out agent is spawned wearing exactly ONE lens. The lens decides what the agent goes looking for and what it argues for. It never changes the directive, the record the agent writes, or the rules it works under.

        `compliant` is the solo lens: one mind covering every angle when there is no fan-out. The other four — `\(party)` — are the party, spawned together so their disagreements surface as options rather than as one agent's preference.

        A lens argues its case and stops. One reader weighs what the lenses produce.

        \(lenses)
        """
}()
