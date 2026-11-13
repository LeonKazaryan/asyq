/// How the kon is laid out for a category.
enum KonLayout {
    /// From the first kenei's outer end to the last one's.
    static func rowWidth(_ category: AgeCategory) -> Float {
        Float(category.keneiCount - 1) * GameTuning.Field.keneiSpacing + 2 * BoneShape.kenei.halfExtents.x
    }
}
