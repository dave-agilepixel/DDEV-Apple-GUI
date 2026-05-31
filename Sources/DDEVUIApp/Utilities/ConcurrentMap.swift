/// Maps `items` through `transform` with at most `limit` transforms running concurrently,
/// preserving input order in the result.
///
/// Used to bound subprocess fan-out: a large workspace must not put N blocking `describe`
/// calls in flight at once and pressure the global dispatch pool (audit M1). The task group
/// is primed with `limit` tasks and a new one is started only as each result arrives.
func concurrentMap<Input: Sendable, Output: Sendable>(
    _ items: [Input],
    limit: Int,
    _ transform: @escaping @Sendable (Input) async -> Output
) async -> [Output] {
    precondition(limit >= 1, "limit must be >= 1")
    guard !items.isEmpty else { return [] }

    return await withTaskGroup(of: (Int, Output).self) { group in
        var results = [Output?](repeating: nil, count: items.count)
        var nextIndex = 0

        let primed = min(limit, items.count)
        while nextIndex < primed {
            let index = nextIndex
            let element = items[index]
            group.addTask { (index, await transform(element)) }
            nextIndex += 1
        }

        while let (index, output) = await group.next() {
            results[index] = output
            if nextIndex < items.count {
                let index = nextIndex
                let element = items[index]
                group.addTask { (index, await transform(element)) }
                nextIndex += 1
            }
        }

        return results.compactMap { $0 }
    }
}
