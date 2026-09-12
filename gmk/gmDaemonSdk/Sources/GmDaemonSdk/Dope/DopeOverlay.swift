import Foundation

/// Read-through / copy-on-write resolution across two dope layers.
///
/// This is the masking resolver, and it is deliberately a PURE FUNCTION over
/// two already-hydrated `DopeScopeTree` values: no database, no filesystem,
/// no SQL. That is possible because `fetchDopeTree` already projects every
/// uuid FK into a dot-path code, so the two trees speak the same language
/// before they ever meet. Consequences worth stating, because they are what
/// make this affordable:
///
///  - None of the single-scope read sites in Store+Dope change. Every layer
///    is still exactly one scope and every read is still against one scope
///    row; `fetchDopeTree` is simply called twice.
///  - It never touches the base_composable machinery
///    (requireBaseChainReaches / requireAcyclicBase / baseComposableReferrers),
///    which exists to REFUSE cross-scope references and would reject exactly
///    what masking needs. This is a separate code path on purpose.
///  - It is unit-testable with no store at all.
///
/// Identity across layers is POSITIONAL: a node at dot-path `d.e.p` in the
/// overlay masks whatever sits at `d.e.p` in the base. No cross-layer
/// pointer is stored anywhere, so nothing can dangle, nothing needs
/// re-minting when ingest churns uuids, and a wholesale promotion of the
/// base cannot invalidate an overlay.
///
/// `resolve` NEVER throws. The health check calls it best-effort and a throwing
/// merge would break doctor's exit contract; a malformed pair degrades to
/// warnings, following DopeValidator's collect-every-error posture.
public enum DopeOverlay {

    /// Where a resolved node came from, and what happened to it.
    public enum Origin: String, Codable, Hashable, Sendable {
        /// Present only in the base — the overlay has nothing at this path.
        case base
        /// The overlay carried a real node at this path; its body won
        /// wholesale (copy-on-write, never a field-level merge).
        case overridden
        /// Overlay-only node whose parent path exists in the base.
        case added
        /// The overlay carried a whiteout here: the node is OMITTED from the
        /// resolved tree and recorded in `hidden`.
        case tombstoned
        /// The overlay has a node at a path the base no longer has. Legal and
        /// warned, never an error — a base is free to evolve out from under a
        /// personal overlay.
        case orphanedMask
    }

    /// Per-path provenance. `effectiveUuid` is where copy-on-write lives: a
    /// caller holding a node whose origin is `.base` is holding a BASE row,
    /// so writing it would write the shared layer.
    public struct Resolution: Codable, Hashable, Sendable {
        public let path: String
        public let origin: Origin
        public let effectiveUuid: String
        public let baseUuid: String?
        public let overlayUuid: String?

        public init(path: String, origin: Origin, effectiveUuid: String,
                    baseUuid: String?, overlayUuid: String?) {
            self.path = path
            self.origin = origin
            self.effectiveUuid = effectiveUuid
            self.baseUuid = baseUuid
            self.overlayUuid = overlayUuid
        }
    }

    public struct Resolved: Sendable {
        /// The merged tree, with tombstoned subtrees removed.
        public let tree: DopeScopeTree
        /// dot-path -> provenance, including the hidden ones.
        public let resolutions: [String: Resolution]
        /// Dot-paths masked away by a whiteout.
        public let hidden: [String]
        /// Non-fatal observations (orphaned masks, most often).
        public let warnings: [String]

        public init(tree: DopeScopeTree, resolutions: [String: Resolution],
                    hidden: [String], warnings: [String]) {
            self.tree = tree
            self.resolutions = resolutions
            self.hidden = hidden
            self.warnings = warnings
        }

        /// Hand a plain `DopeScopeTree` to everything downstream —
        /// DopeCanvasLayout, DiagramResolver, the headless renderer, GMVibes.
        /// This is what keeps the resolver from forcing a type change through
        /// five subsystems at once.
        public func flattened() -> DopeScopeTree { tree }
    }


    static func isTombstone(_ identity: DopeNodeIdentity) -> Bool {
        identity.deletedOn != nil
    }

    /// Merge `overlay` over `base`. A nil overlay resolves to the base
    /// unchanged; a nil base resolves the overlay alone (every node an
    /// orphaned mask, since there is nothing to mask).
    public static func resolve(base: DopeScopeTree?, overlay: DopeScopeTree?) -> Resolved {
        switch (base, overlay) {
        case (nil, nil):
            return Resolved(tree: DopeScopeTree.empty, resolutions: [:], hidden: [], warnings: [])
        case let (someBase?, nil):
            return singleLayerResolve(someBase, origin: .base)
        case let (nil, someOverlay?):
            var r = singleLayerResolve(someOverlay, origin: .orphanedMask)
            return Resolved(tree: r.tree, resolutions: r.resolutions, hidden: r.hidden,
                            warnings: r.warnings + ["no base layer: every overlay node resolves alone"])
        case let (someBase?, someOverlay?):
            return merge(base: someBase, overlay: someOverlay)
        }
    }

    // MARK: - Single layer (nothing to merge against)

    private static func singleLayerResolve(_ tree: DopeScopeTree, origin: Origin) -> Resolved {
        var resolutions = [String: Resolution]()
        var hidden = [String]()
        var domains = [DopePersistenceNode]()

        for domain in tree.domains {
            let dPath = domain.body.code
            if isTombstone(domain.identity) {
                hidden.append(dPath)
                resolutions[dPath] = Resolution(path: dPath, origin: .tombstoned,
                                                effectiveUuid: domain.identity.uuid,
                                                baseUuid: nil, overlayUuid: domain.identity.uuid)
                continue
            }
            resolutions[dPath] = Resolution(path: dPath, origin: origin,
                                            effectiveUuid: domain.identity.uuid,
                                            baseUuid: origin == .base ? domain.identity.uuid : nil,
                                            overlayUuid: origin == .base ? nil : domain.identity.uuid)
            var entities = [DopeEntityNode]()
            for entity in domain.entities {
                let ePath = "\(dPath).\(entity.body.code)"
                if isTombstone(entity.identity) {
                    hidden.append(ePath); continue
                }
                resolutions[ePath] = Resolution(path: ePath, origin: origin,
                                                effectiveUuid: entity.identity.uuid,
                                                baseUuid: origin == .base ? entity.identity.uuid : nil,
                                                overlayUuid: origin == .base ? nil : entity.identity.uuid)
                var props = [DopePropertyNode]()
                for p in entity.properties {
                    let pPath = "\(ePath).\(p.body.code)"
                    if isTombstone(p.identity) { hidden.append(pPath); continue }
                    resolutions[pPath] = Resolution(path: pPath, origin: origin,
                                                    effectiveUuid: p.identity.uuid,
                                                    baseUuid: origin == .base ? p.identity.uuid : nil,
                                                    overlayUuid: origin == .base ? nil : p.identity.uuid)
                    props.append(p)
                }
                entities.append(DopeEntityNode(identity: entity.identity, body: entity.body,
                                               properties: props))
            }
            var enums = [DopeEnumNode]()
            for en in domain.enums {
                let nPath = "\(dPath).enums.\(en.body.code)"
                if isTombstone(en.identity) { hidden.append(nPath); continue }
                resolutions[nPath] = Resolution(path: nPath, origin: origin,
                                                effectiveUuid: en.identity.uuid,
                                                baseUuid: origin == .base ? en.identity.uuid : nil,
                                                overlayUuid: origin == .base ? nil : en.identity.uuid)
                var options = [DopeOptionNode]()
                for o in en.options {
                    let oPath = "\(nPath).\(o.body.code)"
                    if isTombstone(o.identity) { hidden.append(oPath); continue }
                    resolutions[oPath] = Resolution(path: oPath, origin: origin,
                                                    effectiveUuid: o.identity.uuid,
                                                    baseUuid: origin == .base ? o.identity.uuid : nil,
                                                    overlayUuid: origin == .base ? nil : o.identity.uuid)
                    options.append(o)
                }
                enums.append(DopeEnumNode(identity: en.identity, body: en.body, options: options))
            }
            domains.append(DopePersistenceNode(identity: domain.identity, body: domain.body,
                                               entities: entities, enums: enums))
        }
        return Resolved(tree: tree.replacingDomains(domains), resolutions: resolutions,
                        hidden: hidden, warnings: [])
    }

    // MARK: - Two-layer merge

    private static func merge(base: DopeScopeTree, overlay: DopeScopeTree) -> Resolved {
        var resolutions = [String: Resolution]()
        var hidden = [String]()
        var warnings = [String]()

        let overlayDomains = Dictionary(
            overlay.domains.map { ($0.body.code, $0) }, uniquingKeysWith: { a, _ in a })
        var consumedDomains = Set<String>()
        var domains = [DopePersistenceNode]()

        // Base order first: a merge must not reshuffle the shared tree.
        for baseDomain in base.domains {
            let path = baseDomain.body.code
            let ov = overlayDomains[path]
            if let ov { consumedDomains.insert(path) }

            if let ov, isTombstone(ov.identity) {
                hidden.append(path)
                resolutions[path] = Resolution(path: path, origin: .tombstoned,
                                               effectiveUuid: ov.identity.uuid,
                                               baseUuid: baseDomain.identity.uuid,
                                               overlayUuid: ov.identity.uuid)
                continue
            }

            // Present in the overlay means it overrides, wholesale. Copy-up
            // materializes ancestors with the base's real values, so an
            // ancestor carried along for a deeper edit is a faithful copy
            // rather than an empty shell — which is why no marker is needed.
            let origin: Origin = ov == nil ? .base : .overridden
            let body = ov?.body ?? baseDomain.body
            let identity = ov?.identity ?? baseDomain.identity
            resolutions[path] = Resolution(path: path, origin: origin,
                                           effectiveUuid: identity.uuid,
                                           baseUuid: baseDomain.identity.uuid,
                                           overlayUuid: ov?.identity.uuid)

            let (entities, enums) = mergeDomainChildren(
                basePath: path, base: baseDomain, overlay: ov,
                resolutions: &resolutions, hidden: &hidden)
            domains.append(DopePersistenceNode(identity: identity, body: body,
                                               entities: entities, enums: enums))
        }

        // Overlay-only domains: additions, or orphaned masks if they are
        // whiteouts over something the base no longer has.
        for domain in overlay.domains where !consumedDomains.contains(domain.body.code) {
            let path = domain.body.code
            if isTombstone(domain.identity) {
                hidden.append(path)
                warnings.append("orphaned mask: '\(path)' is a whiteout over a node the base no longer has")
                resolutions[path] = Resolution(path: path, origin: .orphanedMask,
                                               effectiveUuid: domain.identity.uuid,
                                               baseUuid: nil, overlayUuid: domain.identity.uuid)
                continue
            }
            let sub = singleLayerResolve(
                base.replacingDomains([domain]), origin: .added)
            for (k, v) in sub.resolutions { resolutions[k] = v }
            hidden.append(contentsOf: sub.hidden)
            domains.append(contentsOf: sub.tree.domains)
        }

        return Resolved(tree: base.replacingDomains(domains), resolutions: resolutions,
                        hidden: hidden, warnings: warnings)
    }

    private static func mergeDomainChildren(
        basePath: String, base: DopePersistenceNode, overlay: DopePersistenceNode?,
        resolutions: inout [String: Resolution], hidden: inout [String]
    ) -> ([DopeEntityNode], [DopeEnumNode]) {
        let ovEntities = Dictionary(
            (overlay?.entities ?? []).map { ($0.body.code, $0) }, uniquingKeysWith: { a, _ in a })
        let ovEnums = Dictionary(
            (overlay?.enums ?? []).map { ($0.body.code, $0) }, uniquingKeysWith: { a, _ in a })
        var consumedE = Set<String>(), consumedN = Set<String>()
        var entities = [DopeEntityNode](), enums = [DopeEnumNode]()

        for be in base.entities {
            let path = "\(basePath).\(be.body.code)"
            let ov = ovEntities[be.body.code]
            if ov != nil { consumedE.insert(be.body.code) }
            if let ov, isTombstone(ov.identity) {
                hidden.append(path)
                resolutions[path] = Resolution(path: path, origin: .tombstoned,
                                               effectiveUuid: ov.identity.uuid,
                                               baseUuid: be.identity.uuid,
                                               overlayUuid: ov.identity.uuid)
                continue
            }
            let use = ov ?? be
            resolutions[path] = Resolution(
                path: path, origin: ov == nil ? .base : .overridden,
                effectiveUuid: use.identity.uuid, baseUuid: be.identity.uuid,
                overlayUuid: ov?.identity.uuid)

            let ovProps = Dictionary(
                (ov?.properties ?? []).map { ($0.body.code, $0) }, uniquingKeysWith: { a, _ in a })
            var consumedP = Set<String>()
            var props = [DopePropertyNode]()
            for bp in be.properties {
                let pPath = "\(path).\(bp.body.code)"
                let op = ovProps[bp.body.code]
                if op != nil { consumedP.insert(bp.body.code) }
                if let op, isTombstone(op.identity) {
                    hidden.append(pPath)
                    resolutions[pPath] = Resolution(path: pPath, origin: .tombstoned,
                                                    effectiveUuid: op.identity.uuid,
                                                    baseUuid: bp.identity.uuid,
                                                    overlayUuid: op.identity.uuid)
                    continue
                }
                let useP = op ?? bp
                resolutions[pPath] = Resolution(
                    path: pPath, origin: op == nil ? .base : .overridden,
                    effectiveUuid: useP.identity.uuid, baseUuid: bp.identity.uuid,
                    overlayUuid: op?.identity.uuid)
                props.append(useP)
            }
            for op in (ov?.properties ?? []) where !consumedP.contains(op.body.code) {
                let pPath = "\(path).\(op.body.code)"
                if isTombstone(op.identity) { hidden.append(pPath); continue }
                resolutions[pPath] = Resolution(path: pPath, origin: .added,
                                                effectiveUuid: op.identity.uuid,
                                                baseUuid: nil, overlayUuid: op.identity.uuid)
                props.append(op)
            }
            entities.append(DopeEntityNode(identity: use.identity, body: use.body,
                                           properties: props))
        }
        for oe in (overlay?.entities ?? []) where !consumedE.contains(oe.body.code) {
            let path = "\(basePath).\(oe.body.code)"
            if isTombstone(oe.identity) { hidden.append(path); continue }
            resolutions[path] = Resolution(path: path, origin: .added,
                                           effectiveUuid: oe.identity.uuid,
                                           baseUuid: nil, overlayUuid: oe.identity.uuid)
            entities.append(oe)
        }

        for bn in base.enums {
            let path = "\(basePath).enums.\(bn.body.code)"
            let ov = ovEnums[bn.body.code]
            if ov != nil { consumedN.insert(bn.body.code) }
            if let ov, isTombstone(ov.identity) {
                hidden.append(path)
                resolutions[path] = Resolution(path: path, origin: .tombstoned,
                                               effectiveUuid: ov.identity.uuid,
                                               baseUuid: bn.identity.uuid,
                                               overlayUuid: ov.identity.uuid)
                continue
            }
            let use = ov ?? bn
            resolutions[path] = Resolution(
                path: path, origin: ov == nil ? .base : .overridden,
                effectiveUuid: use.identity.uuid, baseUuid: bn.identity.uuid,
                overlayUuid: ov?.identity.uuid)

            let ovOpts = Dictionary(
                (ov?.options ?? []).map { ($0.body.code, $0) }, uniquingKeysWith: { a, _ in a })
            var consumedO = Set<String>()
            var options = [DopeOptionNode]()
            for bo in bn.options {
                let oPath = "\(path).\(bo.body.code)"
                let oo = ovOpts[bo.body.code]
                if oo != nil { consumedO.insert(bo.body.code) }
                if let oo, isTombstone(oo.identity) {
                    hidden.append(oPath)
                    resolutions[oPath] = Resolution(path: oPath, origin: .tombstoned,
                                                    effectiveUuid: oo.identity.uuid,
                                                    baseUuid: bo.identity.uuid,
                                                    overlayUuid: oo.identity.uuid)
                    continue
                }
                let useO = oo ?? bo
                resolutions[oPath] = Resolution(
                    path: oPath, origin: oo == nil ? .base : .overridden,
                    effectiveUuid: useO.identity.uuid, baseUuid: bo.identity.uuid,
                    overlayUuid: oo?.identity.uuid)
                options.append(useO)
            }
            for oo in (ov?.options ?? []) where !consumedO.contains(oo.body.code) {
                let oPath = "\(path).\(oo.body.code)"
                if isTombstone(oo.identity) { hidden.append(oPath); continue }
                resolutions[oPath] = Resolution(path: oPath, origin: .added,
                                                effectiveUuid: oo.identity.uuid,
                                                baseUuid: nil, overlayUuid: oo.identity.uuid)
                options.append(oo)
            }
            enums.append(DopeEnumNode(identity: use.identity, body: use.body, options: options))
        }
        for on in (overlay?.enums ?? []) where !consumedN.contains(on.body.code) {
            let path = "\(basePath).enums.\(on.body.code)"
            if isTombstone(on.identity) { hidden.append(path); continue }
            resolutions[path] = Resolution(path: path, origin: .added,
                                           effectiveUuid: on.identity.uuid,
                                           baseUuid: nil, overlayUuid: on.identity.uuid)
            enums.append(on)
        }
        return (entities, enums)
    }
}
