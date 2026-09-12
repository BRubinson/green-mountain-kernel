import Foundation

/// The canonical DOPE acronym — every doc, comment, and help string
/// references this definition; drift is a build/test failure, not a sweep.
///
/// Think of the .doped system like doping silicon into a P-type or N-type
/// extrinsic semiconductor to make transistors: the domain model is what
/// turns a plain project into a driven one.
public enum DopeVocabulary {
    /// DOPE — the core expansion.
    public static let acronym = "Domain Optimized Project Essence"
    /// DOPED — the on-disk `.doped.json` form. The trailing D (Driver) is
    /// optional and primarily references the saved jsons; the core is DOPE.
    public static let driverAcronym = "Domain Optimized Project Essence Driver"
    /// The retired expansion — exists only so tests can ban it from the repo.
    public static let retiredAcronym = "Domain Oriented Persistence Entity Diagram"
}
